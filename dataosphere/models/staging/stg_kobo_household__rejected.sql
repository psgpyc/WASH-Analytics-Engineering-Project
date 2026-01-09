{{config(materialized='view')}}

with source as (
    select  
        *
    from
        {{ ref('stg_kobo_household__base') }}
)
select 
    *
from
    source
where
    is_deleted = true
    or dq_missing_blank_household_id = true
    or dq_missing_blank_submission_id = true
    or dq_missing_ward_id = true
    or dq_missing_blank_water_filter_type = true
    or dq_missing_blank_primary_water_source = true
    or dq_invalid_hh_size = true
    or dq_unknown_other_filter_type = true
    or dq_invalid_water_filter_type = true
    or dq_unknown_other_primary_water_source = true
    or dq_invalid_primary_water_source = true

