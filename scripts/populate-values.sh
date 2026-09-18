#!/usr/bin/env bash
# Replaces the manual "copy each terraform output into values.yaml by
# hand" step (VALIDATION.md Step 3/9) with an automated one.
# Uses yq (YAML-aware editing), not sed - sed does blind text
# substitution and risks corrupting YAML structure if a value ever
# contains a character sed treats specially; yq understands the file as
# actual YAML and edits specific keys safely regardless of content.
#
# Run this from the repo root, AFTER `terraform apply` has succeeded
# in terraform/core/. Requires: yq (https://github.com/mikefarah/yq),
# jq, terraform.
set -euo pipefail

if ! command -v yq &> /dev/null; then
  echo "yq is required but not installed. See https://github.com/mikefarah/yq"
  exit 1
fi

cd terraform/core
OUTPUTS=$(terraform output -json)
cd ../..

get() { echo "$OUTPUTS" | jq -r ".$1.value"; }

GRAFANA_CLIENT_ID=$(get grafana_identity_client_id)
SUBSCRIPTION_ID=$(get subscription_id)
TENANT_ID=$(get tenant_id)

echo "=== Populating charts/aduke-monitoring/values.yaml ==="
# "kube-prometheus-stack" is quoted in the yq path because it contains
# a hyphen, which yq's expression parser would otherwise treat as an
# operator rather than part of the key name.
#
# The serviceAccount annotation is deliberately NOT set to a raw value
# here - it stays as the literal template string referencing
# .Values.global.grafanaIdentityClientId, so this client ID exists in
# exactly one place in the file (see DECISIONS.md - this project
# already hit and fixed the duplication bug once).
yq -i "
  .global.grafanaIdentityClientId = \"${GRAFANA_CLIENT_ID}\" |
  .keyVaultTenantId = \"${TENANT_ID}\" |
  .\"kube-prometheus-stack\".grafana.serviceAccount.annotations.\"azure.workload.identity/client-id\" = \"{{ .Values.global.grafanaIdentityClientId }}\" |
  .\"kube-prometheus-stack\".grafana.additionalDataSources[0].jsonData.subscriptionId = \"${SUBSCRIPTION_ID}\" |
  .\"kube-prometheus-stack\".grafana.additionalDataSources[0].jsonData.tenantId = \"${TENANT_ID}\"
" charts/aduke-monitoring/values.yaml

echo ""
echo "=== Done. Confirm no REPLACE_WITH_TERRAFORM_OUTPUT placeholders remain: ==="
grep -rn "REPLACE_WITH_TERRAFORM_OUTPUT" charts/aduke-monitoring/values.yaml && echo "WARNING: placeholders still remain above" || echo "Clean - no placeholders left"
