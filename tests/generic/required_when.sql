-- ---------------------------------------------------------------------
-- Generic test: requires_when
--
-- Purpose:
--   - Enforce conditional data requirements within a model
--   - Validate that when a given condition is true, another condition
--     must also be satisfied
--   - Commonly used to enforce logical consistency between columns
--     (e.g. source-dependent requirements)
--
-- Parameters:
--   - model:
--       The model (table/view) being tested.
--   - condition_sql:
--       A SQL boolean expression defining when the requirement applies.
--   - required_sql:
--       A SQL boolean expression that must be true when condition_sql is true.
--
-- Test logic:
--   - The test FAILS if any row exists where:
--       condition_sql evaluates to TRUE
--       AND required_sql evaluates to FALSE
--
-- Expected behavior:
--   - Returns zero rows when all conditional requirements are satisfied → test PASSES
--   - Returns one or more rows when conditional rules are violated → test FAILS
--
-- Example use cases:
--   - Ensure call funnel steps come from activity events:
--
--       tests:
--         - requires_when:
--             arguments:
--               condition_sql: "funnel_step in ('Step 2.1: Sales Call 1','Step 3.1: Sales Call 2')"
--               required_sql: "event_source = 'activity'"
--
--   - Ensure stage-based steps always have an event_time:
--
--       tests:
--         - requires_when:
--             arguments:
--               condition_sql: "event_source = 'stage_change'"
--               required_sql: "event_time is not null"
--
-- ---------------------------------------------------------------------

{% test requires_when(model, condition_sql, required_sql) %}
select *
from {{ model }}
where ({{ condition_sql }})
  and not ({{ required_sql }})
{% endtest %}
