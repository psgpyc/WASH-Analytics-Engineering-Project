select
    household_id, 
    dbt_valid_from, 
    dbt_valid_to
from
    {{ ref('snap_dim_household_current') }}
where
    dbt_valid_to is not null
    and dbt_valid_to <= dbt_valid_from