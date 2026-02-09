{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key=['deal_id','month','funnel_step'],
    on_schema_change='sync_all_columns'
) }}


-- ---------------------------------------------------------------------
-- Intermediate model: int_funnel_events
--
-- Purpose:
--   - Create a canonical monthly funnel event stream at grain:
--       1 row per (deal_id, month, funnel_step)
--   - Combine two event sources:
--       * stage_change events from deal_changes (steps 1..9 via pipeline stages)
--       * activity events for calls (Step 2.1 and Step 3.1)
--   - Exclude operationally duplicated deals where the FINAL lost reason is
--     "Duplicate entry" (based on the latest lost_reason change per deal)
--
-- Transformations:
--   - Identify excluded deals using latest lost_reason_label per deal
--   - Generate stage-based events from stage_id change history
--   - Generate call-based events from completed activities (is_done = true)
--   - Union stage and call events into a single event stream
--   - Deduplicate events to one per (deal_id, month, funnel_step) using earliest event_time
--   - Remove excluded deals from the final output
--
-- Incremental strategy:
--   - delete+insert on unique key: (deal_id, month, funnel_step)
--   - Rolling lookback window applied separately to:
--       * stage events using change_time
--       * activity events using due_date timestamp
--     This captures late-arriving updates while keeping runs efficient
--
-- Data quality tests (defined in _int_schema.yml):
--   - (deal_id, month, funnel_step):
--       * unique (severity: error)
--     Rationale: this model defines the canonical grain for downstream reporting.
--
--   - deal_id, month, funnel_step, event_time, event_source:
--       * not_null (severity: error)
--     Rationale: required for monthly attribution and stable aggregation.
--
--   - event_source:
--       * accepted_values in ('stage_change','activity') (severity: error)
--     Rationale: ensures events can be interpreted consistently downstream.
--
--   - requires_when rules:
--       * call steps (2.1, 3.1) must come from event_source='activity' (severity: error)
--       * non-call steps must come from event_source='stage_change' (severity: error)
--       * event_time must be present for both sources (severity: error)
--     Rationale: prevents silent mixing of event sources and guarantees month logic is valid.
--
-- Notes:
--   - Stage steps are intentionally labeled dynamically as:
--       "Step <stage_id>: <stage_label>"
--     This matches the pipeline stage ids/names and keeps the model robust to stage renames.
--   - Call steps are intentionally hard-coded to 2.1 and 3.1 to meet the task requirement.
--   - Exclusion logic uses FINAL lost_reason (latest by change_time). This ensures we
--     only exclude deals that are ultimately marked as duplicates.
--
-- ---------------------------------------------------------------------

with lost_reason_ranked as (
    -- Pull lost_reason change events and rank them so rn=1 is the latest per deal.
    -- This is required because a deal's lost_reason can change over time, and we only
    -- want to exclude deals whose FINAL reason is "Duplicate entry".
    select
        deal_id,
        change_time,
        lost_reason_label,
        row_number() over (
            partition by deal_id
            order by change_time desc
        ) as rn
    from {{ ref('int_deal_changes_dedup_enriched') }}
    where changed_field_key = 'lost_reason'
      and lost_reason_label is not null
),

excluded_deals as (
    -- Keep only deals whose latest lost_reason_label is "Duplicate entry".
    -- Lower/trim normalization protects against casing/whitespace inconsistencies.
    select deal_id
    from lost_reason_ranked
    where rn = 1
      and lower(trim(lost_reason_label)) = 'duplicate entry'
),

stage_events as (
    -- Convert each stage change into a funnel event with:
    --   - event_time = change_time
    --   - month = month bucket of change_time
    --   - funnel_step = dynamic label based on stage_id + stage_label
    -- This forms the backbone of steps 1..9 (pipeline progression).
    select
        dc.deal_id,
        dc.change_time as event_time,
        date_trunc('month', dc.change_time)::date as month,
        ('Step ' || dc.stage_id::text || ': ' || dc.stage_label) as funnel_step,
        dc.stage_id::numeric as funnel_step_order,
        'stage_change' as event_source
    from {{ ref('int_deal_changes_dedup_enriched') }} dc
    where dc.changed_field_key = 'stage_id'
      and dc.stage_id is not null

      {% if is_incremental() %}
        and dc.change_time >= {{ incremental_lookback() }}
      {% endif %}
),

call_events_raw as (
    -- Convert completed activities into call funnel events:
    --   - Sales Call 1: activity_type_code = 'meeting'  -> Step 2.1
    --   - Sales Call 2: activity_type_code = 'sc_2'     -> Step 3.1
    -- We only include done activities (is_done = true) to avoid counting planned calls.
    select
        a.deal_id,
        a.due_date::timestamp as event_time,
        date_trunc('month', a.due_date::timestamp)::date as month,

        case
            when a.activity_type_code = 'meeting' then 'Step 2.1: Sales Call 1'
            when a.activity_type_code = 'sc_2' then 'Step 3.1: Sales Call 2'
        end as funnel_step,

        case
            when a.activity_type_code = 'meeting' then 2.1::numeric
            when a.activity_type_code = 'sc_2' then 3.1::numeric
        end as funnel_step_order,

        'activity' as event_source
    from {{ ref('int_activity_dedup_enriched') }} a
    where a.deal_id is not null
      and a.due_date is not null
      and a.is_done = true
      and a.activity_type_code in ('meeting', 'sc_2')

      {% if is_incremental() %}
        and a.due_date::timestamp >= {{ incremental_lookback() }}
      {% endif %}
),


all_events as (
    -- Combine both event streams into one unified funnel event table.
    -- This makes downstream aggregation consistent across stage and call steps.
    select * from stage_events
    union all
    select * from call_events_raw
),

dedup as (
    -- Enforce the model grain:
    -- keep only the earliest event_time when the same deal hits the same funnel_step
    -- multiple times within the same month.
    select
        e.*,
        row_number() over (
            partition by e.deal_id, e.month, e.funnel_step
            order by e.event_time asc
        ) as rn
    from all_events e
),

final as (
    -- Remove excluded deals ("Duplicate entry") after deduplication so:
    --   - exclusions apply consistently across both stage and call events
    --   - we don't leak duplicate deals into the reporting model
    select
        d.deal_id,
        d.month,
        d.funnel_step,
        d.event_time,
        d.event_source,
        d.funnel_step_order
    from dedup d
    left join excluded_deals x
      on d.deal_id = x.deal_id
    where d.rn = 1
      and x.deal_id is null
)

select *
from final
