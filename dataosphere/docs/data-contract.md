# WASH data contract 

This file is the single source of truth for how we:
- clean and standardise categorical fields
- classify a household survey event as “safe drinking water”
- define time/period reporting
- publish facts and monitoring outputs

If you change anything in here, you’re changing the meaning of the dashboards. That means:
- update the macro(s) / mapping
- update dbt tests that enforce the rule
- commit it with a clear explanation


## 1) Canonical value sets

These are the only values we accept downstream. Anything else must be mapped upstream (staging) or deliberately quarantined.

### 1.1 `stg_kobo_household.water_filter_type`

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
- `other` and `unknown` are allowed values, but they are not “safe” for KPI classification unless we explicitly decide they are.


### 1.2 `stg_kobo_household.primary_water_source`

Accepted values (no duplicates / no mixed categories):
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
- We do not allow ambiguous duplicates like `spring` or `tapstand`. If they show up upstream, map them to the canonical categories (or quarantine).

---

### 1.3 `stg_kobo_water_point.source_type`

Accepted values (same taxonomy as household `primary_water_source`):
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

### 1.4 `stg_kobo_member.member_sex`

Accepted values:
- m
- f
- male
- female
- other
- unknown

---

### 1.5 `stg_kobo_member.member_had_diarrhoea_14d` (tri-state)

Accepted values:
- yes
- no
- unknown

What `unknown` means here:
- the source response was missing, invalid, or couldn’t be parsed reliably.

Important:
- `unknown` is not “no”. We don’t get to assume health outcomes.

---

## 2) Time basis

We report by a single timestamp so time-based KPIs stay consistent.

- event timestamp: `record_loaded_at`
- event date: `event_date = DATE(record_loaded_at)`
- default reporting grain: `ward_id × event_date`
- timezone: treat as UTC (or convert to UTC before deriving `event_date`)

Why `record_loaded_at`:
- It is always present and deterministic for warehouse-side reporting.
- It reflects “when the record became available for analytics”, which is what our current pipeline can guarantee.

Eligibility:
- if `record_loaded_at` is null (should not happen by contract), the row is not eligible for period-based KPI reporting and should be quarantined or fixed upstream.

---

## 3) KPI: “safe drinking water”

### 3.1 Grain

Everything for “safe drinking water” is classified at:
- `household_id × submission_id`

That is the unit we count, filter, and trend over time.

### 3.2 Safe drinking water definition

A household survey event is “safe” only when all three are true:

1) **Safe primary source**
- `has_safe_primary_source = primary_water_source IN SAFE_PRIMARY_WATER_SOURCES`

2) **Safe filter/treatment**
- `has_safe_water_filter = water_filter_type IN SAFE_WATER_FILTER_TYPES`

3) **No diarrhoea in last 14 days (strict tri-state)**
This comes from the member rollup at the same grain.

---

## 4) Safe lists

These are project-level definitions. If stakeholders change the definition, change it here first.

### 4.1 SAFE_PRIMARY_WATER_SOURCES

Default “safe” list:
- piped_to_dwelling
- piped_to_yard_plot
- public_tap_standpipe
- tubewell_borehole
- protected_dug_well
- protected_spring
- rainwater
- bottled_water

### 4.2 SAFE_WATER_FILTER_TYPES

Default “safe” list:
- boil
- chlorine
- sodis
- ceramic
- biosand
- ro_uv

Notes:
- `candle` is excluded by default (variable performance + maintenance). If stakeholders accept it, we add it here and version the change.
- `cloth` is excluded.
- none / other / unknown are not safe.

---

## 5) Member → household diarrhoea rollup (strict)

Field:
- `stg_kobo_member.member_had_diarrhoea_14d` (yes/no/unknown)

Rollup outputs at `household_id × submission_id`:
- `member_count` (count of distinct `member_index`)
- `total_diarrhoea_case_count_14d` (sum yes)
- `total_no_diarrhoea_count_14d` (sum no)
- `total_unknown_diarrhoea_count_14d` (sum unknown)
- `has_no_diarrhoea_14d_members` (derived)

Consistency rule (must always hold):
- `member_count = yes + no + unknown`

Strict “no diarrhoea” rule (this is what we actually use):
- `has_no_diarrhoea_14d_members` is true only when:
  - `member_count > 0`
  - `total_diarrhoea_case_count_14d = 0`
  - `total_unknown_diarrhoea_count_14d = 0`
  - `total_no_diarrhoea_count_14d = member_count`

Interpretation:
- if even one member is unknown, we don’t claim the household has “no diarrhoea”.
- if there are no member records for the event, we don’t claim anything.

---

## 6) Published models

This section is for anyone consuming the tables. Keep it short: purpose, grain, required fields, the rules that matter.

### 6.1 `fact_household_wash_event`

Purpose:
- KPI-ready household-event fact used to report “safe drinking water” by ward and period.

Grain (primary key):
- household_id × submission_id

Guaranteed slicers:
- ward_id
- event_date

Eligibility:
- only household-events with `member_count >= 1`

Key logic that must not drift:
- `is_safe_drinking = has_safe_primary_source AND has_safe_water_filter AND has_no_diarrhoea_14d_members`

---

### 6.2 `fact_agg_safe_drinking_ward_day`

Purpose:
- ward/day aggregate so BI tools don’t have to rebuild KPI logic.

Grain:
- ward_id × event_date

Must always be true:
- `household_events_safe <= household_events_total`
- `pct_safe` is between 0 and 1

---

## 7) Monitoring outputs (for debugging, not analytics)

These exist so we can answer “what broke?” without digging through compiled SQL.

### 7.1 `mon_total_by_model_day`
- what it is: daily accepted/base row counts
- grain: base_model_name × event_date

### 7.2 `mon_rejections_by_model_day`
- what it is: daily rejected row counts
- grain: base_model_name × event_date

### 7.3 `mon_rejection_rate_day`
- what it is: rejection_rate = rejected / base
- sanity rules: rate is 0–1 and rejected <= base

### 7.4 `mon_rejection_by_reason_day`
- what it is: daily rejected counts split by *one* reason bucket per row
- grain: base_model_name × event_date × reason_bucket
- reason buckets (standard set):
  - missing_keys
  - orphan_fk
  - invalid_required_field
  - invalid_canonical
  - invalid_range
  - unknown_other
  - soft_deleted
  - other

Precedence note:
- a row gets the first matching bucket. This is intentional to avoid double-counting.

### 7.5 `mon_unknown_diarrhoea_rate_ward_day`
- what it is: how often diarrhoea is recorded as `unknown` (ward/day)
- grain: ward_id × event_date
- interpretation: high unknown rate = weak completeness; treat KPI outputs with caution for those slices.

---

## 8) When you change the contract

If you touch:
- canonical sets
- safe lists
- diarrhoea rollup logic
- period rules

…then you must:
1) update this file
2) update the macro / mapping layer
3) update or add dbt tests to lock the new behaviour in
4) write the commit message like a human (“what changed and why”), not “update stuff”