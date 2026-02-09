-- ---------------------------------------------------------------------
-- Generic test: has_value_in_column
--
-- Purpose:
--   - Validate that a required value exists at least once in a given column
--   - Commonly used to assert presence of mandatory configuration keys,
--     enum values, or metadata rows (e.g. required field_key entries)
--
-- Parameters:
--   - model:
--       The model (table/view) being tested.
--   - field_key_column:
--       The column in which the required value should appear.
--   - required_key:
--       The expected value that must exist at least once in the column.
--
-- Test logic:
--   - The test FAILS if NO row exists where:
--       lower(field_key_column) = lower(required_key)
--   - Case-insensitive comparison is used to avoid failures due to casing
--     differences in source systems.
--
-- Expected behavior:
--   - Returns zero rows when the required value exists → test PASSES
--   - Returns one row when the required value is missing → test FAILS
--
-- Example use case:
--   - Ensure required field metadata is present:
--
--       tests:
--         - has_value_in_column:
--             arguments:
--               field_key_column: field_key
--               required_key: stage_id
--
-- Notes:
--   - This test checks existence only, not uniqueness or correctness of
--     additional attributes.
--   - Intended for metadata/configuration validation rather than fact tables.
--
-- ---------------------------------------------------------------------

{% test has_value_in_column(model, field_key_column, required_key) %}
select 1
where not exists (
  select 1
  from {{ model }}
  where lower({{ field_key_column }}) = lower('{{ required_key }}')
)
{% endtest %}
