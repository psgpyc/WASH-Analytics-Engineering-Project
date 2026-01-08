{{ config(materialized='view')}}


with source as (
    select  
        water_point_id,
        submission_id,
        ward_id,
        distance_minutes,
        source_type,
        water_source_functional,
        record_loaded_at,
        batch_id,
        source_file,
        dq_missing_blank_water_point_id,
        dq_missing_blank_submission_id,
        dq_missing_ward_id,
        dq_missing_blank_source_type,
        dq_negative_distance_minutes,
        dq_orphan_submission_id,
        dq_missing_distance_minutes
    from
        {{ref('stg_kobo_water_point__base')}}
)
select 
    *
from
    source
where
    dq_missing_blank_water_point_id = true
    or
    dq_missing_blank_submission_id = true
    or
    dq_missing_ward_id = true
    or
    dq_missing_blank_source_type = true
    or
    dq_negative_distance_minutes = true
    or
    dq_orphan_submission_id = true
    or
    dq_missing_distance_minutes = true