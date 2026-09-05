# Working with Plain's API

## Authoritative sources

| Source | Purpose |
| --- | --- |
| https://www.plain.com/docs/llms.txt | Discover relevant current product and API pages. |
| https://www.plain.com/docs/graphql-reference/mutations/OPERATION.md | Mutation documentation; check permissions where stated. |
| https://www.plain.com/docs/graphql-reference/queries/OPERATION.md | Query documentation. |
| https://core-api.uk.plain.com/graphql/v1/schema.graphql | Current input/output types, enums and field descriptions. |

Operation pages can be terse; use the schema when a page omits input shapes. Avoid repeatedly downloading
the entire schema: cache it during the setup and inspect the relevant definitions. If docs and observed
API behavior disagree, report the specific discrepancy. Don't claim a capability is impossible because
a page doesn't list it. These references guide discovery; the CLI's encoded operations still need tests
when the API changes.

POST to `https://core-api.uk.plain.com/graphql/v1`, or the endpoint selected by `PLAIN_API_URL`, with
`Authorization: Bearer $PLAIN_API_KEY`, `Content-Type: application/json` and `{query, variables}`.
Credential handling is defined in the configuration skill; never print the key.

## Read, resolve, write, verify

Start with workspace identity, permissions and relevant existing state. Paginate connections until
`pageInfo.hasNextPage` is false; fixed `first: 100` limits are not complete inventories. Resolve actual
IDs before writes. A name passed where an ID belongs can lead to an ineffective action.

For mutations, select `error { message code fields { field message } }` as well as the created/updated
object. Check HTTP errors, top-level GraphQL `errors`, and mutation `error`; transport success is not
operation success. Read back the resulting state after an important mutation. Never automatically retry
writes on network errors: first determine whether the previous request took effect.

The helper's `request QUERY_FILE [VARIABLES_FILE]` supports operations it does not wrap, after their
shape has been verified. Keep keys out of these files. It applies the same error handling as helper
commands. Do not use it to bypass a missing capability or approval.

## Teams and identity

Teams are label types with `type: TEAM`, not a separate `teams` GraphQL query. The helper exposes
`teams`, `label create --team`, and `team add-member --team LABEL_ID --user USER_ID`.
`addLabelsToUser` takes `entityId` for the user and `labelTypeIds` for membership.

Resolve users with `users` or the documented `userByEmail` query. Inspect user labels to verify membership.
An empty/new team or a member awaiting invitation needs an explicit handoff. For agent assignment, read
the current API shape and agent identity; do not treat a Sidekick discussion as user assignment.

## Workflow graphs

Read `workflow list` before adding another published workflow. Use `workflow get ID` to inspect trigger,
steps, payloads and transitions. Build terminal steps first so earlier steps can refer to real next-step
IDs. Action transitions contain one next ID (or null); an else-if classifier with N prompts needs N+1
transitions, including the fallback. Give steps descriptive names and separate canvas positions.

Do classification, labeling, priority, ownership and Sidekick initiation together. Do not rely on a
workflow's own label action to trigger a second workflow. Verify that relevant existing workflows do not
also classify/start investigations for the same entry event.

Creating a workflow makes a draft. Publish only the agreed complete graph. For a published graph update,
explain the unpublish/edit/republish interval and retain the prior graph. See [TRIAGE.md](TRIAGE.md) for
Sidekick payload discovery from current templates and real-workspace verification.

The following reads are covered by the helper:

```graphql
query { workflowCapabilities(triggerType: EVENTS) { hasConditionSupport allowedActionTypes } }
query { workflowTemplateGallery { id title tags } }
query($id: ID!) {
  workflowTemplate(templateId: $id) {
    id title workflows { name trigger startStepId steps { id type name payload transitions positionX positionY } }
  }
}
```

## Sidekick API contract

Checked against the public schema during this revision; read the current definition when applying.

```graphql
query {
  sidekickSkills {
    name displayName description isEnabled
    ... on CustomSidekickSkill { customSkillId }
  }
}
query($id: ID!) {
  sidekickCustomSkill(id: $id) { id name displayName description instructions isEnabled }
}
mutation($i: CreateSidekickCustomSkillInput!) {
  createSidekickCustomSkill(input: $i) {
    customSkill { id name displayName description instructions isEnabled }
    error { message code fields { field message } }
  }
}
```

Create input: `displayName`, `description`, `instructions`. The optional legacy `name` field is ignored;
use the returned slug for `/skill-name` references. Update input uses `customSkillId` and optional
`displayName`, `description`, `instructions`, `isEnabled`; instructions replace the whole body. Creation
alone is not proof the skill is enabled or invoked by a workflow.

`sidekickMcpServers` returns custom MCP connections, including `isConnected` and discovered tools.
`serviceAuthorizations` lists built-in service connections; consult each service's configuration query
for accessible repo/project scope. Missing read permissions mean “unknown,” not “disconnected.”
`agentSandboxToolPolicies` exposes effective action modes. Do not infer write permission from a skill's
wording or globally change approval modes during setup.

## Optional surfaces and operational traps

Read the relevant docs/input types when requested, rather than carrying every API shape in a skill:

- Tiers precede their SLAs. First-response and next-response targets are separate SLA records; inspect
  priority filters, business-hours behavior and pre-breach warning validation.
- Business-hours synchronization replaces the whole set. Read the current slots and show the difference;
  the helper refuses an existing set without `--force`. Do not use `--force` without the agreed change.
- Thread fields can depend on labels; field keys are immutable. Tenant values depend on their schemas.
- Escalation paths depend on users/labels; workflows depend on those objects and saved Sidekick skills.
- Help-center publishing is customer-facing. Use actual source content and agreed visibility. Creating a
  knowledge source, publishing an article, and enabling Ari are distinct operations.
- Webhook events come from `subscriptionEventTypes`; do not guess them.
- For a requested snippet, preserve exact approved text and surface unresolved old-system placeholders.

Imports are outside these skills' execution scope. An existing export can inform the design. Link the
appropriate importer docs for historical-ticket migration and do not promise it configures labels or
workflows for this onboarding.

## Human connection tasks

MCP authentication, OAuth consent, inbound channels, DNS, and account/member operations may require
human UI steps. Check the exact operation/docs before stating a limitation. Use a known current UI path
or documentation link; never invent a deep link. Read-only connected-status checks may be performed here,
but the customer connects their tools in Plain's UI. Include each outstanding task and affected behavior
in the handoff. A configured workspace without an inbound channel cannot receive new support tickets.
