# Working with Plain's API

**This file deliberately contains almost no facts about Plain.** Facts go stale; Plain's docs don't. What
this gives you is where to look, how to look, and how to work safely — so whatever you build is correct on
the day you build it rather than on the day this was written.

If you catch yourself about to state something specific about Plain — a field name, an enum value, a
permission, whether a thing is possible — **look it up first**. That takes seconds and it's the difference
between building the right thing and confidently building the wrong one.

---

## Where the truth lives

| Source | Use it for |
|---|---|
| `https://www.plain.com/docs/product/what-is-plain.md` | What Plain is and how the product fits together — start here for anything conceptual |
| `https://www.plain.com/docs/llms.txt` | The full docs index (~1,000 pages). Every page has a `.md` version. This is your map. |
| `https://www.plain.com/docs/graphql-reference/mutations/<name>.md` | A specific mutation: its arguments **and the exact permission it requires** |
| `https://www.plain.com/docs/graphql-reference/queries/<name>.md` | The same for queries |
| `https://core-api.uk.plain.com/graphql/v1/schema.graphql` | Exact input-type shapes and enum values when the docs page doesn't spell them out |

Fetch the index when you don't know what exists. Fetch the operation page when you know the name. Fetch
the schema when you need a precise shape or a list of enum values.

**Endpoint:** `POST https://core-api.uk.plain.com/graphql/v1`
**Headers:** `Authorization: Bearer $PLAIN_API_KEY` and `Content-Type: application/json`
**Body:** `{ "query": "...", "variables": {...}, "operationName": "..." }`

Never read, print, echo or log the key's value — reference the environment variable only.

---

## Ask the API, don't assume

Anything that looks like a list — permissions, event types, enum values, what exists in this workspace —
should come from a live query, not from memory. These are the ones worth knowing:

```graphql
query { myWorkspace { id name } }                    # which workspace am I actually pointed at?
query { myPermissions { permissions } }              # what can this key really do?
query { subscriptionEventTypes }                     # valid webhook event types
query { workflowCapabilities(triggerType: ...) }     # what a workflow of this type may contain
query { users(first: 50) { edges { node { id publicName } } } }
query { labelTypes(first: 100) { edges { node { id name type } } } }  # teams are TEAM-kind labels
query { workflows(first: 20) { edges { node { id name publishedAt { iso8601 } } } } }
query { labelTypes(first: 100) { edges { node { id name } } } }
query { tiers(first: 20) { edges { node { id name } } } }
```

**Teams are not a separate entity.** A team is a label type of kind `TEAM`, so they're listed by filtering
`labelTypes` on `type`, created the same way any label is, and referenced by their label-type ID wherever
something assigns to a team. There is no `teams` query.

Start every session with `myWorkspace` and `myPermissions`. The first tells you whether you're about to
modify the workspace they meant — read the name back to them before creating anything. The second tells
you what will fail before it fails.

---

## Before you call a mutation

1. **Read its doc page** — `…/graphql-reference/mutations/<name>.md`. Arguments and required permission.
2. **If the shape is ambiguous, check the schema** for the input type.
3. **Resolve every ID you need first.** Payloads embed IDs, not names — a name where an ID belongs will
   often be accepted and then silently do nothing.
4. **Send it, then check `error` before believing it worked:**
   ```graphql
   { ... error { message code fields { field message } } }
   ```
   The `fields` array names exactly what's wrong. Most validation failures are self-correcting: read it,
   fix that field, retry. Don't guess at a second attempt.

**The API validates more strictly than the schema advertises.** Fields the schema marks optional can be
required at runtime, and some combinations that look legal are rejected. This is normal and it is not a
reason to give up on a call — the error tells you precisely what to change. Never work around a validation
error by inventing a different field name.

**Verify the end state, not the step status.** Some operations report success while doing nothing useful.
After anything that matters, read the object back and confirm it actually changed.

---

## Order of operations

Dependencies are real: build the things other things point at, first.

**Tiers** → **SLAs** (need a tier) → **business hours** → **labels** → **field schemas** → **escalation
paths** (need labels and users) → **workflows** (need label, user, team and tier IDs to exist) → **saved
views** → **help centre** → its **groups** → its **articles** → **knowledge sources** → **Sidekick** →
**webhooks** → **tenants and their field values**.

Keep a running map of name → real ID as you go.

---

## Triage architecture

This is the part worth understanding structurally, because it's about how to compose the pieces rather
than what they're called. Check the workflow docs
(`https://www.plain.com/docs/product/workflows.md` and the pages under it) for current specifics.

**One workflow per entry trigger, doing classification and routing together.** A workflow's own actions
don't cascade into other workflows, so the intuitive "triage applies a label, a second workflow reacts to
that label" design will silently never fire for automated triage. Label-triggered workflows are for
reacting to *human* labelling.

Inside that one workflow:

1. **Cheap deterministic conditions first** — a dedicated support address, a tier, an existing label.
   They're instant, free, and they shrink the population before you spend AI latency. Anything
   high-stakes should have a deterministic route so the critical path never depends on a prompt.
2. **One multi-branch AI condition rather than a chain of binary ones.** Plain's `else_if` condition takes
   an ordered list of conditions and stops at the first match, so it's one step and one short-circuiting
   evaluation instead of N sequential model calls.
3. **Chain each branch's actions** — label, then priority, then assignment — by pointing each action at
   the next.
4. **Always wire the fallback branch** to a visible "Needs triage" label rather than nothing, so
   unclassified threads surface instead of vanishing.
5. **Publish it.** Creating a workflow leaves it as an inactive draft; it does nothing until published.

**Ordering is the tiebreak** — there's no scoring and no best-match. Precedence: **stakes first, frequency
second.** A branch that's expensive to mis-triage goes first regardless of how rare it is; order the rest
most-likely-first for latency. Say which rule you applied so the person can disagree.

**Build the steps leaf-first**, because a step's transitions need the IDs of the steps it points at.

**Audit before you add.** Multiple published workflows on the same trigger all fire, with no ordering
guarantee — the symptom is threads picking up labels nobody expected. List what's published first.

**Test it and tune from the trace.** Create a real-looking thread, then read the workflow execution back:
the condition step's output tells you which branch matched. That's the tuning loop, and doing it once in
front of the customer teaches them to maintain it.

---

## Writing AI prompt conditions

Plain documents this properly, including what context the model sees and worked good/bad examples:
**`https://www.plain.com/docs/product/workflows/workflows-conditions.md`** — read it rather than
improvising a house style, because the in-product UI teaches the same convention and consistency matters.

The short version: write `Match if… / Don't match if…`, one decision per condition, with concrete examples
in the customer's own vocabulary. Only ask about what's in the thread — anything about plans, tiers or
external systems belongs in a deterministic condition instead. Never "use your best judgment".

**The highest-leverage thing you can do is ask for their real tickets.** A handful of genuine subject
lines beats any prompt you'd write from imagination — it gives you their customers' actual vocabulary and
usually surfaces a category nobody mentioned.

---

## When something is refused or seems impossible

**Do not tell a customer that Plain can't do something based on your own inability to find it.** Absence
of evidence is not absence of capability, and a wrong "that's not possible" is worse than a wrong field
name — people make purchasing and migration decisions on it.

The order to work through:

1. Search the docs index for the capability.
2. Read the relevant operation's doc page.
3. If a call is genuinely refused, quote the actual error you got.
4. If you still can't confirm it either way, say exactly that — *"I couldn't confirm this; check the docs
   or ask Plain"* — rather than asserting a limitation.

Some things genuinely need a human in a browser: OAuth consent for channels and connectors, DNS
verification, and anything that requires a real logged-in user rather than an API key. When you hit one,
name the specific settings page and, if there's time, walk them through it rather than filing it in a
report. And be straight that **support isn't live until an inbound channel is connected** — a configured
workspace with no channel receives nothing.

---

## Migrating from another help desk

**Check for a built-in importer before writing anything custom.** Plain has importers for common providers
that carry over history with original timestamps — see
`https://www.plain.com/docs/product/integrations/` for what's supported, and each provider's page for
exactly what does and doesn't come across.

For a source with no built-in importer, Plain has import mutations that preserve original timestamps,
authors and attachments, and are idempotent so a re-run doesn't duplicate. Start at
`https://www.plain.com/docs/graphql/threads/import.md` and
`https://www.plain.com/docs/graphql/custom-ticket-importer.md`. Imports are designed not to trigger SLAs,
auto-responses or workflows, so migrating history doesn't email anyone or start clocks — confirm that on
the docs page before you promise it.

Note that import needs its own permission scope, which isn't part of a normal configuration key.

---

## Metrics

For auditing an existing workspace — response times, resolution times, CSAT, SLA compliance, AI-handled
versus human-handled — Plain exposes thread metric queries supporting grouping (by label, assignee, tier,
channel and more), configurable percentiles, and a mode that returns the underlying thread IDs so a
finding can cite its evidence.

Get the current metric names and grouping dimensions from the schema enums or the query's doc page rather
than from memory; they change as Plain adds metrics. Prefer percentiles over medians when you're looking
for where customers are actually suffering — medians hide the tail.
