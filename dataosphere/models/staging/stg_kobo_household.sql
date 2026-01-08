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
    is_deleted = false
    and dq_missing_household_id = false
    and dq_missing_ward_id = false
    and dq_invalid_hh_size = false
    and dq_unknown_other_filter_type = false
    and dq_unknown_other_primary_water_source = false
