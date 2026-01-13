# WASH Analytics Engineering (dbt + Snowflake)

Contract-first analytics engineering project modelling Kobo-style WASH survey data in **Snowflake** using **dbt**.

This repo is intentionally “production-shaped”: it assumes the RAW tables already exist in Snowflake, and focuses on what an analytics engineer does next — standardise, validate, quarantine, integrate, publish marts, and monitor.

If you’re a hiring manager: this is the kind of repo you can skim quickly and still understand the modelling choices, KPI contract, and how I keep the data trustworthy.

---

## Table of contents

- [What this repo is](#what-this-repo-is)
- [The data domain](#the-data-domain)
- [Repository structure](#repository-structure)
- [Architecture overview](#architecture-overview)
- [Modelling principles](#modelling-principles)
- [Key contracts](#key-contracts)
- [Published marts](#published-marts)
- [Snapshots (SCD2 history)](#snapshots-scd2-household-history)
- [Monitoring and triage](#monitoring-and-triage)
- [How to run](#how-to-run)
- [How to review changes](#how-to-review-changes)
- [What I’d do next](#what-id-do-next)
- [Licence](#licence)

---

## What this repo is

Survey data breaks in predictable ways:
- repeated submissions over time
- inconsistent categoricals (`tapstand` vs `public_tap_standpipe`)
- missing keys and orphan foreign keys
- “unknown” answers that are meaningful (especially for health outcomes)
- soft-deleted records that should not flow downstream

This project shows how I deal with that as an analytics engineer:

1) define the rules explicitly (contracts + canonical sets + KPI definition)  
2) enforce them in staging (typed, canonicalised, deduped, tested)  
3) quarantine bad records while keeping them inspectable (`__rejected`)  
4) build intermediate integration models with stable grains  
5) publish marts that BI tools can use without rebuilding KPI logic  
6) create monitoring tables so debugging is fast and repeatable  

---

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

Important detail:
- household data is **event-scoped**, not a master registry
- the same `household_id` can appear across multiple submissions (updates, re-visits, surveys over time)

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

---

## Architecture overview

### High level flow

```mermaid
flowchart LR
  RAW[(Snowflake RAW tables)]
  STG[dbt STAGING\nstg_*]
  INT[dbt INTERMEDIATE\nint_*]
  MARTS[dbt MARTS\ndim_ / fact_]
  MON[dbt MONITORING\nmon_*]
  SNAP[dbt SNAPSHOTS\nSCD2 history]

  RAW --> STG --> INT --> MARTS
  STG --> MON
  INT --> MON
  MARTS --> MON
  INT --> SNAP
```

### What each layer is responsible for

```mermaid
flowchart TB
  A[RAW\n"As received"] --> B[STAGING\n"Make it usable"]
  B --> C[INTERMEDIATE\n"Make it analytic"]
  C --> D[MARTS\n"Make it BI-ready"]
  B --> E[REJECTED\n"Keep bad rows inspectable"]
  E --> F[MONITORING\n"Track what broke and why"]
  C --> G[SNAPSHOTS\n"SCD2 history for household attributes"]

  classDef layer fill:#111827,stroke:#9CA3AF,color:#E5E7EB;
  class B,C,D,E,F,G layer;
```

---

## Modelling principles

### 1) Contract-first
- Canonical sets define what values are allowed downstream.
- KPI rules are written once (contract + macros) and enforced via dbt tests.

### 2) Join-safe grains
Every model declares a grain and enforces it (unique tests / composite uniqueness).
- if a model is meant to be 1 row per key, it must prove it

### 3) Deterministic transformations
- safe casting
- trimming/lowercasing strings
- standardised timestamps
- dedupe ordering based on lineage (`record_loaded_at`, plus a tie-breaker)

### 4) Accountability 
- `store_failures` enabled so failures land in audit tables
- `__rejected` models retain bad rows for inspection and replay

### 5) Monitoring is part of the system
If a stakeholder asks “why did the KPI drop yesterday?”, I want monitoring tables that answer it without reading compiled SQL.

---

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

Reason:
- it is deterministic and always present for warehouse-side reporting in this setup

---

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

---

## Published marts

### `fact_household_wash_event`
Purpose:
- KPI-ready household-event table for safe drinking water reporting.

Grain:
- `household_id × submission_id`

Guaranteed slicers:
- `ward_id`
- `event_date`

Eligibility:
- `member_count >= 1`

Contract invariant (enforced by tests):
- `is_safe_drinking = has_safe_primary_source AND has_safe_water_filter AND has_no_diarrhoea_14d_members`

---

### `fact_agg_safe_drinking_ward_day`
Purpose:
- daily ward-level aggregate so BI tools don’t have to rebuild KPI logic.

Grain:
- `ward_id × event_date`

Must always be true:
- `household_events_safe <= household_events_total`
- `pct_safe between 0 and 1`

---

### `dim_household_current`
Purpose:
- current household attributes (latest known values), built as a “current view” of event-scoped household captures.

Grain:
- `household_id`

Usage note:
- joining event facts to current dim answers **current state** questions  
- it does not represent historical attribute values at the time of each event unless you do a point-in-time join via the snapshot table

---

## Snapshots (SCD2 household history)

This repo includes a dbt snapshot to track household attribute changes over time.

### What it’s for
- keep history of attribute changes (filter type, source type, toilet status, reported size, and location fields)
- enable point-in-time analysis when needed

### How it fits

```mermaid
flowchart LR
  INT[int_household_current_source] --> SNAP[snap_dim_household_current\nSCD2 history]
  SNAP --> DIMV[dim_household_current\n(current view over snapshot)]
```

Operationally:
- new RAW arrives
- you run dbt models (stg/int/marts)
- you run `dbt snapshot`
- snapshot compares current source rows and inserts new SCD2 versions when changes occur

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

So if someone changes:
- canonical sets
- safe lists
- diarrhoea rollup logic
- time basis

…the PR should include:
- contract update
- macro update (if applicable)
- test update (so drift is caught immediately)

---

## What I’d do next

- CI/CD with `dbt build` + tests on PRs (selectors + slim CI)
- environment separation (dev/test/prod)
- documentation site generation (dbt docs + links to contracts)
- alerting thresholds for monitoring (rejection spikes, unknown diarrhoea spikes)

---

## Licence

MIT
