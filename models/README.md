# Sales Funnel Analytics – dbt Models

## Overview

This project implements a **monthly sales funnel reporting model** based on **Pipedrive CRM data**, using **dbt** with a layered architecture:

- **Staging**: light cleaning and standardization of raw data  
- **Intermediate**: deduplication, enrichment, and business-rule enforcement  
- **Mart**: final reporting model for analytics and dashboards  

The final output model is:
rep_sales_funnel_monthly
(month, kpi_name, funnel_step, deals_count)

It reports **monthly deal counts** across all required funnel steps, including sales calls, with explicit handling of dirty data and operational duplicates.

---

## Folder Structure
```text
models/
├── staging/
│ ├── stg_users.sql
│ ├── stg_activity.sql
│ ├── stg_activity_types.sql
│ ├── stg_deal_changes.sql
│ ├── stg_fields.sql
│ ├── stg_stages.sql
│ └── _stg_schema.yml
│
├── intermediate/
│ ├── int_activity_dedup_enriched.sql
│ ├── int_deal_changes_dedup_enriched.sql
│ ├── int_stage_lookup_from_fields.sql
│ ├── int_reason_lost_lookup_from_fields.sql
│ ├── int_funnel_events.sql
│ └── _int_schema.yml
│
├── marts/
│ ├── rep_sales_funnel_monthly.sql
│ └── _mart_schema.yml
│
├── sources.yml
└── README.md
```
Supporting folders:

```text
macros/
└── incremental_lookback.sql

tests/
├── generic/
├── intermediate/
└── marts/
```
---

## Data Sources (Pipedrive)

All data originates from **Pipedrive CRM exports**:

| Source Table | Description |
|--------------|-------------|
| users | Sales users / owners |
| activity | Deal-related activities |
| activity_types | Activity configuration and status |
| deal_changes | Historical change log (stages, lost reason) |
| stages | Pipeline stage dimension |
| fields | Metadata and option enumerations |

Key characteristics of Pipedrive data:
- Stage history exists only as a **change log**
- Activity types can be activated/deactivated over time
- Duplicate deals exist and are flagged via lost reasons
- Metadata-driven configuration via JSON fields

---

## Assumptions

This project makes a set of explicit, data-driven assumptions based on observed **Pipedrive CRM behavior** and validation of the extracted datasets. These assumptions are documented to ensure transparency, reproducibility, and auditability.

---

### 1. Pipedrive Required vs Optional Fields

Based on Pipedrive documentation and observed data behavior:

- **User email (`users.email`) is treated as a required field**
  - Pipedrive enforces email for user records
  - Validated using:
    - `not_null` and `matches_regex` tests
  - Tests are configured with **severity: warn** in staging to surface issues without blocking the pipeline

- **Activity due dates (`activity.due_date`) may be NULL**
  - Pipedrive allows activities without a scheduled or completed date
  - As a result:
    - `due_date` is not enforced as required in staging
    - Call-based funnel events only consider activities with non-null `due_date`
    - Null due dates are preserved in staging for observability

This distinction reflects **actual CRM constraints**, not idealized schemas.

---

### 2. Stage Source of Truth

Pipedrive exposes pipeline stages via two representations:

- `stages` table (canonical pipeline configuration)
- `fields.field_value_options` for `field_key = 'stage_id'` (metadata enumeration)

Observed data shows these two sources to be logically equivalent.

**Assumption**
- The `stages` table is treated as the **single source of truth** for:
  - stage identifiers
  - stage names
  - funnel step labeling

**Implementation**
- All stage-based funnel logic uses `stg_stages`
- A comparison model and tests exist between:
  - `stg_stages`
  - `int_stage_lookup_from_fields`
- Any divergence is surfaced as an **error** in the intermediate layer

This approach provides stability while still detecting configuration drift.

---

### 3. Activity vs Deal Stage Relationship

Analysis of the raw data shows **very limited overlap** between:

- deals appearing in `deal_changes` (stage transitions)
- deals appearing in `activity` (sales calls)

#### Assumptions derived from this observation

- **Sales call events are modeled independently of stage changes**
- Call-based funnel steps (**Sales Call 1** and **Sales Call 2**) are:
  - derived exclusively from the `activity` table
  - not required to have a corresponding stage change
- Activities are **not joined to stage events** when constructing funnel events

This prevents:
- unintended row loss
- undercounting valid call events
- bias caused by sparse cross-table overlap

---

### 4. No Sequential Dependency Between Sales Calls

Data inspection indicates that:

- **Sales Call 2 does not reliably occur after Sales Call 1**
- There is no consistent temporal dependency between:
  - `meeting` (Sales Call 1)
  - `sc_2` (Sales Call 2)

**Assumption**
- Sales Call 1 and Sales Call 2 are treated as **independent funnel events**

**Implementation**
- No ordering constraint is enforced between call steps
- Funnel step order (`2.1`, `3.1`) is used **only for reporting display**
- Counts are computed independently per month

This ensures funnel metrics reflect **observed CRM behavior**, not assumed sales processes.

---

### 5. Duplicate Deal Handling

**Assumption**
- Deals whose **final lost reason** is `"Duplicate entry"` represent operational duplicates
- These deals must not contribute to funnel KPIs

**Implementation**
- Final lost reason is determined as the **latest** `lost_reason` change by `change_time`
- Deals with final lost reason `"Duplicate entry"` are:
  - excluded in `int_funnel_events`
  - validated via a dedicated singular test

This guarantees duplicate deals never leak into reporting outputs.


---

## Design Principles

### Staging Layer Philosophy

**Goal:** reflect the source data as faithfully as possible.

- No business logic
- No filtering
- No deduplication
- Only:
  - type casting
  - trimming strings
  - normalizing empty strings to NULL

**Testing strategy**
- Mostly `severity: warn`
- Surface data issues early
- Do not block downstream models

---

### Intermediate Layer Philosophy

**Goal:** enforce correctness and business rules.

This layer:
- Deduplicates raw data
- Enriches records with lookups
- Filters invalid data
- Enforces critical assumptions

**Testing strategy**
- Mostly `severity: error`
- Fail fast if KPIs would become incorrect

---

## Key Intermediate Models

### `int_activity_dedup_enriched`

**Responsibilities**
- Enforce 1 row per `activity_id`
- Enrich activities with type metadata
- Provide clean activity events for funnel calls

**Critical assumption**
- Call KPIs depend on:
  - `meeting` → Sales Call 1
  - `sc_2` → Sales Call 2

**Enforcement**
- Activity types must exist and be active:
  - WARN in staging
  - ERROR in intermediate

---

### `int_deal_changes_dedup_enriched`

**Responsibilities**
- Filter to stage and lost reason changes
- Deduplicate exact duplicate change events
- Cast numeric values safely
- Enrich with stage and lost reason labels

**Why**
- Stage changes drive the funnel
- Lost reason determines exclusion logic

---

### `int_stage_lookup_from_fields`  
### `int_reason_lost_lookup_from_fields`

**Purpose**
- Parse Pipedrive field metadata (`field_value_options`)
- Produce lookup tables for stages and lost reasons

**Materialization**
- Views (small, deterministic, configuration-driven)

---

### `int_funnel_events`

**Purpose**
Create the canonical funnel event table at grain:
(deal_id, month, funnel_step)

**Event sources**

1. **Stage changes**
   - Derived from deal change history
   - Dynamic labeling: `Step <stage_id>: <stage_name>`

2. **Activity events**
   - Completed activities only (`is_done = true`)
   - Hard-coded steps:
     - Step 2.1: Sales Call 1
     - Step 3.1: Sales Call 2

**Duplicate deal exclusion**
- Deals with final `lost_reason = 'Duplicate entry'` are excluded
- Final = latest change by `change_time`
- Enforced by model logic and tests

---

## Final Mart

### `rep_sales_funnel_monthly`

**Grain**
(month, kpi_name, funnel_step)


**Key design choice**
- Full **month × funnel step grid**
- Missing combinations filled with `deals_count = 0`

**Why**
- Stable dashboards
- No missing rows
- Predictable schema

---

## Funnel Steps

| Order | Funnel Step | KPI Name |
|------:|-------------|----------|
| 1.0 | Step 1: Lead Generation | Deals Created |
| 2.0 | Step 2: Qualified Lead | Deals Qualified |
| 2.1 | Step 2.1: Sales Call 1 | Sales Call 1 |
| 3.0 | Step 3: Needs Assessment | Needs Assessment |
| 3.1 | Step 3.1: Sales Call 2 | Sales Call 2 |
| 4.0 | Step 4: Proposal/Quote Preparation | Proposals Prepared |
| 5.0 | Step 5: Negotiation | Deals in Negotiation |
| 6.0 | Step 6: Closing | Deals Closed |
| 7.0 | Step 7: Implementation/Onboarding | Deals Onboarded |
| 8.0 | Step 8: Follow-up/Customer Success | Customer Follow-up |
| 9.0 | Step 9: Renewal/Expansion | Deals Renewal |

---

## Testing Strategy Summary

### Staging
- Warn-only tests
- Visibility into dirty or unexpected data

### Intermediate
- Error-level tests
- Enforce business logic and assumptions

### Mart
- Strict correctness
- Guarantees:
  - Fixed number of steps per month
  - No negative counts
  - No future months
  - No missing funnel steps

---

## Duplicate Deal Handling

**Assumption**
- Deals with final `lost_reason = 'Duplicate entry'` are operational duplicates

**Implementation**
- Identified in deal change history
- Excluded in `int_funnel_events`
- Validated via singular test

This ensures duplicate deals never affect KPIs.

---

## Incremental Strategy

- Large intermediate models are incremental
- Reusable macro: `incremental_lookback(days=7)`
- Rolling window captures:
  - late-arriving updates
  - corrected timestamps
  - Pipedrive re-exports

---

## Final Notes

This project is designed to be:

- **Auditable** – assumptions are explicit and tested  
- **Fail-fast** – critical issues raise errors early  
- **Extensible** – new steps or activity types can be added cleanly  
- **Production-ready** – strict grain, contracts, and invariants  
