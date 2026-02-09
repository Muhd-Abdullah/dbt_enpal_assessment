{{ config(
    materialized='incremental',
    incremental_strategy='delete+insert',
    unique_key='activity_id',
    on_schema_change='sync_all_columns'
) }}


-- ---------------------------------------------------------------------
-- Intermediate model: int_activity_dedup_enriched
--
-- Purpose:
--   - Deduplicate activity records to enforce a strict 1-row-per-activity_id grain
--   - Enrich activities with activity type attributes (id, name, active flag)
--   - Provide a clean activity event dataset used to derive funnel call steps
--     (Step 2.1: Sales Call 1, Step 3.1: Sales Call 2)
--
-- Incremental strategy:
--   - delete+insert on unique_key=activity_id
--   - Uses a rolling lookback window on due_date to capture late-arriving updates
--     (Pipedrive exports can change recently scheduled activities)
--
-- Data quality tests (defined in _int_schema.yml):
--   - activity_id:
--       * not_null (severity: error)
--       * unique  (severity: error)
--     Rationale: this model must always represent one canonical row per activity_id.
--
--   - activity_type_code:
--       * not_null (severity: error)
--       * relationships to stg_activity_types.activity_type_code (severity: error)
--     Rationale: classification into call KPIs depends on resolving the activity type.
--
--   - activity_type_id:
--       * relationships to stg_activity_types.activity_type_id (severity: error)
--     Rationale: ensures lookup integrity for the enriched activity type attributes.
--
--   - activity_type_is_active:
--       * activity_type_is_active must be true for required call activity types:
--           - meeting (Sales Call 1)
--           - sc_2    (Sales Call 2)
--       * enforced via generic test activity_type_is_active (severity: error)
--     Rationale: if these activity types are inactive in Pipedrive, call KPIs would
--       silently drop to zero or become incorrect. This must fail fast in intermediate.
--
--   - is_done:
--       * not_null (severity: error)
--     Rationale: used in dedup ranking and downstream logic to identify completed calls.
--
--   - assigned_to_user_id:
--       * relationships to stg_users.user_id (severity: warn)
--     Rationale: activities may be unassigned or users may be missing from extracts;
--       this should be visible but should not block the pipeline.
--
--   - due_date:
--       * not_null (severity: warn)
--     Rationale: due_date may be null in Pipedrive exports; handled explicitly in the model.
--
-- ---------------------------------------------------------------------

with activity as (
    -- Base activity rows from staging.
    -- In incremental runs, only reprocess a rolling window (plus NULL due_date)
    -- to catch late updates without rescanning full history.
    select
        activity_id,
        activity_type_code,
        assigned_to_user_id,
        deal_id,
        is_done,
        due_date
    from {{ ref('stg_activity') }}

    {% if is_incremental() %}
      -- Rolling reprocess window to catch late-arriving / corrected rows.
      -- Include due_date IS NULL rows since they cannot be evaluated against the window.
      where
        due_date >= {{ incremental_lookback() }} -- Default 7 days
        or due_date is null
    {% endif %}

),

activity_ranked as (
    -- Identify duplicate candidates per activity_id and pick the "best" record.
    -- Ranking logic:
    --   1) due_date desc: prefer the most recently scheduled activity record
    --   2) is_done desc: prefer completed record if timestamps tie
    --   3) deal_id desc: deterministic final tie-breaker
    select
        a.*,
        row_number() over (
            partition by activity_id
            order by
                due_date desc nulls last,
                is_done desc,
                deal_id desc
        ) as rn
    from activity a

),

activity_deduped as (
    -- Keep one canonical row per activity_id after ranking.
    -- Enforces model grain required for accurate counting and downstream joins.
    select
        activity_id,
        activity_type_code,
        assigned_to_user_id,
        deal_id,
        is_done,
        due_date
    from activity_ranked
    where rn = 1

),

activity_types as (
    -- Lookup table for activity type attributes.
    -- Used to translate type codes (e.g. meeting, sc_2) into ids/names and active flags.
    select
        activity_type_id,
        activity_type_code,
        activity_type_name,
        is_active
    from {{ ref('stg_activity_types') }}

),

final as (    
    -- Enrich deduplicated activities with activity type attributes.
    -- Left join preserves the activity row even if the lookup is missing, but
    -- relationship tests are set to ERROR to avoid silently breaking KPI mapping.
    select
        d.activity_id,
        d.deal_id,
        d.assigned_to_user_id,
        d.activity_type_code,

        t.activity_type_id,
        t.activity_type_name,
        t.is_active as activity_type_is_active,

        d.is_done,
        d.due_date
    from activity_deduped d
    left join activity_types t
      on d.activity_type_code = t.activity_type_code

)

select * from final