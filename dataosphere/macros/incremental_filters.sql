{% macro wash_incremental_load_filter(load_col='record_loaded_at',
                                     lookback_var='wash_load_lookback_days',
                                     base_ts="to_timestamp_ntz('1900-01-01')") %}
    
    {{ load_col }} >= dateadd(
                            day, 
                            -{{ var(lookback_var, 7) }}, 
                            (
                                select
                                    coalesce( max({{ load_col }}), {{ base_ts }})
                                from
                                    {{ this }} 
                            )
                        )
   
{% endmacro %}



{% macro wash_event_lookback_filter(lookback_col='event_date',
                                    lookback_var='wash_event_lookback_days') %}
    {{ lookback_col }} >= dateadd(day, -{{var(lookback_var, 30)}}, current_date())

{% endmacro %}