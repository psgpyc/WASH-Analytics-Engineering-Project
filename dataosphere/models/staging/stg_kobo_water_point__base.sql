{{ config(materialized='view') }}

with source as (
    select
        water_point_id, 
        submission_id,
        ward_id, 
        source_type, 
        functional,
        distance_minutes,
        gps_lat,
        gps_lon,
        _loaded_at, 
        _batch_id, 
        _source_file, 
        _is_deleted
    from    
        {{ source('raw', 'kobo_water_point')}}
), standardised as (
    select 
        -- id/ dimentions
        trim(try_cast(water_point_id as varchar)) as water_point_id,
        trim(try_cast(submission_id as varchar)) as submission_id,

        -- numeric
        try_cast(ward_id as number(38, 0)) as ward_id,
        
        cast(distance_minutes as number(10,2)) as distance_minutes,
        try_cast(gps_lat as float) as gps_lat,
        try_cast(gps_lon as float) as gps_lon,
        
        -- string

        lower(trim(try_cast(source_type as varchar))) as source_type,

        -- boolean
        try_cast(functional as boolean) as water_source_functional,

        -- audit/ lineage
        _loaded_at as record_loaded_at,
        try_cast(_batch_id as varchar)        as batch_id,
        try_cast(_source_file as varchar)     as source_file,
        coalesce(try_cast(_is_deleted as boolean), false) as is_deleted
    from
        source
), set_dq_flags as (
    select 
        *,
        -- data quality checks/ flags
        (water_point_id is null or trim(water_point_id) = '') as dq_missing_blank_water_point_id,
        
        (submission_id is null or trim(submission_id) = '') as dq_missing_blank_submission_id,

        (ward_id is null) as dq_missing_ward_id,

        (source_type is null or trim(source_type) = '') as dq_missing_blank_source_type,

        (
            source_type is not null
            and
            source_type not in (
                    'piped_to_dwelling',
                    'piped_to_yard_plot',
                    'public_tap_standpipe',
                    'tubewell_borehole',
                    'protected_dug_well',
                    'unprotected_dug_well',
                    'protected_spring',
                    'unprotected_spring',
                    'rainwater',
                    'tanker_truck_cart',
                    'bottled_water',
                    'surface_water',
                    'spring',
                    'tapstand',
                    'other',
                    'unknown')
        ) as dq_invalid_source_type,

        (distance_minutes is not null and  distance_minutes < 0) as dq_negative_distance_minutes,

        (
            submission_id is not null
            and 
            submission_id <> ''
            and not exists (
                select
                    1
                from
                    {{ ref('stg_kobo_submission') }} s
                where
                    s.submission_id = standardised.submission_id
            )

        ) as dq_orphan_submission_id,

        (distance_minutes is null) as dq_missing_distance_minutes

    from
        standardised

), dedupe as (
    select
        *
    from
        set_dq_flags
    qualify
        row_number() over(
            partition by water_point_id, submission_id
            order by record_loaded_at desc, source_file desc
        ) = 1
)
select * from dedupe
