{{config(materialized='view')}}

with source as (
    select
        household_id, 
        submission_id,
        member_index,
        member_name, 
        sex, 
        age_years,
        had_diarrhoea_14d,
        _loaded_at,
        _batch_id,
        _source_file,
        _is_deleted
    from
        {{source('raw', 'kobo_member')}}
), standardised as (
    select

        -- ids/ dimentions
        try_cast(household_id as varchar) as household_id,
        try_cast(submission_id as varchar) as submission_id,
        try_cast(member_index as number(38,0)) as member_index,

        -- numeric
        try_cast(age_years as number(38,0)) as member_age_in_years,

        -- strings
        trim(try_cast(member_name as varchar)) as member_name,
        lower(trim(try_cast(sex as varchar))) as member_sex,

        -- boolean
        try_cast(had_diarrhoea_14d as boolean) as member_had_diarrhoea_14d,

        -- audit/ lineage
        _loaded_at AS record_loaded_at,
        try_cast(_batch_id AS VARCHAR) AS batch_id,
        try_cast(_source_file AS VARCHAR) AS source_file, 
        coalesce(try_cast(_is_deleted AS BOOLEAN), false) AS is_deleted

    from
        source
), set_dq_flags as (
    select 
        *,
        (household_id is null) as dq_missing_household_id,
        (submission_id is null) as dq_missing_submission_id,
        (member_index is null) as dq_missing_member_index,
        (member_sex is null or trim(member_sex) = '') as dq_missing_blank_member_sex,
        (member_sex is not null and member_sex not in ('m', 'f' , 'male', 'female', 'other', 'unknown')) as dq_invalid_member_sex,
        (trim(member_name) = '') as dq_blank_member_name,

        (
            member_age_in_years < 0
            or
            member_age_in_years > 120

        ) as dq_invalid_age_in_years,

        (
            household_id is not null 
            and
            not exists (
                select
                    1
                from
                    {{ ref('stg_kobo_household') }} h
                where
                    h.household_id = standardised.household_id

            )
        ) as dq_orphan_household_id,

        (
            submission_id is not null
            and
            not exists (
                select
                    1
                from
                    {{ ref('stg_kobo_submission') }} s
                where
                    s.submission_id = standardised.submission_id
            )
        ) as dq_orphan_submission_id


    from
        standardised
), final as (
    select
        *
    from
        set_dq_flags
    qualify
        row_number() over(
            partition by household_id, member_index
            order by record_loaded_at desc, source_file desc
        ) = 1
)
select 
    *
from
    final

