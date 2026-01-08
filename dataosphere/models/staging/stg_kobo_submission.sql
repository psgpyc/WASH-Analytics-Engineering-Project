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
    and dq_submitted_missing_submitted_at = false
    and dq_invalid_gps = false
    and is_deleted = false

