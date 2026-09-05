---
name: plain-onboarding
description: Set up a Plain workspace through a short conversation. Research the company or use an existing setup as context, then build AI labeling, team routing, tailored Sidekick investigation skills, and knowledge sources through plain-configuration.
license: MIT
metadata:
  author: plain
  version: "0.2"
  requires: curl, jq, a terminal, and a Plain API key for the build
allowed-tools: Bash Read Write WebFetch
---
# Plain onboarding

Help a founder or support leader at a software business get value from an initially empty Plain
workspace. Assume they are using Codex, Claude Code, or another agent with a terminal. They need a useful
starting setup they can change, not a perfect support operating model or a tour of every setting.

**Own the conversation and design.** Hand the agreed result to `plain-configuration` to build and verify.
These coding-agent skills create **workspace Sidekick skills** inside Plain; distinguish the two when
explaining what the customer will receive.

## Start with their business

Open with the outcome and one useful question. For example:

> I can set up Plain so incoming tickets get labeled, routed to the right team, and investigated by
> Sidekick using your tools. What's your company website or docs URL? You can also share an export of
> your current setup, or we can start from scratch.

Use any context they already supplied. Read the site, docs, or export before asking them to repeat it.
Fetch product facts from [Plain's docs index](https://www.plain.com/docs/llms.txt) and relevant pages;
use the site for vocabulary and products, not invented ticket volumes, internal team names, or SLAs.
Documentation sections are not automatically a good ticket taxonomy.

Use the shortest of these paths:

- **Website/docs:** research, propose a small set of useful issue categories, then fill the real gaps.
- **Existing setup/export:** read it as design context. Identify useful labels, teams, and investigation
  routines; propose their equivalents in a new Plain configuration. Do not import historical tickets or
  promise imported settings. If migration comes up, link the appropriate [importer docs](https://www.plain.com/docs/product/integrations)
  and explain that historical-data migration is separate from the labels and workflows being built here.
- **From scratch:** ask what they support and what customers typically need, then propose the same setup.

A brief proposal plus a few corrections is preferable to a long questionnaire. Ask one focused question
at a time, or a small related group when it saves a round trip. Skip answered questions. Explain what a
choice will do in the customer's words; don't narrate research or celebrate every answer.

## Discover what must happen on an incoming ticket

Learn enough to decide these five things, usually over a few exchanges:

1. **Categories:** what are the main reasons customers contact them? Offer labels from your research;
   ask for their top recurring issues or a few representative tickets to refine the vocabulary.
2. **Ownership:** which teams or people handle those categories, and who catches anything unclassified?
   Ask for actual members when team assignment requires them. A five-person company may need one team;
   company size alone is not a reason to invent multiple departments.
3. **Investigation:** “What would a support engineer check before they could resolve one of these?”
   Ask which tools they use or plan to connect: GitHub, Datadog, Sentry, Linear/Jira, Slack, internal MCPs,
   account data, or other systems they name. Record relevant repositories, projects, environments, or
   channels if known. Tools used here in the coding agent are not necessarily connected to Sidekick.
4. **Actions:** what should happen automatically after investigation? Propose an internal summary and
   draft reply by default; ask about preparing/linking issues, requesting missing information, or other
   follow-up skills when useful. Record which actions may execute and which should await a person.
5. **Knowledge and customer replies:** where are their maintained docs? Should Ari answer routine
   questions directly, or should Sidekick prepare replies for the team? Avoid two agents independently
   sending replies on the same branch.

Only ask about support hours, tiers, SLAs, custom fields, saved views, or help-center hosting when their
answers make them relevant or they request them. Preserve relevant information from an export, but do
not make advanced settings a prerequisite for the first useful workflow. Link existing docs as knowledge
sources by default; do not duplicate a maintained documentation site into a new help center.

## The default proposal

Read [the triage blueprint](../plain-configuration/references/TRIAGE.md) when designing Sidekick behavior.
If this file was fetched alone, use the matching sibling URL under the same repository and ref as this
skill. For the published main version that is:
`https://raw.githubusercontent.com/jungfreud/plain-skills/main/skills/plain-configuration/references/TRIAGE.md`.

Propose one coherent **inbound triage workflow**:

- Trigger on a new thread, with deterministic checks for explicit routing facts first where relevant.
- Classify into ordered AI conditions using “Match if… / Don't match if…”, highest-stakes overlaps first.
- On each branch, apply the category label, set the agreed priority, assign the owning team/person,
  then start a Sidekick discussion invoking the appropriate workspace skill.
- Give unmatched threads a visible “Needs triage” label, an owner, and general investigation.
- Use a common Thread triage skill plus focused child skills where the customer needs different work,
  such as Bug investigation or Prepare engineering issue. Every referenced child must be created or
  confirmed as an enabled existing skill. A single general skill is enough for simple setups.
- Ari may own explicitly agreed routine-question branches with knowledge sources, assignment, and its
  response mode configured. Retain team ownership/Sidekick investigation on the other branches.

The workflow owns initial labeling and routing. Sidekick investigates and acts within the agreed scope;
its skill should not casually undo that routing. Keep classification, assignment and Sidekick initiation
in the same workflow. Do not depend on another workflow reacting to a label that this workflow added.
Human-applied-label triggers are an optional later flow, not necessary for the default.

Show a compact table: **ticket category → owner → what Sidekick checks → expected result**. Mark inferred
choices as proposals. Include each planned integration and what will work before it is connected.

A missing MCP does **not** block writing the skill or building a workflow with a supported Sidekick
step. The skill should use available evidence and explicitly report unavailable checks. If a particular
branch cannot do useful work without the tool, agree whether it should wait in draft or run a limited
investigation. Never claim a planned connection was made or tested.

## Agree, connect, build

Before asking for a key, show the proposed setup and get agreement, including publishing the inbound
workflow and any future automatic actions. Save the agreed design using
[the configuration contract](../plain-configuration/references/CONFIG-SPEC.md).
This is an execution handoff, not ongoing cross-session memory. Do not set up recurring checks.

The design can happen without an account. If they do not have a workspace, have them
[create one](https://app.plain.com/workspaces/create/) when ready to apply the design. Explain that an
admin/owner needs to supply the setup access if the person running this cannot.

Read `../plain-configuration/SKILL.md` and its auth instructions. If not installed locally, fetch it
from the same repository/ref as this skill; the published main URL is:
`https://raw.githubusercontent.com/jungfreud/plain-skills/main/skills/plain-configuration/SKILL.md`.
Let that skill obtain its supporting files and use the agreed spec. It owns workspace verification,
credential handling, dependency checks, API calls, existing-config checks, and execution recovery.
Do not re-ask decisions already authorized in this conversation.

Explain meaningful progress in short updates, not raw GraphQL or an ID after every mutation. If a step
fails, say which behavior is affected. Keep real IDs for the build record and report.

## Demonstrate and hand off

Use configuration's test procedure on an agreed test customer/thread. Verify the label, actual team
assignment, and a Sidekick session tied to that thread with the intended skill and resulting evidence.
Test the fallback too. For Ari, verify knowledge readiness, assignment, and its agreed response mode;
a source merely being created does not prove Ari can answer from it.

A **configured** workspace has the agreed objects and workflow. A **verified** path has passed a test.
A **live** path also has its inbound channel, necessary tools and approval settings ready. Report these
separately; a missing MCP can be the last connection task without making the whole setup a failure.

Produce a self-contained local HTML handoff, with inline styling and no API credentials, analytics, or
external scripts. Escape customer-supplied content. Include:

- **What happens to a ticket:** the category/owner/investigation table, in plain language.
- **Built:** actual labels, teams, workflows, Sidekick skills, and knowledge sources with IDs and known
  links; include any additional settings they requested. Never invent deep-link URL patterns.
- **Proved:** real test thread/session references, observed results, and checks still unverified.
- **Finish connecting:** each missing MCP/integration, channel, team membership/invite or approval,
  the specific feature it enables, and the current UI page from the docs. For Sidekick integrations,
  the documented route is Plain AI → Sidekick → Integrations; check it when writing the report.
- **Make it yours:** where to tune labels, workflow conditions and Sidekick skill instructions, plus a
  short prompt to request the next change through plain-configuration.

Lead with the few remaining actions. A customer should understand exactly what happens after connecting
Sentry or their support channel. Include failures separately from normal connection tasks. Close with
what works now and a reminder to revoke or narrow the temporary setup key.
