{{ config(materialized='view') }}

-- ---------------------------------------------------------------------
-- Intermediate model: int_stage_lookup_from_fields
--
-- Purpose:
--   - Extract the list of pipeline stage options from Pipedrive field metadata
--     (stg_fields.field_value_options) for field_key = 'stage_id'
--   - Provide a lightweight lookup (stage_id -> stage_label) derived from the
--     fields configuration, which can be compared/validated against stg_stages
--
-- Transformations:
--   - Filter stg_fields down to the single row that defines the 'stage_id' field
--   - Parse field_value_options JSON array into one row per option
--   - stage_id: cast option id to int for consistent joins
--   - stage_label: trim whitespace and normalize empty strings to NULL
--
-- Data quality tests:
--   - stage_id:
--       * not_null (severity: error)
--       * unique  (severity: error)
--       * relationships to stg_stages.stage_id (severity: error)
--     Rationale: if fields-derived stage options do not align with the canonical
--       stage dimension, funnel mapping can become inconsistent or incorrect.
--
--   - stage_label:
--       * not_null (severity: warn)
--     Rationale: labels are useful for readability; warn-only because metadata
--       can occasionally be incomplete without breaking joins.
--
-- Notes:
--   - This model is materialized as a VIEW because it is small, deterministic,
--     and purely derived from metadata (no heavy transforms).
--   - Null/empty field_value_options are treated as an empty JSON array to avoid
--     runtime failures and to make behavior explicit.
--
-- ---------------------------------------------------------------------

with fields as (
    -- Select only the metadata row that defines the 'stage_id' field.
    -- This isolates the JSON option list we need to explode into stage rows.
    select
        field_key,
        field_value_options
    from {{ ref('stg_fields') }}
    where field_key = 'stage_id'

),

stage_options as (
    -- Explode the JSON array of options into one row per stage.
    -- We defensively coerce NULL/blank field_value_options into '[]' to:
    --   - prevent json parsing errors
    --   - produce zero rows rather than failing the model
    select
        (opt->>'id')::int as stage_id,
        nullif(trim(opt->>'label'), '') as stage_label
    from fields
    cross join lateral jsonb_array_elements(
        case
            when field_value_options is null or trim(field_value_options) = '' then '[]'::jsonb
            else field_value_options::jsonb
        end
    ) as opt

)

select
    stage_id,
    stage_label
from stage_options