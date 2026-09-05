# Internal acceptance scenarios

Run these in a disposable Plain workspace using both Codex and Claude Code, including the minimum model
planned for customer support. Record agent/model, elapsed time, number of customer questions, created
objects, workflow/session evidence, blockers, and whether the HTML handoff accurately describes them.
Never use real customer accounts for test threads or silently enable external writes to pass a test.

| Scenario | Customer input | Observable acceptance |
| --- | --- | --- |
| Small new company | Website/docs, three common issues, founder owns support, GitHub and Sentry planned | Proposes a compact setup with a small interview; creates labels/owner/workflow and saved investigation skill; missing tools are explicit and do not produce invented findings. |
| Established team | Existing design export, several teams, 150+ existing labels/members, Linear connected | Uses export as context, inventories all pages, resolves real members, preserves unrelated configuration; no history import or duplicated existing objects. |
| Background investigation | Agreed Bug branch, connected GitHub/Sentry, engineering handoff skill | New synthetic thread follows classifier → label/priority/owner → Sidekick session with actual saved skill; sources and next action appear. Issue creation respects actual approval mode. |
| Fallback | Ambiguous thread outside known categories | Needs triage, valid owner and general Sidekick investigation; no forced confident classification. |
| Planned tool | Sentry not connected | Skill is built; session reports the unavailable check and uses other evidence. HTML names the connection and retest, without claiming “no incidents.” |
| Ari option | Routine docs questions should receive replies | Knowledge readiness, Ari assignment and selected response mode verified; other branches still route to humans/Sidekick; no competing reply automation. |
| Existing workflow | Published triage already exists | Inspects and proposes an update; no duplicate inbound classifier. Publication changes and any interruption are explained. |
| Interrupted build | Stop after labels and a child skill; resume | Reconciles current state with recorded IDs, creates only missing work, resolves actual returned skill names. No replay of successful creates. |
| API rejection | Missing scope, invalid payload, or timeout after a create | Does not report success, blindly retry writes, invent a new payload type, or publish an incomplete graph. Preserves the error/blocker in handoff. |
| No verified Sidekick payload | No matching docs example, template or existing action | Reports the action contract gap before claiming a complete build; requests a supported example/UI-created step and keeps the graph draft. Engineering must resolve this for a smooth public default. |
| Current-customer insights | Last 30 days; repeated Bug escalation work | Uses data and config evidence, suggests a specific investigation skill, can hand the chosen change to configuration in-session. No fabricated per-skill attribution or persistent memory. |

## Before official publication

Engineering should establish a supported Sidekick workflow action payload or a gallery template that
fresh workspaces can read. The GraphQL schema's string payload alone is insufficient to infer its fields.
Validate both installation routes from the destination repository, current permissions, team membership,
actual automatic Sidekick execution, fallback handling, Ari setup when selected, and representative API
failure recovery. The offline suite checks helper behavior; the smoke test checks reads. Neither proves
model-level onboarding quality or live workflow execution.
