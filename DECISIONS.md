# DECISIONS.md

Living log of architectural decisions for `azure-aks-observability-platform`.
Entries are appended in the order decisions were actually made — including
decisions that were revised — rather than rewritten to look pre-planned.

---

**Decision: hybrid architecture — Application Insights/KQL for app-level
telemetry, Prometheus/Grafana for infrastructure telemetry.**
Considered Azure-native only (simplest, fully managed) and fully OSS
(Prometheus + self-hosted Grafana, minimal Azure Monitor). Chose the
hybrid because it demonstrates the widest range of real skill — KQL,
PromQL, Helm, GitOps, cross-source dashboarding — and mirrors a genuine
enterprise pattern where AKS-hosted apps commonly split app telemetry
(Azure-native APM) from cluster telemetry (Prometheus).

**Decision: OpenTelemetry SDK for Aduke's instrumentation, not the
Application Insights classic SDK.**
OTel is vendor-neutral and is the direction Microsoft itself is migrating
App Insights toward. Costs more setup than auto-instrumentation via the
classic SDK, but avoids vendor lock-in in the instrumentation layer itself.

**Decision: workload identity for Aduke's App Insights auth, not a
connection string.**
Reuses the federated identity already built for `aks-production` — zero
new secrets. Fallback documented (connection string via K8s Secret) in
case the OTel Azure Monitor Exporter's Entra ID auth path proved
under-documented; not needed in practice.

**Decision: saturation lives in Prometheus, not in Aduke's own OTel
metrics.**
App Insights answers "is the app healthy" (latency, traffic, errors, all
from Aduke's own OTel SDK); Prometheus answers "is the infra underneath
it under pressure" (CPU, memory, from cluster-level scraping). One
golden signal, one clear owner — avoids duplicating saturation data
across two pipelines.

**Decision: `WorkloadIdentityCredential` explicitly, not
`DefaultAzureCredential`.**
`DefaultAzureCredential`'s auth-chain fallback behavior is convenient for
local dev but obscures which method actually authenticated in
production. Being explicit removes a category of "why did auth silently
fall back" debugging.

**Decision: Grafana gets its own dedicated managed identity
(`mi-grafana-monitor-reader`), not Aduke's identity reused.**
Grafana only ever needs to *read* telemetry; Aduke's identity can
*write* it (Monitoring Metrics Publisher). Sharing an identity would
mean a compromised Grafana instance inherits write access to the
telemetry pipeline. Scoped to `Log Analytics Reader` on the shared
workspace specifically, not subscription-wide `Monitoring Reader`.

**Decision: Aduke's identity role assignment lives in this repo, not
the AKS platform repo.**
The role assignment needs to reference both sides (the App Insights
resource being protected, and the identity being granted access) — App
Insights doesn't exist until this repo applies, so this repo reaching
backward to a stable, already-provisioned identity is a cleaner
dependency direction than the AKS repo reaching forward to a resource
built after it.

**Decision: `aduke_identity_principal_id` passed as a plain variable
(via GitHub Actions repository variable), not via `terraform_remote_state`
into the AKS repo.**
Unlike the shared logging workspace (deliberately shared platform
infra, correctly coupled via remote state), Aduke's identity is an
implementation detail of one app in one other repo — reaching into that
repo's state for one value is tighter coupling than the relationship
calls for.

**Decision: `TF_VAR_ADUKE_IDENTITY_PRINCIPAL_ID` as a GitHub Actions
repository variable, not committed in `terraform.tfvars`.**
Keeps the real value in exactly one place rather than duplicated across
a local file and memory of whether it's been updated; avoids a
placeholder value sitting permanently in git history.

**Decision: `precondition` guard on the role assignment resource,
checking for both the original placeholder and an empty string.**
Makes `apply` hard-stop with a clear message if the real principal ID
hasn't been set, rather than silently creating a broken role assignment
that only surfaces as a confusing `403` later when Aduke tries to send
telemetry.

**Decision: Helm chart wraps `kube-prometheus-stack` as a pinned
dependency, not vendored.**
Vendoring would mean carrying someone else's large template set as if
it were reviewed/authored code, and would turn a version bump into a
multi-thousand-line diff. Remote reference with a pinned version gets
full reproducibility without carrying unowned code.

**Decision: one Helm chart per logical, independently-lifecycled
component — not one chart with multiple unrelated dependencies.**
`kube-prometheus-stack` is one component (monitoring); cert-manager,
if/when added, is a genuinely separate concern (cluster-wide TLS,
useful to any Ingress) and will get its own chart + its own ArgoCD
Application. Bundling unrelated components under one Chart.yaml would
couple their upgrade lifecycles for no reason.

**Decision: app-of-apps GitOps structure, reversed back in after
initially being deferred.**
Initially deferred (single-component cluster didn't justify the extra
indirection); revisited once a second component (cert-manager) was
anticipated on the roadmap — that's the threshold where app-of-apps
starts earning its keep.

**Decision: `charts/` and `gitops/` as separate top-level folders.**
`charts/` holds what gets deployed (chart definitions, values,
templates); `gitops/` holds how ArgoCD finds out about it (pure
Application manifests). Keeps "deployable content" and "ArgoCD wiring"
from being interleaved in one folder.

**Decision: Grafana's Azure Monitor data source uses workload identity
auth, matching the pattern used everywhere else in this cluster.**

**Decision: Grafana exposed via `kubectl port-forward` only — no
Ingress/public endpoint, for now.**
No owned domain at the time this was built, and this is a non-production
lab accessed on-demand rather than continuously. Revisit once a domain
exists — Ingress + cert-manager + Let's Encrypt is the designed target
state, documented but not yet built.

**Decision: Grafana admin credentials sourced from Key Vault via the
Secrets Store CSI driver, not chart-auto-generated or hardcoded.**
Reuses the CSI pattern already proven on this cluster from the AKS
project, rather than introducing a second, disconnected secrets
mechanism.

**Decision: Alertmanager's webhook routing uses a native
`AlertmanagerConfig` CRD with `urlSecret`, not an inline `values.yaml`
config block.**
The inline `alertmanager.config` block requires embedding the webhook
URL directly in values, which shouldn't hold a value that functions as
a bearer credential. `urlSecret` is a purpose-built mechanism for
referencing a Kubernetes Secret by name/key, avoiding the need to
hand-assemble a full Alertmanager config blob just to keep one field
out of plaintext.

**Decision: KQL/PromQL query folders split as `queries/kql/` and
`queries/ql/`, not merged into one folder.**
Iterated from a single `kql/` folder (containing PromQL files too, with
a README caveat) to fully split folders — more accurate, since a
PromQL file sitting in a folder literally named `kql/` was a naming
inconsistency not worth defending once a cleaner option existed.

**Decision: SLI measured as "% of requests under 300ms" (a `countif`),
not `percentile(duration, 95) < 300` directly.**
Both are close to the same statement, but the `countif`/percentage
framing composes directly into burn-rate math ("X% of budget consumed
per hour"), whereas a raw percentile threshold doesn't decompose into a
budget-consumption rate the same way.

**Decision: 99.5% / 30-day availability SLO, 95% of requests < 300ms
latency SLO.**
99.5% (not 99.9%) is honest given the architecture — a single-instance
app without cross-AZ redundancy claiming 99.9% would be aspirational,
not realistic. p95 (not average or p99) balances catching real
degradation against chasing noise from rare, non-systemic outliers.

**Decision: no SLA defined.**
This project has no external customer relationship to formalize a
contractual promise around — inventing one would misrepresent a
commitment nobody's actually bound by. In production, an SLA would
typically be set looser than the internal SLO, giving room to catch and
fix degradation before it becomes a customer-facing contractual breach.

**Decision: multi-window, multi-burn-rate alerting (Google SRE model),
not a single-window threshold.**
A single window (e.g., `ago(5m)` alone) is either too noisy (short
window, false positives on a low-traffic app) or too slow to clear
(long window, stale data keeps re-triggering after the real issue is
fixed). Two windows (fast + slow) must both breach before firing,
confirmed against the ARM API's actual `criteria.allOf` semantics
(all conditions required, not any) — verified via Microsoft's own API
schema, not assumed.

**Decision: 14.4x burn-rate threshold (page-tier) and 6x (ticket-tier),
adopted from Google's published SRE burn-rate model, not invented
values.**
14.4x corresponds to burning 2% of a 30-day budget within 1 hour; 6x
corresponds to burning 5% within 6 hours. Implemented 2 of Google's 4
published tiers (page and ticket); the remaining slower tiers (3x/24h,
1x/3d) follow the identical pattern, scoped out for project size.

**Decision: differentiated severities and routing by alert tier.**
Page-tier alerts route to email + Teams webhook; ticket-tier alerts
route to email only. Treating every alert as equally urgent is a known
cause of alert fatigue — this differentiation is a deliberate,
demonstrable design choice, not an oversight.

**Decision: Grafonnet (dashboard-as-code), not a UI-exported dashboard
JSON.**
More setup (Jsonnet, `jsonnet-bundler`, a compile step) than exporting
from the UI once, but `importstr` lets dashboard panels reference the
exact same `.kql`/`.promql` files used for ad-hoc investigation —
eliminating query duplication between the query library and the
dashboard, which a UI-exported JSON blob would not achieve.

**Decision: two separate runbooks (availability, latency), not one
generic incident doc.**
The diagnostic paths genuinely diverge — a failed request leaves
exception data; a slow-but-successful request doesn't. A runbook tied
to one specific, known failure signature is more useful during a real
incident than a vague generalist document.

**Decision: fault injection uses a partial (~30%) failure rate on one
route, not a full outage.**
More realistic, and gives the diagnostic queries (`error-rate-by-
endpoint.kql`, `top-exceptions.kql`) genuinely useful data to surface,
rather than an instant, uninteresting 100%-failure result.

**Decision: fault is mitigated as soon as the ticket-tier (6x) alert
fires, not held open to also force the page-tier (14.4x) alert.**
Favors realistic incident response speed over proving every alert tier
fires within a single exercise. The page-tier alert's correctness is
covered by design (identical pattern, verified `allOf` logic, higher
threshold) rather than by deliberately prolonging a self-induced
incident.