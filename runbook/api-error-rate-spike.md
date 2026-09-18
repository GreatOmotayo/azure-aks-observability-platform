# Runbook: API Error Rate Spike — Availability SLO Burn

**Alert(s) that trigger this runbook:**
`alert-aduke-availability-burn-rate` (page, Sev 1) or
`alert-aduke-availability-burn-rate-ticket` (ticket, Sev 3)

**Owns:** Aduke API — 99.5% / 30-day availability SLO

---

## 1. Acknowledge (target: < 5 min)

- Acknowledge the page/ticket in Teams or email.
- Note the time you acknowledged — this starts the alert-to-ack clock for the postmortem.

## 2. Confirm it's real (target: < 5 min)

Run in the Portal (App Insights → Logs):

```kql
// queries/kql/error-rate-by-endpoint.kql
```

- Is `errorRatePercent` genuinely elevated, concentrated on specific endpoints, or spread evenly?
- Cross-check the Grafana dashboard's Golden Signals panel — does Prometheus also show elevated saturation (CPU/memory) around the same time, or is this app-only?

**If the numbers don't corroborate the alert** (e.g., total request volume near zero, one-off blip already gone) → note as a possible false positive, resolve the alert, log it in `TROUBLESHOOTING.md` for review. Stop here.

## 3. Find the fault (target: < 10 min)

Run:

```kql
// queries/kql/top-exceptions.kql
```

- What's the top `problemId`? Which `operation_Name` is it concentrated on?
- Check recent deploys — did Aduke's ArgoCD Application sync recently? (`argocd app history aduke` or check the Git commit history around the incident start time.)
- Check pod health directly: `kubectl get pods -n production`, `kubectl logs <pod> --previous` if a pod recently restarted.

## 4. Mitigate

Pick based on what step 3 found:

| Cause | Action |
|---|---|
| Bad deploy | `kubectl rollout undo deployment/aduke -n production`, or revert the ArgoCD-tracked commit |
| Downstream dependency failing | Check dependency health via `dependencies` table in App Insights; consider a temporary circuit breaker / feature flag if one exists |
| Resource exhaustion (confirmed via Prometheus saturation panel) | `kubectl scale deployment/aduke --replicas=<n> -n production` |
| Unclear | Escalate — don't guess indefinitely; note escalation time for the postmortem |

Note the time mitigation is applied — this ends the ack-to-mitigation clock.

## 5. Confirm recovery

Re-run `error-rate-by-endpoint.kql` — confirm `errorRatePercent` has returned to baseline for at least 10 minutes before considering this resolved.

## 6. After

- Resolve the alert.
- If Sev 1/2: a postmortem is required — see `postmortem/TEMPLATE.md`.
- Log the timeline (detected, acknowledged, mitigated, resolved) — this is the raw data the postmortem needs.