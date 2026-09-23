# VALIDATION.md

## Step 0 — Dependency

This project depends on `azure-aks-container-platform`. Run that
project's own validation plan first (see its `docs/VALIDATION-PLAN.md`).

Repo variables already configured in this project's GitHub Actions:
`AZURE_CLIENT_ID`, `AZURE_TENANT_ID`, `AZURE_SUBSCRIPTION_ID`,
`AZURE_PLATFORM_SUBSCRIPTION_ID`, `GRAFANA_ADMIN_PASSWORD`.

---

## Step 1 — Cluster prerequisites

```bash
kubectl get application -A
```

---

## Step 2 — Apply core Terraform

```bash
cd terraform/core && terraform init && terraform plan
```

```bash
terraform apply
```

---

## Step 3 — populate-values.sh (now CI-automated)

- [ ] Confirm `terraform-core.yml`'s apply job runs `scripts/populate-values.sh` and auto-commits on diff, `[skip ci]` tagged
- [ ] After any `terraform/core` apply, confirm the auto-commit landed:
  ```bash
  git log -1 --oneline -- charts/aduke-monitoring/values.yaml
  ```

---

## Step 4 — Wire Aduke to send telemetry

```bash
kubectl get pods -n app
kubectl describe pod <pod> -n app   # if stuck, check events first
```

---

## Step 5 — Confirm connection string reaches the app

```bash
kubectl exec -n app <pod> -- env | grep APPLICATIONINSIGHTS
```
- [ ] Instrumentation key matches `appi-aduke`'s real current key (re-check after any `terraform/core` destroy/recreate — this drifted twice)

---

## Step 6 — Confirm real telemetry lands

In Portal, on `appi-aduke`'s own Logs blade (both `timestamp` and `TimeGenerated` work here specifically):
```kql
requests | where timestamp > ago(10m) | count
```
- [ ] > 0. If 0, generate real traffic through the actual UI/ingress endpoint — not `kubectl exec ... curl` (image likely has no `curl`; use `wget`, or a disposable `curlimages/curl` pod, or the real external hostname)

---

## Step 7 — Validate the query library

Run each `queries/kql/*.kql` and `queries/ql/*.promql` against real data. Confirm output shape and plausible values.

---

## Step 8 — Apply alert Terraform (requires Step 6 > 0)

```bash
cd terraform/alerts && terraform init && terraform plan && terraform apply
```

---

## Step 9 — Deploy the Helm chart via ArgoCD

```bash
cd charts/aduke-monitoring && helm dependency update
git add Chart.lock charts/*.tgz && git commit -m "chore: vendor dependency" && git push
```
- [ ] Verify pinned chart version against the real current release (Artifact Hub) — do not guess
- [ ] `values.yaml` fields checked against the real subchart source before trusting them across a large version bump (`extraSecretMounts`, `additionalDataSources`, `sidecar.dashboards`, `alertmanagerConfigSelector`)

```bash
kubectl apply -f gitops/observability-root-app.yaml   # one-time only
kubectl get application -n argocd
```
- [ ] Both root and child Application `Synced` + `Healthy`

```bash
kubectl get crd | grep monitoring.coreos.com
```
- [ ] `prometheuses`/`alertmanagers`/`alertmanagerconfigs` present

```bash
kubectl get pods -n monitoring
kubectl get prometheus -n monitoring
kubectl get alertmanager -n monitoring
```
- [ ] Grafana, Prometheus, Alertmanager pods all `Running` (not just Operator/exporters)

**If a `SecretProviderClass`, ConfigMap, or other CRD's specific nested field doesn't reflect a committed git change despite ArgoCD reporting `Synced`:**
```bash
kubectl get <resource> <name> -n monitoring -o yaml | grep -A N "<field>"   # verify live object directly, don't trust reported status
kubectl patch application aduke-monitoring -n argocd --type merge -p '{"metadata":{"annotations":{"argocd.argoproj.io/refresh":"hard"}}}'
# if still stale after refresh + wait:
kubectl patch <resource> <name> -n monitoring --type merge -p '{"spec":{...specific corrected field...}}'
```
This has recurred on: `SecretProviderClass.spec.parameters.clientID`, `SecretProviderClass.spec.secretObjects`, ConfigMap `grafana.ini` content, dashboard ConfigMap. Always verify the live object, never assume sync status reflects reality for these resource types.

**Grafana pod won't start — check in this order (each confirmed as a real, distinct bug this build):**
1. `extraSecretMounts[].csi` must be the full nested `{driver, readOnly, volumeAttributes}` object, not `csi: true` + sibling keys
2. Key Vault secret referenced by `SecretProviderClass` must actually exist
3. `useVMManagedIdentity` must be `"false"` — `"true"` fails with "multiple user assigned identities exist"
4. `global.grafanaIdentityClientId` must match `terraform output` current value — re-verify after any identity recreation
5. Federated credential `subject` must exactly match the real ServiceAccount name (`system:serviceaccount:<ns>:<name>`)
6. Identity needs `Key Vault Secrets User` on the vault (separate from `Log Analytics Reader`)
7. `admin.existingSecret` requires BOTH `admin-user` and `admin-password` keys in the Secret, unconditionally — chart's `userKey` default is `admin-user` even if unset in `values.yaml`
8. Grafana server config needs `grafana.ini: {azure: {workload_identity_enabled: true}}` — separate from the datasource's own `azureAuthType: workloadidentity` setting; Grafana refuses the query without this

```bash
kubectl exec <pod> -n monitoring -c grafana -- env | grep AZURE   # confirm actually-injected values, not assumed
```

---

## Step 10 — Grafana dashboard renders real data

```bash
kubectl port-forward -n monitoring svc/aduke-monitoring-grafana 3000:80
# from jumpbox: also `ssh -L 3000:localhost:3000 <jumpbox>` from local machine
```

- [ ] Dashboard "Aduke — Golden Signals" appears (check sidecar logs if not: `-c grafana-sc-dashboard`)
- [ ] Each Azure Monitor datasource panel: click "Test" on the datasource itself first — if it fails with "Workload Identity authentication is not enabled," that's Step 9 item 8, not this panel
- [ ] Each KQL panel individually has a **Resource** explicitly selected — unset resource silently fails or defaults to the raw workspace
- [ ] If resource picker shows only `law-platform-shared` (workspace) and not `appi-aduke`: grant `Log Analytics Reader` scoped to `appi-aduke` directly (separate grant from the workspace-level one)
- [ ] Confirm which schema you're querying: App Insights compat view (`requests`, `timestamp`, `success`, `operation_Name`) requires the resource set to `appi-aduke`; the raw workspace (`law-platform-shared`) requires the native schema (`AppRequests`, `TimeGenerated`, `Success`, `DurationMs`, `OperationName`) — these are not interchangeable
- [ ] Bake the resolved `resource` field into `golden-signals.jsonnet`'s `kqlTarget()` so `make dashboard` regenerates correctly without manual per-panel UI selection
- [ ] Stat panel units: `standardOptions.withUnit()` at panel level applies to ALL fields; use `standardOptions.override.byName` to scope a unit to specific fields only

---

## Step 11 — Baseline / negative alert test

- [ ] Watch burn-rate panels 30+ min under normal load
- [ ] Both stay comfortably under 1

---

## Step 12 — Fault injection

Per `runbook/fault-injection-plan.md`. Record: `fault_introduced_at`, `alert_fired_at`, `acknowledged_at`, `mitigation_applied_at`, `recovery_confirmed_at`.

---

## Step 13 — Postmortem

Fill `postmortem/TEMPLATE.md` → `postmortem/availability-incident.md` with real timestamps, Step 11 baseline, honest runbook assessment.

---

## Done-state checklist

- [ ] Real postmortem, not template
- [ ] Dashboard confirmed on real data
- [ ] Alert documented NOT firing under normal load AND firing correctly during fault injection
- [ ] `core/` and `alerts/` Terraform both apply cleanly and independently