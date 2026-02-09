{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key=['deal_id','change_time','changed_field_key','new_value'],
    on_schema_change='sync_all_columns'
) }}

-- ---------------------------------------------------------------------
-- Intermediate model: int_deal_changes_dedup_enriched
--
-- Purpose:
--   - Filter deal change history down to the two change types required for the funnel:
--       * stage_id     (pipeline stage transitions)
--       * lost_reason  (deal loss reason updates, used for exclusions such as "Duplicate entry")
--   - Deduplicate exact duplicate change events in the raw export
--   - Enrich numeric ids with readable labels from:
--       * stg_stages (stage_id -> stage_name)
--       * int_reason_lost_lookup_from_fields (lost_reason_id -> lost_reason_label)
--
-- Transformations:
--   - Keep only changed_field_key in ('stage_id','lost_reason')
--   - Keep only numeric new_value (regex '^[0-9]+$') so it can be safely cast to int
--   - new_value_id: cast new_value to int for consistent joins to lookup tables
--   - Deduplicate exact duplicate change events using row_number partitioned by:
--       deal_id, change_time, changed_field_key, new_value
--   - Add typed/enriched columns:
--       stage_id, stage_label, lost_reason_id, lost_reason_label
--
-- Incremental strategy:
--   - delete+insert on unique key:
--       (deal_id, change_time, changed_field_key, new_value)
--   - Uses a rolling lookback on change_time to capture late-arriving / corrected rows
--
-- Data quality tests (defined in _int_schema.yml):
--   - deal_id:
--       * not_null (severity: error)
--   - change_time:
--       * not_null (severity: error)
--   - changed_field_key:
--       * not_null (severity: error)
--       * accepted_values in ('stage_id','lost_reason') (severity: error)
--   - new_value:
--       * not_null (severity: error)
--   - new_value_id:
--       * not_null (severity: error)
--       * is_positive (severity: error)
--   - stage_id:
--       * relationships to stg_stages.stage_id (severity: error)
--     Rationale: stage-based funnel steps depend on valid stage_id resolution.
--   - lost_reason_id:
--       * relationships to int_reason_lost_lookup_from_fields.lost_reason_id (severity: error)
--     Rationale: exclusion of "Duplicate entry" depends on correct lost reason resolution.
--
-- Notes:
--   - Raw data contains duplicate change events; deduplication is necessary to prevent
--     inflated monthly counts in downstream funnel aggregation.
--   - Only numeric new_value is retained to avoid parsing issues and ambiguous labels.
--
-- ---------------------------------------------------------------------

with deal_changes as (
    -- Base event stream:
    -- Keep only stage and lost reason changes, and only where the new_value is numeric.
    -- This ensures new_value can be safely cast to new_value_id and joined to lookups.
    select
        deal_id,
        change_time,
        changed_field_key,
        new_value,
        new_value::int as new_value_id
    from {{ ref('stg_deal_changes') }}
    where changed_field_key in ('stage_id', 'lost_reason')
      and new_value ~ '^[0-9]+$'

    {% if is_incremental() %}
      and change_time >= {{ incremental_lookback() }}
    {% endif %}

),

deal_changes_ranked as (
    -- Rank exact duplicates of the same event (same deal_id + time + field + value).
    -- We keep rn=1 to enforce a single canonical event per exact match.
    select
        dc.*,
        row_number() over (
            partition by
                deal_id,
                change_time,
                changed_field_key,
                new_value
            order by
                deal_id
        ) as rn
    from deal_changes dc

),

deal_changes_deduped as (
    -- Keep only the top-ranked row per exact duplicate group.
    -- This prevents downstream double-counting of stage transitions and lost reason events.
    select *
    from deal_changes_ranked
    where rn = 1

),

stages as (
    -- Canonical stage dimension used to label stage_id events.
    select
        stage_id,
        stage_name
    from {{ ref('stg_stages') }}

),

lost_reason as (
    -- Fields-derived lost reason lookup (id -> label).
    -- Used to label loss events and support filtering/exclusion logic.
    select
        lost_reason_id,
        lost_reason_label
    from {{ ref('int_reason_lost_lookup_from_fields') }}

),

final as (
    -- Enrich deduplicated deal change events with readable labels.
    -- Only populate stage_* columns for stage_id events, and lost_reason_* columns for lost_reason events.
    -- Left joins preserve the event row even if lookup is missing; relationship tests enforce integrity.
    select
        dc.deal_id,
        dc.change_time,
        dc.changed_field_key,
        dc.new_value,
        dc.new_value_id,

        case when dc.changed_field_key = 'stage_id'
             then dc.new_value_id::int
        end as stage_id,

        case when dc.changed_field_key = 'stage_id'
             then s.stage_name
        end as stage_label,

        case when dc.changed_field_key = 'lost_reason'
             then dc.new_value_id::int
        end as lost_reason_id,

        case when dc.changed_field_key = 'lost_reason'
             then lr.lost_reason_label
        end as lost_reason_label

    from deal_changes_deduped dc
    left join stages s
      on dc.changed_field_key = 'stage_id'
     and dc.new_value_id is not null
     and dc.new_value_id::int = s.stage_id
    left join lost_reason lr
      on dc.changed_field_key = 'lost_reason'
     and dc.new_value_id is not null
     and dc.new_value_id::int = lr.lost_reason_id

)

select * from final
