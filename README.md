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

That's powerful, and it's also a lot to take in. The schema is large, and if you point an agent at it cold
it has to work out which handful of operations matter, what order they depend on, and which inputs the API
validates more strictly than the schema suggests.

**These skills are that shortcut.** Each one is a single Markdown file that teaches an agent how to use
Plain's API for one specific outcome — configure a workspace, or pull insights out of one — so you get it
right first time and finish in one sitting.

## Who it's for

- **New to Plain** and you'd rather your agent set the workspace up than click through settings.
- **Already on Plain** and you want to change how triage, routing or SLAs work without hunting through
  docs.
- **A developer** integrating with Plain's API, agent or not. The reference is a working method for the
  API — where to look things up and how to avoid the common traps — and stands on its own.

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
is the simplest choice for a one-off setup key; your agent can also work out the narrower set of
permissions a given configuration actually needs, since every operation's doc page states its own.

**Don't paste the key into the chat.** Put it in a file only you can read, and your agent will load it per
command:

```bash
printf 'export PLAIN_SETUP_KEY="plainApiKey_xxx"\n' > ~/.plain-setup.env && chmod 600 ~/.plain-setup.env
```

Then just tell your agent it's set. The skills reference the variable and never read or print its value,
so the secret stays out of your conversation history. Don't append it to `~/.zshrc` — that writes a
temporary credential into a file people commit to dotfiles repos.

When you're done, delete the machine user (and the env file). A setup key can change your configuration
and publish public content.

**plain-insights needs only read access**, which is a much safer thing to hand an agent — it can't change
anything.

## The reference

[`reference/graphql-reference.md`](./reference/graphql-reference.md) is a method guide, not a fact sheet.
It deliberately contains almost no specifics about Plain — those live in
[Plain's docs](https://www.plain.com/docs), which are always current, and the skills are written to look
them up at the moment they're needed rather than recall them.

What the reference does give you: where the authoritative sources are and how to query them, the order
things depend on each other, how to handle errors and verify that a change actually landed, and the
architecture of a good triage setup — one workflow on thread creation, cheap deterministic checks before
expensive AI ones, a single multi-branch classifier, always a fallback, always tested against real
threads.

That split is deliberate. A skill that memorises an API is wrong within a release; a skill that knows
where to look stays right.

## Verify it still holds

`tests/smoke.sh` is a read-only check that the API and the documentation endpoints the skills rely on are
reachable and behaving.

```bash
PLAIN_SETUP_KEY=plainApiKey_xxx ./tests/smoke.sh
```

## Found something wrong?

APIs move. If a skill hits something that doesn't match, please
[open an issue](https://github.com/jungfreud/plain-skills/issues) with the error the API returned — that's
the most useful contribution there is.

For questions about Plain itself, see the [docs](https://www.plain.com/docs) or
[get in touch](https://www.plain.com).
