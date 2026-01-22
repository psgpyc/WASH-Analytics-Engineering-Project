{{ 
    config(
        materialized='table', 
        schema='monitoring', 
    ) 
}}

with base as (
  select
    ward_id,
    to_date(submitted_at) as event_date,
    submitted_at,
    record_loaded_at
  from {{ ref('int_submission_submitted') }}
  where submitted_at is not null
    and record_loaded_at is not null
),

agg as (
  select
    ward_id,
    event_date,
    count(*) as submissions_total,
    sum(
      case
        when to_date(submitted_at) < to_date(record_loaded_at) then 1 else 0
      end
    ) as submissions_late
  from base
  group by 1, 2
)

select
  ward_id,
  event_date,
  submissions_total,
  submissions_late,
  case
    when submissions_total = 0 then 0
    else submissions_late / submissions_total::float
  end as late_arrival_rate
from agg