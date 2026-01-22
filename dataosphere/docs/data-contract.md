# WASH data contract

This file is the single source of truth for what the WASH tables mean.

It defines:
- the canonical value sets we accept downstream
- how we classify a household survey event as “safe drinking water”
- which timestamp we use for period reporting
- what we publish for reporting and operations (facts, dimensions, monitoring)
- how we track household attribute changes over time using SCD2 via dbt snapshots

If you change anything in here, you are changing what the dashboards mean. When this changes:
- update the macros or mapping logic
- update the dbt tests that lock the rules in
- commit with a clear explanation of what changed and why

---

## 0. Contract metadata

Scope
- This contract covers the drinking-water part of WASH reporting:
  - safe water source
  - household filter or treatment
  - diarrhoea in the last 14 days, using strict tri-state handling
- This repo does not cover sanitation or hygiene indicators.

System boundary
- RAW tables already exist in Snowflake.
- dbt is responsible for:
  - standardisation
  - validation and quarantine
  - integration
  - marts
  - monitoring outputs for day-to-day operations

Ownership
- Data owner: Programme team or M&E lead
- Data steward: Analytics Engineering
- Approvers for KPI definition changes: Programme lead and M&E lead

Change control
- Contract changes are made through a PR.
- Any change to KPI meaning must include:
  - the rationale
  - expected impact on reported numbers
  - the date the change becomes effective

Versioning
- We version changes in a practical way for survey reporting:
  - Major change: KPI definition or grain changes, breaking changes to published marts
  - Minor change: new columns, new monitoring outputs, new accepted values
  - Patch change: clarification, bug fixes that restore the intended meaning

---

## 0.1 Security and sensitive data

This dataset is intended for programme monitoring and does not require direct personal identifiers.

PII policy
- Do not store names, phone numbers, precise addresses, or national IDs in marts.
- Household identifiers like household_id are treated as pseudonymous keys and should still be handled as sensitive.

Data classification
- RAW and staging may contain sensitive operational fields and should be restricted to engineering and analytics access.
- Marts are curated for reporting but remain confidential.

If sensitive data is detected
- Quarantine affected rows or columns immediately.
- Raise an issue and record:
  - what field was detected
  - where it originated
  - what action was taken
- Add a dbt test or guardrail so the issue does not quietly return.

---

## 0.2 Freshness and operational expectations

Freshness expectation
- During active data collection, RAW sources should be no more than 24 hours stale.
- Outside active collection periods, freshness checks may be treated as informational.

Operational behaviour
- Freshness is checked via dbt source freshness and should be visible in CI and monitoring outputs.
- If freshness is breached:
  - dashboards should be treated as delayed data
  - triage should start at ingestion, upstream of dbt

Late-arriving data
- Published marts use incremental builds with a rolling lookback window to keep period metrics correct when submissions land late.
- Backfills are supported using start_date and end_date variables.

---

## 0.3 Consumers and downstream use

Primary consumer
- Safe drinking water by ward and day reporting pack

Contracted outputs used downstream
- fact_agg_safe_drinking_ward_day as the preferred input for BI
- fact_household_wash_event for drill-down and explainability
- mon_* monitoring tables for operational triage

Change impact rule
- Any change to KPI definition, grain, safe lists, or period rules should be treated as breaking for consumers unless a clear compatibility note is included.

---

## 1. Canonical value sets

These are the only values we accept downstream.
Anything else must be mapped in staging or deliberately quarantined.

### 1.1 stg_kobo_household.water_filter_type

Accepted values:
- none
- boil
- candle
- chlorine
- sodis
- ceramic
- biosand
- cloth
- ro_uv
- other
- unknown

Notes:
- other and unknown are allowed values, but they are not considered safe for KPI classification unless stakeholders explicitly decide otherwise.

---

### 1.2 stg_kobo_household.primary_water_source

Accepted values:
- piped_to_dwelling
- piped_to_yard_plot
- public_tap_standpipe
- tubewell_borehole
- protected_dug_well
- unprotected_dug_well
- protected_spring
- unprotected_spring
- rainwater
- tanker_truck_cart
- bottled_water
- surface_water
- other
- unknown

Notes:
- We do not allow ambiguous duplicates like spring or tapstand.
- If these show up upstream, map them to canonical categories or quarantine them.

---

### 1.3 stg_kobo_water_point.source_type

Accepted values, same taxonomy as household primary_water_source:
- piped_to_dwelling
- piped_to_yard_plot
- public_tap_standpipe
- tubewell_borehole
- protected_dug_well
- unprotected_dug_well
- protected_spring
- unprotected_spring
- rainwater
- tanker_truck_cart
- bottled_water
- surface_water
- other
- unknown

Why we do this:
- so household and water-point reporting can be compared and aggregated without translation.

---

### 1.4 stg_kobo_member.member_sex

Accepted values:
- m
- f
- male
- female
- other
- unknown

---

### 1.5 stg_kobo_member.member_had_diarrhoea_14d

Accepted values:
- yes
- no
- unknown

What unknown means:
- the source response was missing, invalid, or could not be parsed reliably.

Important:
- unknown is not no. We do not assume health outcomes.

---

## 2. Time basis for reporting

We report using one timestamp so period-based indicators stay consistent.

- event timestamp: submitted_at
- event date(reporting date): event_date = DATE(submitted_at)
- default reporting grain: ward_id × event_date
- timezone: treat as UTC, or convert to UTC before deriving event_date

Eligibility rule
- If event type is submitted and submitted_at is null, the row is not eligible for period reporting and must be quarantined or fixed upstream.

---

## 3. KPI: safe drinking water

### 3.1 KPI grain
Safe drinking water is classified at:
- household_id × submission_id

That is the unit we count, filter, and trend over time.

### 3.2 KPI definition
A household survey event is safe only when all three are true:

1) Safe primary source
- has_safe_primary_source = primary_water_source IN SAFE_PRIMARY_WATER_SOURCES

2) Safe filter or treatment
- has_safe_water_filter = water_filter_type IN SAFE_WATER_FILTER_TYPES

3) No diarrhoea in the last 14 days, strict tri-state
- derived from member rollups at the same grain

Final KPI flag:
- is_safe_drinking = has_safe_primary_source AND has_safe_water_filter AND has_no_diarrhoea_14d_members

---

## 4. Safe lists

These are programme definitions. If stakeholders change the definition, change it here first.

Implementation note
- Safe lists are version-controlled in dbt macros so KPI logic remains consistent across models and tests.

### 4.1 SAFE_PRIMARY_WATER_SOURCES
Default safe list:
- piped_to_dwelling
- piped_to_yard_plot
- public_tap_standpipe
- tubewell_borehole
- protected_dug_well
- protected_spring
- rainwater
- bottled_water

### 4.2 SAFE_WATER_FILTER_TYPES
Default safe list:
- boil
- chlorine
- sodis
- ceramic
- biosand
- ro_uv

Notes:
- candle is excluded by default due to variable performance and maintenance.
- cloth is excluded.
- none, other, and unknown are not safe.

---

## 5. Member to household diarrhoea rollup

Field
- `stg_kobo_member.member_had_diarrhoea_14d`, yes no unknown

Rollup outputs at `household_id × submission_id`:
- member_count
- total_diarrhoea_case_count_14d
- total_no_diarrhoea_count_14d
- total_unknown_diarrhoea_count_14d
- has_no_diarrhoea_14d_members

Consistency rule
- member_count = yes + no + unknown

Strict no diarrhoea rule
- has_no_diarrhoea_14d_members is true only when:
  - member_count > 0
  - total_diarrhoea_case_count_14d = 0
  - total_unknown_diarrhoea_count_14d = 0
  - total_no_diarrhoea_count_14d = member_count

Interpretation
- if even one member is unknown, we do not claim no diarrhoea
- if there are no member records for the event, we do not claim anything

---

## 6. Published marts

This section is for anyone consuming the tables. 


### 6.1 `fact_household_wash_event`

**Purpose**
- KPI-ready household-event fact for reporting *safe drinking water* with consistent logic and stable grains.

**Grain**
- `household_id × submission_id`

**Required fields**
- `household_id`, `submission_id`, `submitted_at`, `event_date`, `ward_id`

**Guaranteed slicers**
- `ward_id`
- `event_date`

**Eligibility**
- Only household-events with `member_count >= 1`

**Key logic that must not drift**
- `has_no_diarrhoea_14d_members` is **strict** (tri-state):
  - household is “no diarrhoea” only when:
    - `total_diarrhoea_yes_14d = 0`
    - `total_diarrhoea_unknown_14d = 0`
    - `total_diarrhoea_no_14d = member_count`
- KPI invariant:
  - `is_safe_drinking = has_safe_primary_source AND has_safe_water_filter AND has_no_diarrhoea_14d_members`

---

### 6.2 `fact_household_wash_event_enriched_scd2`

**Purpose**
- Point-in-time enriched household-event fact: joins each household-event to the correct household attributes as of the event timestamp using the SCD2 snapshot validity window.

**Why it exists**
- `dim_household_current` answers “what is the household like now?”
- This model answers “what was the household like at the time of the event?”

**Grain**
- `household_id × submission_id` 

**Join logic**
- SCD2 interval join on household:
  - `f.household_id = s.household_id`
  - `f.submitted_at >= s.dbt_valid_from`
  - `f.submitted_at < COALESCE(s.dbt_valid_to, '9999-12-31')`

**Adds**
- `ward_id`, `district`, `municipality`
- `hh_size_reported`, `has_toilet`
- `water_filter_type`, `primary_water_source`
- plus SCD2 bounds: `dbt_valid_from`, `dbt_valid_to` 

**Operational notes**
- This model depends on snapshot freshness:
  - snapshot history updates only when `dbt snapshot` runs
  - if snapshot is stale, enrichment will reflect the last snapshot run

---

### 6.3 `fact_agg_safe_drinking_ward_day`

**Purpose**
- Ward × day aggregate so BI tools do not rebuild KPI logic and stakeholders can trend the KPI reliably.

**Grain**
- `ward_id × event_date`

**Must always be true**
- `household_events_safe <= household_events_total`
- Percentage is bounded:
  - `pct_safe BETWEEN 0 AND 1`

**Inputs**
- Aggregated from `fact_household_wash_event` 

---

## 7. Household dimensions and SCD2 history

Household attributes (filter type, primary source, toilet, HH size, and location fields) can change over time.
This repo supports both current-state consumption and historical point-in-time analysis.

---

### 7.1 `dim_household_current`

**Purpose**
- Current household attributes for “today’s targeting / latest known state” use-cases.

**Grain**
- `household_id`

**Definition**
- Current row is defined as `dbt_valid_to IS NULL`.

**Implementation**
- A “current view” over the snapshot (so current and history remain aligned without duplicating logic):
  - source: `snap_dim_household_current`
  - filter: `dbt_valid_to IS NULL`

---

### 7.2 `dim_household_history`

**Purpose**
- SCD2 history dimension of household attributes for audit and longitudinal analysis.

**Grain**
- `household_id × dbt_valid_from` 

**Key fields**
- Household attributes: `ward_id`, `district`, `municipality`, `hh_size_reported`, `has_toilet`, `water_filter_type`, `primary_water_source`
- Validity window:
  - `dbt_valid_from`
  - `dbt_valid_to` (NULL means current)

**Implementation**
- Thin dimensional wrapper on top of the snapshot table:
  - source: `snap_dim_household_current`
  - exposes full SCD2 history for BI/analysis

---

### 7.3 Snapshot table: `snap_dim_household_current`

**Purpose**
- System-of-record for SCD2 history of household attributes.

**Snapshot semantics**
- Each version row has:
  - `dbt_valid_from`, `dbt_valid_to`
- Current row:
  - `dbt_valid_to IS NULL`

**Operational point**
- Snapshot history updates only when `dbt snapshot` runs.
- `dbt build` does not update snapshot history by itself.

**How it is used**
- Current-state:
  - `dim_household_current` = snapshot filtered to current row
- Point-in-time:
  - `fact_household_wash_event_enriched_scd2` interval-joins events to snapshot windows using `submitted_at`
- Full history:
  - `dim_household_history` exposes all snapshot rows as a dimension

---

## 8. Data quality enforcement and quarantine

Where rules are enforced
- Source freshness: dbt source freshness checks
- Canonical value sets: accepted_values tests and staging mapping logic
- Grains: uniqueness tests
- Join safety: not_null and relationships tests
- Quarantine: __rejected models keep invalid rows visible and replayable

Severity
- Blockers, must fail CI:
  - broken grains
  - missing join keys
  - KPI invariants not holding
- Warnings, monitor and triage:
  - rising unknown rates
  - drift in categoricals
  - volume changes

## 9. When you change the contract

If you touch:
- canonical sets
- safe lists
- diarrhoea rollup logic
- period rules
- snapshot-tracked household fields
- published mart grains or invariants

Then you must:
1) update this file
2) update the macro or mapping layer, or snapshot tracked columns
3) update or add dbt tests to lock the behaviour in
4) write the commit message like a human, what changed and why