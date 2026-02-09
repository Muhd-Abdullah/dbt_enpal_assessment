-- ---------------------------------------------------------------------
-- Singular test: event_source_validation
--
-- Purpose:
--   - Validate that every row in int_funnel_events has a valid event_source
--   - Enforce that funnel events originate only from the two supported sources:
--       * stage_change  → pipeline stage transitions
--       * activity      → completed sales call activities
--
-- Test logic:
--   - The test FAILS if any row exists where:
--       * event_source IS NULL
--         OR
--       * event_source NOT IN ('stage_change', 'activity')
--
-- Expected behavior:
--   - Returns zero rows when all event_source values are valid → test PASSES
--   - Returns one or more rows when invalid or missing values exist → test FAILS
--
-- Rationale:
--   - int_funnel_events is a canonical event table used for reporting.
--   - Introducing unexpected event_source values would break:
--       * conditional logic (requires_when tests)
--       * funnel step attribution
--       * downstream aggregations in the mart layer
--
-- ---------------------------------------------------------------------

select *
from {{ ref('int_funnel_events') }}
where event_source is null
   or event_source not in ('stage_change','activity')
