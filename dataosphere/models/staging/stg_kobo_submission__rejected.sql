-- models/staging/kobo/stg_kobo_submission__rejected.sql
-- Purpose: quarantine rows that fail staging data-quality rules (for audit + monitoring)

with source as (
    -- IMPORTANT:
    -- We quarantine from the same "standardised" logic as stg_kobo_submission,
    -- so rejected and accepted records are comparable and traceable.

    select 
        *
    from    
        {{ ref('stg_kobo_submission__base')}}
), 
final as (
    select 
        *
    from    
        source
    where
        dq_missing_submission_id = true
        or dq_submitted_missing_submitted_at = true
        or dq_missing_blank_municipality = true
        or dq_missing_blank_district = true
        or dq_invalid_gps = true
        or is_deleted = true
        or dq_missing_blank_enumerator_id = true
)
select * from final