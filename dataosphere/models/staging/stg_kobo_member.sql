{{ config(materialized='view')}}

with source as (
    select
        *
    from
        {{ ref('stg_kobo_member__base') }}
)
select
    *
from
    source
where
    dq_missing_household_id = false
    and dq_missing_submission_id = false
    and dq_missing_member_index = false
    and dq_missing_blank_member_sex = false
    and dq_invalid_member_sex = false
    and dq_blank_member_name = false
    and dq_invalid_age_in_years = false
    and dq_orphan_household_id = false
    and dq_orphan_submission_id = false