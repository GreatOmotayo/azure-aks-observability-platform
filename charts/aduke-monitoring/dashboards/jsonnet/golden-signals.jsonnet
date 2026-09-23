// dashboards/jsonnet/golden-signals.jsonnet
local g = import 'github.com/grafana/grafonnet/gen/grafonnet-latest/main.libsonnet';

local dashboard = g.dashboard;
local row = g.panel.row;
local timeSeries = g.panel.timeSeries;
local table = g.panel.table;
local stat = g.panel.stat;

// --- Datasource references ---
// Names must match exactly what's configured in values.yaml's
// additionalDataSources (Azure Monitor) and the Prometheus datasource
// kube-prometheus-stack provisions by default.
local azureMonitorDs = { type: 'grafana-azure-monitor-datasource', uid: 'azure-monitor' };
local prometheusDs = { type: 'prometheus', uid: 'prometheus' };
local appInsightsResourceId = '/subscriptions/81da4d58-2cce-415e-b178-7288e443b4a0/resourceGroups/rg-aks-observability/providers/Microsoft.Insights/components/appi-aduke';


// --- Raw KQL target helper ---
// Azure Monitor Logs targets aren't a typed Grafonnet builder — this
// constructs the raw query object the plugin expects.
local kqlTarget(query, refId='A') = {
  datasource: azureMonitorDs,
  refId: refId,
  queryType: 'Azure Log Analytics',
  azureLogAnalytics: {
    query: query,
    resource: appInsightsResourceId,
    resultFormat: 'time_series',
  },
};

// --- Panels ---

local latencyPanel =
  timeSeries.new('p95 Latency Trend')
  + timeSeries.queryOptions.withTargets([
      kqlTarget(importstr '../../../../queries/kql/p95-latency-trend.kql'),
    ])
  + timeSeries.standardOptions.withUnit('ms');

local trafficPanel =
  timeSeries.new('Traffic by Endpoint')
  + timeSeries.queryOptions.withTargets([
      kqlTarget(importstr '../../../../queries/kql/traffic-by-endpoint.kql'),
    ]);

local errorRatePanel =
  timeSeries.new('Error Rate by Endpoint')
  + timeSeries.queryOptions.withTargets([
      kqlTarget(importstr '../../../../queries/kql/error-rate-by-endpoint.kql'),
    ])
  + timeSeries.standardOptions.withUnit('percent');

local topExceptionsPanel =
  table.new('Top Exceptions')
  + table.queryOptions.withTargets([
      kqlTarget(importstr '../../../../queries/kql/top-exceptions.kql'),
    ]);

local cpuSaturationPanel =
  timeSeries.new('Node CPU Saturation')
  + timeSeries.queryOptions.withTargets([
      { datasource: prometheusDs, expr: importstr '../../../../queries/promql/node-cpu-saturation.promql', refId: 'A' },
    ])
  + timeSeries.standardOptions.withUnit('percent')
  + timeSeries.standardOptions.thresholds.withSteps([
      { color: 'green', value: null },
      { color: 'orange', value: 70 },
      { color: 'red', value: 90 },
    ]);

local memSaturationPanel =
  timeSeries.new('Pod Memory Saturation')
  + timeSeries.queryOptions.withTargets([
      { datasource: prometheusDs, expr: importstr '../../../../queries/promql/pod-memory-saturation.promql', refId: 'A' },
    ])
  + timeSeries.standardOptions.withUnit('percent');

local availabilityBudgetPanel =
  stat.new('Availability Error Budget Remaining')
  + stat.queryOptions.withTargets([
      kqlTarget(importstr '../../../../queries/kql/sli-availability.kql'),
    ])
  + stat.standardOptions.withOverrides([
      stat.standardOptions.override.byName.new('availabilityPercent')
      + stat.standardOptions.override.byName.withPropertiesFromOptions(
          stat.standardOptions.withUnit('percent')
        ),
      stat.standardOptions.override.byName.new('errorBudgetRemainingPercent')
      + stat.standardOptions.override.byName.withPropertiesFromOptions(
          stat.standardOptions.withUnit('percent')
        ),
    ]);

local latencyBudgetPanel =
  stat.new('Latency Error Budget Remaining')
  + stat.queryOptions.withTargets([
      kqlTarget(importstr '../../../../queries/kql/sli-latency.kql'),
    ])
  + stat.standardOptions.withOverrides([
      stat.standardOptions.override.byName.new('percentUnder300ms')
      + stat.standardOptions.override.byName.withPropertiesFromOptions(
          stat.standardOptions.withUnit('percent')
        ),
      stat.standardOptions.override.byName.new('errorBudgetRemainingPercent')
      + stat.standardOptions.override.byName.withPropertiesFromOptions(
          stat.standardOptions.withUnit('percent')
        ),
    ]);

// --- Assembly: one row per golden signal, per the layout we designed ---
dashboard.new('Aduke — Golden Signals')
+ dashboard.withUid('aduke-golden-signals')
+ dashboard.withTags(['aduke', 'golden-signals', 'slo'])
+ dashboard.withPanels(
    g.util.grid.makeGrid([
      row.new('Latency') + row.withPanels([latencyPanel]),
      row.new('Traffic') + row.withPanels([trafficPanel]),
      row.new('Errors') + row.withPanels([errorRatePanel, topExceptionsPanel]),
      row.new('Saturation') + row.withPanels([cpuSaturationPanel, memSaturationPanel]),
      row.new('SLO Status') + row.withPanels([availabilityBudgetPanel, latencyBudgetPanel]),
    ])
  )