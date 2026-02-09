-- ---------------------------------------------------------------------
-- Staging model: stg_users
--
-- Purpose:
--   - Load raw Pipedrive users data from the postgres_public.users source
--   - Apply light standardization (types + string cleanup) only
--
-- Transformations:
--   - user_id: cast to bigint for consistent joins downstream
--   - user_name/user_email: trim whitespace and normalize empty strings to NULL
--   - modified_at: cast to timestamp for consistent temporal handling
--
-- Data quality tests:
--   - user_id:
--       * not_null (severity: warn)
--       * unique  (severity: warn)
--     Rationale: user_id is expected to behave like a stable primary key in staging.
--
--   - user_email:
--       * not_null (severity: warn)
--       * matches_regex email pattern (severity: warn, allow_null: false)
--     Rationale: Pipedrive has user_email as required field so this should not be null or wrong
--
-- ---------------------------------------------------------------------

with source as (
  select * from {{ source('postgres_public', 'users') }}
)

select
  cast(id as bigint) as user_id,
  nullif(trim(cast(name as varchar)), '') as user_name,
  nullif(trim(cast(email as varchar)), '') as user_email,
  cast(modified as timestamp) as modified_at
from source
