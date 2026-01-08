# docs/staging.md

## Purpose of staging (stg_* models)

Staging models are the first transformation layer on top of RAW sources. Their job is to make upstream survey data safe and predictable to build on by applying consistent standardisation and basic data quality rules.

In this project, staging is responsible for:
- **Standardising types**: casting raw fields into deterministic Snowflake types (e.g., timestamps, booleans, numerics).
- **Normalising strings**: trimming whitespace and standardising case where appropriate (e.g., lowercasing categorical fields).
- **Defining grain**: ensuring each staging model has an explicit, stable grain suitable for joins.
- **Deduplicating**: choosing a deterministic “latest record wins” rule when multiple raw records exist for the same business key.
- **Soft delete handling**: excluding records flagged as deleted from “accepted” datasets (while preserving ability to audit/replay).
- **Generating DQ flags (where applicable)**: deriving dq_* fields that explain why a record is invalid or should be quarantined.
- **Enforcing contracts via tests**: not_null / unique / relationships / accepted_values / expression tests define the staging contract.

Staging is **not** responsible for:
- KPI calculations or business aggregates
- dimensional modelling (facts/dims)
- final dashboard-ready marts

Those belong in intermediate (int_*) and marts layers.

---

## Accepted vs rejected pattern (quarantine + replayability)

Survey pipelines encounter expected “bad” or incomplete data (missing keys, invalid categories, orphan records, out-of-range values). We do not silently drop these records.

This project follows an **accepted vs rejected** pattern:

### Accepted dataset
- The standard staging model (e.g., `stg_kobo_household`) represents **accepted records** that meet the staging contract.
- These records are safe to use for downstream modelling (int_*, fct_*, dim_*, marts).

### Rejected dataset (quarantine)
- A companion model (e.g., `stg_kobo_household__rejected`) captures records that fail one or more data quality checks.
- Rejected records are retained for:
  - triage and root-cause analysis
  - feedback loops to data collection teams
  - replay/backfill after fixes (mapping updates, source system corrections, logic adjustments)

### How rejection is determined
A record is rejected when it violates one or more of:
- **Key constraints** (missing/blank business keys)
- **Referential integrity** (orphan foreign keys)
- **Canonical values** (unexpected category values)
- **Business plausibility** (e.g., negative distance_minutes, implausible age)
- **Contract expressions** (e.g., status='submitted' requires submitted_at)

Rejected records should include:
- dq_* boolean flags (one per rule)
- optional reason codes / arrays (if you extend later)
- lineage fields (batch_id, source_file, record_loaded_at)

---

## Deduplication behaviour 

Because RAW ingestion can land duplicates (retries, re-exports, late-arriving files), staging applies deterministic deduplication.

Standard approach in this project:
- Use `ROW_NUMBER()` with a partition on the declared grain/business key.
- Order by:
  1) `record_loaded_at` DESC (latest ingestion wins)
  2) `source_file` DESC (stable tie-breaker)

This ensures staging models are:
- reproducible across runs
- stable for downstream joins
- traceable back to the load lineage

---

## Soft delete behaviour

RAW ingestion includes a soft delete flag (e.g., `is_deleted` / `_is_deleted`) to represent records removed or invalidated upstream.

In staging:
- **Accepted datasets exclude** records where `is_deleted = true`.
- **Rejected/quarantine can optionally include** deleted records if you want a full audit trail.

Key principle:
- Do not physically delete upstream history in analytics layers.
- Use soft delete semantics so downstream consumers see the “current accepted truth” while engineers retain full accountability.

---

## Staging contracts in this project

Staging models covered:
- `stg_kobo_submission`: submission event backbone (timestamps/status/context)
- `stg_kobo_household`: household-level WASH responses per survey event
- `stg_kobo_member`: member roster / health attributes used for rollups (e.g., diarrhoea)
- `stg_kobo_water_point`: water point observations and accessibility measures

Each model’s contract is expressed through:
- model and column descriptions in `models/staging/stg_kobo.yml`
- tests (not_null, unique, relationships, accepted_values, expression tests)
- canonical definitions referenced in `docs/data-contracts.md`