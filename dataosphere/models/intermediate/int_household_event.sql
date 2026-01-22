{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['household_id', 'submission_id'],
        on_schema_change='sync_all_columns'
    )
}}

with joined as (
    select
        hh.household_id,
        ss.submission_id,
        ss.ward_id,
        ss.municipality,
        ss.district,
        ss.submitted_at,
        hh.hh_size_reported,
        hh.water_filter_type,
        hh.primary_water_source,
        hh.has_toilet,
        ss.record_loaded_at
    from
        {{ ref('stg_kobo_household') }} as hh
    join
        {{ ref('int_submission_submitted') }} as ss
    on
        hh.submission_id = ss.submission_id
    
), filtered as (
    select  
        *
    from
        joined
    {% if is_incremental() %}
        where {{ wash_incremental_load_filter(load_col='record_loaded_at')}}
    {% endif %}
)
select * from filtered