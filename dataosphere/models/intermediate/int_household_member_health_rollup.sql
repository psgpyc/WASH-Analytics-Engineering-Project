{{
    config(
        materialized='incremental',
        incremental_strategy='merge',
        unique_key=['household_id', 'submission_id'],
        on_schema_change='sync_all_columns'
    )

}}

with impacted_keys as (
    select  
        distinct household_id, submission_id
    from
        {{ ref('stg_kobo_member') }}
    {% if is_incremental() %}
        where {{ wash_incremental_load_filter(load_col='record_loaded_at') }}
    {% endif %}
),
members_of_impacted as (
    select
        m.*
    from    
        {{ ref('stg_kobo_member') }} m
    join
        impacted_keys k
    on
        m.household_id = k.household_id
        and m.submission_id = k.submission_id

),
grouped as (
    select
        household_id,
        submission_id,
        max(record_loaded_at) as record_loaded_at,
        count(distinct member_index) as member_count,
        SUM(
            cast(member_had_diarrhoea_14d = 'yes' as number(1,0))
        ) as total_diarrhoea_case_count_14d,
        SUM(
            cast(member_had_diarrhoea_14d = 'no' as number(1,0))
        ) as total_no_diarrhoea_count_14d,
        SUM(
            cast(member_had_diarrhoea_14d = 'unknown' as number(1,0))
        ) as total_unknown_diarrhoea_count_14d
    from
        members_of_impacted
    group by
        household_id, submission_id

), add_recorded_count as (
    select
        *,
        (
            total_diarrhoea_case_count_14d 
            + total_no_diarrhoea_count_14d 
            + total_unknown_diarrhoea_count_14d
        ) as total_recorded_cases
    from
        grouped

), set_dq_flags as (
    select
        *,
        (member_count > 15) as dq_invalid_member_count,
        (total_recorded_cases > member_count) as dq_invalid_diarrhoea_case_count,
        (
            total_diarrhoea_case_count_14d = 0
            and
            total_unknown_diarrhoea_count_14d = 0
            and
            (total_no_diarrhoea_count_14d > 0 and total_no_diarrhoea_count_14d = member_count)
    
        ) as has_no_diarrhoea_14d_members
    from    
        add_recorded_count
)
select * from set_dq_flags