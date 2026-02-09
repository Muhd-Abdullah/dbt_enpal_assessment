-- ---------------------------------------------------------------------
-- Singular test: new_value_as_int
--
-- Purpose:
--   - Validate that `new_value` in int_deal_changes_dedup_enriched contains
--     only numeric values when present
--   - Ensure `new_value` can be safely cast to integer (new_value_id)
--     without runtime errors or silent data corruption
--
-- Test logic:
--   - The test FAILS if any row exists where:
--       * new_value IS NOT NULL
--       * AND new_value does NOT match the numeric regex '^[0-9]+$'
--
-- Expected behavior:
--   - Returns zero rows when all non-null new_value entries are numeric → test PASSES
--   - Returns one or more rows when non-numeric values are present → test FAILS
--
-- Rationale:
--   - int_deal_changes_dedup_enriched relies on casting new_value to int
--     (new_value_id) for joins to stage and lost reason lookup tables.
--   - Non-numeric values would:
--       * break enrichment joins
--       * cause incorrect funnel attribution
--       * potentially fail incremental runs
--
--
-- ---------------------------------------------------------------------

select *
from {{ ref('int_deal_changes_dedup_enriched') }}
where new_value is not null
  and new_value !~ '^[0-9]+$'
