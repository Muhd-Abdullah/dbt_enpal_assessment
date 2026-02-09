{{ config(materialized='view') }}

-- ---------------------------------------------------------------------
-- Intermediate model: int_reason_lost_lookup_from_fields
--
-- Purpose:
--   - Extract the list of "lost reason" options from Pipedrive field metadata
--     (stg_fields.field_value_options) for field_key = 'lost_reason'
--   - Provide a lookup (lost_reason_id -> lost_reason_label) to enrich deal loss
--     events and to support business rules such as excluding deals with final
--     lost_reason_label = 'Duplicate entry'
--
-- Transformations:
--   - Filter stg_fields down to the single row that defines the 'lost_reason' field
--   - Parse field_value_options JSON array into one row per option
--   - lost_reason_id: cast option id to int for consistent joins
--   - lost_reason_label: trim whitespace and normalize empty strings to NULL
--
-- Data quality tests:
--   - lost_reason_id:
--       * not_null (severity: error)
--       * unique  (severity: error)
--     Rationale: lost_reason_id uniquely identifies a lost reason option and is
--       used as a foreign key for enrichment and exclusion logic.
--
--   - lost_reason_label:
--       * not_null (severity: warn)
--     Rationale: label is used for readability and filtering (e.g. 'Duplicate entry');
--       warn-only because metadata may occasionally be incomplete.
--
-- Notes:
--   - This model is materialized as a VIEW because it is small, deterministic,
--     and purely derived from metadata (no heavy transforms).
--   - Null/empty field_value_options are treated as an empty JSON array to avoid
--     runtime failures and to make behavior explicit.
--
-- ---------------------------------------------------------------------

with fields as (
    -- Select only the metadata row that defines the 'lost_reason' field.
    -- This isolates the JSON option list we need to explode into lost reason rows.
    select
        field_key,
        field_value_options
    from {{ ref('stg_fields') }}
    where field_key = 'lost_reason'
),

options as (
    -- Explode the JSON array of options into one row per lost reason.
    -- We defensively coerce NULL/blank field_value_options into '[]' to:
    --   - prevent json parsing errors
    --   - produce zero rows rather than failing the model
    select
        (opt->>'id')::int as lost_reason_id,
        nullif(trim(opt->>'label'), '') as lost_reason_label
    from fields
    cross join lateral jsonb_array_elements(
        case
            when field_value_options is null or trim(field_value_options) = '' then '[]'::jsonb
            else field_value_options::jsonb
        end
    ) as opt
)

select * from options