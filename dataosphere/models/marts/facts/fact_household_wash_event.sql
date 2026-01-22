{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['household_id','submission_id'],
    on_schema_change='sync_all_columns'
) }}

with source as (
    select

    -- keys & slices
    household_id, 
    submission_id, 
    ward_id, 
    submitted_at, 
    
    -- derived
    to_date(submitted_at) as event_date,  

    -- household attributes 
    hh_size_reported,
    has_toilet,
    water_filter_type, 
    primary_water_source,


    -- member rollup (event scoped)
    member_count,

    total_diarrhoea_case_count_14d as total_diarrhoea_yes_14d,
    total_no_diarrhoea_count_14d as total_diarrhoea_no_14d,
    total_unknown_diarrhoea_count_14d as total_diarrhoea_unknown_14d,

    has_no_diarrhoea_14d_members

    from
        {{ref('int_household_safe_inputs')}}

), kpi_flags as (
    select
        *,
        (
            primary_water_source in {{ wash_safe_primary_sources() }}
        ) as has_safe_primary_source,

        (
            water_filter_type in {{ wash_safe_water_filters() }}
        ) as has_safe_water_filter

    from
        source 

), final as (
    select
        *,
        (
            has_safe_primary_source = true
            and
            has_safe_water_filter = true
            and
            has_no_diarrhoea_14d_members = true
        ) as is_safe_drinking
    from
        kpi_flags
) 
select
    *
from
    final

-- only selecting household_id x submission_id where atleast one member are present
where
    member_count >= 1
{% if is_incremental() %}
    and {{ wash_event_lookback_filter('event_date') }}
{% endif %}