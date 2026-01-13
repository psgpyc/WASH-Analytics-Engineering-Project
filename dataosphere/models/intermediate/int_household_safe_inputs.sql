{{
    config(
        materialized='view',
        schema='intermediate'
    )
}}

with joined as (
    select
        he.household_id,
        he.submission_id, 
        he.submitted_at,
        he.ward_id, 
        he.hh_size_reported,
        he.water_filter_type,
        he.primary_water_source,
        he.has_toilet,
        hmhr.member_count, 
        hmhr.total_diarrhoea_case_count_14d,
        hmhr.total_unknown_diarrhoea_count_14d,
        hmhr.total_no_diarrhoea_count_14d,
        hmhr.has_no_diarrhoea_14d_members
    from    
        {{ref('int_household_event')}} as he
    join
        {{ref('int_household_member_health_rollup')}} as hmhr
    on
        he.household_id = hmhr.household_id
        and
        he.submission_id = hmhr.submission_id
)
select 
    * 
from 
    joined

