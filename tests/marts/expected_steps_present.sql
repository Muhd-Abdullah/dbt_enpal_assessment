-- ---------------------------------------------------------------------
-- Singular test: expected_steps_present
--
-- Purpose:
--   - Ensure the final mart (rep_sales_funnel_monthly) contains ALL required
--     funnel steps and KPI names defined by the assessment task
--   - Prevent accidental removal/renaming of steps that would break downstream
--     dashboards and stakeholder expectations
--
-- Test logic (high-level):
--   1) Define the required (funnel_step, kpi_name) pairs in a small inline table
--   2) Extract the distinct (funnel_step, kpi_name) pairs that are actually present
--      in the mart output
--   3) Left join expected -> present and return any missing pairs
--
-- Expected behavior:
--   - Returns zero rows when all required steps are present → test PASSES
--   - Returns one or more rows (missing step pairs) → test FAILS
--
-- Rationale:
--   - rep_sales_funnel_monthly intentionally produces a complete grid of months × steps.
--     If any step disappears, it indicates a regression in:
--       * step_dim definition
--       * funnel event mapping (int_funnel_events)
--       * or the mart logic / schema changes
--
-- ---------------------------------------------------------------------

with expected(funnel_step, kpi_name) as (
  values
    ('Step 1: Lead Generation',              'Deals Created'),
    ('Step 2: Qualified Lead',               'Deals Qualified'),
    ('Step 2.1: Sales Call 1',               'Sales Call 1'),
    ('Step 3: Needs Assessment',             'Needs Assessment'),
    ('Step 3.1: Sales Call 2',               'Sales Call 2'),
    ('Step 4: Proposal/Quote Preparation',   'Proposals Prepared'),
    ('Step 5: Negotiation',                  'Deals in Negotiation'),
    ('Step 6: Closing',                      'Deals Closed'),
    ('Step 7: Implementation/Onboarding',    'Deals Onboarded'),
    ('Step 8: Follow-up/Customer Success',   'Customer Follow-up'),
    ('Step 9: Renewal/Expansion',            'Deals Renewal')
),
present as (
  select distinct funnel_step, kpi_name
  from {{ ref('rep_sales_funnel_monthly') }}
)
select e.*
from expected e
left join present p
  on e.funnel_step = p.funnel_step
 and e.kpi_name    = p.kpi_name
where p.funnel_step is null
