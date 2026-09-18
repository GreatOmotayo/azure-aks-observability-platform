# Runbook: p95 Latency Degradation — Latency SLO Burn

**Alert(s) that trigger this runbook:**
`alert-aduke-latency-burn-rate` (page, Sev 2) or
`alert-aduke-latency-burn-rate-ticket` (ticket, Sev 3)

**Owns:** Aduke API — 95% of requests < 300ms / 30-day latency SLO

---

## 1. Acknowledge (target: < 5 min)

- Acknowledge the page/ticket.
- Note acknowledgment time — starts the alert-to-ack clock for the postmortem.

## 2. Confirm it's real (target: < 5 min)

Run in the Portal (App Insights → Logs):

```kql
// queries/kql/p95-latency-trend.kql
```

- Is the degradation across all endpoints, or concentrated on specific `operation_Name`s?
- Is it a sudden step-change (points to a deploy or a dependency going bad) or a gradual climb (points to resource exhaustion or a slow leak)?
- Cross-check the Grafana dashboard's saturation panels (CPU/memory) — is infra under pressure at the same time?

**If the numbers don't corroborate** (e.g., degradation already resolved, isolated to a single low-traffic endpoint that doesn't matter) → note as a possible false positive, resolve, log in `TROUBLESHOOTING.md`. Stop here.

## 3. Find the fault (target: < 10 min)

Unlike the error-rate runbook, `top-exceptions.kql` won't help here directly — slow requests usually aren't throwing exceptions, they're just slow. Instead:

- Check `queries/ql/node-cpu-saturation.promql` and `pod-memory-saturation.promql` in Grafana — is the node/pod under CPU or memory pressure? Sustained high CPU is a common direct cause of rising latency.
- Check the `dependencies` table in App Insights for slow outbound calls:
```kql
  dependencies
  | where TimeGenerated > ago(30m)
  | summarize p95Duration = percentile(duration, 95) by name, target
  | order by p95Duration desc
```
  A slow downstream dependency (database, external API) is a very common cause of latency degradation that isn't visible in `requests` alone.
- Check recent deploys — same as the error-rate runbook: `argocd app history aduke`, recent commits.
- Check `queries/ql/saturation-forecast.promql` — is this a sudden spike, or has `predict_linear` shown this trending upward for a while (suggesting a slow leak rather than an acute event)?

## 4. Mitigate

| Cause | Action |
|---|---|
| Bad deploy (introduced inefficient code path) | `kubectl rollout undo deployment/aduke -n production`, or revert the ArgoCD-tracked commit |
| Downstream dependency slow | If the dependency has a timeout/retry config, tighten it to fail fast rather than hang; consider a temporary circuit breaker if one exists |
| CPU/memory saturation (confirmed via Prometheus) | `kubectl scale deployment/aduke --replicas=<n> -n production`, or increase resource limits if consistently under-provisioned |
| Gradual climb, no clear trigger (possible leak) | Restart the affected pod(s) as an immediate mitigation (`kubectl rollout restart deployment/aduke -n production`); flag for deeper investigation in the postmortem, since a restart treats the symptom, not the cause |
| Unclear | Escalate — don't guess indefinitely; note escalation time for the postmortem |

Note the time mitigation is applied — ends the ack-to-mitigation clock.

## 5. Confirm recovery

Re-run `p95-latency-trend.kql` — confirm p95 has returned to baseline for at least 10 minutes before considering this resolved.

## 6. After

- Resolve the alert.
- If Sev 1/2: a postmortem is required — see `postmortem/TEMPLATE.md`.
- Log the timeline (detected, acknowledged, mitigated, resolved).