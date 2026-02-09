-- ---------------------------------------------------------------------
-- Singular test: exclude_duplicate_entry_deals
--
-- Purpose:
--   - Ensure that deals whose FINAL lost reason is "Duplicate entry" are fully
--     excluded from the canonical funnel event table (int_funnel_events)
--   - Prevent operational duplicate deals from inflating funnel counts in reporting
--
-- Test logic (high-level):
--   1) Identify the latest (final) lost_reason per deal using change_time ordering
--   2) Filter deals where the final lost_reason_label = 'duplicate entry'
--   3) Check whether any of those deals still appear in int_funnel_events
--   4) Return leaked deal_ids (any returned rows = test failure)
--
-- Expected behavior:
--   - Returns zero rows when exclusion logic works correctly → test PASSES
--   - Returns one or more deal_ids when excluded deals leaked → test FAILS
--
-- Rationale:
--   - Pipedrive exports can include operational duplicates marked with lost_reason
--     "Duplicate entry". These should not be counted in funnel KPIs.
--   - The exclusion is applied in int_funnel_events; this test verifies that
--     the business rule is enforced end-to-end.
--
-- ---------------------------------------------------------------------


with lost_reason_ranked as (
  -- Rank lost_reason events so rn=1 is the latest per deal.
  -- Required because lost_reason can change over time and we only want the FINAL state.
  select
    deal_id,
    change_time,
    lost_reason_label,
    row_number() over (
      partition by deal_id
      order by change_time desc
    ) as rn
  from {{ ref('int_deal_changes_dedup_enriched') }}
  where changed_field_key = 'lost_reason'
    and lost_reason_label is not null
),
final_duplicate_deals as (
  -- Deals whose FINAL (latest) lost reason label is "duplicate entry".
  -- These deals must be excluded from funnel KPIs.
  select deal_id
  from lost_reason_ranked
  where rn = 1
    and lower(lost_reason_label) = 'duplicate entry'
),
leaks as (
  -- Any overlap between excluded deals and int_funnel_events indicates leakage,
  -- meaning exclusion logic did not fully remove the duplicate deals.
  select distinct f.deal_id
  from {{ ref('int_funnel_events') }} f
  join final_duplicate_deals d
    on f.deal_id = d.deal_id
)
select *
from leaks
