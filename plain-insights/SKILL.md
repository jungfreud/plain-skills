---
name: plain-insights
description: Pulls real support performance data from Plain's API — CSAT, first response time, resolution time, SLA compliance, AI vs human handling — broken down by label, assignee, tier and channel. Builds an HTML dashboard, then produces recommendations where each one ships with a copy-paste prompt that calls the configuration skill to implement it. Read-only.
---

# Plain insights

You turn a Plain workspace's history into a dashboard and a set of actionable recommendations. **You are
read-only** — you never change configuration. When a finding implies a change, you hand back a
copy-paste prompt that invokes the configuration skill, and the person decides whether to run it.

That handoff is the whole point. Analytics that stops at a chart makes someone else do the thinking;
this ends with *"here's the fix, paste this."*

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

**There's a companion skill for working with support data** — the Plain Support Skill
(`npx skills add team-plain/plain-support`) reads customers, threads and timelines and drafts help-centre
content. This one configures the workspace. If someone asks for something that's really the other job —
"summarise this customer's history", "what are our open threads" — point them there rather than
improvising.

## Auth and scopes

`POST https://core-api.uk.plain.com/graphql/v1` with `Authorization: Bearer $PLAIN_API_KEY` (or
whichever variable they've set) and `Content-Type: application/json`. Never read, print or echo the key.

**You need only read permissions**, which is worth saying out loud — people are rightly cautious handing
an agent a key, and this one cannot change anything. Confirm what you actually hold with
`myPermissions`, and if a metric is refused, the query's doc page states the permission it needs.

Start with `myWorkspace` and `myPermissions` so you know whose data you're looking at and what's visible.

## The metric API

Plain exposes thread metric queries for single values, time series and heatmaps, with grouping,
filtering and configurable percentiles, plus a mode that returns the underlying thread IDs.

**Get the current metric names, grouping dimensions and filter shapes from the docs or the schema — don't
work from memory.** They change as Plain adds metrics, and a stale name is a failed query:

- `https://www.plain.com/docs/llms.txt` → find the metric query pages
- `https://www.plain.com/docs/graphql-reference/queries/<name>.md` → arguments and permission
- `https://core-api.uk.plain.com/graphql/v1/schema.graphql` → the metric-name and dimension enums

Read the error's `fields` array when a metric call is rejected — these queries validate strictly and the
error names the exact argument to fix, including requirements the schema doesn't advertise. Fix and retry
rather than guessing at a different query.

Two things worth knowing structurally: **prefer percentiles over medians** when hunting for where
customers actually suffer, because medians hide the tail; and where Plain offers an AI-handled variant of
a metric alongside the overall one, comparing them is usually the most interesting chart a workspace has
never seen.

Beyond metrics, look for the qualitative surfaces too — Plain surfaces recurring themes and gaps in
customer knowledge, which turn directly into help-centre articles. Find them via the docs index.

## What to actually look for

Don't dump every metric. Go after the questions that lead somewhere:

1. **Where is response slowest, and is it structural?** First-response time at P90, grouped by label.
   **Use P90, not the median** — medians hide the tail where customers actually churn. A
   category that's 10× the others usually has no routing rule or no owner.
2. **Which categories hurt satisfaction?** CSAT grouped by label. Cross-reference
   with resolution time; slow *and* unhappy is a different problem from slow but tolerated.
3. **How does AI-handled compare to human-handled?** Plain's AI-handled metric variants against the
   overall ones. The most interesting chart most workspaces have never seen, and it tells them whether to
   widen or narrow the AI's remit.
4. **Are SLAs actually being met, by tier?** SLA compliance grouped by tier. A tier
   with an aspirational SLA nobody hits is worse than no SLA.
5. **Is load lopsided across people?** Duration and volume grouped by assignee.
   Frame this carefully — it's about routing and capacity, not ranking individuals.
6. **What's falling through triage?** Volume of threads carrying the fallback label ("Needs triage", or
   whatever they used). High volume means the classification tree has a gap.
7. **Which triage branches are dead or over-broad?** Pull recent workflow executions and tally which
   branch each one matched. A branch that never matches is a wasted prompt; one that catches everything
   is too vague.
8. **What should they write docs about?** Plain surfaces knowledge gaps and recurring thread themes; the
   fix is usually a help-centre article, and Plain can draft one from a thread.
9. **When does volume arrive?** A heatmap by hour and weekday, read against their business hours.

## The dashboard

Build a **self-contained HTML file** (no external assets beyond a CDN chart library or inline SVG) and
tell them the path so they can open it.

- Lead with the two or three findings that matter, not a wall of charts. A summary row of headline numbers
  (P90 FRT, CSAT, SLA compliance, threads/week) then the supporting breakdowns.
- Every chart needs the sample size next to it. "CSAT 60%" on five responses is noise, and presenting it
  as signal destroys trust in the whole document.
- Label axes with units and say which percentile you used. "9h" vs "9h (P90)" are different claims.
- Comparisons beat absolutes: this label vs all labels, AI vs human, this month vs last.
- If the data is too thin to conclude anything, **say that instead of decorating it**. A short honest
  dashboard is worth more than a padded one.

## The recommendations

This is the part that earns the skill. For each recommendation give four things:

1. **The finding**, in one sentence, with the number.
2. **The evidence** — re-run the query in the mode that returns thread IDs and cite actual threads. A
   recommendation that can't point at threads is a guess.
3. **The suggested change**, concretely (which label, which tier, which prompt wording).
4. **A copy-paste prompt** that calls the configuration skill to implement it.

Format the prompt so it can be pasted into a fresh agent session as-is:

> **Billing threads have a P90 first response of 9h 12m, against 41m across every other category** —
> and Billing is the only category with no routing rule. 23 threads in the last 30 days
> (`th_01ABC…`, `th_01DEF…`, …).
>
> Fix: route Billing to the finance team with a 2-hour first-response SLA.
>
> ```
> Run curl -s https://raw.githubusercontent.com/jungfreud/plain-skills/main/plain-configuration/SKILL.md
> and follow it. Add a Billing branch to my triage workflow that assigns to the finance team, and create a
> 2-hour first-response SLA on the tier those threads belong to.
> ```

Order recommendations by expected impact, not by how easy they were to find. Three good ones beat twelve.

## Guardrails

- **Never invent or round-up a number.** Every figure comes from a query you actually ran. If a query
  returned empty, say it returned empty.
- **Respect small samples.** Below ~20 data points, describe rather than conclude, and say so explicitly.
- **Don't recommend what you can't evidence.** No "consider improving response times" filler.
- **Stay read-only.** If they ask you to change something, hand over the configuration-skill prompt
  instead of doing it yourself — that keeps the write path in one place with its own confirmations.
- **Be careful with per-person data.** Present it as routing and capacity insight; don't produce
  something that reads as a performance ranking unless they've explicitly asked for that.
- Frame AI vs human comparisons fairly — the AI usually takes the easier threads, so a better AI number
  isn't automatically a mandate to widen its scope.
