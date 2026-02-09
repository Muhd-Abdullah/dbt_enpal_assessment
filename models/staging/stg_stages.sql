-- ---------------------------------------------------------------------
-- Staging model: stg_stages
--
-- Purpose:
--   - Load raw Pipedrive stages data from the postgres_public.stages source
--   - Apply light standardization (types + string cleanup) only
--
-- Transformations:
--   - stage_id: cast to int for consistent joins with deal_changes / stage mapping tables
--   - stage_name: trim whitespace and normalize empty strings to NULL
--
-- Data quality tests:
--   - stage_id:
--       * not_null (severity: warn)
--       * unique  (severity: warn)
--     Rationale: stage_id should behave as a stable primary key for pipeline stages.
--
--   - stage_name:
--       * not_null (severity: warn)
--     Rationale: stage_name is required for readable funnel step mapping and reporting.
--
-- ---------------------------------------------------------------------

with source as (
  select * from {{ source('postgres_public', 'stages') }}
)

select
  cast(stage_id as int) as stage_id,
  nullif(trim(cast(stage_name as varchar)), '') as stage_name
from source