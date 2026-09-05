<h1 align="center">Plain skills</h1>

<p align="center">Set up and improve your <a href="https://www.plain.com">Plain</a> workspace with your coding agent.</p>

Start with your company website, docs, an existing setup export, or a few answers. Your agent proposes a
useful setup, builds it with Plain's API, and shows you what happens when a ticket arrives.

## What you get

The default setup gives you:

- **AI labels and routing:** one inbound workflow classifies tickets, applies labels and priority, and
  assigns the right team or person, with a visible fallback for anything it cannot classify.
- **Sidekick investigations:** each branch starts a Sidekick session with a skill tailored to how your
  support engineers work. For example: check related GitHub issues, look for knowledge gaps, inspect
  recent incident signals in Datadog or Sentry, and prepare an engineering handoff.
- **Your knowledge:** connect maintained docs as knowledge sources. If you want Ari to respond to routine
  questions, configure the relevant assignment and response mode as part of the setup.
- **A clear handoff:** an HTML summary of what was built and tested, and the remaining connections to
  complete in Plain's UI. Skills can be prepared for MCPs you plan to connect later.

The agent asks about your real categories, ownership, tools and desired actions. It does not require a
complete support strategy before starting. Tiers, SLAs, fields, saved views and other configuration are
available when useful, or as later changes.

Connecting an integration does not grant every action: existing Plain/Sidekick approval rules still
apply. The setup distinguishes configured, tested and live behavior, so a pending channel connection or
an issue-creation approval is visible rather than hidden behind “done.”

## The skills

| Skill | Use it for |
| --- | --- |
| [plain-onboarding](skills/plain-onboarding/SKILL.md) | A short guided setup: research your company, propose a design, and call configuration to build it. |
| [plain-configuration](skills/plain-configuration/SKILL.md) | Build or change a workspace directly, including workspace Sidekick skills and the workflows that invoke them. |
| [plain-insights](skills/plain-insights/SKILL.md) | Review a period of support activity, see evidence-backed suggestions, and optionally apply a chosen improvement in the same conversation. |

There are two kinds of skill here: these files run in **your coding agent**; the investigation routines
they create run in **Sidekick inside Plain**.

Plain's [Support Skill](https://www.plain.com/docs/agents/agent-skill) is a companion for reading customers,
threads and timelines and working with support content:

```bash
npx skills add team-plain/plain-support
```

## Get started

Use Codex, Claude Code, or another coding agent with a terminal. The command-line helper needs `curl` and
`jq`; it does not require you to know GraphQL. You can design your workspace before supplying an API key.

Install the bundle through [skills.sh](https://skills.sh):

```bash
npx skills add jungfreud/plain-skills
```

Then ask:

> Use plain-onboarding to set up my Plain workspace. Our website is https://example.com.
> Propose useful labels, team routing and a Sidekick investigation workflow.

Or paste this into your coding agent without installing first:

```text
Fetch https://raw.githubusercontent.com/jungfreud/plain-skills/main/skills/plain-onboarding/SKILL.md
with curl -fsSL and follow it. Set up my Plain workspace using my company website and a few questions.
Download supporting files as the skill instructs.
```

The skills resolve local siblings when installed. When fetched alone, they explain how to download the
configuration helper and references from the same repository and version.

For a direct change:

> Use plain-configuration. Add a Bug branch to our inbound workflow, route it to Engineering, and have
> Sidekick investigate related GitHub issues and Sentry errors before preparing a Linear issue.

For an existing workspace:

> Use plain-insights. Review the last 30 days and give me a dashboard with suggestions for better
> labeling, routing, and Sidekick investigations. Let me choose which changes to apply.

## API access

Create a temporary setup key in **Settings → Machine Users** when the agent is ready to build. The agent
will identify the permissions needed for the agreed setup. An Admin preset is an option for a temporary
key if you choose that scope; it is not required for every task. Insights needs read access until you
choose to apply a change.

**Do not paste a key into chat.** The configuration skill shows how to enter it privately in your own
terminal and make it available to the agent without printing it or saving it in your shell profile.
If a remote agent cannot see the terminal's environment or file, use that agent's supported secret input.
When setup is finished, revoke the temporary key and delete its local credential file.

MCP/integration authentication and channel connections happen in Plain's UI. Credentials for GitHub,
Datadog or Sentry do not belong in generated Sidekick instructions or the HTML report.

## Existing help desks

An export can inform the new design. These skills build labels, teams, workflows and investigation skills
in Plain; they do not run a historical-ticket migration. Handle migration separately using the relevant
[Plain importer documentation](https://www.plain.com/docs/product/integrations). Check that provider's
current coverage instead of assuming it transfers workspace configuration.

## How the build works

The configuration skill uses an explicit design, checks existing workspace state, creates dependencies
before workflows, and verifies actual results. Its CLI wraps common operations. For less common changes,
it reads the current [Plain docs](https://www.plain.com/docs/llms.txt) and schema before constructing a call.

Some workflow action payloads are JSON strings whose full shape is not described in the GraphQL schema.
For these, the skill reads a live workflow or gallery template, remaps IDs, and validates the resulting
step. It never guesses a Sidekick action payload. A missing API contract is reported as an incomplete
build step, not as a successful integration.

If a build is interrupted, the agent uses its local execution record and the live workspace to resume
only what remains. This is not an automatic transactional installer; never blindly rerun create commands.
Insights reads fresh data each time and keeps no ongoing decision memory.

## Internal review and testing

This repository is the review copy before adoption into Plain's official distribution. It does not
imply that this version has passed engineering's live-workspace tests.

Run the offline CLI checks:

```bash
python3 tests/cli_contract.py
```

With a read-capable key already supplied securely, run:

```bash
./tests/smoke.sh
```

The smoke test checks documentation reachability and API reads. It does not create configuration or
prove that the entire customer journey works. Use [the review scenarios](tests/SCENARIOS.md) to check the
full setup in a disposable workspace with Codex and Claude Code, including the minimum model you intend
to support. Live mutations and model evaluations are separate from the offline checks.

To move the distribution later, `./scripts/retarget.sh team-plain/REPOSITORY main` rewrites this bundle's
own links and install commands; it preserves links to other repositories. Review the diff before
publishing and verify installation from the final location.
