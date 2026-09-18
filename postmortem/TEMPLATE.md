# Postmortem: [Incident Title]

**Date:** [date]
**Author:** Omotayo
**Severity:** [Sev level, alert tier that fired]
**Status:** Resolved

## Summary

[2-3 sentences: what happened, what was the user/system impact, how was it resolved. Someone should be able to read only this section and understand the incident.]

## Impact

- **Duration:** [total incident duration, fault_introduced_at → recovery_confirmed_at]
- **Affected:** [which endpoint(s)/users/requests were impacted]
- **SLO impact:** [how much of the 30-day error budget this incident consumed — calculate using the burn-rate math: duration × burn rate ÷ total budget]

## Timeline

All times [timezone].

| Time | Event |
|---|---|
| [fault_introduced_at] | Fault committed to [route] |
| [deploy_completed_at] | ArgoCD synced the change to production |
| [alert_fired_at] | `alert-aduke-availability-burn-rate-ticket` fired |
| [acknowledged_at] | Alert acknowledged |
| [+Xm] | Diagnosis: `error-rate-by-endpoint.kql` confirmed elevated rate on [route] |
| [+Xm] | Diagnosis: `top-exceptions.kql` confirmed [exception type] |
| [mitigation_applied_at] | Mitigated via [rollback/other action] |
| [recovery_confirmed_at] | Confirmed error rate returned to baseline |

**Alert-to-acknowledgment:** [X minutes]
**Acknowledgment-to-mitigation:** [X minutes]

## Root cause

[What actually caused the failure — be specific. "A deliberately introduced unhandled exception on 30% of requests to [route], injected as part of a planned fault-injection exercise to validate the availability burn-rate alert and runbook."]

## What went well

- [e.g., alert fired within expected time given the burn-rate math]
- [e.g., runbook's diagnostic queries surfaced the exact cause without guesswork]

## What went wrong / what would you change

[Be honest here — this section is the actual point of a postmortem. Did the runbook miss a step? Was a query slower to interpret than expected? Did the alert take longer to fire than the burn-rate math predicted, and if so, why?]

## Action items

| Action | Owner | Status |
|---|---|---|
| [e.g., "Add a synthetic canary check for this route"] | Omotayo | Not started |
| [e.g., "Update runbook step 3 to mention X"] | Omotayo | Not started |