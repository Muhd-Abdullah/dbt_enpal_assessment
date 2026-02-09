-- ---------------------------------------------------------------------
-- Macro: incremental_lookback
--
-- Purpose:
--   - Provide a reusable rolling lookback window for incremental models
--   - Used to reprocess a small, recent slice of data to capture:
--       * late-arriving records
--       * corrected timestamps
--       * updates in source systems (e.g. Pipedrive exports)
--
-- Parameters:
--   - days (integer, default = 7):
--       Number of days to look back from the current date.
--
-- Returns:
--   - A SQL expression representing:
--       current_date - interval '<days> days'
--
--
-- ---------------------------------------------------------------------

{% macro incremental_lookback(days=7) %}
  (current_date - ({{ days }} * interval '1 day'))
{% endmacro %}