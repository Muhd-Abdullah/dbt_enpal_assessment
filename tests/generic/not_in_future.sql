-- ---------------------------------------------------------------------
-- Generic test: not_in_future
--
-- Purpose:
--   - Ensure that date or timestamp values do not lie in the future
--   - Commonly used for event times, reporting periods, or completed activities
--
-- Parameters:
--   - model:
--       The model (table/view) being tested.
--   - column_name:
--       The date or timestamp column that must not contain future values.
--
-- Test logic:
--   - The test FAILS if any row exists where:
--       column_name IS NOT NULL
--       AND column_name > current_timestamp
--
-- Expected behavior:
--   - Returns zero rows when all values are <= current_timestamp → test PASSES
--   - Returns one or more rows when future-dated values exist → test FAILS
--
-- Example use case:
--   - Ensure reporting months are not future-dated:
--
--       tests:
--         - not_in_future:
--             arguments:
--               column_name: month
--
-- ---------------------------------------------------------------------

{% test not_in_future(model, column_name) %}
select *
from {{ model }}
where {{ column_name }} is not null
  and {{ column_name }} > current_timestamp
{% endtest %}
