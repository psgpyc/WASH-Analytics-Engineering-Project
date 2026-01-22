{{ config(
    materialized='incremental',
    incremental_strategy='merge',
    unique_key=['ward_id','event_date'],
    on_schema_change='sync_all_columns'
) }}

with base as (
    select *
    from {{ ref('fact_household_wash_event') }}
),
grouped as (
    select
        ward_id,
        event_date,
        count(*) as household_events_total,
        sum(iff(is_safe_drinking, 1, 0)) as household_events_safe,
        round(div0(
            sum(iff(is_safe_drinking, 1, 0)),
            count(*)
        ), 2) as pct_safe
    from base
    group by ward_id, event_date
)
select 
    * 
from 
    grouped
{% if is_incremental() %}
where {{ wash_event_lookback_filter('event_date') }}
{% endif %}