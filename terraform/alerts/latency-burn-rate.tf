resource "azurerm_monitor_scheduled_query_rules_alert_v2" "latency_burn_rate" {
  name                = "alert-aduke-latency-burn-rate"
  resource_group_name = data.terraform_remote_state.core.outputs.observability_resource_group_name
  location            = data.terraform_remote_state.core.outputs.observability_location

  evaluation_frequency = "PT5M" # run this check every 5 mins
  window_duration      = "PT5M" # over a 5-mins evaluation window
  scopes               = [data.terraform_remote_state.core.outputs.application_insight_id]
  severity             = 2

  # --- fast window: 5m lookback, catch acute spikes
  criteria {
    query = <<-QUERY
      let sloTargetPercent = 95.0;
      let fastBurn = toscalar(
        requests
        | where timestamp > ago(5m)
        | summarize
            totalRequests = count(),
            slowRequests = countif(duration >= 300)
        | extend currentSlowRatePercent = round( 100.0 * slowRequests / totalRequests, 4)
        | extend allowedSlowRatePercent = 100.0 - sloTargetPercent
        | extend burnRate = round( currentSlowRatePercent / allowedSlowRatePercent, 2)
        | where totalRequests > 0
        | project burnRate
      );
      let slowBurn = toscalar(
        requests
        | where timestamp > ago(1h)
        | summarize
            totalRequests = count(),
            slowRequests = countif(success == false)
        | extend currentSlowRatePercent = round( 100.0 * slowRequests / totalRequests, 4)
        | extend allowedSlowRatePercent = 100.0 - sloTargetPercent
        | extend burnRate = round( currentSlowRatePercent / allowedSlowRatePercent, 2)
        | where totalRequests > 0
        | project burnRate
      );
      print combineBurnRate = min_of( coalesce(fastBurn, 0.0), coalesce(slowBurn, 0.0));
    QUERY

    time_aggregation_method = "Maximum"
    threshold               = 14.4 // 2% of a 30 days budget consumed within 1 hour
    operator                = "GreaterThan"
    metric_measure_column   = "combineBurnRate"

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.ops_notifications.id]
  }

  description = <<-DESC
    Multi-window burn-rate alert for the 95%/30-day latency SLO
    Fires only when BOTH the 5 minute and 1-hour burn rate exceed 14.4x
    (Google SRE's fast burn threshold - exhaust a 30 day budget in ~50h at that rate)
  DESC
  enabled     = true
}

