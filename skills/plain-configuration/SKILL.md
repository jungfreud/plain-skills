---
name: plain-configuration
description: Build or change a Plain workspace over its API, including AI labeling, team routing, workspace Sidekick skills and their invoking workflows. Use directly for a specific change, or to apply a design from plain-onboarding or plain-insights.
license: MIT
metadata:
  author: plain
  version: "0.2"
  requires: curl, jq, a terminal, and PLAIN_API_KEY
allowed-tools: Bash Read Write WebFetch
---
# Plain configuration

Turn an agreed design into verified Plain configuration. A direct request should remain focused: build
what was requested, ask only material missing questions, and leave unrelated settings alone. When called
by onboarding or insights, carry forward the user's decisions and authorization in the same conversation.

## Load the build resources

Resolve `scripts/plain-config.sh` relative to **this skill's directory**, not the user's working directory.
Set `PLAIN_CONFIG_CLI` to that absolute path and invoke it as `bash "$PLAIN_CONFIG_CLI" …`.
Read [API.md](references/API.md) before API work and [CONFIG-SPEC.md](references/CONFIG-SPEC.md) when
normalizing a design. Read [TRIAGE.md](references/TRIAGE.md) for Sidekick skills, inbound workflow design,
Ari, and end-to-end verification.

If fetched as a standalone Markdown file, first obtain the supporting bundle. Derive the base from the
URL of the SKILL.md actually loaded, retaining its owner, repository, and ref. Do not silently switch a
review branch or pinned version to main. Example for the published main version:

```bash
PLAIN_SKILL_BASE="https://raw.githubusercontent.com/jungfreud/plain-skills/main/skills/plain-configuration"
PLAIN_SKILL_DIR=$(mktemp -d "${TMPDIR:-/tmp}/plain-configuration.XXXXXX")
mkdir -p "$PLAIN_SKILL_DIR/scripts" "$PLAIN_SKILL_DIR/references"
for file in scripts/plain-config.sh references/API.md references/CONFIG-SPEC.md references/TRIAGE.md; do
  curl -fsSL --connect-timeout 10 --max-time 60 "$PLAIN_SKILL_BASE/$file" -o "$PLAIN_SKILL_DIR/$file" || exit 1
done
PLAIN_CONFIG_CLI="$PLAIN_SKILL_DIR/scripts/plain-config.sh"
```

Use the same downloaded files throughout the build. Stop if a required download fails; do not execute an
error page or reconstruct a missing helper from memory. Check `curl` and `jq` before requesting a key.

## Credentials and preflight

Use `PLAIN_API_KEY` if already available; test its presence without printing it. Default endpoint:
`https://core-api.uk.plain.com/graphql/v1`; `PLAIN_API_URL` can select the user's documented endpoint.

If a key is needed, tell the person to create a temporary key in Plain's **Settings → Machine Users**.
Derive the read/write permissions from the agreed operations using current docs/schema; if neither names
them, verify the key with `myPermissions` and report the actual missing-scope error rather than inventing
scope names. A temporary Admin key is an optional convenience, not a requirement. Read-only insight
access does not authorize changing scopes or creating a new write key without the person supplying it.

Ask the person to run this in **their own terminal**, never to paste the key into chat:

```bash
bash -c 'umask 077; read -r -s -p "Plain API key: " plain_setup_key; printf "\n"; printf "export PLAIN_API_KEY=%q\n" "$plain_setup_key" > "$HOME/.plain-setup.env"; unset plain_setup_key'
```

The input is hidden and is not a literal command in shell history. Source that protected file separately
for each agent command, e.g. `source ~/.plain-setup.env && bash "$PLAIN_CONFIG_CLI" workspace`. Never cat
it, print environment values, enable shell tracing, or place keys in scripts, reports or shell profiles.
If the agent runs remotely and cannot see the file, use its supported secret-input mechanism; do not
pretend a local export reaches it. If there is no usable terminal or credential mechanism, deliver the
configuration design and explain the specific execution blocker without accepting a secret in chat.

Run:

```bash
bash "$PLAIN_CONFIG_CLI" workspace
bash "$PLAIN_CONFIG_CLI" permissions
bash "$PLAIN_CONFIG_CLI" audit
bash "$PLAIN_CONFIG_CLI" users
bash "$PLAIN_CONFIG_CLI" teams
```

Read back the workspace name and compare it to the intended target. Resolve any mismatch before writes.
For Sidekick also read `skill list`, `integrations`, `policies`, and `workflow capabilities EVENTS`.
`integrations` reports built-in service authorizations and custom MCPs separately. Connected status is a
prerequisite, not proof that a particular repo/project/tool call succeeds.

## Plan changes against what exists

Normalize the request using the config contract; show a compact **create / reuse / update / pending**
summary, including workflow publication and future actions. Confirm unresolved choices once. An agreed
onboarding spec already authorizes its ordinary implementation; do not ask again for every object.

- Read all pages of relevant existing objects. The helper's list commands paginate; check continuation
  on any custom query as well. Never conclude a team or workflow is absent from only the first page.
- Match existing objects by recorded ID or unambiguous external ID/name. Read their actual configuration
  before reusing or changing them. Multiple matches need resolution, not an arbitrary choice.
- Check existing published workflows on the same trigger. Do not stack a second inbound classifier
  without addressing the overlap. Preserve unrelated rules and explicit customer choices.
- Resolve users by verified email/ID. **Teams are TEAM-kind label types**: use `label create --team`,
  `team add-member`, and `teams`. A named team with no available members does not prove usable routing.
- Check workflow/Sidekick payload support before promising the full build. The `TRIAGE.md` reference
  describes obtaining exact JSON from a live workflow/template when the schema does not describe it.

Keep a local, secret-free execution record with workspace ID, agreed objects, real IDs, changes, and
verification results. After an interrupted or failed request, reconcile with live state before retrying
any create: a timeout can mean the server succeeded. Resume missing work; do not replay the entire spec.
This record is for the current setup/recovery, not ongoing customer memory or background monitoring.

## Build in dependency order

Create or reuse the dependencies selected in the spec:

1. Users and teams/membership; category labels and fallback label.
2. Requested tiers, SLAs, business hours, fields, and escalation paths.
3. Knowledge sources; requested help-center/Ari settings.
4. Sidekick child skills, then the parent skill referencing the **returned invocation names**.
5. One inbound workflow: terminal investigation actions first, then assignment/priority/label actions,
   the classifier and any prefilters, then set the start step and publish the agreed graph.
6. Requested saved views, tenant data or other additional configuration.

Use the CLI for covered operations; `bash "$PLAIN_CONFIG_CLI" help` lists them without requiring a key.
It is a set of operation helpers, not a YAML-to-workspace installer. For uncovered operations, read the
current operation docs/input types, then use the `request` command with a query and variables file.
Do not mistake a field in the design contract for a supported CLI flag or API field.

```bash
bash "$PLAIN_CONFIG_CLI" label create --name Bug --icon bug
bash "$PLAIN_CONFIG_CLI" label create --name Engineering --team --icon users
bash "$PLAIN_CONFIG_CLI" team add-member --team lt_REAL_TEAM --user u_REAL_USER
bash "$PLAIN_CONFIG_CLI" skill create --display-name "Bug investigation" \
  --description "Investigate product failures with the configured engineering tools." \
  --instructions-file bug-investigation.md
bash "$PLAIN_CONFIG_CLI" skill get REAL_CUSTOM_SKILL_ID
```

Skills default to the approved investigation scope. Do not broaden workspace-wide tool policies to make
a demo look autonomous. If a selected future action needs approval, preserve that policy and make the
resulting pending action visible; change a policy only as a separately explained, authorized change.

The helper exits nonzero for transport, HTTP, GraphQL and mutation errors while preserving structured
API error details. Read the actual error and fields, correct a specific validation issue, and retry once.
If still refused, record the blocker and continue only independent work. Do not guess new payload types,
loop, or silently omit the final Sidekick step and call the workflow complete.

## Updates, publication and verification

Read back each important object, including full workflow graph and saved skill instructions. A successful
API call alone does not prove the intended behavior. Follow the test procedure in `TRIAGE.md`.

For existing Sidekick skills, `skill update` replaces the instruction body: read it first, preserve
unrelated instructions, and show the substantive change. Build referenced child skills before updating
the parent. A renamed skill can change its invocation name; use the API result and repair dependents.

For a live workflow, explain the unpublish/edit/republish window before changing it. Keep a snapshot of the
old graph. If rebuilding fails, restore only the known old configuration when safe and authorized, or
leave the workflow explicitly pending with the reason; never claim automatic rollback.

Show a concrete change for approval if it extends the agreed scope, publishes customer-facing content,
enables automatic customer replies, changes action permissions, or replaces existing settings such as
business hours. Honor authorization already given for the exact change; do not manufacture repeated gates.

## Return the outcome

Return **built/reused/updated**, with actual IDs and behavior, **verified**, with actual test evidence, and
**pending**, with the specific human task or failed build step. Distinguish configuration from an inbound
channel being connected and from Sidekick tools being available.

Onboarding renders the HTML handoff. Used directly, give a compact conversation summary unless the user
requests a report. Used by insights, return the change result so the same conversation/report can show it.
Remind the person to revoke/narrow the temporary setup key and delete its credential file when finished.
