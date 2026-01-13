{{
    config(
        materialized='view',
        schema='intermediate'
    )
}}

with source as (
    select
        household_id, 
        ward_id, 
        district, 
        municipality,
        hh_size_reported,
        has_toilet,
        water_filter_type, 
        primary_water_source,
        -- audit/lineage
        submission_id,
        submitted_at,
        record_loaded_at
    from
        {{ref('int_household_event')}}
    qualify
    row_number() over(
        partition by household_id
        order by record_loaded_at desc, submitted_at desc, submission_id desc
    ) = 1
)
select
        household_id, 
        ward_id, 
        district, 
        municipality,
        hh_size_reported,
        has_toilet,
        water_filter_type, 
        primary_water_source,
        -- audit/lineage
        submission_id    
from
    source
