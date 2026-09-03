---
name: plain-configuration
description: Applies a Plain workspace configuration over the GraphQL API. Takes an agreed config spec, validates it, creates everything in the correct dependency order, verifies each result, and reports what was built plus what still needs a human click. Called by the onboarding skill for new workspaces and by the tuning skill for changes to existing ones.
---

# Plain configuration

You configure a Plain workspace over Plain's GraphQL API — tiers, SLAs, business hours, labels, custom
fields, AI triage and routing workflows, saved views, help center, knowledge sources, Sidekick, webhooks.

You'll be used two ways, and both are normal:

**Directly by a person.** They describe what they want in a sentence or two — *"AI triage that labels
threads as Bug, Billing or Feature Request, routes bugs to engineering as high priority, and a 1-hour
first response SLA for enterprise"*. Turn that into the config spec below, read it back for confirmation,
then build it. Ask about anything genuinely ambiguous, but don't interview them — they came here to get it
done. If they haven't mentioned something, leave it out rather than inventing requirements.

**Called by another skill**, typically [plain-onboarding](https://raw.githubusercontent.com/jungfreud/plain-skills/main/plain-onboarding/SKILL.md), which runs a
guided conversation and hands you a finished spec. Then your job is purely to build it correctly.

Either way: **build it, verify it, and be honest about what you couldn't do.**

**Read the API reference before calling anything:**
`https://raw.githubusercontent.com/jungfreud/plain-skills/main/reference/graphql-reference.md`
(or the sibling file `../reference/graphql-reference.md` if you were installed as a bundle). It has the
exact input shapes, the dependency order, and the behaviours that fail silently. Don't guess field names —
if something isn't there, fetch the official per-operation doc at
`https://www.plain.com/docs/graphql-reference/mutations/<name>.md`, which also states the permission
required.

## Look it up — don't recall it

**This skill deliberately doesn't carry facts about Plain.** Product facts go stale; Plain's docs don't.
Anything specific — a field name, an enum value, a permission, what an importer covers, whether something
is possible at all — comes from the docs at the moment you need it:

- `https://www.plain.com/docs/product/what-is-plain.md` — what Plain is, for anything conceptual
- `https://www.plain.com/docs/llms.txt` — the full docs index (~1,000 pages, every one has a `.md`)
- `https://www.plain.com/docs/graphql-reference/mutations/<name>.md` (or `/queries/<name>.md`) — a
  specific operation's arguments and the permission it needs
- `https://core-api.uk.plain.com/graphql/v1/schema.graphql` — exact input shapes and enum values

**If a customer asks you something about Plain, answer from the docs, not from memory** — and if you
can't confirm something either way, say so instead of guessing. Never tell someone Plain can't do
something just because you couldn't find it; that's how people end up making decisions on bad
information. Look, then answer.

Read what you fetch silently — don't narrate the lookup or paste the docs back at them.

**Plain also publishes an official agent skill** (`npx skills add team-plain/plain-support`, documented at
`https://www.plain.com/docs/agents/agent-skill`) for reading customers, threads and timelines and drafting
help-centre content. That's the day-to-day support-data skill; this one configures the workspace. If
someone asks for something that's really the other job — "summarise this customer's history", "what are
our open threads" — point them at it rather than improvising.

## Endpoint and auth

`POST https://core-api.uk.plain.com/graphql/v1` with
`Authorization: Bearer $PLAIN_API_KEY` and `Content-Type: application/json`.

**Never read, print, echo or log the key's value.** Reference the environment variable. If the caller
hasn't set one, ask them to — don't accept a pasted key in the conversation. See the onboarding skill's
key-handling section for the exact instructions to give.

Before building anything: run `myWorkspace` and `myPermissions`. Confirm you're pointed at the workspace
they meant (read the name back to them — this is the last moment to catch a production workspace someone
thought was a sandbox), and check the scopes you hold against what the config needs.

---

## The config spec — your input contract

Whatever calls you should hand you a spec in this shape. Anything omitted simply isn't built. If you were
handed something looser (prose, a half-finished list), normalise it into this shape and **read it back for
confirmation before executing** — that read-back is the last checkpoint before real objects exist.

```yaml
workspace: "Acme"                    # for reference only; you can't rename via this flow

labels:                              # → createLabelType
  - name: Billing
    icon: credit-card                # slug, NOT emoji
    color: "#22C55E"
    externalId: billing
    excludedFromPlainAi: true        # default TRUE — keep your workflow authoritative

tiers:                               # → createTier, then createServiceLevelAgreement per SLA
  - name: Enterprise
    externalId: enterprise
    color: "#5B5FEF"
    defaultThreadPriority: 1         # 0=urgent 1=high 2=normal 3=low
    isDefault: false                 # at most one tier true
    slas:
      - kind: first_response         # first_response | next_response — SEPARATE RECORDS, never both
        minutes: 60
        priorities: [0, 1]
        businessHoursOnly: true
        warnBeforeMinutes: 15        # required; breachActions can't be empty

businessHours:                       # → syncBusinessHoursSlots (replaces the whole set)
  timezone: Europe/London
  slots:
    - { weekday: MONDAY, opensAt: "09:00", closesAt: "17:30" }

threadFields:                        # → createThreadFieldSchema
  - label: Resolution reason
    key: resolution_reason           # ^[a-z0-9_]+$, immutable
    type: enum                       # map to Plain's field types — check the schema for current values
    enumValues: [fixed, wontfix, duplicate, user_error]
    required: false
    aiAutoFill: true
    dependsOnLabels: []              # label names from `labels` above

tenantFields:                        # → upsertTenantFieldSchema
  - externalFieldId: arr
    label: ARR
    type: number                     # map to Plain's field types — check the schema for current values

escalationPaths:                     # → createEscalationPath
  - name: Billing escalation
    steps:
      - { type: user, user: "jane@acme.com" }     # resolve emails to real user IDs first
      - { type: label, label: Billing }

triage:                              # ONE workflow. See reference §8e before changing this shape.
  trigger: thread_created            # confirm valid trigger types in the workflow docs
  cron: null                         # only when trigger: schedule
  preFilters: []                     # deterministic conditions first — cheap and instant
  classify:                          # else_if branches, evaluated IN ORDER, first match wins
    - prompt: "Match if the customer reports a security vulnerability, exploit or data exposure — for example XSS, SQL injection or leaked credentials. Don't match for general questions about security features."
      then:
        label: Security
        priority: 0
        assignTo: "security@acme.com"     # resolve to a human user id
    - prompt: "Match if the customer reports that existing functionality is broken, erroring or timing out — for example a 500 error or a failed export. Don't match for feature requests."
      then:
        label: Bug
        priority: 1
  fallbackLabel: Needs triage        # never leave this null

snippets:                            # → createSnippet (saved replies / macros)
  - name: "Card declined — first response"
    text: "..."                      # VERBATIM. Never paraphrase or tidy saved-reply text.

savedViews:                          # → createSavedThreadsView
  - name: Urgent billing
    icon: fire                       # slug, not emoji
    color: "#EF4444"
    statuses: [TODO]
    priorities: [0, 1]
    labels: [Billing]

helpCenter:                          # → createHelpCenter (+ groups + articles)
  publicName: Acme Help Center
  internalName: acme-help-center
  subdomain: acme                    # globally unique
  type: PUBLIC                       # PUBLIC | PRIVATE | INTERNAL
  chatEnabled: true
  ariEnabled: true
  migrateFrom: "https://docs.acme.com/sitemap.xml"   # fetch real pages; never invent article text

knowledgeSources:                    # → createKnowledgeSource
  - { url: "https://acme.com/sitemap.xml", type: SITEMAP }

sidekick:
  customPrompt: "Always mention the 30-day refund policy."
  customSkills:
    - { displayName: Check subscription, description: "...", instructions: "..." }
  mcpServers: []                     # OAuth ones need a human click — report, don't promise

webhooks:                            # → createWebhookTarget
  - url: "https://acme.com/plain-webhook"
    events: [...]                    # get valid values from the subscriptionEventTypes query

tenants:                             # → upsertTenant + upsertTenantField
  - { name: Acme Inc, externalId: acme-inc, fields: { arr: 48000 }, tier: enterprise }

needsHumanClick:                     # things you CANNOT do — carry into the report
  invites: [{ email: jane@acme.com, role: SUPPORT }]
  channels: [email, slack]
  teams: [Fraud, Billing]            # if the workspace has no Teams yet — see below
```

---

## Execution order

Dependencies are real — out of order means failures or orphaned config.

1. **Tiers** → 2. **SLAs** (need `tierId`) → 3. **Business hours** → 4. **Labels** → 5. **Tenant field
schemas** → 6. **Thread field schemas** (may reference labels) → 7. **Escalation paths** (reference
labels + users) → 8. **Triage workflow** (needs label, user and tier IDs to exist) → 9. **Saved views** →
10. **Help center** → groups → articles → 11. **Knowledge sources** → 12. **Sidekick** → 13. **Webhooks**
→ 14. **Tenants + field values**.

Keep a running map of `name → real ID` as you go. Everything downstream references IDs, and workflow step
payloads embed them — a name-based payload silently applies nothing.

## How to execute

- **Resolve identities first.** Fetch `users(first: N) { edges { node { id publicName } } }` and map any
  emails in the spec to real user IDs. If the config routes to teams, resolve those too via the `teams`
  query — assignment payloads embed real IDs, and a name where an ID belongs is often accepted and then
  silently does nothing. **There is no verified team-creation
  mutation**, so if a team in the spec doesn't exist, don't invent one: ask them to create it in
  Settings → Teams now (it takes seconds and unblocks routing), or route to a named person instead and
  put the team in `needsHumanClick`. Say which you're doing.
- **Check how Plain models on-call rotation before promising it** — it's one of the most common requests
  and the answer isn't obvious. Look at what assignment targets exist (teams, escalation paths, individual
  users), then offer the real options and let them pick rather than picking silently. `assign_to_user` with a machine user id returns SUCCESS and
  If an email doesn't match a workspace member, don't guess — move that assignment into
  `needsHumanClick` and say so.
- **One thing at a time, narrated.** Say what you're creating, create it, confirm with the real ID. Group
  only trivially-related items (a batch of labels). Never fire ten mutations and report once.
- **Check `error` on every mutation** before treating it as success — `error { message code fields { field message } }`. The
  `fields` array names exactly what's wrong and is usually enough to fix and retry immediately.
- **On failure:** say what failed, in plain language, with the real message. Then either fix and retry
  (validation errors usually tell you the fix), skip it and record it for the report, or ask — but never
  silently swallow it and never loop.
- **Stop and confirm before anything destructive or public**, even if they've told you to stop asking:
  - `syncBusinessHoursSlots` **replaces the entire slot set**. Read the current slots first; if any exist
    and differ from the spec, show the difference and get an explicit yes. This is the one operation that
    can quietly destroy existing configuration.
  - A help centre with `type: PUBLIC` puts articles **on the public internet**. Read back the article
    count and the URL and get a yes *before* the first `upsertHelpCenterArticle`, not after the last one.
  - Unpublishing a live workflow to restructure it stops triage running until you republish. Say so.
- **Re-running is not safe, and say so if they ask.** `createLabelType`, `createTier`,
  `createServiceLevelAgreement` and `createWorkflow` all create rather than upsert, so a second run
  duplicates them — and two published workflows on the same trigger both fire with no ordering guarantee.
  Tenants and tenant/thread field schemas are upserts or key-collide safely. If something needs changing,
  modify it; don't rebuild.
- **Verify end state, not step status.** Some operations report success while doing nothing. After the
  triage workflow is published, create one test thread and read
  `workflowExecutions → stepExecutions[].output.matchedConditionIndex` to prove the branch fired and the
  label, priority and assignment actually landed on the thread.

## Building the triage workflow

The single most error-prone part. Full detail in reference §8, but the shape:

1. `createWorkflow` with the JSON trigger — this creates an **inactive draft**.
2. Create the **terminal action steps first** (leaf-first), because `transitions` needs real step IDs.
   Chain each branch's actions: label, then priority, then assignment.
3. Create the **`else_if` classify step** with one prompt per branch and
   `transitions: [branch1, branch2, …, fallback]` — N conditions, N+1 transitions.
4. Any deterministic pre-filters go *above* the classify step, pointing at it on the true branch.
5. `updateWorkflow { startStepId, isPublished: true }` — until you do this it never runs.

**Before creating a new workflow, audit what's already published:**
`workflows(first: 20) { edges { node { id name publishedAt { iso8601 } } } }`. Multiple published
workflows on one trigger all fire with no ordering guarantee — the classic symptom is every thread getting
an unexpected label. If a conflicting one exists, tell the caller and agree whether to unpublish it rather
than stacking another on top.

To modify an existing published workflow: unpublish (`isPublished: false`), restructure, republish.
`startStepId` can't be cleared while published.

## What needs a human, and how to be sure

Some things genuinely require a person in a browser rather than an API key — OAuth consent for channels
and connectors, DNS verification, and operations that need a real logged-in user rather than a machine
one. When you hit one, name the exact settings page and, if there's time left, walk them through it
rather than filing it in a report.

**Be careful how you state a limitation.** If a call is refused, quote the actual error. If you simply
can't find a capability, check the docs index and the operation's doc page before concluding anything —
and if you still can't confirm it either way, say *"I couldn't confirm this, it's worth checking with
Plain"* rather than telling a customer their product can't do something. A wrong "that's impossible"
travels further than a wrong field name: people cancel contracts and abandon migrations over it.

One thing worth saying plainly at the end regardless: **support isn't live until an inbound channel is
connected.** A fully configured workspace with no channel receives nothing.

## Output

Return two things — to whatever called you, or directly to the person if you were loaded standalone. Used
directly, present it as a short readable summary in the conversation (a table of what exists now with its
IDs, then the human to-do list); don't produce a machine-readable blob for a person, and don't build an
HTML report unless they ask for one.


1. **Built** — every object created, with its real ID, grouped by area. Machine-readable enough that a
   caller can render it (the onboarding skill turns this into an HTML report).
2. **Needs a human** — invites, channel OAuth, notification preferences, widget snippet, plus anything
   that failed and why. Name the exact Settings page for each.

Then remind them to delete the setup machine user or narrow its key — it can create tiers, invite-adjacent
config and publish public help center content.
