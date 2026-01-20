-- Fails if the snapshot has overlapping validity windows for the same household

with source as (
    select
        household_id,
        dbt_valid_from,
        coalesce(dbt_valid_to, to_timestamp_ntz('9999-12-31 00:00:00')) as dbt_valid_to
    from
        {{ ref('snap_dim_household_current') }}
),
ordered as (
    select  
        *,
        lag(dbt_valid_to) over(partition by household_id order by dbt_valid_from) as prev_valid_to
    from
        source
)
select
  household_id,
  dbt_valid_from,
  dbt_valid_to,
  prev_valid_to
from ordered
where prev_valid_to is not null
  and dbt_valid_from < prev_valid_to
