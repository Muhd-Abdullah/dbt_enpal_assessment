-- ---------------------------------------------------------------------
-- Singular test: rows_per_month
--
-- Purpose:
--   - Ensure that each month in the final mart (rep_sales_funnel_monthly)
--     contains exactly one row per required funnel step
--   - Validate that the month × funnel step grid is complete and stable
--
-- Test logic:
--   - Group the mart output by month
--   - Count the number of rows per month
--   - The test FAILS if any month does NOT have exactly 11 rows
--     (one for each required funnel step)
--
-- Expected behavior:
--   - Returns zero rows when every month has exactly 11 funnel steps → test PASSES
--   - Returns one or more rows when a month has missing or extra steps → test FAILS
--
-- Rationale:
--   - rep_sales_funnel_monthly is designed to produce a fixed schema:
--       11 funnel steps per month, regardless of activity
--   - Deviations indicate a regression in:
--       * step_dim definition
--       * month spine generation
--       * join logic between grid and events
--
-- ---------------------------------------------------------------------

select
  month,
  count(*) as rows_in_month
from {{ ref('rep_sales_funnel_monthly') }}
group by 1
having count(*) <> 11
