# Plain GraphQL configuration reference

A curated path through Plain's GraphQL API for configuring a workspace: the operations that matter, in the
order they depend on each other, with their real input shapes.

Where the schema and the runtime validator disagree, this documents what the API actually accepts. Those
cases are called out — they're the ones that cost you an afternoon otherwise.

**Endpoint:** `https://core-api.uk.plain.com/graphql/v1` (POST only)
**Auth:** `Authorization: Bearer plainApiKey_xxx` plus `Content-Type: application/json`
**Body:** `{ "query": "...", "variables": {...}, "operationName": "..." }`

### Verifying anything here

Official per-operation docs, including the exact permission each needs:
```
https://www.plain.com/docs/graphql-reference/mutations/<mutationName>.md
https://www.plain.com/docs/graphql-reference/queries/<queryName>.md
```
Full docs index: `https://www.plain.com/docs/llms.txt`. Raw schema (for input-type and enum shapes):
`https://core-api.uk.plain.com/graphql/v1/schema.graphql`.

---

## Gotchas that will bite you

1. **`DateTime` is an object, not a scalar.** Every timestamp needs subfields:
   `publishedAt { iso8601 }` or `{ unixTimestamp }`. Selecting it bare is a validation error.
2. **Icons are slugs, not emoji.** `icon` must match `^[a-z0-9_-]+$` — e.g. `credit-card`, `fire`.
   Passing `💳` fails with *"icon must be lowercase alphanumeric, _, or -"*.
3. **The schema marks some fields optional that the validator requires.** Known cases:
   `upsertHelpCenterArticle.description`, and `threadsFilter.displayOptions.hasLinearIssues` /
   `hasJiraIssues` (which are also `@deprecated` — still required).
4. **`inviteUserToWorkspace` is forbidden to machine users.** A setup API key *cannot* invite teammates
   (`ForbiddenError: Machine user not allowed to perform this operation`). Team invites are UI-only.
   `assignRolesToUser` on an *existing* user does work with a machine key.
5. **SLA response times are mutually exclusive.** One SLA record holds *either*
   `firstResponseTimeMinutes` *or* `nextResponseTimeMinutes`, never both. Want both? Create two records
   against the same tier.
6. **`breachActions` cannot be empty.** Every entry must carry
   `beforeBreachAction: { beforeBreachMinutes: Int! }`.
7. **`KnowledgeSource` is a union** (`KnowledgeSourceSitemap` | `KnowledgeSourceUrl`) — select through
   inline fragments.
8. **Workflow event names ≠ webhook event names.** Two different namespaces; see §8 and §13.
9. **Permission scope suffixes are inconsistent**: `tier:edit` (not `:update`),
   `tenantFieldSchema:update` but `threadFieldSchema:edit`. Don't extrapolate — check the operation's doc.

---

## 0. Order of operations

1. Tiers → 2. SLAs (need `tierId`) → 3. Business hours → 4. Label types → 5. Tenant field schemas →
6. Thread field schemas → 7. Escalation paths → 8. Workflows (need label/user/tier IDs) → 9. Saved views →
10. Help center + groups + articles → 11. Knowledge sources → 12. Sidekick → 13. Webhooks →
14. Roles (invites are UI-only) → 15. Tenants + field values

---

## 1. Tiers

```graphql
mutation { createTier(input: {
  name: "Enterprise", externalId: "enterprise", color: "#5B5FEF"
  defaultThreadPriority: 1      # 0=urgent 1=high 2=normal 3=low
  memberIdentifiers: []          # [{ companyId } | { tenantId }]
  isDefault: false               # only one tier may be true
}) { tier { id name } error { message code fields { field message } } } }
```
Scopes: `tier:create`, `tier:read`, `tier:edit`, `tier:delete`, `tierMembership:create/delete/read`.
Add members later with `addMembersToTier`.

## 2. SLAs (per tier)

One record per response type — **not both in one call.**

```graphql
# First-response SLA
mutation { createServiceLevelAgreement(input: {
  tierId: "tier_..."
  serviceLevelAgreement: {
    firstResponseTimeMinutes: 60
    threadPriorityFilter: [0, 1]        # optional; defaults to all priorities
    useBusinessHoursOnly: true
    breachActions: [{ beforeBreachAction: { beforeBreachMinutes: 15 } }]
  }
}) { serviceLevelAgreement { id } error { message code fields { field message } } } }

# Next-response SLA — a SECOND call against the same tier
mutation { createServiceLevelAgreement(input: {
  tierId: "tier_..."
  serviceLevelAgreement: {
    nextResponseTimeMinutes: 240
    useBusinessHoursOnly: true
    breachActions: [{ beforeBreachAction: { beforeBreachMinutes: 30 } }]
  }
}) { serviceLevelAgreement { id } error { message code } } }
```
Scopes: `serviceLevelAgreement:create/edit/delete`.

## 3. Business hours

Output field is `slots`. `BusinessHoursSlot` has **no `id`** — only timezone/weekday/opensAt/closesAt.

```graphql
mutation { syncBusinessHoursSlots(input: {
  slots: [
    { timezone: "Europe/London", weekday: MONDAY, opensAt: "09:00", closesAt: "17:30" }
    { timezone: "Europe/London", weekday: FRIDAY, opensAt: "09:00", closesAt: "17:00" }
  ]
}) { slots { weekday opensAt closesAt } error { message code fields { field message } } } }
```
This replaces the full set of slots each call. Scopes: `businessHours:edit`, `businessHours:read`.
(`upsertBusinessHours` exists but is deprecated.)

## 4. Label types

```graphql
mutation { createLabelType(input: {
  name: "Billing"
  icon: "credit-card"        # slug only — NOT emoji
  color: "#22C55E"
  type: DEFAULT              # or TEAM
  description: "Billing and invoicing questions"
  externalId: "billing"
  isExcludedFromAi: true     # DEFAULT TO TRUE — see below
}) { labelType { id name } error { message code fields { field message } } } }
```

**Always create labels with `isExcludedFromAi: true` unless the customer explicitly asks otherwise.**
Plain's built-in AI triage applies labels independently of your workflows, so leaving this `false` means
two systems label the same threads and your triage tree stops being authoritative — a thread routed to
`Security` can also pick up an unrelated `Bug` label. Excluding labels from the
built-in AI makes your workflow the single source of truth, which is what a customer designing explicit
triage rules actually wants. Existing labels can be flipped with
`updateLabelType(input: { labelTypeId: "lt_...", isExcludedFromAi: { value: true } })`.
Scopes: `labelType:create/edit/read`, `label:create`, `suggestedLabelType:read`.
Also `archiveLabelType`/`unarchiveLabelType` (prefer archiving), `moveLabelType`,
`suggestedLabelTypes` + `acceptSuggestedLabelTypes` (useful when migrating).

## 5. Tenant field schemas

```graphql
mutation { upsertTenantFieldSchema(input: {
  tenantFieldSchemas: [{
    source: "api"              # new schemas must be "api"
    externalFieldId: "arr", label: "ARR"
    type: NUMBER_TYPE          # STRING_TYPE | NUMBER_TYPE | BOOLEAN_TYPE | STRING_ARRAY | DATETIME_TYPE | USER_REFERENCE_TYPE
    options: [], isVisible: true, order: 0
  }]
}) { tenantFieldSchemas { id label } error { message code fields { field message } } } }
```
Scopes: `tenantFieldSchema:create/update/read/delete` (note `:update`, not `:edit`).

## 6. Thread field schemas

```graphql
mutation { createThreadFieldSchema(input: {
  label: "Resolution reason"
  key: "resolution_reason"     # ^[a-z0-9_]+$, immutable
  description: "Why this ticket was closed"
  order: 0
  type: ENUM                   # STRING | BOOL | ENUM | NUMBER | CURRENCY | DATE
  enumValues: ["fixed", "wontfix", "duplicate", "user_error"]
  isRequired: false
  isAiAutoFillEnabled: true    # let Ari fill it from the conversation
  isAvailableToAgents: true
  isClientReadonly: false
  dependsOnLabelTypeIds: []
}) { threadFieldSchema { id key } error { message code fields { field message } } } }
```
Scopes: `threadFieldSchema:create/edit/read/delete` (`:edit`, not `:update`), `threadField:create/update/read/delete`.

## 7. Escalation paths

`EscalationPathStepType` is **`USER`** (with `userId` — machine users allowed) or **`LABEL_TYPE`** (with
`labelTypeId`). There is no `ASSIGN_USER`/`ADD_LABEL`.

```graphql
mutation { createEscalationPath(input: {
  name: "Billing escalation"
  description: "Escalate unresolved billing issues"
  steps: [
    { type: USER, userId: "mu_..." }
    { type: LABEL_TYPE, labelTypeId: "lt_..." }
  ]
}) { escalationPath { id name } error { message code fields { field message } } } }
```
Scopes: `escalationPath:create/edit/read/delete/execute`.

## 8. Workflows

**Four steps, or it silently never runs:** create (draft) → add steps → set `startStepId` → publish.

### 8a. Create with trigger

`trigger` is a JSON-encoded string:

| type | extra fields |
|---|---|
| `manual` | none — runs via `triggerWorkflow` or a UI button |
| `events` | `events: string[]` (≥1) |
| `schedule` | `cron: string` (UTC) — this is what makes recurring digests possible |

Workflow event names: `thread.thread_created`, `thread.message_added`, `thread.thread_field_updated`,
`thread.thread_labels_changed`, `thread.thread_status_transitioned`.

```graphql
mutation { createWorkflow(input: {
  name: "Route billing tickets"
  trigger: "{\"type\":\"events\",\"events\":[\"thread.thread_created\"]}"
}) { workflow { id trigger publishedAt { iso8601 } } error { message code } } }
```
`publishedAt: null` ⇒ inactive draft.

### 8b. Add steps

```graphql
mutation { createWorkflowStep(input: {
  workflowId: "wf_..."
  type: ACTION                 # CONDITION | ACTION | WAIT
  name: "Label as billing"
  payload: "{\"version\":1,\"type\":\"apply_labels\",\"labelTypeIds\":[\"lt_...\"]}"
  transitions: [null]          # ACTION: 1 element; CONDITION: 2 (true,false); null = terminal
  positionX: 0, positionY: 0
}) { workflowStep { id type } error { message code fields { field message } } } }
```
Payloads are `{ version: 1, type: <discriminator>, ... }`:
- **CONDITION** — `contains_label`, `thread_field_equals`, `thread_field_is_set`, `priority_equals`,
  `assigned_to`, `customer_equals`, `ai_workflow_rule_condition`, or combinators `and`/`or`/`not`/`else_if`.
- **ACTION** — `apply_labels`, `remove_labels`, `set_priority`, `set_status`, `set_tier`,
  `assign_to_user`, `assign_to_team`, `add_note`, `send_message`, `send_slack_notification`,
  `send_http_request`, `set_thread_field`, `snooze_thread`, `escalate_thread`.
- **WAIT** — `{ "duration": <seconds>, "cancelCondition"?: <condition> }`.

Payloads embed workspace-specific IDs — never copy them between workspaces; resolve real IDs first.
`bulkUpsertWorkflowSteps` can set the whole step list plus `startStepId` and `trigger` in one call.

### 8c. Publish

```graphql
mutation { updateWorkflow(input: {
  workflowId: "wf_..."
  startStepId: { value: "wfs_..." }
  isPublished: { value: true }
}) { workflow { id startStepId publishedAt { iso8601 } } error { message code } } }
```
Note: there is **no `workflow:*` permission scope** — only `workflowRule:create/edit/read/trigger`.
Workflow mutations succeeded with an Admin-preset key. `startStepId` can't be cleared while published.

### 8d. AI prompt conditions and branching

The AI condition takes a **plain-English prompt inline** — you do *not* need to create a `WorkflowRule`
first:

```json
{"version":1,"type":"ai_workflow_rule_condition","prompt":"This is a security vulnerability report or responsible disclosure"}
```

**Build branching chains leaf-first.** `transitions` needs real step IDs, so create the terminal actions
first, then the conditions that point at them, then set `startStepId` to the top condition. An if /
else-if / else router looks like this:

| step | type | payload | transitions |
|---|---|---|---|
| D | ACTION | `apply_labels` → Bug | `[null]` |
| E | ACTION | `apply_labels` → Feature Request | `[null]` |
| B | ACTION | `apply_labels` → Security | `[null]` |
| C | CONDITION | AI prompt: *"customer is reporting something broken"* | `[D, E]` |
| A | CONDITION | AI prompt: *"security vulnerability report"* | `[B, C]` |

…then `updateWorkflow { startStepId: A, isPublished: true }`. Condition transitions are strictly
`[trueStepId, falseStepId]`.

Verified behaviour on three real threads (~3.2s per run, `executionStatus: SUCCESS`):
- *"Possible XSS in comment field…"* → A matched → Security. Only two steps ran.
- *"Export button throws 500…"* → A false, C matched → Bug.
- *"Please add dark mode"* → A false, C false → Feature Request.

Branching is genuinely exclusive — the untaken branch never executes.

**Debugging executions.** `workflowExecutions(workflowId:, first:)` returns per-run traces, and each
`stepExecutions[].output` is JSON containing `conditionMatched` — the fastest way to see which branch the
AI chose:
```graphql
query { workflowExecutions(workflowId: "wf_...", first: 5) { edges { node {
  triggeredBy executionStatus executionDurationMs errorMessage
  stepExecutions { workflowStepId status output }
} } } }
```
Note `triggeredBy` comes back prefixed — `domain.thread.thread_created` — while the trigger config uses
`thread.thread_created`.

### 8e. Architecture: how to structure triage and routing

Three constraints dictate the design:

1. **Workflow actions do not cascade into other workflows.** A label applied by a workflow
   (`systemId: workflows_handler`) does **not** fire a workflow triggered on
   `thread.thread_labels_changed`. A triage workflow applying `Security` produces **zero executions** on a
   workflow listening for label changes.
2. **API- or human-applied label changes *do* fire those workflows.** The same workflow fires
   immediately when the label comes from `addLabels` or a person in the app.
3. **Triggers are an OR-list of events.** No AND, no predicates at the trigger level — all narrowing
   happens in condition steps.

**So the intuitive two-layer design — "triage labels on thread_created, routing reacts to label added" —
does not work for automated triage.** The second layer never fires.

#### The efficient, controllable shape

**One workflow per entry trigger, doing classify → label → route inline.** On
`thread.thread_created`:

1. **Cheap deterministic conditions first** — `support_email_equals`, tier/`customer_equals`,
   `contains_label`. They're instant and free, and they shrink the population before you spend AI latency.
2. **One `else_if` switch for the classification**, not a chain of binary AI conditions. `else_if` is a
   genuine **N-way switch**: `conditions: [c1, c2, c3]` with `transitions: [s1, s2, s3, fallback]`. It
   returns `matchedConditionIndex` and **stops at the first match**:
   ```json
   {"version":1,"type":"else_if","conditions":[
     {"version":1,"type":"ai_workflow_rule_condition","prompt":"security vulnerability report"},
     {"version":1,"type":"ai_workflow_rule_condition","prompt":"something is broken or erroring"},
     {"version":1,"type":"ai_workflow_rule_condition","prompt":"requesting a new feature"}]}
   ```
   A "charts not loading, console shows 502" thread returns `matchedConditionIndex: 1` and applies
   `Bug` — **one step, one execution**, and the third prompt is never evaluated.
3. **Chain the per-branch actions** — ACTION steps take `transitions: [nextStepId]`, so a branch can run
   `apply_labels` → `set_priority` → `assign_to_team` → `escalate_thread` in sequence.

**Why this beats a chain:** each `ai_workflow_rule_condition` is an LLM call (~1–3s). Three chained binary
AI conditions is three sequential calls on the worst-case path; one `else_if` is a single step that
short-circuits. Order the branches most-likely-first.

**What label-triggered workflows are still for:** reacting to a *human* agent manually re-labelling a
thread. Keep them for that — just never rely on them to catch automated output.

**If you genuinely need decoupled layers**, the escape hatches are a `send_http_request` action calling
back into the API (re-enters as an API actor, so it *would* cascade — at the cost of latency and loop
risk) or a webhook out to your own service. Both are infrastructure, not no-code; avoid unless the
separation is worth it.

**Don't stack multiple workflows on the same trigger.** During testing a leftover workflow that applied
`Billing` unconditionally on `thread.thread_created` silently labelled *every* thread alongside the real
triage. Multiple published workflows on one event all fire, with no ordering guarantee — audit
`workflows(first: N) { edges { node { name publishedAt { iso8601 } } } }` before adding another, and
delete the experiments.

### 8f. How to write AI prompt conditions

Official guidance (worth reading, and mirrored in the in-product UI):
`https://www.plain.com/docs/product/workflows/workflows-conditions#ai-prompts`

Each prompt returns a single **match / no match** boolean, evaluated against a context snapshot Plain
assembles: the thread's message history (up to 600 messages, 3,000 chars each), thread metadata (title,
description, status, priority, labels), customer name and email, channel, assignees, thread fields and
their schemas, and attachment count. **Nothing else** — no CRM, no product usage, no external data.

1. **Use Plain's `Match if… / Don't match if…` convention.** State what takes the Yes branch, then
   clarify what shouldn't:
   > *"Match if the customer explicitly requests a refund. Don't match for general billing questions or
   > payment issues without refund mentions."*
2. **Give specific criteria and concrete examples**, in the customer's own vocabulary:
   > *"Match if the customer reports that existing functionality is broken, erroring, or timing out — for
   > example a 500 error, a failed export, or a page that will not load."*
   Never *"use your best judgment to decide if this is important"* — the model can't guess what
   "important" means to this workspace.
3. **One decision per prompt.** Don't stuff several outcomes into one condition, and don't ask the prompt
   to take actions — it only returns match/no-match; actions are separate steps. If you need real boolean
   logic, use the `and` / `or` / `not` combinators. Prefer positive statements over stacked negations.
4. **Order is your tiebreaker, and it does real work.** `else_if` stops at the first match, so put the
   highest-stakes and most specific case first. A security bug should hit `security` before `bug` purely
   because security is listed first. Later prompts may assume the earlier ones were false — don't
   over-qualify them ("a bug but not a security issue" is unnecessary and hurts).
5. **Only ask about what's actually in the thread.** The model sees the conversation, not your CRM,
   plan tier, or the sending domain. Route on those with deterministic conditions
   (`customer_equals`, tier, `support_email_equals`) — they're free and instant. Save prompts for
   genuine language judgement.
6. **Always wire the fallback branch.** `transitions` has N+1 entries; the last one is "nothing matched".
   Point it at a `Needs triage` label rather than `null`, so unclassified threads are visible instead of
   silently untouched. A message like *"Thanks for the help"* matches nothing and needs somewhere to go.
7. **Tune from traces, not vibes.** `stepExecutions[0].output.matchedConditionIndex` tells you exactly
   which prompt won. Push your real historical threads through it and reword wherever the index is wrong.
8. **One or two sentences.** Long prompts drift.

Ordering by *frequency* also cuts latency, since a match short-circuits the remaining prompts.

### ⚠️ `assign_to_user` needs a human user id — machine ids fail silently

`assign_to_user` with a machine user id (`mu_...`) returns **`status: SUCCESS` with `entities: []` and
assigns nobody.** No error, no warning. With a human id (`u_...`) it assigns correctly.

```json
{"version":1,"type":"assign_to_user","userId":"u_..."}   // ✅ works
{"version":1,"type":"assign_to_user","userId":"mu_..."}  // ⚠️ SUCCESS, but no assignment
```
Fetch real human IDs with `users(first: N) { edges { node { id publicName } } }` before building
assignment steps, and verify `thread.assignedTo` is non-null after a test run rather than trusting the
step status.

### ⚠️ Plain's built-in AI triage also labels threads **and sets priority**

Plain runs its own AI triage independently of your workflows, so a thread can carry your workflow's
`Security` label **and** an unrelated `Bug` label applied by a different system actor:

```
labels[].createdBy.systemId == "workflows_handler"      ← your workflow
labels[].createdBy.systemId == "thread_triage_handler"  ← Plain's built-in AI triage
```
If a label should be controlled *only* by your workflow, create it with **`isExcludedFromAi: true`**.
Otherwise expect built-in triage to apply it too, and don't mistake that for a workflow bug. Checking
`createdBy.systemId` on a thread's labels tells you instantly which system applied what.

**It sets priority too.** A thread whose workflow only applies a label can still come back at priority
`0`, and a workflow that sets priority `1` can end up at `0` — the two systems compete, last writer wins. There is **no setting in the
GraphQL schema to disable built-in triage** — it appears to be UI/plan-level, so if deterministic
priority matters to a customer, check Settings → Agents in the app rather than assuming the workflow is
authoritative. Always verify the end state on a test thread instead of trusting the step trace.

## 8g. Metrics — auditing an existing workspace

Useful when tuning rather than setting up: find where response times are worst, which labels drag CSAT
down, how AI-handled threads compare to human-handled.

```graphql
query { threadSingleValueMetric(input: {
  metricName: threads_first_response_time
  from: "2026-08-01T00:00:00Z"
  to: "2026-09-02T12:00:00Z"
  groupBy: [{ dimension: LABEL_TYPE }]     # field is `dimension`, not `groupBy`
  percentile: 90                            # P90; defaults to median
  mode: METRIC                              # or THREAD_IDS
}) { values { value group { dimension value } } } }
```

- **Queries:** `threadSingleValueMetric`, `threadTimeSeriesMetric`, `threadHeatmapMetric` (the
  un-prefixed `singleValueMetric`/`timeSeriesMetric`/`heatmapMetric` are deprecated — they don't support
  filtering or group-by).
- **`groupBy` dimensions:** `ASSIGNEE`, `LABEL_TYPE`, `TIER`, `PRIORITY`, `COMPANY`, `TENANT`,
  `CUSTOMER_GROUP`, `MESSAGE_SOURCE`, `THREAD_FIELD` and `TENANT_FIELD` (both need `subKey`).
  `ASSIGNEE` requires `metricsAgent:read`.
- **Metric names:** `threads_first_response_time`, `threads_resolution_time`,
  `threads_time_customer_waiting`, `threads_time_between_follow_up_responses`,
  `threads_csat__percentage`, `threads_csat__count`, `service_level_agreement_compliance_frt` / `_nrt`,
  `threads_created_count` (time-series only), `threads_status_count__todo|done|snoozed`,
  `threads_all_time_count_done`. Most have an `agent_` variant for AI-handled threads.
- **`mode: THREAD_IDS`** returns the actual thread IDs behind a number — use it to cite evidence for a
  recommendation instead of asserting it.
- Scopes: `metrics:read`, plus `metricsAgent:read` for assignee/agent breakdowns.

**Gotchas:**
- `to` **cannot be in the future** — a date even a day ahead fails validation.
- Output is `values { value group { … } }` — `group` singular, not `groups`.
- **CSAT metrics require `filters.surveyResponse.rating`** — omitting it fails with *"rating is required
  for CSAT metrics"*, which the schema doesn't tell you.
- All-time counts (e.g. `threads_all_time_count_done`) **reject** a date range; everything else requires
  one.
- `percentile` is only accepted on the configurable-percentile duration metrics; it's rejected elsewhere.

## 9. Saved (custom) views

Nearly every `threadsFilter` field is non-null — an empty `{}` is rejected. Pass empty arrays. And the
two `@deprecated` display flags are still **required**.

```graphql
mutation { createSavedThreadsView(input: {
  name: "Urgent billing", icon: "fire", color: "#EF4444", isHidden: false
  threadsFilter: {
    statuses: [TODO]                # TODO | SNOOZED | DONE
    statusDetails: [], priorities: [0, 1]
    assignedToUser: [], participants: [], customerGroups: [], companies: []
    tenants: [], tiers: [], labelTypeIds: ["lt_..."]
    messageSource: [], supportEmailAddresses: [], slaTypes: [], slaStatuses: []
    threadFields: [], tenantFields: [], threadLinkGroupIds: [], threadLinkSources: []
    groupBy: NONE                   # NONE|PRIORITY|STATUS|COMPANY|LABEL|TIER|CHANNEL|ASSIGNEE|CUSTOMER_GROUP|TENANT
    layout: TABLE                   # TABLE | BOARD
    sort: { field: CREATED_AT, direction: DESC }
    # ThreadsSortField: STATUS_CHANGED_AT | CREATED_AT | CLOSEST_TO_BREACH_SLA
    #                   | LAST_INBOUND_MESSAGE_AT | PRIORITY | THREAD_FIELD
    displayOptions: {
      hasStatus: true, hasCustomer: true, hasCompany: false, hasPreviewText: true
      hasTier: true, hasCustomerGroups: false, hasLabels: true
      hasLinearIssues: false, hasJiraIssues: false     # deprecated BUT REQUIRED
      hasLinkedThreads: false, hasServiceLevelAgreements: true
      hasChannels: true, hasLastUpdated: true, hasAssignees: true, hasRef: true
    }
  }
}) { savedThreadsView { id name } error { message code fields { field message } } } }
```
`and`/`or`/`not` accept nested filters. Scopes: `savedThreadsView:create/edit/read/delete`.

## 10. Help center + migration

```graphql
mutation { createHelpCenter(input: {
  publicName: "Acme Help Center", internalName: "acme-help-center"
  type: PUBLIC                      # PUBLIC | PRIVATE | INTERNAL
  description: "Support docs for Acme"
  subdomain: "acme"                 # must be globally unique
  isChatEnabled: true
  isCustomerFacingAiEnabled: true   # Ari answers directly on the help center
}) { helpCenter { id publicName } error { message code fields { field message } } } }

mutation { createHelpCenterArticleGroup(input: {
  helpCenterId: "hc_...", name: "Getting started"
  # parentHelpCenterArticleGroupId: "..." to nest
}) { helpCenterArticleGroup { id name } error { message code } } }

mutation { upsertHelpCenterArticle(input: {
  helpCenterId: "hc_...", helpCenterArticleGroupId: "hcag_..."
  title: "How to reset your password"
  description: "Steps to reset a forgotten password"   # REQUIRED despite schema saying optional
  contentHtml: "<p>Click forgot password.</p>"
  status: PUBLISHED
  slug: "reset-password"
}) { helpCenterArticle { id title } error { message code fields { field message } } } }
```
Scopes: `helpCenter:create/edit/read/delete` plus **separate** `helpCenterArticle:*` and
`helpCenterArticleGroup:*` scopes. `generateHelpCenterArticle` AI-drafts from a thread.
For bulk migration: fetch each source page, convert to clean HTML, create groups mirroring their nav,
then loop `upsertHelpCenterArticle`.

## 11. Ari knowledge sources

`KnowledgeSource` is a union — use inline fragments.

```graphql
mutation { createKnowledgeSource(input: {
  url: "https://acme.com/sitemap.xml"
  type: SITEMAP              # SITEMAP (crawls the sitemap) | URL (single page)
  labelTypeIds: []
}) {
  knowledgeSource {
    __typename
    ... on KnowledgeSourceSitemap { id url }
    ... on KnowledgeSourceUrl { id url }
  }
  error { message code fields { field message } }
} }
```
A help center you create is auto-indexed — no separate source needed. Scopes:
`knowledgeSource:create/read/delete`. Also `reindexKnowledgeSource`, `deleteKnowledgeSource`.

## 12. Sidekick

```graphql
mutation { updateSidekickSettings(input: {
  customPrompt: "Always mention our 30-day refund policy."
}) { error { message code } } }

mutation { createSidekickCustomSkill(input: {
  displayName: "Check subscription status"
  description: "Looks up a customer's plan and billing status"
  instructions: "Use the billing MCP for lookups only."
}) { customSkill { id displayName } error { message code } } }   # output is `customSkill`
```
Scopes: `sidekickSettings:read/update`, `sidekickCustomSkill:create/edit/read/delete`,
`sidekickMcpServer:read/update` — **note there is no `sidekickMcpServer:create` scope**, so
`createSidekickMcpServer` may be restricted; verify before promising it.
Per-integration scopes exist and are individually gated:
`sidekickPosthogIntegration:update`, `sidekickSentryIntegration:update`,
`sidekickLinearIntegration:update`, `sidekickJiraIntegration:update`, `sidekickGithubIntegration:update`,
`sidekickNotionIntegration:update`, `sidekickHubspotIntegration:update`, `sidekickDatadogIntegration:update`,
`sidekickGrafanaIntegration:update`, `sidekickIncidentioIntegration:update`, `sidekickAttioIntegration:update`,
`sidekickLaunchdarklyIntegration:update`, plus `workspaceSlackSidekickIntegration:create/update/delete`.
OAuth-based connectors still need a human to complete consent in the browser.

## 13. Webhook targets

```graphql
mutation { createWebhookTarget(input: {
  url: "https://acme.com/plain-webhook"
  eventSubscriptions: [
    { eventType: "thread.service_level_agreement_status_transitioned" }
    { eventType: "thread.thread_created" }
  ]
  isEnabled: true
  description: "Ops alerts"
}) { webhookTarget { id } error { message code fields { field message } } } }
```
**`thread.sla_status_transitioned` does not exist.** Valid webhook event types (distinct from workflow
events): `thread.thread_created`, `thread.thread_status_transitioned`,
`thread.thread_assignment_transitioned`, `thread.email_received`, `thread.email_sent`,
`thread.slack_message_received`, `thread.slack_message_sent`, `thread.slack_message_updated`,
`thread.discord_message_received`, `thread.discord_message_sent`, `thread.discord_message_updated`,
`thread.ms_teams_message_sent`, `thread.ms_teams_message_received`, `thread.chat_sent`,
`thread.chat_received`, `thread.note_created`, `thread.note_mention_created`,
`discussion.discussion_created`, `discussion.message_created`, `thread.thread_labels_changed`,
`thread.thread_priority_changed`, `thread.thread_field_created`, `thread.thread_field_updated`,
`thread.thread_field_deleted`, `thread.service_level_agreement_status_transitioned`,
`thread.thread_tenant_updated`, `thread.thread_locked`, `customer.customer_created`,
`customer.customer_updated`, `customer.customer_deleted`, `customer.customer_changed`,
`customer.customer_group_changed`, `customer.customer_group_memberships_changed`,
`timeline.timeline_entry_changed`. Scopes: `webhookTarget:create/edit/read/delete`.

## 14. Team members and roles — invites are UI-only

```graphql
# ❌ FAILS with a machine-user key:
# inviteUserToWorkspace(input: { email: "...", roleKey: SUPPORT })
#   → ForbiddenError: Machine user not allowed to perform this operation
```
**Inviting teammates cannot be automated with a setup API key** — it requires a human actor context.
Put invites in the handoff report as a UI task (Settings → Members), don't try to script them.

`assignRolesToUser` *does* work with a machine key for users who already exist:
```graphql
mutation { assignRolesToUser(input: { userId: "u_...", roleKey: SUPPORT }) { error { message code } } }
```
`RoleKey`: `OWNER | ADMIN | SUPPORT | VIEWER | NONE`, or `customRoleId`. Scopes: `roles:read/assign/create/edit`.

## 15. Tenants and field values

```graphql
mutation { upsertTenant(input: {
  identifier: { externalId: "acme-inc" }
  name: "Acme Inc", externalId: "acme-inc"
  # primaryDomain / alternateDomains / isDomainAutoJoinEnabled are beta — may not be enabled
}) { tenant { id name } error { message code fields { field message } } } }

mutation { upsertTenantField(input: {
  tenantFieldIdentifier: {
    tenantIdentifier: { externalId: "acme-inc" }   # or tenantId
    externalFieldId: "arr"
  }
  type: NUMBER_TYPE
  numberValue: 48000        # set exactly the one value field matching `type`
}) { tenantField { id } error { message code fields { field message } } } }
```
Scopes: `tenant:create/read/delete`, `tenantField:create/update/read/delete`. Tier a tenant with
`updateTenantTier`.

---

## Permission scopes

An Admin-preset key carries roughly 390 scopes. The ones this configuration flow uses:

| Area | Scopes |
|---|---|
| Tiers | `tier:create`, `tier:read`, `tier:edit`, `tier:delete`, `tierMembership:create/delete/read` |
| SLAs | `serviceLevelAgreement:create/edit/delete` |
| Business hours | `businessHours:edit`, `businessHours:read` |
| Labels | `labelType:create/edit/read`, `label:create`, `suggestedLabelType:read` |
| Tenant fields | `tenantFieldSchema:create/update/read/delete`, `tenantField:create/update/read/delete` |
| Tenants | `tenant:create/read/delete` |
| Thread fields | `threadFieldSchema:create/edit/read/delete`, `threadField:create/update/read/delete` |
| Escalation paths | `escalationPath:create/edit/read/delete/execute` |
| Workflows | **no `workflow:*` scope exists** — only `workflowRule:create/edit/read/trigger` |
| Saved views | `savedThreadsView:create/edit/read/delete` |
| Help centre | `helpCenter:*` **plus separate** `helpCenterArticle:*`, `helpCenterArticleGroup:*` |
| Knowledge sources | `knowledgeSource:create/read/delete`, `knowledgeGap:*`, `knowledgeGapSignal:*` |
| Sidekick | `sidekickSettings:read/update`, `sidekickCustomSkill:create/edit/read/delete`, `sidekickMcpServer:read/update` (no `:create`), per-integration `sidekick<Service>Integration:read/update` |
| Webhooks | `webhookTarget:create/edit/read/delete` |
| Roles | `roles:read/assign/create/edit` |
| Sanity check | `permission:read` → call `myPermissions` first to see exactly what you hold |

Easiest path for a one-time setup key remains the **Admin preset**. Delete the machine user
(`deleteMachineUser`) or narrow the key afterwards.

## What can't be done with an API key

- **Inviting teammates** — `inviteUserToWorkspace` rejects machine users outright. Settings → Members.
- **Personal notification preferences** — no mutation exists (`updateInternalNotifications` only marks
  notifications read/archived). Avatar → Preferences, per user.
- **OAuth completion for channels and OAuth MCP servers** — Slack / MS Teams / Discord / email
  forwarding have `create*Integration` mutations that provision the shell, but consent and DNS
  verification need a human browser session. Support is **not live until a channel is connected.**
- **Chat widget snippet placement** — happens on the customer's own site.
