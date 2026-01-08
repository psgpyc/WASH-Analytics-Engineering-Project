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
    and dq_missing_household_id = true
    and dq_missing_ward_id = true
    and dq_invalid_hh_size = true
    and dq_unknown_other_filter_type = true
    and dq_unknown_other_primary_water_source = true
