-- ---------------------------------------------------------------------
-- Staging model: stg_activity_types
--
-- Purpose:
--   - Load raw Pipedrive activity type definitions from postgres_public.activity_types
--   - Provide a lookup between activity type codes and human-readable names
--   - Surface configuration metadata required to classify activities into
--     funnel-related events (e.g. Sales Call 1, Sales Call 2)
--
-- Transformations:
--   - activity_type_id: cast to bigint for stable identification
--   - activity_type_code: trim whitespace and normalize empty strings to NULL
--   - activity_type_name: trim whitespace and normalize empty strings to NULL
--   - is_active: cast to boolean to indicate whether the activity type is currently active
--
-- Data quality tests (defined in _stg_schema.yml):
--   - activity_type_id:
--       * not_null (severity: warn)
--       * unique  (severity: warn)
--     Rationale: activity_type_id should uniquely identify an activity type,
--       but source data issues should not block the pipeline at staging level.
--
--   - activity_type_code:
--       * not_null (severity: warn)
--     Rationale: activity_type_code is required to join activities to their type definitions.
--
--   - is_active (configuration awareness):
--       * required call-related activity types must exist and be active:
--           - meeting (Sales Call 1)
--           - sc_2    (Sales Call 2)
--       * enforced via generic test activity_type_is_active (severity: warn)
--     Rationale: staging should surface configuration issues (e.g. deactivated
--       activity types) without failing the pipeline; stricter enforcement
--       happens in the intermediate layer.
--
-- ---------------------------------------------------------------------

with source as (
  select * from {{ source('postgres_public', 'activity_types') }}
)

select
  cast(id as bigint) as activity_type_id,
  nullif(trim(cast(type as varchar)), '') as activity_type_code,
  nullif(trim(cast(name as varchar)), '') as activity_type_name,
  cast(active as boolean) as is_active
from source