{{
    config(
        materialized='table',
        schema='marts'
    )
}}


with source as (
    select
        *
    from
        {{ ref('snap_dim_household') }}
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
    submission_id,
    dbt_valid_to,
    dbt_valid_from

from
    source

