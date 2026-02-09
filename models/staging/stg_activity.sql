-- ---------------------------------------------------------------------
-- Staging model: stg_activity
--
-- Purpose:
--   - Load raw Pipedrive activity data from postgres_public.activity
--   - Represent all activities associated with deals (e.g. calls, meetings)
--   - Serve as the event source for call-related funnel steps
--     (Sales Call 1, Sales Call 2)
--
-- Transformations:
--   - activity_id: cast to bigint for stable activity identification
--   - activity_type_code: trim whitespace and normalize empty strings to NULL
--   - assigned_to_user_id: cast to bigint for joins to stg_users
--   - deal_id: cast to bigint for joins to deal-level models
--   - is_done: cast to boolean to distinguish completed vs planned activities
--   - due_date: cast to date for time-based aggregation if required
--
-- Data quality tests:
--   - activity_id:
--       * not_null (severity: warn)
--       * unique  (severity: warn)
--     Rationale: activity_id uniquely identifies an activity in Pipedrive.
--
--   - deal_id:
--       * not_null (severity: warn)
--     Rationale: activities are expected to be associated with a deal
--     for funnel and performance analysis.
--
--   - activity_type_code:
--       * not_null (severity: warn)
--     Rationale: required to classify activities (e.g. meeting, sc_2).
--
-- ---------------------------------------------------------------------

with source as (
  select * from {{ source('postgres_public', 'activity') }}
)

select
  cast(activity_id as bigint) as activity_id,
  nullif(trim(cast(type as varchar)), '') as activity_type_code,
  cast(assigned_to_user as bigint) as assigned_to_user_id,
  cast(deal_id as bigint) as deal_id,
  cast(done as boolean) as is_done,
  cast(due_to as date) as due_date
from source
