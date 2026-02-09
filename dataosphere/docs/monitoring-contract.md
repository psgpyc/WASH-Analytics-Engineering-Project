# Monitoring Contracts (WASH dbt + Snowflake)

This document defines the **monitoring layer contracts** for the WASH analytics project.
Monitoring models are **operational observability** outputs that help you answer:

- **How much bad data do we have?**
- **Where is it coming from (which model)?**
- **Why is it rejected (which reason bucket)?**
- **Are key survey fields incomplete (e.g., diarrhoea unknown rate)?**

Monitoring models are **derived** from:
- `<base>__base` (accepted/base output) for denominators
- `<base>__rejected` (quarantined/rejected output) for numerators and reason analysis

The monitoring layer is designed to be:
- **Deterministic** (same inputs → same results)
- **Auditable** (counts tie back to rejected rows)
- **Fast for triage** (daily grain, simple metrics, stable buckets)


## Naming & Conventions

### Base model naming
We follow a strict naming convention:

- Accepted/base models: `<base>__base`  
- Rejected/quarantine models: `<base>__rejected`

`base_model_name` is the canonical identifier:
- Derived from the rejected/base model naming convention
- Example: `stg_kobo_household` from `stg_kobo_household__rejected`

### Monitoring date rule (operational date)
Monitoring uses **load date**, not event time:

- `event_date = to_date(record_loaded_at)`
- Reason: monitoring is about *data processing health and ingestion*, not survey submission timing.

> KPI reporting uses `submitted_at` (event time). Monitoring uses `record_loaded_at` (operational time).


## Monitoring Models

### 1) `mon_total_by_model_day`
**Purpose**  
Daily denominator: how many base/accepted rows were produced by each model.

**Grain**  
- `base_model_name × event_date`

**Core fields**
- `base_model_name` (string)
- `event_date` (date)
- `base_row_count` (integer)

**Contract rules**
- Exactly one row per `(base_model_name, event_date)`
- `base_row_count >= 0`
- `base_model_name` and `event_date` not null

**Interpretation**
- This is your *daily throughput trend* per model.
- Used as denominator for rejection rate.


### 2) `mon_rejections_by_model_day`
**Purpose**  
Daily numerator: how many rows were rejected/quarantined per model.

**Grain**  
- `base_model_name × event_date`

**Core fields**
- `base_model_name` (string)
- `event_date` (date)
- `rejected_row_count` (integer)

**Contract rules**
- Exactly one row per `(base_model_name, event_date)`
- `rejected_row_count >= 0`
- `base_model_name` and `event_date` not null

**Interpretation**
- This tracks the volume of bad data per model over time.
- Used as numerator for rejection rate.


### 3) `mon_rejection_rate_day`
**Purpose**  
Daily rejection rate by model.

**Grain**  
- `model_name × event_date`
  - `model_name` must align with how the model is implemented (physical name vs base name)
  - In practice: keep this consistent with the join logic you chose

**Core fields**
- `model_name` (string)
- `event_date` (date)
- `base_row_count` (integer)
- `rejected_row_count` (integer)
- `rejection_rate` (decimal)

**Contract rules**
- Exactly one row per `(model_name, event_date)`
- `base_row_count >= 0`
- `rejected_row_count >= 0`
- `rejection_rate between 0 and 1`
- `rejected_row_count <= base_row_count`
- All fields not null (as configured)

**Interpretation**
- This is your headline metric to spot spikes.
- High rejection rate means: either ingestion/schema drift, upstream changes, or data capture issues.


### 4) `mon_rejection_by_reason_day`
**Purpose**  
Daily rejection counts by model and **reason bucket**.
This is the primary debugging slicer: *“what kind of bad data?”*

**Grain**  
- `base_model_name × event_date × reason_bucket`
  - (Your model also contains `model_name`; the enforced uniqueness is by base name/date/bucket.)

**Core fields**
- `base_model_name` (string)
- `event_date` (date)
- `reason_bucket` (string)
- `rejected_rows` (integer)

**Reason bucket contract**
Each rejected row must map into **exactly one** reason bucket based on precedence.

Allowed buckets:
- `missing_keys`
- `orphan_fk`
- `invalid_required_field`
- `invalid_canonical`
- `invalid_range`
- `unknown_other`
- `soft_deleted`
- `other`

**Precedence rule**
Reason assignment is **first-match wins** (CASE evaluation order).
This means:
- If multiple DQ flags are true for a rejected row, the assigned bucket is determined by the **CASE order**.
- This is intentional: it keeps reason categorisation deterministic.

**Contract rules**
- Exactly one row per `(base_model_name, event_date, reason_bucket)`
- `rejected_rows >= 0`
- `reason_bucket` must be one of the allowed values
- `base_model_name`, `event_date`, `reason_bucket`, `rejected_rows` not null (as configured)

**Interpretation**
- `missing_keys` spike → instrument/data extraction issue (keys missing)
- `orphan_fk` spike → referential sequencing issue (child arrives before parent) or integrity issue
- `invalid_canonical` spike → unexpected categorical values (mapping needed)
- `invalid_range` spike → numeric bounds issues
- `unknown_other` spike → field collection quality issues
- `soft_deleted` spike → upstream soft deletes increased
- `other` spike → your bucketing is incomplete; add coverage

**Implementation note**
Some models may not logically have all buckets (e.g., submissions may not have FK or orphan). That is fine:
- They will simply not produce rows for that bucket on that day.
- Bucket absence ≠ error.


### 5) `mon_unknown_diarrhoea_rate_ward_day`
**Purpose**  
Daily monitoring of diarrhoea-response completeness by ward.
Tracks how often member diarrhoea status is `'unknown'`.

**Grain**  
- `ward_id × event_date`

**Core fields (expected contract)**
- `ward_id` (number/string depending on your schema)
- `event_date` (date)
- `unknown_diarrhoea_count` (integer)
- `total_diarrhoea_responses` (integer)  *(recommended denominator)*
- `unknown_diarrhoea_rate` (decimal)     *(recommended metric)*

**Contract rules**
- Exactly one row per `(ward_id, event_date)`
- `unknown_diarrhoea_count >= 0`
- Unknown rate between 0 and 1 (inclusive)
- Fields used for reporting not null (as configured)

**Interpretation**
- High unknown rate signals survey completeness issues and should trigger triage before trusting downstream “safe drinking water” KPIs.

---

## Operational Use

### Daily checks (fast triage)
1) `mon_rejection_rate_day`  
   Find models with unusual spikes.

2) `mon_rejection_by_reason_day`  
   Break down the spike into categories (missing keys vs orphan fk vs invalid canonical, etc.).

3) `mon_unknown_diarrhoea_rate_ward_day`  
   Validate key health input completeness for KPI credibility.

### Weekly checks (system health)
- Look at trends over 7–30 days:
  - rejections trending up/down by model
  - dominant reason buckets
  - wards with persistent unknown diarrhoea rates

---

## Change Control

Monitoring contracts are **version-controlled**.

Any change to:
- staging DQ flags
- rejected model logic
- reason bucket precedence
- canonical value sets that affect rejection categorisation

must include updates to:
- `mon_rejection_by_reason_day` bucketing logic (if applicable)
- this monitoring contract doc (this file)

If a reason bucket is missing coverage (too much `other`), treat that as a signal:
- add a new bucket OR
- refine DQ flags and the CASE precedence

---

## Recommended Run Commands

Run all monitoring models:
- `dbt build --select tag:monitoring`

Run only reason monitoring:
- `dbt run --select mon_rejection_by_reason_day`
- `dbt test --select mon_rejection_by_reason_day`

---