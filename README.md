[![dbt CI](https://github.com/psgpyc/survey-analytics-engineering-wash/actions/workflows/dbt-wash-ci.yml/badge.svg)](https://github.com/psgpyc/survey-analytics-engineering-wash/actions/workflows/dbt-wash-ci.yml)
[![dbt Docs Publish](https://github.com/psgpyc/survey-analytics-engineering-wash/actions/workflows/dbt-docs-pages.yml/badge.svg)](https://github.com/psgpyc/survey-analytics-engineering-wash/actions/workflows/dbt-docs-pages.yml)

[![dbt docs](https://img.shields.io/badge/dbt%20docs-live-brightgreen)](https://psgpyc.github.io/survey-analytics-engineering-wash/)


> Live dbt Docs: https://psgpyc.github.io/WASH-Analytics-Engineering-Project/

> Quick review guide: [How to review this repo](#how-to-review-this-repo)

# WASH: Analytics Engineering Project, Modelling Kobo-style survey data in Snowflake using dbt.

This repository is a production-shaped analytics engineering case study. 
It demonstrates how to take messy, semi-structured, late-arriving survey data and turn it into deterministic, auditable analytics outputs.

Specifically, this project demonstrates:

- Modelling semi-structured JSON survey submissions in Snowflake using dbt
- Designing analytics models that remain stable under late-arriving data
- Enforcing data contracts and quarantining invalid records instead of silently dropping them
- Publishing analytics-ready fact and dimension tables for BI consumption
- Monitoring data freshness, volume drift, and rejection rates over time

## Architecture overview

Raw Kobo-style JSON survey submissions land in a private, SSE-KMS encrypted S3 bucket. Events flow through SNS to SQS (with a DLQ), and Snowpipe auto-ingests the data into Snowflake RAW tables.

From there, dbt standardises and validates the data, quarantines bad rows, builds integrated intermediate models, publishes dimensional marts for BI, and ships monitoring models for freshness and data quality.

![WASH ARCHITECTURE DIAGRAM](./assets/wash-architecture-diag.svg)

## Problem Statement

A programme team running a Kobo-based WASH survey needed reporting that was consistent and explainable day to day.

Key challenges included:

- Late-arriving submissions due to poor connectivity in remote areas
- Schema drift and inconsistent value sets across survey versions
- Ambiguous KPI definitions implemented directly in BI tools
- Silent data quality failures that were hard to detect

> The ask was straightforward: take what is arriving in and turn it into something they can safely use for routine monitoring and decision-making.

They wanted one primary KPI they could trust and trend:

> Primary KPI: Safe drinking water by ward and day.

Additionally, they also wanted to answer practical questions when the numbers moved:

- What changed since the last survey round, and which ward(sectors) are driving it?

- What kinds of issues are showing up most often in the field data collection (missing keys, invalid categoricals, orphan relationships, out-of-range values, unknown)?

For context, WASH programmes span a broad set of interventions across water, sanitation, and hygiene (see UNHCR’s overview: https://www.unhcr.org/sens/introduction/module-5-wash/).  
In this project, I focus only on the drinking water slice of that domain — specifically safe water sources and household-level treatment/filters — because that is what the KPI is designed to measure.

## Workflow

I treated this as an analytics engineering problem. The goal was to make the KPI deterministic, auditable, and resilient to messy, event-scoped survey data.

Here is the approach I followed:

<img width="878" height="396" alt="image" src="https://github.com/user-attachments/assets/05c5ab05-cb46-4823-be4a-c368abe52563" />


1) **Stakeholder Alignment**

   - Confirm what “safe drinking water” means in their programme context? What water sources and filtration methods are considered safe?
   - Agree on how to treat missing/“unknown” values, especially for KPI-critical fields and health outcomes.
   - Agree the reporting time basis that we can guarantee consistently in the warehouse.
   - Agree what should be excluded from downstream reporting.
   - Align on **late-arriving data** expectations and how far back is the lookback window.  
   - Define **survey versioning rules**. How value sets change between survery rounds are handeled, and how it is reported.  
   - Confirm output expectations: required tables, required dimensions, and what “success” looks like for reporting.

2) **Data definition**

   - Fix the KPI grain.
   - Define the KPI **unit of analysis** and the primary key used for counting.  
   - Define which slicers must work everywhere and what “eligible” means for counting.
   - Define how to handle unknowns and missing values in KPI-critical fields.  
   - Define dedupe rules.  
   - Define any required time windows
   - Specify the output contract for the KPI table (expected columns, types, and meaning)

3) **Data contracts**

   - Document canonical value sets, values allowed downstream.
   - Document the “safe lists” that define the KPI.
   - Document the rollup rules, including strict tri-state handling.
   - Specify the contract for rejected/quarantined data.

4) **Build the dbt layers**

   <img width="659" height="526" alt="image" src="https://github.com/user-attachments/assets/02f84dc6-70c1-4661-adee-74f9ea75702a" />


   - **Staging (`stg_`)** standardises types and categoricals, enforces grains, and generates DQ flags.
   - **Quarantine (`__rejected`)** keeps bad rows visible and replayable without letting them pollute marts.
   - **Intermediate (`int_`)** produces join-safe integration models and rollups at stable grains.
   - **Marts (`fact_` / `dim_`)** publish KPI-ready outputs so downstream dashboards stay simple and consistent.

5) **Monitoring and observability**  

   - Publish monitoring models for freshness, volume changes, and rejection rates by model/day.  
   - Track top rejection reasons (missing keys, invalid categoricals, orphan relationships, out-of-range values).  
   - Monitor “unknown” rates for KPI-critical fields so KPI movement is explainable.  
   - Surface these signals in CI and in warehouse tables so issues are caught before reporting.


The result is a KPI that is repeatable, auditable, and explainable: the definition is written down, enforced with tests, and supported by monitoring outputs so stakeholders can understand changes instead of guessing.

---

## Repository structure

```
dataosphere/
  models/
    sources/            # source definitions for RAW/LANDING tables
    extract/            # extracts typed columns from landing JSON (VARIANT)
    raw/                # raw_* models (canonical RAW tables built from landing)
    staging/            # stg_ models with stg_*__base and stg_*__rejected patterns
    intermediate/       # int_ integration models and rollups (stable grains)
    marts/
      facts/            # KPI facts and aggregates for BI
      dimensions/       # dimensions (current and derived)
    monitoring/         # mon_ operational monitoring outputs (freshness, rejection rates)
  snapshots/            # SCD2 snapshots (dbt snapshots)
  macros/               # reusable SQL macros (incremental filters, helpers)
  docs/
    data-contract.md
    monitoring-contract.md
infra/
  terraform/            # AWS infrastructure-as-code (S3, notifications, queues, etc.)
```

##  Documentation and contracts

This repo keeps implementation and contracts close to the code:

- **Live dbt Docs (lineage + model docs):** https://psgpyc.github.io/WASH-Analytics-Engineering-Project/
- **Data contracts:**
  - [`dataosphere/docs/data-contract.md`](dataosphere/docs/data-contract.md)
  - [`dataosphere/docs/monitoring-contract.md`](dataosphere/docs/monitoring-contract.md)
- **Contracts enforced in code:** dbt YAML + tests + macros.

---

### Late-arriving data strategy

Survey submissions may arrive days or weeks late.

To handle this safely:

- Incremental models use event timestamps rather than load timestamps
- Lookback windows are applied to reprocess recent history on each run
- Deduplication logic ensures idempotent re-runs
- Monitoring models surface late-arrival patterns and anomalies

This ensures downstream KPIs remain stable even as late data arrives.


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
- **Purpose:** KPI-ready household-event fact table (base for safe drinking water).
- **Grain:** `household_id × submission_id`
- **Guaranteed slicers:** `ward_id`, `event_date`
- **Eligibility:** `member_count >= 1`
- **Invariant (tested):** `is_safe_drinking = has_safe_primary_source AND has_safe_water_filter AND has_no_diarrhoea_14d_members`

### `fact_household_wash_event_enriched_scd2`
- **Purpose:** base fact enriched with household attributes as-of the event date (point-in-time correct).
- **Grain:** `household_id`

### `fact_agg_safe_drinking_ward_day`
- **Purpose:** daily ward aggregate so BI does not rebuild KPI logic.
- **Grain:** `ward_id × event_date`
- **Invariants (tested):** `household_events_safe <= household_events_total`, `pct_safe BETWEEN 0 AND 1`

### `dim_household_current`
- **Purpose:** latest-known household attributes (current-state view).
- **Grain:** `household_id`
- **Note:** use for current state analysis, not historical point-in-time.

### `dim_household_history`
- **Purpose:** household attribute history as SCD2 (tracks changes over time).
- **Grain:** SCD2 history by `household_id` with validity windows.
- **Note:** enables point-in-time joins (also available via the enriched fact).

---

## Monitoring and triage

Monitoring models are intentionally small and sliceable for day-to-day operations:
- Freshness and volume drift checks
- Rejection rates and rejection reasons (bucketed)
- KPI-critical “unknown” rates to explain movement

Full monitoring definitions live in [`dataosphere/docs/monitoring-contract.md`](dataosphere/docs/monitoring-contract.md).

---

## CI and documentation

- dbt models are validated using GitHub Actions
- CI runs use a Snowflake service user with key-pair authentication
- Each pull request runs in an isolated schema
- dbt documentation is published automatically via GitHub Pages

Live documentation:
https://psgpyc.github.io/WASH-Analytics-Engineering-Project/

## How to review this repo

If you are reviewing this repository as part of a hiring or technical evaluation, the links below point to the most relevant parts.

**Architecture and flow**  
Start with the high-level design to understand how data moves from ingestion to analytics outputs.  
[Architecture overview](#architecture-overview)

**Analytics outputs and KPIs**  
Review the final analytical interfaces intended for BI tools and reporting.  
[Primary KPI facts](dataosphere/models/marts/facts)  
[Dimensions](dataosphere/models/marts/dimensions)

**Workflow and modelling approach**  
Understand the contract-first approach, late-arriving strategy, and data quality design.  
[Workflow](#workflow)

**Data contracts and quality rules**  
Review how KPI definitions, allowed values, and rejected data are documented.  
[Data contract](dataosphere/docs/data-contract.md)  
[Monitoring contract](dataosphere/docs/monitoring-contract.md)

**Lineage and documentation**  
Explore full model lineage, column-level documentation, and tests.  
[Live dbt Docs](https://psgpyc.github.io/WASH-Analytics-Engineering-Project/)

**Operational monitoring**  
Inspect the models used to track freshness, rejection rates, and data drift.  
[Monitoring models](dataosphere/models/monitoring)

**Infrastructure**  
Review the infrastructure-as-code used to provision ingestion components.  
[Terraform configuration](infra)

## Licence

MIT
