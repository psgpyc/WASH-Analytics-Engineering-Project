{{ config(materialized='view')}}

WITH source as (
    SELECT
        submission_id,
        status,
        submitted_at,
        collected_at,
        enumerator_id,
        device_id,
        ward_id,
        municipality,
        district,
        gps_lat,
        gps_lon,
        consent,

        _loaded_at,
        _batch_id,
        _source_file,
        _is_deleted
    FROM
        {{  source('raw', 'kobo_submission')  }}
), standardised AS (
    select
        -- business key
        try_cast(submission_id as varchar) as submission_id,

        -- strings
        lower(trim(try_cast(status as varchar))) as status,

        -- timestamps 
        submitted_at as submitted_at,
        collected_at as collected_at,

        -- ids / dimensions
        try_cast(enumerator_id as varchar) as enumerator_id,
        try_cast(device_id as varchar) as device_id,
        try_cast(ward_id as number(38,0)) as ward_id,
        try_cast(municipality as varchar) as municipality,
        try_cast(district as varchar) as district,

        -- geo
        try_cast(gps_lat as float) as gps_lat,
        try_cast(gps_lon as float) as gps_lon,

        -- flags
        try_cast(consent as boolean) as consent,

        -- lineage / audit
        _loaded_at as record_loaded_at,
        try_cast(_batch_id as varchar)        as batch_id,
        try_cast(_source_file as varchar)     as source_file,
        coalesce(try_cast(_is_deleted as boolean), false) as is_deleted,

        -- data quality flags (calculated on the casted/standardised values)
        (try_cast(submission_id as varchar) is null) as dq_missing_submission_id,

        (
            lower(trim(try_cast(status as varchar))) = 'submitted'
            and submitted_at is null
        ) as dq_submitted_missing_submitted_at,

        (
            (try_cast(gps_lat as float) is not null and (try_cast(gps_lat as float) < -90 or try_cast(gps_lat as float) > 90))
            or (try_cast(gps_lon as float) is not null and (try_cast(gps_lon as float) < -180 or try_cast(gps_lon as float) > 180))
        ) as dq_invalid_gps

    from source
), deduped AS (
    SELECT 
        *
    FROM    
        standardised
    QUALIFY 
        ROW_NUMBER() OVER(
            PARTITION BY submission_id
            ORDER BY record_loaded_at DESC, source_file desc
        ) = 1
) 
select * from deduped
