{% snapshot snap_dim_household_current %}

{{
  config(
    target_schema='snapshots',
    unique_key='household_id',
    strategy='check',
    check_cols=[
      'ward_id',
      'district',
      'municipality',
      'hh_size_reported',
      'has_toilet',
      'water_filter_type',
      'primary_water_source'
    ],
    invalidate_hard_deletes=true
  )
}}

select
  household_id,
  ward_id,
  district,
  municipality,
  hh_size_reported,
  has_toilet,
  water_filter_type,
  primary_water_source,
  submission_id
from {{ ref('int_household_current_source') }}

{% endsnapshot %}