-- ---------------------------------------------------------------------
-- Mart model: rep_sales_funnel_monthly
--
-- Purpose:
--   - Produce the final monthly sales funnel report at grain:
--       1 row per (month, kpi_name, funnel_step)
--   - Ensure a complete and stable output shape by creating a full grid of:
--       every month × every required funnel step
--   - Populate deals_count using int_funnel_events (distinct deals per step per month),
--     defaulting to 0 when no events occurred (required for reporting completeness)
--
-- Transformations:
--   - Define the required funnel steps + KPI names as a small in-model dimension (step_dim)
--   - Build a month spine (month_dim) from observed months in int_funnel_events
--   - Aggregate actual observed events into counts (events)
--   - Create a complete month × step grid (grid)
--   - Left join counts onto the grid and coalesce missing counts to 0
--
-- Data quality tests:
--   - Model-level:
--       * unique on (month, kpi_name, funnel_step) (severity: error)
--     Rationale: prevents duplicate rows and guarantees correct grain.
--
--   - month:
--       * not_null (severity: error)
--       * not_in_future (severity: error)
--     Rationale: monthly reporting must have a valid month and should not include future months
--       (int_funnel_events is based on completed events).
--
--   - kpi_name:
--       * not_null (severity: error)
--   - funnel_step:
--       * not_null (severity: error)
--   - deals_count:
--       * not_null (severity: error)
--       * (non-negative check) (severity: error)
--     Rationale: deals_count is intentionally allowed to be 0 because we create a full grid;
--       however it must never be negative.
--
-- Notes:
--   - This mart intentionally contains 0s for missing month/step combinations.
--     This is by design to keep dashboards stable and comparable across months.
-- ---------------------------------------------------------------------
with step_dim as (
    -- Static funnel step dimension required by the task:
    -- Defines:
    --   - funnel_step_order (for ordering)
    --   - funnel_step (output label)
    --   - kpi_name (business-friendly metric name)
    --
    -- Keeping this explicit ensures the mart always returns the required steps,
    -- even if certain steps have no events in some months.
    select * from (
        values
          (1.0, 'Step 1: Lead Generation',              'Deals Created'),
          (2.0, 'Step 2: Qualified Lead',               'Deals Qualified'),
          (2.1, 'Step 2.1: Sales Call 1',               'Sales Call 1'),
          (3.0, 'Step 3: Needs Assessment',             'Needs Assessment'),
          (3.1, 'Step 3.1: Sales Call 2',               'Sales Call 2'),
          (4.0, 'Step 4: Proposal/Quote Preparation',   'Proposals Prepared'),
          (5.0, 'Step 5: Negotiation',                  'Deals in Negotiation'),
          (6.0, 'Step 6: Closing',                      'Deals Closed'),
          (7.0, 'Step 7: Implementation/Onboarding',    'Deals Onboarded'),
          (8.0, 'Step 8: Follow-up/Customer Success',   'Customer Follow-up'),
          (9.0, 'Step 9: Renewal/Expansion',            'Deals Renewal')
    ) as t(funnel_step_order, funnel_step, kpi_name)
),

month_dim as (
    -- Month spine:
    -- We derive all months from int_funnel_events so the mart only includes months
    -- where at least one funnel event exists (no artificial future months).
    select distinct month
    from {{ ref('int_funnel_events') }}
),

events as (
    -- Aggregate observed funnel events:
    -- Count distinct deals by (month, funnel_step_order).
    -- funnel_step_order is used as the join key since the final labels come from step_dim.
    select
        month,
        funnel_step_order,
        count(distinct deal_id) as deals_count
    from {{ ref('int_funnel_events') }}
    group by 1,2
),

grid as (
    -- Complete output grid:
    -- Cross join ensures every month has every required funnel step.
    -- This is required so that missing steps appear as 0 instead of missing rows.
    select
        m.month,
        s.kpi_name,
        s.funnel_step,
        s.funnel_step_order
    from month_dim m
    cross join step_dim s
)

select
    g.month,
    g.kpi_name,
    g.funnel_step,
    coalesce(e.deals_count, 0) as deals_count
from grid g
left join events e
  on e.month = g.month
 and e.funnel_step_order = g.funnel_step_order
order by g.month, g.funnel_step_order
