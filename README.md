# WASH: Analytics Engineering Project, Modelling Kobo-style survey data in Snowflake using dbt.

This repo is intentionally “production-shaped”. 

It assumes the RAW tables already exist in Snowflake, and focuses on what an analytics engineer does next — standardise, validate, quarantine, integrate, publish marts, and monitor.

## Problem Statement

A programme team running a Kobo-based WASH survey already had RAW tables landing in Snowflake, but they needed reporting that was consistent and explainable day to day. 

> The ask was straightforward: take what is arriving in RAW and turn it into something they can safely use for routine monitoring and decision-making.

They wanted one primary KPI they could trust and trend:

> [!IMPORTANT]
> Primary KPI: Safe drinking water by ward and day.

Additionally, they also wanted to answer practical questions when the numbers moved:

- What changed since the last survey round, and which wards are driving it?

- What kinds of issues are showing up most often in the field data collection (missing keys, invalid categoricals, orphan relationships, out-of-range values, unknown)?


## Workflow

I treated this as an analytics engineering problem. The goal was to make the KPI deterministic, auditable, and resilient to messy, event-scoped survey data.

<img width="878" height="396" alt="image" src="https://github.com/user-attachments/assets/05c5ab05-cb46-4823-be4a-c368abe52563" />


Here is the approach I followed:

1) **Stakeholder Alignment**
  To Lock down business meaning, so the KPI stays consistent.

   - Confirm what “safe drinking water” means in their programme context? What water sources and filtration methods are considered safe?
   - Agree on how to treat missing/“unknown” values, especially for KPI-critical fields and health outcomes.
   - Agree the reporting time basis that we can guarantee consistently in the warehouse.
   - Agree what should be excluded from downstream reporting.
   - Align on **late-arriving data** expectations and how far back is the lookback window.  
   - Define **survey versioning rules**. How value sets change between survery rounds are handeled, and how it is reported.  
   - Confirm output expectations: required tables, required dimensions, and what “success” looks like for reporting.

2) **Data definition**
   Make the KPI computable and repeatable by defining it in warehouse terms.

   - Fix the KPI grain.
   - Define the KPI **unit of analysis** and the primary key used for counting.  
   - Define which slicers must work everywhere and what “eligible” means for counting.
   - Define how to handle unknowns and missing values in KPI-critical fields.  
   - Define dedupe rules.  
   - Define any required time windows
   - Specify the output contract for the KPI table (expected columns, types, and meaning)

3) **Data contracts**
  Turn assumptions into versioned documentation to make changes intentional and reviewable

   - Document canonical value sets, values allowed downstream.
   - Document the “safe lists” that define the KPI.
   - Document the rollup rules, including strict tri-state handling.
   - Specify the contract for rejected/quarantined data.

4) **Build the dbt layers**
  Standardise, validate, quarantine, integrate, then publish marts that BI can use.

  <img width="878" height="658" alt="image" src="https://github.com/user-attachments/assets/f06d238a-04c7-4f6f-a4ba-277ff8fe3a0f" />


   - **Staging (`stg_`)** standardises types and categoricals, enforces grains, and generates DQ flags.
   - **Quarantine (`__rejected`)** keeps bad rows visible and replayable without letting them pollute marts.
   - **Intermediate (`int_`)** produces join-safe integration models and rollups at stable grains.
   - **Marts (`fact_` / `dim_`)** publish KPI-ready outputs so downstream dashboards stay simple and consistent.

5) **Monitoring and observability**  
   Add ongoing checks so data drift and quality issues show up early, not after dashboards break.  

   - Publish monitoring models for freshness, volume changes, and rejection rates by model/day.  
   - Track top rejection reasons (missing keys, invalid categoricals, orphan relationships, out-of-range values).  
   - Monitor “unknown” rates for KPI-critical fields so KPI movement is explainable.  
   - Surface these signals in CI and in warehouse tables so issues are caught before reporting.



The result is a KPI that is repeatable, auditable, and explainable: the definition is written down, enforced with tests, and supported by monitoring outputs so stakeholders can understand changes instead of guessing.


## The data domain

The RAW tables represent a Kobo-style form structure:

- `kobo_submission`  
  - grain: 1 row per `submission_id`
  - includes submission status, ward_id, location fields, timestamps, lineage

- `kobo_household`  
  - household section captured inside a submission (event-scoped)
  - households can appear in multiple submissions over time

- `kobo_member`  
  - repeat group for household members
  - grain is composite: `(household_id, submission_id, member_index)`

- `kobo_water_point`  
  - observations of water points
  - grain is composite: `(water_point_id, submission_id)` (depending on form design)

<img width="1313" height="641" alt="image" src="https://github.com/user-attachments/assets/7fe9e779-52ac-4f1c-b3e0-fd6988059e9a" />

---

## Repository structure

```
dataosphere/
  models/
    staging/           # stg_ models + __base and __rejected patterns
    intermediate/      # int_ integration and rollups
    marts/
      facts/           # KPI facts and aggregates
      dimentions/      # dimensions (current)
    monitoring/        # mon_ operational monitoring outputs
  snapshots/           # SCD2 snapshots (dbt snapshots)
  docs/
    data-contract.md
    monitoring-contract.md
```

## Key contracts

### Canonical value sets (enforced downstream)

- `stg_kobo_household.water_filter_type`
  - `none`, `boil`, `candle`, `chlorine`, `sodis`, `ceramic`, `biosand`, `cloth`, `ro_uv`, `other`, `unknown`

- `stg_kobo_household.primary_water_source` and `stg_kobo_water_point.source_type`
  - `piped_to_dwelling`, `piped_to_yard_plot`, `public_tap_standpipe`, `tubewell_borehole`,
    `protected_dug_well`, `unprotected_dug_well`, `protected_spring`, `unprotected_spring`,
    `rainwater`, `tanker_truck_cart`, `bottled_water`, `surface_water`, `other`, `unknown`

- `stg_kobo_member.member_sex`
  - `m`, `f`, `male`, `female`, `other`, `unknown`

- `stg_kobo_member.member_had_diarrhoea_14d` (tri-state)
  - `yes`, `no`, `unknown`
  - unknown is **not** treated as no (strict rule)

### Time basis

For this project’s reporting and monitoring:
- event timestamp: `record_loaded_at`
- event date: `event_date = DATE(record_loaded_at)`
- default reporting grain: `ward_id × event_date`
- timezone: treat as UTC (or convert before deriving date)


## KPI: Safe drinking water (household-event)

### KPI grain
- `household_id × submission_id`

### Input rules (safe lists)
Safe lists are version-controlled in macros:
- SAFE_PRIMARY_WATER_SOURCES
- SAFE_WATER_FILTER_TYPES

### Strict diarrhoea rule (tri-state)
At `household_id × submission_id`, compute:
- `member_count`
- `total_diarrhoea_yes_14d`
- `total_diarrhoea_no_14d`
- `total_diarrhoea_unknown_14d`

Consistency must hold:
- `member_count = yes + no + unknown`

Household is “no diarrhoea” only when:
- `member_count > 0`
- `yes = 0`
- `unknown = 0`
- `no = member_count`

Final KPI:
- `is_safe_drinking = safe_source AND safe_filter AND no_diarrhoea`


## Published marts

Repo structure (from `models/marts/`):
- `marts/dimensions/`
  - `dim_household_current.sql`
  - `dim_household_history.sql`
  - `dim_wash.yml` (docs + tests for dims)
- `marts/facts/`
  - `fact_household_wash_event.sql`
  - `fact_household_wash_event_enriched_scd2.sql`
  - `fact_agg_safe_drinking_ward_day.sql`
  - `fact_wash.yml` (docs + tests for facts)

---

### `fact_household_wash_event`
Purpose:
- KPI-ready household-event fact table used as the base for safe drinking water reporting.

Grain:
- `household_id × submission_id`

Guaranteed slicers:
- `ward_id`
- `event_date`

Eligibility:
- `member_count >= 1`

Contract invariant:
- `is_safe_drinking = has_safe_primary_source AND has_safe_water_filter AND has_no_diarrhoea_14d_members`

---

### `fact_household_wash_event_enriched_scd2`
Purpose:
- Event fact enriched with household attributes as-of the event date using SCD2 history (point-in-time correct).

Grain:
- `household_id`

---

### `fact_agg_safe_drinking_ward_day`
Purpose:
- Daily ward-level aggregate so BI tools do not have to rebuild KPI logic.

Grain:
- `ward_id × event_date`

Must always be true (enforced by tests):
- `household_events_safe <= household_events_total`
- `pct_safe between 0 and 1`

---

### `dim_household_current`
Purpose:
- Current household attributes (latest known values), built as a “current view” of event-scoped household captures.

Grain:
- `household_id`

---

### `dim_household_history`
Purpose:
- Household attribute history as an SCD2 dimension (tracks how household attributes change over time).

Grain:
- `household_id × valid_from` (SCD2-style history)

Usage note:
- Enables point-in-time joins (either directly, or via `fact_household_wash_event_enriched_scd2`).
- Useful for “what changed over time” analysis and cohort-style comparisons.

## Snapshots (SCD2 household history)

This repo includes a dbt snapshot to track household attribute changes over time.

### What it’s for
- keep history of attribute changes (filter type, source type, toilet status, reported size, and location fields)
- enable point-in-time analysis when needed

---

## Monitoring and triage

Monitoring models are intentionally small, simple, and sliceable.

### What exists

- `mon_total_by_model_day`
  - daily base row counts
  - grain: `base_model_name × event_date`

- `mon_rejections_by_model_day`
  - daily rejected row counts
  - grain: `base_model_name × event_date`

- `mon_rejection_rate_day`
  - rejection rate derived from totals + rejections
  - grain: `base_model_name × event_date`

- `mon_rejection_by_reason_day`
  - “why” slicer for rejected rows
  - grain: `base_model_name × event_date × reason_bucket`
  - standard buckets: `missing_keys`, `orphan_fk`, `invalid_required_field`, `invalid_canonical`, `invalid_range`, `unknown_other`, `soft_deleted`, `other`

- `mon_unknown_diarrhoea_rate_ward_day`
  - tracks diarrhoea completeness issues by ward/day
  - grain: `ward_id × event_date`

---

## How to run

Install packages:
```bash
dbt deps
```

Parse (fast sanity check):
```bash
dbt parse
```

Build + test staging first:
```bash
dbt build --select tag:staging
```

Build everything:
```bash
dbt build
```

Run snapshots:
```bash
dbt snapshot
```

Run only monitoring:
```bash
dbt build --select tag:monitoring
```

---

## How to review changes

This repo is designed to make changes reviewable:

- KPI definitions live in:
  - `docs/data-contract.md`
  - macros for safe lists
  - dbt tests that lock invariants

---

### CI on pull requests 
- On every PR to `master`, CI runs:
  - `dbt deps`
  - `dbt debug`
  - `dbt build` for selected layers (staging / intermediate / marts / monitoring)
- CI writes to an isolated Snowflake schema per PR:
  - `DBT_CI_PR_<pr_number>`
- CI uses an env-var driven dbt profile stored in `dataosphere/ci/` .

### Docs published to GitHub Pages
- On every push to `master`, the workflow generates dbt docs and publishes them to GitHub Pages.
- This keeps documentation always up to date with the latest merged definitions (models, tests, exposures, contracts).


## Licence

MIT
