-- ---------------------------------------------------------------------
-- Singular test: month_check
--
-- Purpose:
--   - Validate that the `month` column in int_funnel_events is correctly
--     normalized to the first day of the month
--   - Enforce a consistent monthly grain for downstream aggregation and reporting
--
-- Test logic:
--   - The test FAILS if any row exists where:
--       * month IS NOT NULL
--       * AND month is NOT equal to date_trunc('month', month)::date
--
-- Expected behavior:
--   - Returns zero rows when all month values are properly normalized → test PASSES
--   - Returns one or more rows when month values are not month-aligned → test FAILS
--
-- Rationale:
--   - int_funnel_events is the canonical monthly event table.
--   - If month values are not aligned to the first day of the month, it can:
--       * break grouping logic
--       * cause duplicate or missing rows in the mart layer
--       * lead to inconsistent reporting across models
--
-- ---------------------------------------------------------------------

select *
from {{ ref('int_funnel_events') }}
where month is not null
  and month <> date_trunc('month', month)::date
