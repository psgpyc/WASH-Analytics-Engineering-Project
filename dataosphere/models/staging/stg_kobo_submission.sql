{{ config(materialized='view')}}

with source as (
    select  
        *
    from    
        {{ ref('stg_kobo_submission__base') }}
)
select 
    *
from    
    source
where
    dq_missing_submission_id = false
    and status = 'submitted'
    and dq_submitted_missing_submitted_at = false
    and dq_missing_blank_municipality = false
    and dq_missing_blank_district = false
    and dq_invalid_gps = false
    and is_deleted = false
    and dq_missing_blank_enumerator_id = false


