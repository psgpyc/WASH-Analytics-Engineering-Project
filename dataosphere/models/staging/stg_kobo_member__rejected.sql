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
    dq_missing_household_id = true
    or dq_missing_submission_id = true
    or dq_missing_member_index = true
    or dq_missing_blank_member_sex = true
    or dq_invalid_member_sex = true
    or dq_blank_member_name = true
    or dq_invalid_age_in_years = true
    or dq_orphan_household_id = true
    or dq_orphan_submission_id = true