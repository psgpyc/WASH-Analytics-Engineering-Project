# docs/data-contracts.md

## Overview

This document defines the canonical value sets and KPI-building rules used throughout the WASH analytics models. The goal is to ensure that:
- categorical values are consistent across forms and tables
- indicators are deterministic and auditable
- changes to definitions are explicit and version-controlled

---

## Canonical sets (categorical fields)

### 1) Household water_filter_type (canonical)
Used in: `stg_kobo_household.water_filter_type`

Canonical values:
- `none`
- `boil`
- `candle`
- `chlorine`
- `sodis`
- `ceramic`
- `biosand`
- `cloth`
- `ro_uv`
- `other`
- `unknown`

Notes:
- This is a normalised reporting set. If Kobo collects more granular variants, they should be mapped into these categories upstream (staging standardisation) or in a dedicated mapping layer.

---

### 2) Household primary_water_source (canonical)
Used in: `stg_kobo_household.primary_water_source`

Canonical values (cleaned; no duplicates):
- `piped_to_dwelling`
- `piped_to_yard_plot`
- `public_tap_standpipe`
- `tubewell_borehole`
- `protected_dug_well`
- `unprotected_dug_well`
- `protected_spring`
- `unprotected_spring`
- `rainwater`
- `tanker_truck_cart`
- `bottled_water`
- `surface_water`
- `other`
- `unknown`

Notes:
- We do **not** use ambiguous categories like `spring` or `tapstand` alongside `protected_spring/unprotected_spring` and `public_tap_standpipe`. If those appear upstream, they must be mapped to canonical values.

---

### 3) Water point source_type (canonical)
Used in: `stg_kobo_water_point.source_type`

Canonical values (aligned to household primary_water_source):
- `piped_to_dwelling`
- `piped_to_yard_plot`
- `public_tap_standpipe`
- `tubewell_borehole`
- `protected_dug_well`
- `unprotected_dug_well`
- `protected_spring`
- `unprotected_spring`
- `rainwater`
- `tanker_truck_cart`
- `bottled_water`
- `surface_water`
- `other`
- `unknown`

Notes:
- The water point classification uses the same canonical categories as household reporting to support consistent aggregation and comparison.

---

### 4) Member sex (canonical)
Used in: `stg_kobo_member.member_sex`

Canonical values:
- `m`
- `f`
- `male`
- `female`
- `other`
- `unknown`

---

## Safe drinking water definitions (KPI contract)

### KPI goal
Measure the number (and % where denominator is available) of households with “safe drinking water” by ward and period.

### Safe drinking water (household-level) is defined as:
A household survey event is classified as safe if ALL conditions hold:

1) **Safe primary water source**
- `has_safe_primary_source = primary_water_source IN SAFE_PRIMARY_WATER_SOURCES`

2) **Safe water treatment / filter**
- `has_safe_water_filter = water_filter_type IN SAFE_WATER_FILTER_TYPES`

3) **No diarrhoea in last 14 days**
- `no_diarrhoea_14d = (count of members with had_diarrhoea_14d = true) = 0`
- Computed at grain: `household_id × submission_id` from member records

Final KPI flag:
- `is_safe_drinking = has_safe_primary_source AND has_safe_water_filter AND no_diarrhoea_14d`

---

## Safe lists used by the KPI

### SAFE_PRIMARY_WATER_SOURCES (household-level)
Default “safe” set for reporting in this project:
- `piped_to_dwelling`
- `piped_to_yard_plot`
- `public_tap_standpipe`
- `tubewell_borehole`
- `protected_dug_well`
- `protected_spring`
- `rainwater`
- `bottled_water`

---

### SAFE_WATER_FILTER_TYPES (household-level)
Default “safe” set for reporting in this project:
- `boil`
- `chlorine`
- `sodis`
- `ceramic`
- `biosand`
- `ro_uv`

Notes:
- “candle” is excluded here by default (effectiveness varies by product/maintenance). You can include it if your stakeholder definition treats it as safe.
- “cloth” is excluded (generally not sufficient for safe drinking water).
- “none/other/unknown” are not safe.
---

## Diarrhoea rule (member rollup)
Field: `stg_kobo_member.member_had_diarrhoea_14d`

Derivation to household×submission:
- `member_count = count(*)`
- `diarrhoea_case_count_14d = sum(case when member_had_diarrhoea_14d = true then 1 else 0 end)`
- `no_diarrhoea_14d = (diarrhoea_case_count_14d = 0)`

Handling missing member data:
- Recommended strict approach:
  - if member records are missing for a household×submission, treat `no_diarrhoea_14d` as unknown (null) and do not classify the household as safe unless explicitly supported by evidence.