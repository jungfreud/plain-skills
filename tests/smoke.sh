#!/usr/bin/env bash
# Read-only smoke test: does the live Plain API still match what the reference documents?
#
# Usage:  PLAIN_SETUP_KEY=plainApiKey_xxx ./tests/smoke.sh
#
# Only runs queries — no mutations, nothing created or changed. Safe against any workspace,
# though a throwaway one is still the sensible choice.

set -uo pipefail

: "${PLAIN_SETUP_KEY:?Set PLAIN_SETUP_KEY (do not paste the key into a chat)}"
ENDPOINT="https://core-api.uk.plain.com/graphql/v1"
PASS=0
FAIL=0

command -v jq >/dev/null || { echo "jq is required"; exit 1; }

q() {
  curl -s -X POST "$ENDPOINT" \
    -H "Authorization: Bearer $PLAIN_SETUP_KEY" \
    -H "Content-Type: application/json" \
    --data "$(jq -nc --arg q "$1" '{query:$q}')"
}

# check <name> <query> <jq-filter-that-must-be-non-null>
check() {
  local name="$1" query="$2" filter="$3" out got
  out=$(q "$query")
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
echo "$PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] || {
  echo
  echo "A failure usually means the API changed and reference/graphql-reference.md is now wrong."
  echo "Please open an issue with the error above."
  exit 1
}
