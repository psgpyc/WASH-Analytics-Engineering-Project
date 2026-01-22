select
    household_id,
    count(*) as current_rows
from
    {{ ref('snap_dim_household') }}
where
    dbt_valid_to is null
group by
    household_id
having count(*) > 1