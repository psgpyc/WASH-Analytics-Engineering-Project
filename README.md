# WASH Analytics Engineering (dbt + Snowflake)

Production-grade analytics engineering project for Kobo-style WASH survey data in Snowflake using dbt.

This repo demonstrates a contract-first approach:
- RAW sources defined via `sources.yml` (freshness + metadata)
- Staging models that standardise types, normalise values, dedupe, and generate DQ flags
- Data tests with stored failures for accountability and auditability
- Pattern for rejected/quarantined records to support replayability and clean downstream marts

---

## Architecture (high level)

S3 (raw JSON exports) → Snowpipe → Snowflake RAW tables → dbt STAGING (`stg_`) → (next) INTERMEDIATE (`int_`) → (next) MARTS (`dim_` / `fct_`)

Key production principles:
- Replayable loads (raw is immutable, processed is derived)
- Accountability (store test failures, keep rejected rows)
- Deterministic modelling (typed + canonicalised staging)
- Join-safe grains (staging grains explicitly defined and tested)

---

## Project contents

### RAW sources (Snowflake)
Kobo-style tables:
- `kobo_submission` – 1 row per submission
- `kobo_household` – 1 row per household
- `kobo_member` – repeat group members (composite grain)
- `kobo_water_point` – water point observations (composite grain)

### Staging models (dbt)
Each staging model:
- casts to predictable data types (Snowflake safe casting where relevant)
- normalises strings (trim/lower)
- dedupes by declared grain using `record_loaded_at` ordering
- adds DQ flags to support quarantine
- includes dbt tests: `not_null`, `unique`, `relationships`, `unique_together` ,and expression tests

---

## How to run (local)

1) Install dbt packages
- `dbt deps`

2) Validate the project parses
- `dbt parse`

3) Build & test staging (recommended workflow)
- `dbt build --select tag:staging`

4) Run a single model
- `dbt run --select stg_kobo_submission`

5) Run tests for a model
- `dbt test --select stg_kobo_submission`

---

## Data quality strategy

- Source freshness checks ensure ingestion SLAs are met
- Contract tests ensure keys, relationships, and canonical values hold
- Store failures is enabled for audit tables, making bad records inspectable
- Rejected records can be routed to `__rejected` models for replay/triage

---

## Next steps (planned)

- Intermediate integration models (`int_...`) to reshape staging into analytical grains
- Dimensional marts (`dim_...`, `fct_...`) for BI dashboards and KPI reporting
- Monitoring models (`mon_...`) for rejection trends and freshness dashboards

---

## Licence

MIT
