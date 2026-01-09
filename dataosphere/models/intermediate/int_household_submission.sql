with source as (
    select
        hh.household_id,
        s.submission_id,
        

    from
        {{ ref('stg_kobo_household') }} hh
    left join
        {{ ref('stg_kobo_submission')}} s
    on
        hh.submission_id = s.submission_id
)