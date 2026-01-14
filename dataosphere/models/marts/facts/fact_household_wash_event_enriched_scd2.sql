{{ config(
    materialized='table',
    schema='marts'
) }}

with fact as (
    select
        household_id,
        submission_id,
        submitted_at,
        event_date, 
        total_diarrhoea_yes_14d,
        total_diarrhoea_no_14d,
        total_diarrhoea_unknown_14d,
        has_no_diarrhoea_14d_members,
        has_safe_primary_source,
        has_safe_water_filter,
        is_safe_drinking
    from
        {{ ref('fact_household_wash_event') }}

), scd2 as (
    select
        household_id,

        dbt_valid_from,
        dbt_valid_to,

        ward_id,
        district,
        municipality,
        hh_size_reported,
        has_toilet,
        water_filter_type,
        primary_water_source

    from {{ ref('snap_dim_household_current') }}

), joined as (
    select
        f.*,
        s.ward_id,
        s.district,
        s.municipality,
        s.hh_size_reported,
        s.has_toilet, 
        s.water_filter_type, 
        s.primary_water_source,
        s.dbt_valid_from,
        s.dbt_valid_to
    from
        fact as f
    left join
        scd2 as s
    on
        f.household_id = s.household_id
    and
        f.submitted_at  >= s.dbt_valid_from
    and
        f.submitted_at < coalesce(s.dbt_valid_to, to_timestamp_ntz('9999-12-31 00:00:00'))
)
select * from joined