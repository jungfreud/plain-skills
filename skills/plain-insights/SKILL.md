---
name: plain-insights
description: Review a period of Plain support activity and suggest better labels, routing and Sidekick investigations. Produce an evidence-backed HTML dashboard, and hand a selected improvement to plain-configuration in the same conversation.
license: MIT
metadata:
  author: plain
  version: "0.2"
  requires: curl, jq, a terminal, and a Plain API key
allowed-tools: Bash Read Write WebFetch
---
# Plain insights

Help an existing Plain customer understand what to improve in their support setup. Focus on useful
changes: a missing label for recurring issues, a slow escalation route, a knowledge gap, or a Sidekick
routine that can collect context before a human starts work. Analysis is read-only; a chosen change is
applied by `plain-configuration` with its normal scope and verification in the same conversation.

## Start with a period and current context

Use the requested time range; otherwise default to the last 30 complete days and state exact dates and
timezone. Ask about the goal only when it would change the analysis. Do not run a long onboarding
interview or assume previous decisions are remembered. Read fresh data each time; do not create a
scheduled job, background monitor or persistent decision history.

Start with workspace identity and permissions. Use existing read access. For auth and helper setup, read
`../plain-configuration/SKILL.md` (or the matching URL under the same repository/ref as this skill; main:
`https://raw.githubusercontent.com/jungfreud/plain-skills/main/skills/plain-configuration/SKILL.md`).
Use only its read commands during this phase; loading it is not permission to apply configuration.

Read current labels, teams/members, relevant published workflows and their conditions/actions, enabled
Sidekick skills and their instructions, knowledge sources, and relevant connection status. A missing
permission means “not visible,” not “not configured.” Paginate every collection used for an inventory.

Look up metric names, dimensions, filter shapes and thread-ID drilldowns in
[Plain's docs index](https://www.plain.com/docs/llms.txt), the operation pages and
[the schema](https://core-api.uk.plain.com/graphql/v1/schema.graphql). Never invent a metric or API field.
Use the companion Plain Support Skill if installed for reading support conversations; otherwise consult
the relevant Plain thread/timeline docs. Evidence collection for this audit is part of this task.

## Questions worth answering

Select the few with sufficient data and a useful next action:

- **Recurring topics with no useful label:** inspect a representative sample of threads as well as
  existing labels; propose a new category only when it adds a distinct operational/reporting use.
- **Slow responses, resolution or escalation:** examine P90 plus volume by category/team and relevant
  tier/channel; inspect examples, routing and assignment history before diagnosing the bottleneck.
- **Lost triage:** look at fallback volume, wrong assignments and workflow execution traces. Empty or
  over-broad branches may need better conditions, but an intentionally rare security branch is not
  redundant merely because it did not fire this month.
- **Repeated engineering investigation:** check whether agents repeatedly collect the same logs, check
  the same issue tracker, or request missing context. Suggest a tailored Sidekick skill that does that
  preparation, with clear evidence and an appropriate owner.
- **Knowledge gaps:** identify recurring answerable questions and missing/unclear source material;
  recommend a source update or article draft, not unsupported automatic publication.
- **Sidekick skill effectiveness, where measurable:** associate actual skill invocations with their
  threads and outcomes only if those links are available. Compare like-for-like cohorts by category,
  severity/channel and period, disclose sample sizes and selection effects. If the API cannot attribute
  a session to a skill, say per-skill impact is not measurable from the available data.
- **CSAT / SLA / workload:** use them when they explain a setup change. Present per-person data as a
  routing/capacity question, not a performance ranking.

AI-handled vs overall metrics are not automatically AI vs human. Never subtract medians/percentiles to
invent a human cohort. Use explicit cohorts or label the comparison accurately. Treat correlations as
hypotheses, not proof that a skill caused faster resolution. Check duration units, coverage and sample
sizes; below roughly 20 observations describe the examples without strong conclusions.

## Recommendations that can be acted on

For each of the top two or three recommendations provide:

1. **Finding:** actual number or observed theme, exact period, sample size and coverage.
2. **Evidence:** thread links/IDs and relevant configuration or trace evidence; distinguish a sample
   from a full-population count.
3. **Proposed change:** specific label, workflow branch, routing change, knowledge update or Sidekick
   skill. Describe what the skill should check and what it should produce.
4. **Prerequisites and uncertainty:** tools, permissions and any alternative explanation for the issue.
5. **Apply prompt:** enough context for plain-configuration to inspect the current setup and propose
   the exact change, preserving existing behavior.

Example hypothesis, only after collecting evidence: repeated Bug escalations wait for logs and related
issues. Propose a Bug investigation routine that searches the connected Sentry/GitHub tools and prepares
a Linear issue with reproduction and sources. Inspect existing issues to avoid duplicates, and preserve
approval rules for issue creation. Explain this may reduce preparation time; do not promise it will fix
resolution time without testing.

Do not change a tier-wide SLA to address a category-specific delay without checking its other affected
threads. Do not tighten an SLA merely to make a slow process appear fixed.

## Dashboard and same-conversation handoff

Produce a self-contained HTML file with inline styling and charts (SVG is sufficient), no external
scripts/assets, no keys, and escaped source content. Give it an **Overview** and **Suggestions** tab,
with keyboard-accessible controls. Headline the findings, period and data coverage. Add only charts that
support them, showing units, percentile, sample sizes and appropriate comparisons. If there is little
data, a short report with clearly limited observations is enough.

In Suggestions, include the evidence, proposed behavior, prerequisites and a copyable apply prompt.
The file must not call APIs or run changes; it is a report. Never embed credentials. For a standalone
prompt, use the matching configuration-skill URL and summarize the recommended scope in the text.

Ask which improvement they want to apply. If they choose one, load plain-configuration and pass the
selected change and evidence **in this conversation**, retaining their authorization. It checks current
state and shows the actual change before writing. If only a read key is available, explain the exact
additional access needed at that point; do not request write access just to generate the dashboard.

After configuration returns, state what changed, what was verified and what remains pending. Update the
report with the result if useful. If they only want the report, stop there.
