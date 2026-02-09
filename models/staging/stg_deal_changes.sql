-- ---------------------------------------------------------------------
-- Staging model: stg_deal_changes
--
-- Purpose:
--   - Load raw Pipedrive deal change history from postgres_public.deal_changes
--   - Capture all historical changes applied to deals (e.g. stage changes,
--     lost reason updates, custom field updates)
--   - Serve as the foundational event log for funnel reconstruction
--
-- Transformations:
--   - deal_id: cast to bigint for consistent joins across all deal-based models
--   - change_time: cast to timestamp to support temporal ordering and aggregation
--   - changed_field_key: trim whitespace and normalize empty strings to NULL
--   - new_value: trim whitespace and normalize empty strings to NULL
--
-- Data quality tests:
--   - deal_id:
--       * not_null (severity: warn)
--     Rationale: every change record should be associated with a deal.
--
--   - change_time:
--       * not_null (severity: warn)
--     Rationale: change_time is required to order events and assign them to months.
--
--   - changed_field_key:
--       * not_null (severity: warn)
--     Rationale: identifies which deal attribute was changed
--     (e.g. stage_id, lost_reason, custom fields).
--
-- ---------------------------------------------------------------------

with source as (
  select * from {{ source('postgres_public', 'deal_changes') }}
)

select
  cast(deal_id as bigint) as deal_id,
  cast(change_time as timestamp) as change_time,
  nullif(trim(cast(changed_field_key as varchar)), '') as changed_field_key,
  nullif(trim(cast(new_value as varchar)), '') as new_value
from source
