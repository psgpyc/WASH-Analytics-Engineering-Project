{{
    config(
        materialized='table',
        schema='monitoring'
    )
}}


with source as (
    select
        ward_id, 
        event_date,
        sum(member_count) as member_count,
        sum(cast(total_diarrhoea_unknown_14d as number(1,0))) as unknown_diarrhoea_count
    from
        {{ ref('fact_household_wash_event') }}
    group by
        ward_id, event_date
)
select
    *,
    round(div0(unknown_diarrhoea_count, member_count), 3) as unknown_rate
from    
    source