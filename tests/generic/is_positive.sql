-- ---------------------------------------------------------------------
-- Generic test: is_positive
--
-- Purpose:
--   - Ensure that a numeric column never contains negative values
--   - Commonly used for counts, amounts, or metrics where negatives
--     are logically invalid (e.g. deal counts, event counts)
--
-- Parameters:
--   - model:
--       The model (table/view) being tested.
--   - column_name:
--       The numeric column that must be non-negative.
--
-- Test logic:
--   - The test FAILS if any row exists where:
--       column_name IS NOT NULL
--       AND column_name < 0
--
-- Expected behavior:
--   - Returns zero rows when all values are >= 0 → test PASSES
--   - Returns one or more rows when negative values exist → test FAILS
--
-- Important note on naming:
--   - Despite the name "is_positive", this test enforces NON-NEGATIVE (>= 0),
--     not strictly positive (> 0).
--   - This is intentional and aligns with use cases where zero is valid
--     (e.g. monthly funnel steps with no events).
--
-- Example use case:
--   - Validate that aggregated counts in reporting models never go below zero:
--
--       tests:
--         - is_positive:
--             arguments:
--               column_name: deals_count
--
-- ---------------------------------------------------------------------

{% test is_positive(model, column_name) %}
select *
from {{ model }}
where {{ column_name }} is not null
  and {{ column_name }} < 0
{% endtest %}
