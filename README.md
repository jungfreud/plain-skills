<h1 align="center">Plain skills</h1>

<p align="center">
  Configure and improve your <a href="https://www.plain.com">Plain</a> workspace by talking to your coding agent.
</p>

<p align="center">
  <a href="https://www.plain.com">plain.com</a> ·
  <a href="https://www.plain.com/docs">Docs</a> ·
  <a href="https://www.plain.com/docs/graphql/introduction">GraphQL API</a>
</p>

---

## What this is

[Plain](https://www.plain.com) is a customer support platform for software companies. Everything in it —
tiers, SLAs, labels, routing, the AI agents, the help center — is a first-class object in a GraphQL API
rather than something buried in a settings screen. Anything you can do in the app, you can do over the API.

That's powerful, and it's also a lot to take in: the schema runs to roughly 440 mutations. If you point an
agent at it cold, it has to work out which handful of operations matter, what order they depend on, and
which inputs the schema describes differently to how the API actually validates them.

**These skills are that shortcut.** Each one is a single Markdown file that teaches an agent how to use
Plain's API for one specific outcome — configure a workspace, or pull insights out of one — so you get it
right first time and finish in one sitting.

## Who it's for

- **New to Plain** and you'd rather your agent set the workspace up than click through settings.
- **Already on Plain** and you want to change how triage, routing or SLAs work without hunting through
  docs.
- **A developer** integrating with Plain's API, agent or not. The reference is a curated path through the
  schema and stands on its own.

You don't need to know the GraphQL API, and you don't need to install anything.

## The skills

Each is standalone. Load whichever matches what you're doing — or let the onboarding skill call the
configuration skill for you.

| Skill | Use it when | What it does |
| --- | --- | --- |
| **[plain-configuration](./plain-configuration/SKILL.md)** | You know what you want your workspace to do | Teaches your agent to build it: tiers, SLAs, business hours, labels, custom fields, AI triage and routing workflows, saved views, help center, knowledge sources, Sidekick, webhooks. Applies everything in the right order, verifies each step, and tells you what still needs a click in the app. |
| **[plain-onboarding](./plain-onboarding/SKILL.md)** | You're starting from scratch and want to be walked through it | A guided conversation about how your support actually works today. It designs the workspace with you, explains what each choice buys you, then hands the result to **plain-configuration** to build. |
| **[plain-insights](./plain-insights/SKILL.md)** | You want to know what to improve | Read-only. Pulls CSAT, first response and resolution times, SLA compliance and AI-vs-human handling — by label, assignee, tier and channel — into an HTML dashboard, then turns each finding into a prompt you can paste to fix it. |

The modularity is the point. **plain-configuration** is the engine and works entirely on its own —
describe what you want in a sentence and your agent can one-shot it. **plain-onboarding** is a
conversation layer that produces a configuration spec and calls the engine with it. **plain-insights**
looks at what's actually happening and hands you prompts that call the engine too.

```
                 plain-onboarding ─┐
   (guided conversation)           │
                                   ├──▶  plain-configuration  ──▶  your workspace
                 plain-insights ───┘         (the engine)
   (find what to improve)
```

## Get started

Paste this into any agent with a terminal — Claude Code, Codex, Cursor:

**Set up a new workspace, guided:**

```
Run curl -s https://raw.githubusercontent.com/jungfreud/plain-skills/main/plain-onboarding/SKILL.md
and follow exactly what it outputs. I'm new to Plain — walk me through it and set up my workspace.
```

**Already know what you want:**

```
Run curl -s https://raw.githubusercontent.com/jungfreud/plain-skills/main/plain-configuration/SKILL.md
and follow it. I want AI triage that labels incoming threads as Bug, Billing or Feature Request, routes
bugs to engineering as high priority, and a 1-hour first response SLA for enterprise customers.
```

**Find out what to improve:**

```
Run curl -s https://raw.githubusercontent.com/jungfreud/plain-skills/main/plain-insights/SKILL.md
and follow it. Show me where our support is slowest and what I should change.
```

It's a `curl` rather than "read this URL" because not every agent has a web-fetch tool, but they can all
run a shell command.

Prefer a package manager? Via [skills.sh](https://www.skills.sh):

```
npx skills add jungfreud/plain-skills
```

## Your API key

You'll need a Plain workspace and an API key: **Settings → Machine Users → Add API key**. The Admin preset
covers everything; if you'd rather scope it tightly, the exact permissions are listed in the
[reference](./reference/graphql-reference.md).

**Don't paste the key into the chat.** Set it as an environment variable yourself:

```bash
echo 'export PLAIN_SETUP_KEY="plainApiKey_xxx"' >> ~/.zshrc && source ~/.zshrc
```

Then just tell your agent it's set. The skills reference `$PLAIN_SETUP_KEY` and never read or print its
value, so the secret stays out of your conversation history.

When you're done, delete the machine user or narrow the key — a setup key can create tiers and publish
public help center content.

For **plain-insights**, a read-only key is enough (`metrics:read`, `metricsAgent:read`, `thread:read`,
`labelType:read`, `tier:read`, `user:read`, `permission:read`), which is a safer thing to hand an agent.

## The reference

[`reference/graphql-reference.md`](./reference/graphql-reference.md) is the curated path through the API:
the ~30 mutations that matter for configuring a workspace, with their exact input shapes, the dependency
order, and the behaviours you'd otherwise find the hard way. For example:

- A workflow's SLA first-response and next-response targets are mutually exclusive — you need two records
- `inviteUserToWorkspace` can't be used by machine users, so invites are always a human step
- Workflow actions don't cascade into other workflows, which changes how you structure triage and routing
- `assign_to_user` given a machine-user ID reports success and assigns nobody
- Label icons are slugs, not emoji; `DateTime` is an object, not a scalar

It also lays out the recommended triage architecture: one workflow on thread creation, cheap deterministic
conditions first, then a single `else_if` switch of AI prompt conditions — an N-way switch that stops at
the first match — with each branch chaining its own label, priority and assignment actions.

## Verify it still holds

`tests/smoke.sh` is a read-only check that the API still behaves the way the reference describes.

```bash
PLAIN_SETUP_KEY=plainApiKey_xxx ./tests/smoke.sh
```

## Found something wrong?

APIs move. If a skill hits something that doesn't match, please
[open an issue](https://github.com/jungfreud/plain-skills/issues) with the error the API returned — that's
the most useful contribution there is.

For questions about Plain itself, see the [docs](https://www.plain.com/docs) or
[get in touch](https://www.plain.com).
