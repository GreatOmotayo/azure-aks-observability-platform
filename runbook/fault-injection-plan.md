# Fault Injection Plan — Availability SLO Incident

**Status:** Planned / Not yet executed
**Target alert:** `alert-aduke-availability-burn-rate-ticket` (Sev 3, 6x threshold)
**Runbook exercised:** `runbook/api-error-rate-spike.md`

## Objective

Deliberately inject a realistic partial-failure fault into Aduke, confirm the
availability burn-rate alert fires, follow the runbook to diagnose and
mitigate, and record real timestamps for the postmortem's
alert-to-acknowledgment and acknowledgment-to-mitigation intervals.

## Scope decision

The fault is fixed as soon as the **ticket-tier (6x)** alert fires and the
runbook's steps are complete — not held open to also force the page-tier
(14.4x) alert. This favors realistic response speed over proving every
alert tier fires in one exercise. The page-tier alert's correctness is
covered by design (identical logic/pattern, higher threshold, already
verified via the `criteria.allOf` AND-logic research) rather than by a
second, deliberately prolonged incident.

## The fault

Modify one existing Aduke route (non-health-check endpoint) to throw an
unhandled exception on ~30% of requests — a partial degradation, not a
full outage. Chosen over a 100%-failure fault because it's more realistic
and gives `error-rate-by-endpoint.kql` and `top-exceptions.kql` genuinely
useful data to surface, rather than an obvious, uninteresting result.

## Execution steps and timestamps to record

| Step | Action | Timestamp to record |
|---|---|---|
| 1 | Commit the fault to the target route | `fault_introduced_at` |
| 2 | ArgoCD syncs the change to `aks-production` | `deploy_completed_at` |
| 3 | Ticket-tier alert notification received | `alert_fired_at` |
| 4 | Alert acknowledged | `acknowledged_at` |
| 5 | Run `error-rate-by-endpoint.kql` — confirm elevated rate on target route | — |
| 6 | Run `top-exceptions.kql` — confirm injected exception appears | — |
| 7 | Mitigate: `kubectl rollout undo deployment/aduke -n production` (or revert via ArgoCD) | `mitigation_applied_at` |
| 8 | Re-run `error-rate-by-endpoint.kql` — confirm return to baseline | `recovery_confirmed_at` |

## Derived metrics (calculated after execution)

- **Alert-to-acknowledgment:** `acknowledged_at - alert_fired_at`
- **Acknowledgment-to-mitigation:** `mitigation_applied_at - acknowledged_at`
- **Total incident duration:** `recovery_confirmed_at - fault_introduced_at`

## What happens next

These timestamps and the diagnostic findings from steps 5–6 feed directly
into `postmortem/availability-incident.md`, following the standard
timeline / impact / root cause / what-we'd-change structure.