# Configuration contract

This is the design handed from onboarding or insights to configuration, not a GraphQL input or a file
the CLI automatically applies. Omitted areas are left alone. Record proposals as such until agreed.
Use names/keys while designing, then resolve all references to real workspace IDs at execution time.

## First-session design

```yaml
workspace: Acme
labels:
  - {name: Bug, icon: bug, externalId: bug, excludedFromPlainAi: true}
  - {name: Product support, icon: help-circle, externalId: product-support, excludedFromPlainAi: true}
  - {name: Needs triage, icon: inbox, externalId: needs-triage, excludedFromPlainAi: true}
teams:
  - {name: Engineering, members: [jane@acme.example]}
  - {name: Support, members: [sam@acme.example]}
knowledgeSources:
  - {url: "https://docs.acme.example/sitemap.xml", type: SITEMAP}
integrations:
  - name: GitHub
    status: planned                   # planned | connected | unavailable; verify when keyed
    scope: "acme/api repository"
    purpose: "Find related bugs and relevant implementation"
  - name: Sentry
    status: planned
    scope: "API project, production"
    purpose: "Correlate the reported error with recent events"
sidekick:
  skills:
    - key: engineering-handoff        # local design key, NOT the API invocation slug
      displayName: Prepare engineering issue
      description: "Prepare a reproducible engineering issue after investigation."
      instructionsFile: engineering-handoff.md
      requires: [GitHub]              # design dependency, not an API field
      actions: [draft_issue]          # final instructions define scope and permissions
    - key: thread-triage
      displayName: Thread triage
      description: "Investigate a newly routed support thread and prepare the next action."
      instructionsFile: thread-triage.md
      children: [engineering-handoff]
      requires: [GitHub, Sentry]
      actions: [internal_summary, draft_reply]
  missingToolBehavior: "Use available evidence, list skipped checks, and leave a human next step."
  policyChanges: []                   # separate explicit decisions; defaults remain intact
triage:
  name: Inbound triage
  trigger: thread_created             # map to verified event payload at execution
  preFilters: []                      # deterministic routing facts, when relevant
  classify:
    - prompt: "Match if existing functionality is broken, errors or times out. Don't match for a request for a new feature or a how-to question."
      then:
        label: Bug
        priority: 1
        assignToTeam: Engineering
        sidekick: {skill: thread-triage, context: "Investigate the failure; use engineering handoff when justified."}
    - prompt: "Match if the customer asks how to use existing functionality. Don't match for a failure of functionality they already use."
      then:
        label: Product support
        priority: 2
        assignToTeam: Support
        sidekick: {skill: thread-triage, context: "Check maintained docs, identify any knowledge gap, and draft an answer."}
  fallback:
    label: Needs triage
    assignToTeam: Support
    sidekick: {skill: thread-triage, context: "Investigate without forcing a category; identify missing information."}
  publish: true                       # only after customer agrees and graph is complete
ari:                                 # optional; do not assume knowledge alone enables replies
  enabledFor: []                     # explicitly selected branch/category/channel scope
  responseMode: shadow                # shadow | live; confirm live customer replies
  handoffOwner: Support
needsHumanClick:
  integrations: [GitHub, Sentry]
  channels: [email]
  invites: []
  teamMembership: []
  approvals: []
```

Adapt categories, teams, tools and child skills to what the customer actually needs. A simple company
may use one Thread triage skill and one owner. A larger team may need branch-specific investigation
skills. Do not create unused skills or require every integration shown in the example.

## Optional configuration

Keep these capabilities available for specific requests; they are not mandatory onboarding questions.
Use the current API docs for exact inputs and the helper's `help` for implemented flags.

| Design area | Capture |
| --- | --- |
| Tiers / SLAs | Name, external ID, default priority/tier, first or next response target, priorities, business-hours behavior and warning. First and next targets are separate SLA records. |
| Business hours | Timezone and all weekday/open/close slots; read existing slots before a replacement. |
| Thread fields | Label, immutable key, type, choices, required/AI-fill settings and label dependencies. |
| Tenant fields / tenants | External field IDs, types and account values/tier; keep account/entity modeling explicit. |
| Escalation paths | Named steps referencing verified users and labels. |
| Saved views | Name, statuses, priorities, labels and other requested filters. |
| Help center | Visibility, name/domain, chat/Ari choices, and actual source content if requested. Publish only agreed content. |
| Snippets | Exact approved text; surface unresolved placeholders and preserve the original. |
| Sidekick settings | Specific prompt/configuration changes, preserving existing unrelated settings. |
| Webhooks | Destination and current event types; no credentials in the design/report. |

## Execution result / recovery record

Keep a local record for the current build with workspace ID and entries such as:

```yaml
objects:
  - area: sidekickSkill
    designKey: thread-triage
    id: ACTUAL_RETURNED_ID
    invocationName: ACTUAL_RETURNED_NAME
    operation: created                # created | reused | updated | pending | failed
    verified: true
pending:
  - item: Sentry connection
    affects: "Error correlation in Thread triage"
    action: "Plain AI → Sidekick → Integrations → Sentry → Connect"
verification:
  - threadId: ACTUAL_TEST_THREAD_ID
    workflowExecutionId: ACTUAL_EXECUTION_ID
    sidekickDiscussionId: ACTUAL_DISCUSSION_ID
    observed: "Bug label and owner verified; Sidekick reported Sentry unavailable."
```

Only populate IDs and observations returned by real calls. Record failures and uncertain outcomes
explicitly. On resume, read the workspace and those objects again; do not trust a stale record or retry
an uncertain create blindly. No periodic job or ongoing insights history is part of this contract.
