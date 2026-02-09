-- ---------------------------------------------------------------------
-- Generic test: activity_type_is_active
--
-- Purpose:
--   - Ensure a specific activity type code exists and is active
--   - Used to guarantee KPI-critical activity types (e.g. meeting, sc_2)
--     are not disabled in Pipedrive configuration
--
-- Parameters:
--   - model:
--       The model being tested.
--   - code_column:
--       Column containing the activity type code (e.g. activity_type_code).
--   - required_code:
--       The activity type code that must exist and be active (e.g. 'meeting').
--   - active_column:
--       Column indicating active status (default: is_active).
--
-- Test logic:
--   - FAIL if the required_code is missing OR present but not active (false/null)
--   - Returns a consistent result shape for both failure cases
--
-- ---------------------------------------------------------------------

{% test activity_type_is_active(model, code_column, required_code, active_column='is_active') %}

with matching as (

  -- Find the required activity type row (case-insensitive).
  select
    {{ code_column }} as activity_type_code,
    {{ active_column }} as is_active
  from {{ model }}
  where lower({{ code_column }}) = lower('{{ required_code }}')

)

-- Case 1: code exists but is inactive / null
select
  activity_type_code,
  is_active,
  'inactive_or_null' as failure_reason
from matching
where is_active is distinct from true

union all

-- Case 2: code does not exist at all
select
  '{{ required_code }}' as activity_type_code,
  null::boolean as is_active,
  'missing_required_code' as failure_reason
where not exists (select 1 from matching)

{% endtest %}
