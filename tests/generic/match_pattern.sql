-- ---------------------------------------------------------------------
-- Generic test: matches_regex
--
-- Purpose:
--   - Validate that column values match a required regular expression pattern
--   - Commonly used to enforce formatting rules (e.g. email addresses, codes)
--
-- Parameters:
--   - model:
--       The model (table/view) being tested.
--   - column_name:
--       The column whose values should be validated against the regex.
--   - regex:
--       The regular expression pattern values must match.
--   - allow_null (boolean, default = false):
--       Controls whether NULL values are considered valid.
--
-- Test logic:
--   - If allow_null = true:
--       * The test FAILS only when the column is NOT NULL
--         AND the value does NOT match the regex.
--
--   - If allow_null = false:
--       * The test FAILS when the column IS NULL
--         OR when the value does NOT match the regex.
--
-- Expected behavior:
--   - Returns zero rows when all values satisfy the regex rules → test PASSES
--   - Returns one or more rows when invalid values exist → test FAILS
--
-- Example use case:
--   - Enforce valid email format while disallowing NULLs:
--
--       tests:
--         - matches_regex:
--             arguments:
--               column_name: user_email
--               regex: '^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$'
--               allow_null: false
--
-- ---------------------------------------------------------------------

{% test matches_regex(model, column_name, regex, allow_null=false) %}
select *
from {{ model }}
where
  {% if allow_null %}
    {{ column_name }} is not null
    and {{ column_name }} !~ '{{ regex }}'
  {% else %}
    ({{ column_name }} is null) or ({{ column_name }} !~ '{{ regex }}')
  {% endif %}
{% endtest %}
