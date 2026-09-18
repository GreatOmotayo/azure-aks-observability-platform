# DEPLOYMENT.md

How `charts/aduke-monitoring` actually becomes running pods on
`aks-production`. Written because the mechanics (Helm subcharts +
ArgoCD app-of-apps) aren't obvious from reading the repo structure alone.

## Prerequisite

ArgoCD must already be installed and running on `aks-production` —
this repo does not install ArgoCD itself.

## One-time local setup (before first deploy)

```bash
cd charts/aduke-monitoring
helm dependency update
```

This reads `Chart.yaml`'s `dependencies:` block, downloads the pinned
`kube-prometheus-stack` release from the Prometheus community's Helm
repo as a `.tgz`, drops it into `charts/aduke-monitoring/charts/`, and
writes `Chart.lock`. Commit both `Chart.lock` and the `.tgz` — this is
what makes deploys reproducible and lets ArgoCD render the chart
without needing live network access to the upstream Helm repo at
sync time.

## The deploy chain

1. **Bootstrap the root Application (one-time, manual):**
```bash
   kubectl apply -f gitops/root-app.yaml
```
   This can't be GitOps-managed itself — someone has to apply it once.

2. **ArgoCD discovers child Applications.** `root-app.yaml` watches
   `gitops/apps/` (`directory.recurse: true`) and finds
   `aduke-monitoring.yaml`.

3. **ArgoCD creates the `aduke-monitoring` Application**, whose source
   points at `charts/aduke-monitoring`.

4. **ArgoCD renders the chart** — the Helm equivalent of `helm
   template`, combining:
   - Your own `templates/*.yaml` (SecretProviderClasses, AlertmanagerConfig)
   - The `kube-prometheus-stack` subchart's own templates (already
     written by its maintainers, living inside the `.tgz` — you never
     see or edit these directly)
   both driven by `values.yaml` — your top-level keys feed your
   templates; the nested `kube-prometheus-stack:` block feeds the
   subchart's templates, scoped automatically by Helm.

5. **ArgoCD applies the rendered manifests** to the `monitoring`
   namespace (auto-created via `syncOptions: CreateNamespace=true`).

6. **Kubernetes scheduling takes over** — ordinary pod creation,
   image pulls, nothing Helm/ArgoCD-specific from here.

7. **The Secrets Store CSI driver mounts Key Vault secrets** into the
   Grafana pod at startup, using Grafana's federated workload identity,
   materializing `grafana-admin-credentials`.

8. **Verify:**
```bash
   kubectl get application -n argocd      # both root-app and aduke-monitoring should show Synced + Healthy
   kubectl get pods -n monitoring
```

## Why Prometheus/Alertmanager don't have their own `gitops/apps/` entry

They're not separate components — they're dependencies *of*
`aduke-monitoring`, declared in its `Chart.yaml`. One ArgoCD
Application renders and deploys the whole chart (your templates +
the subchart's), as one unit. A second `gitops/apps/` entry pointing
directly at `kube-prometheus-stack` would create a conflicting second
Application fighting over the same Kubernetes objects — this was a
deliberate design choice (see DECISIONS.md), not a gap.

## Updating the dashboard

```bash
make dashboard   # compiles dashboards/jsonnet/golden-signals.jsonnet
                 # → dashboards/golden-signals.json, loaded into Grafana
                 # via the ConfigMap sidecar on next ArgoCD sync
```

## Common failure modes

- **Dashboard doesn't appear in Grafana:** check the sidecar's logs
  (`kubectl logs -n monitoring <grafana-pod> -c grafana-sc-dashboard`)
  before assuming the ConfigMap or label is wrong — this fails silently.
- **KQL/PromQL columns "unknown":** confirm you're querying the Portal's
  Logs blade directly, not a disconnected VS Code extension. Also
  confirm workspace-based App Insights schema (`TimeGenerated`, not
  `timestamp`).