#!/bin/bash
# Plain Config CLI - configure a Plain workspace via the GraphQL API
# Requires: PLAIN_API_KEY environment variable, curl, jq
#
# Companion to team-plain/plain-support for reading support data.
# Wraps common configuration operations, Sidekick skills and workflow discovery.
# Unwrapped verified operations can use request with query/variables files.
#
# Every command prints the raw JSON response. Mutations surface `error` — always
# check it. Commands that the API validates strictly are wrapped here so the
# caller doesn't have to remember the rules.

set -euo pipefail

API_URL="${PLAIN_API_URL:-https://core-api.uk.plain.com/graphql/v1}"

check_deps() {
    command -v curl >/dev/null 2>&1 || { echo "Error: curl is required" >&2; exit 1; }
    command -v jq   >/dev/null 2>&1 || { echo "Error: jq is required" >&2; exit 1; }
    [ -n "${PLAIN_API_KEY:-}" ] || { echo "Error: PLAIN_API_KEY environment variable is required" >&2; exit 1; }
}

gql() {
    local query="$1" variables="${2:-}" response status=0
    [ -n "$variables" ] || variables='{}'
    response=$(curl -sS --fail-with-body --connect-timeout 10 --max-time 60 -X POST "$API_URL" \
        -H "Content-Type: application/json" \
        -H "Authorization: Bearer $PLAIN_API_KEY" \
        -d "$(jq -n --arg q "$query" --argjson v "$variables" '{query: $q, variables: $v}')") || status=$?
    printf '%s\n' "$response"
    [ "$status" -eq 0 ] || return "$status"
    printf '%s' "$response" | jq -e 'type == "object" and (has("data") or has("errors"))' >/dev/null \
        || { echo "Error: API returned an invalid GraphQL response" >&2; return 1; }
    if printf '%s' "$response" | jq -e '
        ((.errors // []) | length > 0) or
        ([.data[]? | objects | .error? | select(. != null)] | length > 0)' >/dev/null; then
        echo "Error: API operation failed; inspect the returned errors/error fields" >&2
        return 1
    fi
}

# Aggregate a connection without pretending the first page is the entire workspace.
connection() {
    local root="$1" query="$2" after=null page next all='[]'
    while :; do
        page=$(gql "$query" "$(jq -nc --argjson a "$after" '{after:$a}')") || { printf '%s\n' "$page"; return 1; }
        printf '%s' "$page" | jq -e --arg r "$root" \
            '.data[$r] | (.edges | type == "array") and (.pageInfo.hasNextPage | type == "boolean")' >/dev/null \
            || die "Missing connection data for $root; inventory is incomplete"
        all=$(printf '%s\n%s\n' "$all" "$page" | jq -sc --arg r "$root" '.[0] + .[1].data[$r].edges')
        [ "$(printf '%s' "$page" | jq -r --arg r "$root" '.data[$r].pageInfo.hasNextPage')" = true ] || break
        next=$(printf '%s' "$page" | jq -c --arg r "$root" '.data[$r].pageInfo.endCursor')
        [ "$next" != null ] && [ "$next" != "$after" ] || die "Pagination did not advance for $root"
        after="$next"
    done
    printf '%s\n%s\n' "$all" "$page" | jq -sc --arg r "$root" \
        '{data:{($r):{edges:.[0],pageInfo:.[1].data[$r].pageInfo}}}'
}

request() {
    [ -f "${1:-}" ] || die "request: query file required"
    local variables='{}'
    if [ -n "${2:-}" ]; then
        [ -f "$2" ] || die "request: variables file not found"
        variables=$(cat "$2")
        printf '%s' "$variables" | jq -e 'type == "object"' >/dev/null || die "Variables must be a JSON object"
    fi
    gql "$(cat "$1")" "$variables"
}

die() { echo "Error: $*" >&2; exit 1; }

# ============================================================================
# WORKSPACE  — always run these first
# ============================================================================

workspace() {
    gql 'query { myWorkspace { id name publicName } }'
}

permissions() {
    gql 'query { myPermissions { permissions } }'
}

# Everything that exists already. Run before building to avoid duplicates and
# to catch workflows that will fire alongside anything you add.
audit() {
    local out part root selection
    out=$(workspace) || { printf '%s\n' "$out"; return 1; }
    for root in tiers labelTypes threadFieldSchemas workflows savedThreadsViews helpCenters users; do
        case "$root" in
            tiers) part=$(tier_list) || { printf '%s\n' "$part"; return 1; } ;;
            labelTypes) part=$(label_list) || { printf '%s\n' "$part"; return 1; } ;;
            workflows) part=$(workflow_list) || { printf '%s\n' "$part"; return 1; } ;;
            users) part=$(users) || { printf '%s\n' "$part"; return 1; } ;;
            *)
                case "$root" in
                    threadFieldSchemas) selection='id key label' ;;
                    savedThreadsViews) selection='id name' ;;
                    helpCenters) selection='id publicName' ;;
                esac
                part=$(connection "$root" "query(\$after: String) { $root(first: 50, after: \$after) { edges { node { $selection } } pageInfo { hasNextPage endCursor } } }") || { printf '%s\n' "$part"; return 1; } ;;
        esac
        out=$(printf '%s\n%s\n' "$out" "$part" | jq -sc '.[1] as $b | .[0] | .data += $b.data')
    done
    printf '%s\n' "$out"
}

users() {
    connection users 'query($after: String) { users(first: 100, after: $after) {
      edges { node { id publicName email isDeleted labels { labelType { id name type } } } }
      pageInfo { hasNextPage endCursor } } }'
}

teams() { label_list | jq '{data:{teams:[.data.labelTypes.edges[].node | select(.type=="TEAM")]}}'; }

team_add_member() {
    local team="" user=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --team) team="$2"; shift 2 ;;
            --user) user="$2"; shift 2 ;;
            *) die "team add-member: unknown option $1" ;;
        esac
    done
    [ -n "$team" ] && [ -n "$user" ] || die "team add-member: --team and --user required"
    gql 'mutation($i: AddLabelsToUserInput!) { addLabelsToUser(input: $i) {
      user { id publicName labels { labelType { id name type } } }
      error { message code fields { field message } } } }' \
      "$(jq -nc --arg t "$team" --arg u "$user" '{i:{entityId:$u,labelTypeIds:[$t]}}')"
}

# ============================================================================
# LABELS
# ============================================================================

# Defaults isExcludedFromAi to true so the workspace's own triage doesn't
# compete with workflows you build. Pass --ai-managed to opt out.
label_create() {
    local name="" icon="tag" color="#6B7280" desc="" external="" exclude=true kind="DEFAULT"
    while [[ $# -gt 0 ]]; do
        case $1 in
            --name)        name="$2"; shift 2 ;;
            --icon)        icon="$2"; shift 2 ;;
            --color)       color="$2"; shift 2 ;;
            --description) desc="$2"; shift 2 ;;
            --external-id) external="$2"; shift 2 ;;
            --ai-managed)  exclude=false; shift ;;
            --team)        kind="TEAM"; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    [ -n "$name" ] || die "label create: --name is required"
    [ -n "$desc" ] || desc="$name"
    [ -n "$external" ] || external=$(echo "$name" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')
    # icon must be lowercase alphanumeric/underscore/hyphen — emoji are rejected
    if ! echo "$icon" | grep -qE '^[a-z0-9_-]+$'; then
        die "label create: --icon must match ^[a-z0-9_-]+$ (got '$icon'). Emoji are not accepted."
    fi
    gql 'mutation($i: CreateLabelTypeInput!) { createLabelType(input: $i) {
           labelType { id name type isExcludedFromAi }
           error { message code fields { field message } } } }' \
        "$(jq -n --arg n "$name" --arg ic "$icon" --arg c "$color" --arg d "$desc" \
                 --arg e "$external" --argjson x "$exclude" \
                 --arg k "$kind" \
           '{i:{name:$n, icon:$ic, color:$c, type:$k, description:$d, externalId:$e, isExcludedFromAi:$x}}')"
}

label_list() {
    connection labelTypes 'query($after: String) { labelTypes(first: 100, after: $after) {
      edges { node { id name externalId type icon isExcludedFromAi } } pageInfo { hasNextPage endCursor } } }'
}

# ============================================================================
# TIERS AND SLAS
# ============================================================================

tier_create() {
    local name="" external="" color="#5B5FEF" priority=2 is_default=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --name)             name="$2"; shift 2 ;;
            --external-id)      external="$2"; shift 2 ;;
            --color)            color="$2"; shift 2 ;;
            --default-priority) priority="$2"; shift 2 ;;
            --default)          is_default=true; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    [ -n "$name" ] || die "tier create: --name is required"
    [ -n "$external" ] || external=$(echo "$name" | tr '[:upper:] ' '[:lower:]-' | tr -cd 'a-z0-9-')
    gql 'mutation($i: CreateTierInput!) { createTier(input: $i) {
           tier { id name } error { message code fields { field message } } } }' \
        "$(jq -n --arg n "$name" --arg e "$external" --arg c "$color" \
                 --argjson p "$priority" --argjson d "$is_default" \
           '{i:{name:$n, externalId:$e, color:$c, defaultThreadPriority:$p, memberIdentifiers:[], isDefault:$d}}')"
}

tier_list() { connection tiers 'query($after: String) { tiers(first: 50, after: $after) {
  edges { node { id name externalId } } pageInfo { hasNextPage endCursor } } }'; }

# One SLA record holds EITHER a first-response OR a next-response target, never
# both, and breachActions cannot be empty. Both rules are enforced here.
sla_create() {
    local tier="" kind="first" minutes="" bh=true warn=15 priorities=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --tier)           tier="$2"; shift 2 ;;
            --kind)           kind="$2"; shift 2 ;;      # first | next
            --minutes)        minutes="$2"; shift 2 ;;
            --priorities)     priorities="$2"; shift 2 ;; # e.g. "0,1"
            --warn-minutes)   warn="$2"; shift 2 ;;
            --round-the-clock) bh=false; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    [ -n "$tier" ]    || die "sla create: --tier <tier_id> is required"
    [ -n "$minutes" ] || die "sla create: --minutes is required"
    case "$kind" in first|next) ;; *) die "sla create: --kind must be 'first' or 'next'" ;; esac

    local sla
    if [ "$kind" = "first" ]; then
        sla=$(jq -n --argjson m "$minutes" --argjson b "$bh" --argjson w "$warn" \
              '{firstResponseTimeMinutes:$m, useBusinessHoursOnly:$b, breachActions:[{beforeBreachAction:{beforeBreachMinutes:$w}}]}')
    else
        sla=$(jq -n --argjson m "$minutes" --argjson b "$bh" --argjson w "$warn" \
              '{nextResponseTimeMinutes:$m, useBusinessHoursOnly:$b, breachActions:[{beforeBreachAction:{beforeBreachMinutes:$w}}]}')
    fi
    if [ -n "$priorities" ]; then
        sla=$(echo "$sla" | jq --argjson p "[$priorities]" '. + {threadPriorityFilter:$p}')
    fi
    gql 'mutation($i: CreateServiceLevelAgreementInput!) { createServiceLevelAgreement(input: $i) {
           serviceLevelAgreement { id } error { message code fields { field message } } } }' \
        "$(jq -n --arg t "$tier" --argjson s "$sla" '{i:{tierId:$t, serviceLevelAgreement:$s}}')"
}

# ============================================================================
# BUSINESS HOURS  — destructive: replaces the entire set
# ============================================================================

hours_get() { gql 'query { businessHoursSlots { timezone { name } weekday opensAt closesAt } }'; }

# Reads the current set first and refuses to clobber a non-empty one without --force.
hours_set() {
    local tz="" open="09:00" close="17:00" days="MONDAY,TUESDAY,WEDNESDAY,THURSDAY,FRIDAY" force=false
    while [[ $# -gt 0 ]]; do
        case $1 in
            --timezone) tz="$2"; shift 2 ;;
            --open)     open="$2"; shift 2 ;;
            --close)    close="$2"; shift 2 ;;
            --days)     days="$2"; shift 2 ;;
            --force)    force=true; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    [ -n "$tz" ] || die "hours set: --timezone is required (e.g. Europe/London)"

    local existing
    existing=$(hours_get | jq -e '.data.businessHoursSlots | if type == "array" then length else error("Missing business hours") end') || return 1
    if [ "$existing" != "0" ] && [ "$force" != true ]; then
        echo "Refusing to overwrite $existing existing business-hours slot(s)." >&2
        echo "This call REPLACES the whole set. Review them, then re-run with --force:" >&2
        hours_get >&2
        exit 1
    fi

    local slots
    slots=$(jq -n --arg tz "$tz" --arg o "$open" --arg c "$close" --arg d "$days" \
        '[$d | split(",") | .[] | {timezone:$tz, weekday:., opensAt:$o, closesAt:$c}]')
    gql 'mutation($i: SyncBusinessHoursSlotsInput!) { syncBusinessHoursSlots(input: $i) {
           slots { weekday opensAt closesAt } error { message code fields { field message } } } }' \
        "$(jq -n --argjson s "$slots" '{i:{slots:$s}}')"
}

# ============================================================================
# THREAD AND TENANT FIELDS
# ============================================================================

threadfield_create() {
    local label="" key="" type="STRING" desc="" order=0 enum_values="" required=false autofill=true
    while [[ $# -gt 0 ]]; do
        case $1 in
            --label)       label="$2"; shift 2 ;;
            --key)         key="$2"; shift 2 ;;
            --type)        type="$2"; shift 2 ;;
            --description) desc="$2"; shift 2 ;;
            --order)       order="$2"; shift 2 ;;
            --values)      enum_values="$2"; shift 2 ;;
            --required)    required=true; shift ;;
            --no-autofill) autofill=false; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    [ -n "$label" ] || die "threadfield create: --label is required"
    [ -n "$key" ] || key=$(echo "$label" | tr '[:upper:] ' '[:lower:]_' | tr -cd 'a-z0-9_')
    [ -n "$desc" ] || desc="$label"
    echo "$key" | grep -qE '^[a-z0-9_]+$' || die "threadfield create: --key must match ^[a-z0-9_]+$ (got '$key')"
    local vals='[]'
    [ -n "$enum_values" ] && vals=$(jq -n --arg v "$enum_values" '$v | split(",")')
    gql 'mutation($i: CreateThreadFieldSchemaInput!) { createThreadFieldSchema(input: $i) {
           threadFieldSchema { id key } error { message code fields { field message } } } }' \
        "$(jq -n --arg l "$label" --arg k "$key" --arg d "$desc" --arg t "$type" \
                 --argjson o "$order" --argjson v "$vals" --argjson r "$required" --argjson a "$autofill" \
           '{i:{label:$l, key:$k, description:$d, order:$o, type:$t, enumValues:$v, isRequired:$r,
                isAiAutoFillEnabled:$a, isAvailableToAgents:true, isClientReadonly:false, dependsOnLabelTypeIds:[]}}')"
}

# ============================================================================
# WORKFLOWS
# ============================================================================
# A workflow is four things: create (draft) -> add steps (leaf-first) ->
# set the start step -> publish. It does nothing until published.

workflow_create() {
    local name="" events="thread.thread_created" cron="" type="events"
    while [[ $# -gt 0 ]]; do
        case $1 in
            --name)   name="$2"; shift 2 ;;
            --events) events="$2"; shift 2 ;;
            --cron)   cron="$2"; type="schedule"; shift 2 ;;
            --manual) type="manual"; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    [ -n "$name" ] || die "workflow create: --name is required"
    local trigger
    case "$type" in
        manual)   trigger='{"type":"manual"}' ;;
        schedule) trigger=$(jq -nc --arg c "$cron" '{type:"schedule", cron:$c}') ;;
        *)        trigger=$(jq -nc --arg e "$events" '{type:"events", events:($e|split(","))}') ;;
    esac
    gql 'mutation($i: CreateWorkflowInput!) { createWorkflow(input: $i) {
           workflow { id name trigger publishedAt { iso8601 } }
           error { message code fields { field message } } } }' \
        "$(jq -n --arg n "$name" --arg t "$trigger" '{i:{name:$n, trigger:$t}}')"
}

# Build terminal actions first — transitions need real step IDs.
step_action() {
    local wf="" name="" payload="" next="null" x=0 y=0
    while [[ $# -gt 0 ]]; do
        case $1 in
            --workflow) wf="$2"; shift 2 ;;
            --name)     name="$2"; shift 2 ;;
            --payload)  payload="$2"; shift 2 ;;
            --payload-file) [ -f "$2" ] || die "Payload file not found"; payload=$(cat "$2"); shift 2 ;;
            --next)     next="\"$2\""; shift 2 ;;
            --x) x="$2"; shift 2 ;;
            --y) y="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    [ -n "$wf" ] && [ -n "$payload" ] || die "step action: --workflow and --payload are required"
    printf '%s' "$payload" | jq -e 'type == "object" and (.type | type == "string") and (.version | type == "number")' >/dev/null \
        || die "Step payload must be a JSON object with a type and version"
    gql 'mutation($i: CreateWorkflowStepInput!) { createWorkflowStep(input: $i) {
           workflowStep { id type transitions } error { message code fields { field message } } } }' \
        "$(jq -n --arg w "$wf" --arg n "${name:-action}" --arg p "$payload" \
                 --argjson t "[$next]" --argjson x "$x" --argjson y "$y" \
           '{i:{workflowId:$w, type:"ACTION", name:$n, payload:$p, transitions:$t, positionX:$x, positionY:$y}}')"
}

# N conditions -> N+1 transitions. The last is the "nothing matched" branch;
# point it at a visible label rather than null.
step_switch() {
    local wf="" name="classify" prompts_file="" transitions="" x=0 y=0
    while [[ $# -gt 0 ]]; do
        case $1 in
            --workflow)    wf="$2"; shift 2 ;;
            --name)        name="$2"; shift 2 ;;
            --prompts)     prompts_file="$2"; shift 2 ;;   # file, one prompt per line
            --transitions) transitions="$2"; shift 2 ;;    # comma-separated step ids, fallback last
            --x) x="$2"; shift 2 ;;
            --y) y="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    [ -n "$wf" ] && [ -n "$prompts_file" ] && [ -n "$transitions" ] \
        || die "step switch: --workflow, --prompts <file> and --transitions are required"
    [ -f "$prompts_file" ] || die "step switch: prompts file not found: $prompts_file"

    local n_prompts n_trans payload trans_json
    n_prompts=$(jq -Rs 'split("\n") | map(select(test("[^\\s]"))) | length' < "$prompts_file")
    [ "$n_prompts" -gt 0 ] || die "step switch: at least one nonblank prompt required"
    trans_json=$(jq -n --arg t "$transitions" '$t | split(",")')
    n_trans=$(echo "$trans_json" | jq 'length')
    [ "$n_trans" -eq $((n_prompts + 1)) ] \
        || die "step switch: $n_prompts prompts needs $((n_prompts + 1)) transitions (got $n_trans). Last one is the fallback."

    payload=$(jq -Rsc --argjson v 1 '
        {version:$v, type:"else_if",
         conditions: (split("\n") | map(select(test("[^\\s]"))) |
                      map({version:1, type:"ai_workflow_rule_condition", prompt:.}))}' < "$prompts_file")
    gql 'mutation($i: CreateWorkflowStepInput!) { createWorkflowStep(input: $i) {
           workflowStep { id transitions } error { message code fields { field message } } } }' \
        "$(jq -n --arg w "$wf" --arg n "$name" --arg p "$payload" --argjson t "$trans_json" \
                 --argjson x "$x" --argjson y "$y" \
           '{i:{workflowId:$w, type:"CONDITION", name:$n, payload:$p, transitions:$t, positionX:$x, positionY:$y}}')"
}

workflow_publish() {
    local wf="" start=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --workflow) wf="$2"; shift 2 ;;
            --start)    start="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    [ -n "$wf" ] && [ -n "$start" ] || die "workflow publish: --workflow and --start <step_id> are required"
    gql 'mutation($i: UpdateWorkflowInput!) { updateWorkflow(input: $i) {
           workflow { id startStepId publishedAt { iso8601 } }
           error { message code fields { field message } } } }' \
        "$(jq -n --arg w "$wf" --arg s "$start" '{i:{workflowId:$w, startStepId:{value:$s}, isPublished:{value:true}}}')"
}

workflow_unpublish() {
    [ -n "${1:-}" ] || die "workflow unpublish: <workflow_id> required"
    gql 'mutation($i: UpdateWorkflowInput!) { updateWorkflow(input: $i) {
           workflow { id publishedAt { iso8601 } } error { message code } } }' \
        "$(jq -n --arg w "$1" '{i:{workflowId:$w, isPublished:{value:false}}}')"
}

workflow_list() {
    connection workflows 'query($after: String) { workflows(first: 50, after: $after) {
      edges { node { id name trigger publishedAt { iso8601 } startStepId } } pageInfo { hasNextPage endCursor } } }'
}

# Which branch did the AI take? This is the tuning loop.
workflow_runs() {
    [ -n "${1:-}" ] || die "workflow runs: <workflow_id> required"
    gql 'query($w: ID!) { workflowExecutions(workflowId: $w, first: 10) { edges { node {
           entityId executionStatus executionDurationMs errorMessage
           stepExecutions { workflowStepId status output } } } } }' \
        "$(jq -n --arg w "$1" '{w:$w}')"
}

# ============================================================================
# PAYLOAD HELPERS  — emit step payloads so callers don't hand-write JSON
# ============================================================================

payload() {
    local kind="${1:-}"; shift || true
    case "$kind" in
        apply-labels) jq -nc --arg l "${1:-}" '{version:1, type:"apply_labels", labelTypeIds:($l|split(","))}' ;;
        set-priority) jq -nc --argjson p "${1:-2}" '{version:1, type:"set_priority", priority:$p}' ;;
        assign-user)  jq -nc --arg u "${1:-}" '{version:1, type:"assign_to_user", userId:$u}' ;;
        assign-team)  jq -nc --arg t "${1:-}" '{version:1, type:"assign_to_team", teamId:$t}' ;;
        *) die "payload: unknown kind '$kind' (apply-labels|set-priority|assign-user|assign-team)" ;;
    esac
}

# ============================================================================
# SAVED VIEWS
# ============================================================================
# The filter has many non-null fields and two deprecated-but-required display
# flags. This fills them all in so a view doesn't fail on a missing key.

view_create() {
    local name="" icon="inbox" color="#6B7280" statuses="TODO" priorities="" labels=""
    local sort_field="CREATED_AT" sort_dir="DESC"
    while [[ $# -gt 0 ]]; do
        case $1 in
            --name)       name="$2"; shift 2 ;;
            --icon)       icon="$2"; shift 2 ;;
            --color)      color="$2"; shift 2 ;;
            --statuses)   statuses="$2"; shift 2 ;;
            --priorities) priorities="$2"; shift 2 ;;
            --labels)     labels="$2"; shift 2 ;;
            --sort)       sort_field="$2"; shift 2 ;;
            --sort-dir)   sort_dir="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    [ -n "$name" ] || die "view create: --name is required"
    local filter
    filter=$(jq -n \
        --argjson st "$(jq -n --arg s "$statuses" '$s|split(",")')" \
        --argjson pr "$( [ -n "$priorities" ] && jq -n --arg p "$priorities" '$p|split(",")|map(tonumber)' || echo '[]')" \
        --argjson lb "$( [ -n "$labels" ] && jq -n --arg l "$labels" '$l|split(",")' || echo '[]')" \
        --arg sf "$sort_field" --arg sd "$sort_dir" '{
        statuses:$st, statusDetails:[], priorities:$pr,
        assignedToUser:[], participants:[], customerGroups:[], companies:[],
        tenants:[], tiers:[], labelTypeIds:$lb,
        messageSource:[], supportEmailAddresses:[], slaTypes:[], slaStatuses:[],
        threadFields:[], tenantFields:[], threadLinkGroupIds:[], threadLinkSources:[],
        groupBy:"NONE", layout:"TABLE",
        sort:{field:$sf, direction:$sd},
        displayOptions:{
          hasStatus:true, hasCustomer:true, hasCompany:false, hasPreviewText:true,
          hasTier:true, hasCustomerGroups:false, hasLabels:true,
          hasLinearIssues:false, hasJiraIssues:false,
          hasLinkedThreads:false, hasServiceLevelAgreements:true,
          hasChannels:true, hasLastUpdated:true, hasAssignees:true, hasRef:true }}')
    gql 'mutation($i: CreateSavedThreadsViewInput!) { createSavedThreadsView(input: $i) {
           savedThreadsView { id name } error { message code fields { field message } } } }' \
        "$(jq -n --arg n "$name" --arg ic "$icon" --arg c "$color" --argjson f "$filter" \
           '{i:{name:$n, icon:$ic, color:$c, isHidden:false, threadsFilter:$f}}')"
}

# ============================================================================
# KNOWLEDGE SOURCES
# ============================================================================

knowledge_add() {
    local url="" type="SITEMAP"
    while [[ $# -gt 0 ]]; do
        case $1 in
            --url)  url="$2"; shift 2 ;;
            --page) type="URL"; shift ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    [ -n "$url" ] || die "knowledge add: --url is required"
    gql 'mutation($i: CreateKnowledgeSourceInput!) { createKnowledgeSource(input: $i) {
           knowledgeSource { __typename
             ... on KnowledgeSourceSitemap { id url }
             ... on KnowledgeSourceUrl { id url } }
           error { message code fields { field message } } } }' \
        "$(jq -n --arg u "$url" --arg t "$type" '{i:{url:$u, type:$t, labelTypeIds:[]}}')"
}

# ============================================================================
# TEST HARNESS  — prove the triage actually fires
# ============================================================================

test_thread() {
    local customer="" title="" body=""
    while [[ $# -gt 0 ]]; do
        case $1 in
            --customer) customer="$2"; shift 2 ;;
            --title)    title="$2"; shift 2 ;;
            --body)     body="$2"; shift 2 ;;
            *) die "Unknown option: $1" ;;
        esac
    done
    [ -n "$customer" ] && [ -n "$title" ] || die "test thread: --customer and --title are required"
    gql 'mutation($i: CreateThreadInput!) { createThread(input: $i) {
           thread { id title } error { message code fields { field message } } } }' \
        "$(jq -n --arg c "$customer" --arg t "$title" --arg b "${body:-$title}" \
           '{i:{customerIdentifier:{customerId:$c}, title:$t, components:[{componentText:{text:$b}}]}}')"
}

# What actually landed on the thread — trust this, not the step status.
thread_state() {
    [ -n "${1:-}" ] || die "thread state: <thread_id> required"
    gql 'query($t: ID!) { thread(threadId: $t) {
           id title priority
           assignedTo { __typename ... on User { id publicName } ... on MachineUser { id name } }
           labels { labelType { name } createdBy { __typename ... on SystemActor { systemId } } } } }' \
        "$(jq -n --arg t "$1" '{t:$t}')"
}

# Sidekick custom skills: returned name is the authoritative invocation slug.
skill_list() {
    gql 'query { sidekickSkills { name displayName description isEnabled
      ... on CustomSidekickSkill { customSkillId } } }'
}

skill_get() {
    [ -n "${1:-}" ] || die "skill get: custom skill ID required"
    gql 'query($id: ID!) { sidekickCustomSkill(id: $id) {
      id name displayName description instructions isEnabled } }' \
      "$(jq -nc --arg id "$1" '{id:$id}')"
}

skill_write() {
    local mode="$1" id="" display="" desc="" file="" enabled=""; shift
    while [[ $# -gt 0 ]]; do
        case $1 in
            --id) id="$2"; shift 2 ;;
            --display-name) display="$2"; shift 2 ;;
            --description) desc="$2"; shift 2 ;;
            --instructions-file) file="$2"; shift 2 ;;
            --enable) enabled=true; shift ;;
            --disable) enabled=false; shift ;;
            *) die "skill $mode: unknown option $1" ;;
        esac
    done
    local input='{}'
    [ -z "$display" ] || input=$(jq -nc --argjson i "$input" --arg v "$display" '$i + {displayName:$v}')
    [ -z "$desc" ] || input=$(jq -nc --argjson i "$input" --arg v "$desc" '$i + {description:$v}')
    if [ -n "$file" ]; then
        [ -s "$file" ] || die "skill $mode: instructions file must exist and be nonempty"
        input=$(jq -nc --argjson i "$input" --rawfile v "$file" '$i + {instructions:$v}')
    fi
    if [ "$mode" = create ]; then
        [ -n "$display" ] && [ -n "$desc" ] && [ -n "$file" ] || die "skill create: display name, description and instructions file required"
        [ -z "$id" ] && [ -z "$enabled" ] || die "skill create: use skill update for ID/enablement"
        gql 'mutation($i: CreateSidekickCustomSkillInput!) { createSidekickCustomSkill(input: $i) {
          customSkill { id name displayName description instructions isEnabled }
          error { message code fields { field message } } } }' "$(jq -nc --argjson i "$input" '{i:$i}')"
    else
        [ -n "$id" ] || die "skill update: --id required"
        [ "$input" != '{}' ] || [ -n "$enabled" ] || die "skill update: no changes supplied"
        input=$(jq -nc --argjson i "$input" --arg id "$id" '$i + {customSkillId:$id}')
        [ -z "$enabled" ] || input=$(jq -nc --argjson i "$input" --argjson e "$enabled" '$i + {isEnabled:$e}')
        gql 'mutation($i: UpdateSidekickCustomSkillInput!) { updateSidekickCustomSkill(input: $i) {
          customSkill { id name displayName description instructions isEnabled }
          error { message code fields { field message } } } }' "$(jq -nc --argjson i "$input" '{i:$i}')"
    fi
}

integrations() {
    local services mcps
    services=$(connection serviceAuthorizations 'query($after: String) {
      serviceAuthorizations(first: 100, after: $after) { edges { node {
        id status serviceIntegration { key name } } } pageInfo { hasNextPage endCursor } } }') || { printf '%s\n' "$services"; return 1; }
    mcps=$(gql 'query { sidekickMcpServers { id name slug isConnected tools { name displayName description } } }') || { printf '%s\n' "$mcps"; return 1; }
    jq -nc --argjson s "$services" --argjson m "$mcps" '$s | .data += $m.data'
}

policies() { gql 'query { agentSandboxToolPolicies { service op displayName mode factoryDefault isOverride } }'; }

workflow_get() {
    [ -n "${1:-}" ] || die "workflow get: ID required"
    gql 'query($id: ID!) { workflow(workflowId: $id) {
      id name trigger startStepId publishedAt { iso8601 }
      steps { id type name payload transitions positionX positionY } } }' \
      "$(jq -nc --arg id "$1" '{id:$id}')"
}

workflow_templates() { gql 'query { workflowTemplateGallery { id title tags } }'; }

workflow_template() {
    [ -n "${1:-}" ] || die "workflow template: ID required"
    gql 'query($id: ID!) { workflowTemplate(templateId: $id) { id title
      workflows { name trigger startStepId steps { id type name payload transitions positionX positionY } } } }' \
      "$(jq -nc --arg id "$1" '{id:$id}')"
}

workflow_capabilities() {
    gql 'query($t: WorkflowTriggerType!) { workflowCapabilities(triggerType: $t) {
      hasConditionSupport hasWaitSupport allowedActionTypes } }' \
      "$(jq -nc --arg t "${1:-EVENTS}" '{t:$t}')"
}

usage() {
    cat <<'USAGE'
plain-config.sh — configure a Plain workspace

  workspace                       which workspace this key points at
  permissions                     what this key can do
  audit                           everything already configured (run before building)
  users                           real user IDs, emails and team labels (all pages)
  teams                           routing teams (TEAM-kind label types)

  label create --name X [--icon slug] [--color #hex] [--ai-managed] [--team]
                                  --team makes a routing team (teams ARE label types)
  label list
  team add-member --team LABEL_ID --user USER_ID

  tier create --name X [--external-id x] [--default] [--default-priority 0-3]
  tier list
  sla create --tier ID --kind first|next --minutes N [--priorities 0,1]
             [--round-the-clock] [--warn-minutes 15]

  hours get
  hours set --timezone TZ [--open 09:00] [--close 17:00] [--days MONDAY,...] [--force]

  threadfield create --label X [--key k] [--type ENUM] [--values a,b,c] [--required]

  workflow create --name X [--events a,b | --cron "0 9 * * MON" | --manual]
  step action --workflow ID --payload JSON|--payload-file FILE [--next STEP_ID] [--name X]
  step switch --workflow ID --prompts FILE --transitions id1,id2,...,fallback
  workflow publish --workflow ID --start STEP_ID
  workflow unpublish ID
  workflow list
  workflow get ID
  workflow templates
  workflow template ID
  workflow capabilities [EVENTS|MANUAL|SCHEDULE]
  workflow runs ID                which branch matched — the tuning loop

  payload apply-labels lt_1,lt_2  emit step payloads
  payload set-priority 0
  payload assign-user u_...
  payload assign-team team_...

  view create --name X [--statuses TODO] [--priorities 0,1] [--labels lt_...]
  knowledge add --url URL [--page]

  test thread --customer c_... --title "..." [--body "..."]
  thread state th_...

  skill list
  skill get CUSTOM_SKILL_ID
  skill create --display-name NAME --description TEXT --instructions-file FILE
  skill update --id ID [--display-name NAME] [--description TEXT] [--instructions-file FILE]
               [--enable|--disable]
  integrations                    built-in and custom MCP connection status
  policies                        effective Sidekick action approvals
  request QUERY_FILE [VARIABLES_FILE]

Every API command prints raw JSON and exits nonzero on transport, GraphQL or mutation errors.
Creating an object is not proof of live behavior; read back and test the intended path.
USAGE
}

cmd="${1:-}"; shift || true
case "$cmd" in ""|-h|--help|help) usage; exit 0 ;; esac
if [ "$cmd" = payload ]; then
    command -v jq >/dev/null || die "jq is required"
else
    check_deps
fi
case "$cmd" in
    workspace)   workspace ;;
    permissions) permissions ;;
    audit)       audit ;;
    users)       users ;;
    teams)       teams ;;
    team) case "${1:-}" in add-member) shift; team_add_member "$@" ;; *) usage; exit 1 ;; esac ;;
    integrations) integrations ;;
    policies) policies ;;
    request) request "$@" ;;
    skill) case "${1:-}" in
      list) skill_list ;;
      get) shift; skill_get "$@" ;;
      create|update) skill_write "$@" ;;
      *) usage; exit 1 ;; esac ;;
    label)   case "${1:-}" in create) shift; label_create "$@" ;; list) label_list ;; *) usage; exit 1 ;; esac ;;
    tier)    case "${1:-}" in create) shift; tier_create "$@" ;; list) tier_list ;; *) usage; exit 1 ;; esac ;;
    sla)     case "${1:-}" in create) shift; sla_create "$@" ;; *) usage; exit 1 ;; esac ;;
    hours)   case "${1:-}" in get) hours_get ;; set) shift; hours_set "$@" ;; *) usage; exit 1 ;; esac ;;
    threadfield) case "${1:-}" in create) shift; threadfield_create "$@" ;; *) usage; exit 1 ;; esac ;;
    workflow) case "${1:-}" in
                 create) shift; workflow_create "$@" ;;
                 publish) shift; workflow_publish "$@" ;;
                 unpublish) shift; workflow_unpublish "$@" ;;
                 list) workflow_list ;;
                 get) shift; workflow_get "$@" ;;
                 templates) workflow_templates ;;
                 template) shift; workflow_template "$@" ;;
                 capabilities) shift; workflow_capabilities "$@" ;;
                 runs) shift; workflow_runs "$@" ;;
                 *) usage; exit 1 ;; esac ;;
    step)    case "${1:-}" in action) shift; step_action "$@" ;; switch) shift; step_switch "$@" ;; *) usage; exit 1 ;; esac ;;
    payload) payload "$@" ;;
    view)    case "${1:-}" in create) shift; view_create "$@" ;; *) usage; exit 1 ;; esac ;;
    knowledge) case "${1:-}" in add) shift; knowledge_add "$@" ;; *) usage; exit 1 ;; esac ;;
    test)    case "${1:-}" in thread) shift; test_thread "$@" ;; *) usage; exit 1 ;; esac ;;
    thread)  case "${1:-}" in state) shift; thread_state "$@" ;; *) usage; exit 1 ;; esac ;;
    ""|-h|--help|help) usage ;;
    *) echo "Unknown command: $cmd" >&2; usage; exit 1 ;;
esac
