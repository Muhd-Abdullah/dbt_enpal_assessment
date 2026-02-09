-- ---------------------------------------------------------------------
-- Staging model: stg_fields
--
-- Purpose:
--   - Load raw Pipedrive fields metadata from the postgres_public.fields source
--   - Expose field definitions and enumerations for downstream lookups
--
-- Transformations:
--   - field_id: cast to bigint for stable identification and joins
--   - field_key: trim whitespace and normalize empty strings to NULL
--   - field_name: trim whitespace and normalize empty strings to NULL
--   - field_value_options: cast to varchar to preserve raw JSON / text structure
--
-- Data quality tests:
--   - field_id:
--       * not_null (severity: warn)
--       * unique  (severity: warn)
--     Rationale: field_id uniquely identifies a field definition in Pipedrive.
--
--   - field_key:
--       * not_null (severity: warn)
--     Rationale: field_key is required to identify fields programmatically
--     (e.g. stage_id, lost_reason, custom CRM fields).
--
-- ---------------------------------------------------------------------

with source as (
  select * from {{ source('postgres_public', 'fields') }}
)

select
  cast("id" as bigint) as field_id,
  nullif(trim(cast("field_key" as varchar)), '') as field_key,
  nullif(trim(cast("name" as varchar)), '') as field_name,
  cast("field_value_options" as varchar) as field_value_options
from source