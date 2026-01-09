{{ config(materialized="view") }}

WITH source AS (
    SELECT
        household_id, 
        submission_id, 
        ward_id,
        household_head_name, 
        phone_last4, 
        hh_size_reported,
        water_filter_type,
        primary_water_source,
        has_toilet,
        _loaded_at,
        _batch_id,
        _source_file, 
        _is_deleted 
    FROM    
        {{ source('raw', 'kobo_household') }}
), standardised AS (
    SELECT
        -- ids/ dimentions
        try_cast(household_id AS VARCHAR) AS household_id,
        try_cast(submission_id AS VARCHAR) AS submission_id,
        try_cast(ward_id AS NUMBER(38,0)) AS ward_id,

        -- numeric
        try_cast(hh_size_reported AS NUMBER(38, 0)) AS hh_size_reported,

        -- strings
        trim(try_cast(household_head_name AS VARCHAR)) AS household_head_name,
        try_cast(phone_last4 AS VARCHAR) AS phone_last4,
        lower(trim(try_cast(water_filter_type AS VARCHAR))) AS water_filter_type,
        lower(trim(try_cast(primary_water_source AS VARCHAR))) AS primary_water_source,

        -- boolean
        try_cast(has_toilet AS BOOLEAN) AS has_toilet,
        

        -- audit/ lineage
        _loaded_at AS record_loaded_at,
        try_cast(_batch_id AS VARCHAR) AS batch_id,
        try_cast(_source_file AS VARCHAR) AS source_file, 
        coalesce(try_cast(_is_deleted AS BOOLEAN), false) AS is_deleted,

    FROM    
        source
), set_dq_flags AS (
    SELECT
        *,

        -- data quality flags
        (household_id IS NULL OR trim(household_id) = '') AS dq_missing_blank_household_id,

        (submission_id IS NULL OR trim(submission_id) = '') AS dq_missing_blank_submission_id,

        (ward_id IS NULL) AS dq_missing_ward_id,

        (water_filter_type IS NULL OR trim(water_filter_type) = '') AS dq_missing_blank_water_filter_type,

        (primary_water_source IS NULL OR trim(primary_water_source) = '') AS dq_missing_blank_primary_water_source,

        (
            hh_size_reported IS NOT NULL 
            AND
            ( 
                hh_size_reported  < 0 
                OR 
                hh_size_reported > 15
            )
        ) AS dq_invalid_hh_size,

        (
            water_filter_type IS NOT NULL
            AND
            trim(water_filter_type) = ''
            AND 
            (
                water_filter_type = 'unknown'
                OR
                water_filter_type  = 'other'
            )
        ) AS dq_unknown_other_filter_type,

        (
            water_filter_type IS NOT NULL
            AND
            trim(water_filter_type) <> ''
            AND
            water_filter_type
            NOT IN (
                'none',
                'boil',
                'candle',
                'chlorine',
                'sodis',
                'ceramic',
                'biosand',
                'cloth',
                'ro_uv',
                'other',
                'unknown'
            )
        ) AS dq_invalid_water_filter_type,

        (
            primary_water_source IS NOT NULL 
            AND
            trim(primary_water_source) <> ''
            AND 
            (
                primary_water_source = 'unknown'
                OR
                primary_water_source = 'other'
            )
        ) AS dq_unknown_other_primary_water_source,

        (
            primary_water_source IS NOT NULL
            AND
            trim(primary_water_source) <> ''
            AND
            primary_water_source
            NOT IN (
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
                'other',
                'unknown'
            )
        ) AS dq_invalid_primary_water_source

    FROM
        standardised

), dedupe AS (
    SELECT 
        *
    FROM    
        set_dq_flags 
    QUALIFY 
        ROW_NUMBER() OVER(
            PARTITION BY household_id, submission_id
            ORDER BY record_loaded_at DESC, source_file DESC
        ) = 1
)
select * from dedupe