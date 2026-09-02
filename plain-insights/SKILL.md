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

## Auth and scopes

`POST https://core-api.uk.plain.com/graphql/v1` with `Authorization: Bearer $PLAIN_INSIGHTS_KEY`
(or `$PLAIN_SETUP_KEY` if that's what they have) and `Content-Type: application/json`.

You only need **read** scopes: `metrics:read`, `metricsAgent:read` (required for any assignee or agent
breakdown), `thread:read`, `labelType:read`, `tier:read`, `user:read`, `permission:read`. Say so — people
are rightly cautious handing an agent a key, and this one can't change anything.

Never read, print or echo the key's value; reference the environment variable. Start with `myWorkspace`
and `myPermissions` to confirm which workspace you're looking at and what you can see.

## The metric API

One query shape covers most of it:

```graphql
query { threadSingleValueMetric(input: {
  metricName: threads_first_response_time
  from: "2026-08-01T00:00:00Z"
  to:   "2026-09-01T00:00:00Z"
  groupBy: [{ dimension: LABEL_TYPE }]     # the field is `dimension`, not `groupBy`
  percentile: 90                            # defaults to 50 (median)
  mode: METRIC                              # or THREAD_IDS
}) { values { value group { dimension value } } } }
```

Also available: `threadTimeSeriesMetric` (adds `interval`, for trends) and `threadHeatmapMetric` (for
time-of-day/day-of-week patterns — good for staffing and business-hours arguments). The un-prefixed
`singleValueMetric` / `timeSeriesMetric` / `heatmapMetric` are deprecated and can't filter or group.

**Metric names.** Durations: `threads_first_response_time`, `threads_resolution_time`,
`threads_time_customer_waiting`, `threads_time_between_follow_up_responses` (each also has a `_median`
variant, and accepts `percentile`). Satisfaction: `threads_csat__percentage`, `threads_csat__count`.
SLAs: `service_level_agreement_compliance_frt`, `service_level_agreement_compliance_nrt`. Volume:
`threads_created_count` (time-series only), `threads_status_count__todo|done|snoozed`,
`threads_all_time_count_done`. **Most have an `agent_` prefixed variant** covering AI-handled threads —
`agent_threads_first_response_time`, `agent_threads_csat__percentage`, `agent_threads_resolution_time`
and so on.

**`groupBy` dimensions:** `LABEL_TYPE`, `ASSIGNEE`, `TIER`, `PRIORITY`, `COMPANY`, `TENANT`,
`CUSTOMER_GROUP`, `MESSAGE_SOURCE`, plus `THREAD_FIELD` and `TENANT_FIELD` (both need `subKey` set to the
field key / external ID).

**Requirements the schema doesn't state, and each one is a hard validation error:**
- `to` **cannot be in the future** — even tomorrow's date fails.
- Output is `values { value group { … } }` — `group` singular, not `groups`.
- **`agent_` metrics require a `groupBy`.** Pass `{ dimension: ASSIGNEE }` for a per-agent breakdown, or
  another dimension together with `filters.userIds`. A bare `agent_` query is rejected.
- **CSAT metrics require `filters.surveyResponse.rating`**, e.g.
  `filters: { surveyResponse: { rating: [1,2,3,4,5] } }`.
- All-time counts (`threads_all_time_count_done`) **reject** a date range; everything else requires one.
- `percentile` only applies to the configurable-percentile duration metrics.
- `threadTimeSeriesMetric` additionally needs `interval` (e.g. `DAY`).
- Empty `values` means no qualifying threads in the window, not a broken query — widen the range before
  concluding anything, and never present an empty result as a finding.

Beyond metrics, three qualitative sources matter: `knowledgeGaps` (AI-generated summaries of questions
customers aren't finding answers to), `threadClusters` (recurring themes), and `customerSurveys`.

## What to actually look for

Don't dump every metric. Go after the questions that lead somewhere:

1. **Where is response slowest, and is it structural?** `threads_first_response_time` at P90 grouped by
   `LABEL_TYPE`. **Use P90, not the median** — medians hide the tail where customers actually churn. A
   category that's 10× the others usually has no routing rule or no owner.
2. **Which categories hurt satisfaction?** `threads_csat__percentage` by `LABEL_TYPE`. Cross-reference
   with resolution time; slow *and* unhappy is a different problem from slow but tolerated.
3. **How does AI-handled compare to human-handled?** The `agent_` variants against the base ones —
   remembering that `agent_` metrics need a `groupBy` (`ASSIGNEE` is usually what you want). This is the
   most interesting chart most workspaces have never seen, and it tells you whether to widen or narrow
   Ari's remit.
4. **Are SLAs actually being met, by tier?** `service_level_agreement_compliance_frt` by `TIER`. A tier
   with an aspirational SLA nobody hits is worse than no SLA.
5. **Is load lopsided across people?** Duration and volume by `ASSIGNEE` (needs `metricsAgent:read`).
   Frame this carefully — it's about routing and capacity, not ranking individuals.
6. **What's falling through triage?** Volume of threads carrying the fallback label ("Needs triage", or
   whatever they used). High volume means the classification tree has a gap.
7. **Which triage branches are dead or over-broad?** Pull recent
   `workflowExecutionsForWorkspace` and tally `stepExecutions[].output.matchedConditionIndex`. A branch
   that never matches is a wasted prompt; one that catches everything is too vague.
8. **What should they write docs about?** `knowledgeGaps` and `threadClusters` — the fix is usually a help
   center article, and `generateHelpCenterArticle` can draft it.
9. **When does volume arrive?** `threadHeatmapMetric` by hour/day, against their business hours.

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
2. **The evidence** — set `mode: THREAD_IDS` on the query behind it and cite actual threads. A
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
