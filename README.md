# Plain skills

Agent skills that teach a coding agent how to configure a [Plain](https://www.plain.com) workspace over
Plain's GraphQL API.

Because Plain is API-first, everything about a workspace — tiers, SLAs, labels, routing, the AI agents,
the help center — is an object an agent can read and change. These skills teach an agent to do that well,
so a customer can set up or improve their workspace by talking to their own agent (Claude Code, Codex,
Cursor) instead of clicking through settings screens.

> **Status: prototype.** Every mutation in `reference/graphql-reference.md` has been executed against a
> live Plain workspace, but the skills themselves are still being iterated on. Not yet an official Plain
> product.

## Skills

| Skill | Audience | What it does |
| --- | --- | --- |
| [`plain-setup`](./plain-setup/SKILL.md) | Net-new customers | Owns the user journey. Interviews someone about how support works today, designs the workspace with them, then hands a config spec to `plain-configuration` to build it. Ends with a live Sidekick demo and a handoff report. |
| [`plain-configuration`](./plain-configuration/SKILL.md) | Called by other skills | The executor. Takes a config spec, applies it over the GraphQL API in the right dependency order, verifies each result, and reports what was built plus what needs a human click. |

Planned: `plain-tune` (change an existing workspace by intent) and `plain-insights` (analyse CSAT,
response and resolution times, then recommend fixes as prompts that call `plain-configuration`).

The split matters: the journey skill owns the conversation, the configuration skill owns the API. That
keeps the conversation uncluttered and makes the executor reusable by every future skill.

## Reference

[`reference/graphql-reference.md`](./reference/graphql-reference.md) is a cleansed, **verified** guide to
the ~30 mutations that matter for workspace setup, out of ~440 in the schema. It documents the exact input
shapes plus the traps that fail silently — for example:

- SLA first-response and next-response times are mutually exclusive (undocumented; needs two records)
- `assign_to_user` with a machine-user id returns `SUCCESS` and assigns nobody
- `inviteUserToWorkspace` is forbidden to machine users entirely, so invites can't be automated
- Workflow actions don't cascade into other workflows, which breaks the intuitive "triage labels → routing
  reacts to label" design
- `DateTime` is an object, not a scalar; label icons are slugs, not emoji

It also covers the recommended triage architecture: one workflow on thread creation, deterministic
conditions first, then a single `else_if` switch of AI prompt conditions (an N-way switch that
short-circuits on first match), with each branch chaining its own label → priority → assignment actions.

## Use it

**Zero install** — paste into any agent with a shell:

```
Run curl -s https://raw.githubusercontent.com/jungfreud/plain-skills/main/plain-setup/SKILL.md
and follow exactly what it outputs. I don't have a Plain account yet — walk me through creating one,
then set up my workspace.
```

A `curl` command rather than "read this URL" is deliberate: not every agent exposes a web-fetch tool, but
essentially all of them can run a shell command.

**Or install as skills** (via [skills.sh](https://www.skills.sh)):

```
npx skills add jungfreud/plain-skills
```

## What you need

A Plain workspace and an API key from **Settings → Machine Users → Add API key**. The Admin preset is the
simplest for a one-time setup key; the precise scope list is in the reference.

Hand the key to your agent as an environment variable rather than pasting it into the chat:

```bash
echo 'export PLAIN_SETUP_KEY="plainApiKey_xxx"' >> ~/.zshrc && source ~/.zshrc
```

Then tell the agent it's set. The skills reference `$PLAIN_SETUP_KEY` and never read or print its value.
Delete the machine user or narrow the key when you're done — it can create tiers and publish public help
center content.

## Testing

`tests/smoke.sh` runs a read-only check that the API still matches what the reference documents. Run it
against a **throwaway workspace**, not production.

```bash
PLAIN_SETUP_KEY=plainApiKey_xxx ./tests/smoke.sh
```

## Contributing

The reference encodes real API behaviour and will rot silently if Plain's API changes and nobody re-runs
the verification. If you hit something that doesn't match, please open an issue or a PR with the actual
error the API returned.
