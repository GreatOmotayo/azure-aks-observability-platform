resource "azurerm_monitor_scheduled_query_rules_alert_v2" "availability_burn_rate_slow_tier" {
  name                = "alert-aduke-availability-burn-rate-ticket"
  resource_group_name = data.terraform_remote_state.core.outputs.observability_resource_group_name
  location            = data.terraform_remote_state.core.outputs.observability_location

  evaluation_frequency = "PT30M" # run this check every 30 mins
  window_duration      = "PT30M" # over a 5-mins evaluation window
  scopes               = [data.terraform_remote_state.core.outputs.application_insight_id]
  severity             = 3 # ticket tier

  # --- fast window: 30m lookback, catch acute spikes
  criteria {
    query = <<-QUERY
      let sloTargetPercent = 99.5;
      let fastBurn = toscalar(
        requests
        | where timestamp > ago(30m)
        | summarize
            totalRequests = count(),
            failedRequests = countif(success == false)
        | extend currentErrorRatePercent = round( 100.0 * failedRequests / totalRequests, 4)
        | extend allowedErrorRatePercent = 100.0 - sloTargetPercent
        | extend burnRate = round( currentErrorRatePercent / allowedErrorRatePercent, 2)
        | where totalRequests > 0
        | project burnRate
      );
      let slowBurn = toscalar(
        requests
        | where timestamp > ago(6h)
        | summarize
            totalRequests = count(),
            failedRequests = countif(success == false)
        | extend currentErrorRatePercent = round( 100.0 * failedRequests / totalRequests, 4)
        | extend allowedErrorRatePercent = 100.0 - sloTargetPercent
        | extend burnRate = round( currentErrorRatePercent / allowedErrorRatePercent, 2)
        | where totalRequests > 0
        | project burnRate
      );
      print combineBurnRate = min_of( coalesce(fastBurn, 0.0 ), coalesce(slowBurn, 0.0 ) );
    QUERY

    time_aggregation_method = "Maximum"
    threshold               = 6 // 5% of a 30 days budget consumed within 6 hour
    operator                = "GreaterThan"
    metric_measure_column   = "combineBurnRate"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.lower_ops_notifications.id]
  }

  description = <<-DESC
    Multi-window burn-rate alert for the 99.5%/30-day availability SLO
    Fires only when BOTH the 30 minute and 6-hour burn rate exceed 6x
    (Google SRE's fast burn threshold - exhaust a 30 day budget in ~50h at that rate)
  DESC
  enabled     = true
}

