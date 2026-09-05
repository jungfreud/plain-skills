#!/usr/bin/env bash
# Read-only smoke test: does the live Plain API still match what the reference documents?
#
# Usage: supply PLAIN_API_KEY securely, then ./tests/smoke.sh
#
# Only runs queries — no mutations, nothing created or changed. Safe against any workspace,
# though a throwaway one is still the sensible choice.

set -uo pipefail
cd "$(dirname "$0")/.."

: "${PLAIN_API_KEY:?Set PLAIN_API_KEY (do not paste the key into a chat)}"
ENDPOINT="${PLAIN_API_URL:-https://core-api.uk.plain.com/graphql/v1}"
PASS=0
FAIL=0

command -v jq >/dev/null || { echo "jq is required"; exit 1; }

q() {
  curl -sS --fail-with-body --connect-timeout 10 --max-time 60 -X POST "$ENDPOINT" \
    -H "Authorization: Bearer $PLAIN_API_KEY" \
    -H "Content-Type: application/json" \
    --data "$(jq -nc --arg q "$1" '{query:$q}')"
}

# check <name> <query> <jq-filter-that-must-be-non-null>
check() {
  local name="$1" query="$2" filter="$3" out got
  if ! out=$(q "$query"); then
    printf '  FAIL  %s (transport/HTTP)\n' "$name"; FAIL=$((FAIL+1)); return
  fi
  if ! printf '%s' "$out" | jq -e 'type == "object" and ((.errors // []) | length == 0)' >/dev/null 2>&1; then
    printf '  FAIL  %s (invalid response or GraphQL error)\n' "$name"; FAIL=$((FAIL+1)); return
  fi
  got=$(printf '%s' "$out" | jq -r "$filter" 2>/dev/null)
  if [ -n "$got" ] && [ "$got" != "null" ]; then
    printf '  ok    %s\n' "$name"; PASS=$((PASS+1))
  else
    printf '  FAIL  %s\n' "$name"
    printf '        %s\n' "$(printf '%s' "$out" | jq -c '.errors[0].message // .' 2>/dev/null | cut -c1-200)"
    FAIL=$((FAIL+1))
  fi
}

echo "Plain API smoke test"
echo

echo "Documentation endpoints the skills depend on"
for u in "https://www.plain.com/docs/product/what-is-plain.md" \
         "https://www.plain.com/docs/llms.txt" \
         "https://www.plain.com/docs/graphql-reference/mutations/createTier.md" \
         "https://core-api.uk.plain.com/graphql/v1/schema.graphql"; do
  code=$(curl -sS --connect-timeout 10 --max-time 60 -o /dev/null -w '%{http_code}' "$u")
  if [ "$code" = "200" ]; then
    printf '  ok    %s\n' "$u"; PASS=$((PASS+1))
  else
    printf '  FAIL  %s (HTTP %s)\n' "$u" "$code"; FAIL=$((FAIL+1))
  fi
done
echo

echo "Connectivity and permissions"
check "myWorkspace returns a workspace" \
  'query { myWorkspace { id name } }' '.data.myWorkspace.id'
check "myPermissions returns scopes" \
  'query { myPermissions { permissions } }' '.data.myPermissions.permissions[0]'

echo
echo "Schema shapes the reference depends on"
# DateTime is an object, not a scalar — selecting it bare must fail.
check "DateTime requires subfields (iso8601)" \
  'query { workflows(first: 1) { edges { node { createdAt { iso8601 } } } } }' \
  '.data.workflows'
# KnowledgeSource is a union and needs inline fragments.
check "KnowledgeSource resolves via inline fragments" \
  'query { knowledgeSources(first: 1) { edges { node { __typename ... on KnowledgeSourceSitemap { id } ... on KnowledgeSourceUrl { id } } } } }' \
  '.data.knowledgeSources'
# Metrics: groupBy field is `dimension`, output is `group` (singular).
check "metrics groupBy uses 'dimension', output uses 'group'" \
  'query { threadSingleValueMetric(input: { metricName: threads_resolution_time_median, from: "2020-01-01T00:00:00Z", to: "2020-01-02T00:00:00Z", groupBy: [{ dimension: LABEL_TYPE }], mode: METRIC }) { values { value group { dimension value } } } }' \
  '.data.threadSingleValueMetric'
# Workflow trigger/steps/publish state all readable.
check "workflow trigger + publish state readable" \
  'query { workflows(first: 1) { edges { node { trigger publishedAt { iso8601 } steps { id transitions } } } } }' \
  '.data.workflows'
# Execution traces carry the condition output the tuning loop relies on.
check "workflowExecutionsForWorkspace exposes stepExecutions.output" \
  'query { workflowExecutionsForWorkspace(first: 1) { edges { node { executionStatus stepExecutions { output } } } } }' \
  '.data.workflowExecutionsForWorkspace'

echo
echo "Config surfaces are queryable"
for pair in \
  "labelTypes|query { labelTypes(first: 1) { edges { node { id isExcludedFromAi } } } }|.data.labelTypes" \
  "tiers|query { tiers(first: 1) { edges { node { id } } } }|.data.tiers" \
  "threadFieldSchemas|query { threadFieldSchemas(first: 1) { edges { node { id key } } } }|.data.threadFieldSchemas" \
  "tenantFieldSchemas|query { tenantFieldSchemas(first: 1) { edges { node { id } } } }|.data.tenantFieldSchemas" \
  "escalationPaths|query { escalationPaths(first: 1) { edges { node { id } } } }|.data.escalationPaths" \
  "savedThreadsViews|query { savedThreadsViews(first: 1) { edges { node { id } } } }|.data.savedThreadsViews" \
  "helpCenters|query { helpCenters(first: 1) { edges { node { id } } } }|.data.helpCenters" \
  "webhookTargets|query { webhookTargets(first: 1) { edges { node { id } } } }|.data.webhookTargets" \
  "sidekickSettings|query { sidekickSettings { customPrompt } }|.data.sidekickSettings" \
  "businessHours|query { businessHoursSlots { weekday opensAt } }|.data" \
; do
  IFS='|' read -r name query filter <<< "$pair"
  check "$name" "$query" "$filter"
done

echo
echo "Sidekick configuration reads"
check "Sidekick skills include invocation names and enablement" \
  'query { sidekickSkills { name displayName isEnabled ... on CustomSidekickSkill { customSkillId } } }' '.data.sidekickSkills'
check "Sidekick custom MCP status is readable" \
  'query { sidekickMcpServers { id name isConnected tools { name } } }' '.data.sidekickMcpServers'
check "Sidekick effective policies are readable" \
  'query { agentSandboxToolPolicies { service op mode } }' '.data.agentSandboxToolPolicies'
check "Workflow templates are readable for action payload discovery" \
  'query { workflowTemplateGallery { id title } }' '.data.workflowTemplateGallery'
check "Thread workflow capabilities are readable" \
  'query { workflowCapabilities(triggerType: EVENTS) { allowedActionTypes } }' '.data.workflowCapabilities'
echo

echo "Configuration CLI"
CLI="skills/plain-configuration/scripts/plain-config.sh"
if [ -x "$CLI" ]; then
  bash -n "$CLI" && { printf '  ok    plain-config.sh parses\n'; PASS=$((PASS+1)); } \
                 || { printf '  FAIL  plain-config.sh has a syntax error\n'; FAIL=$((FAIL+1)); }
  if "$CLI" workspace | jq -e '.data.myWorkspace.id' >/dev/null 2>&1; then
    printf '  ok    plain-config.sh workspace\n'; PASS=$((PASS+1))
  else
    printf '  FAIL  plain-config.sh workspace\n'; FAIL=$((FAIL+1))
  fi
  if "$CLI" audit | jq -e '.data.labelTypes' >/dev/null 2>&1; then
    printf '  ok    plain-config.sh audit\n'; PASS=$((PASS+1))
  else
    printf '  FAIL  plain-config.sh audit\n'; FAIL=$((FAIL+1))
  fi
else
  printf '  FAIL  %s not executable\n' "$CLI"; FAIL=$((FAIL+1))
fi

echo
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || {
  echo
  echo "A failure can mean missing permissions, an API shape change, or a documentation endpoint the skills"
  echo "rely on has moved. Please open an issue with the error above."
  exit 1
}
