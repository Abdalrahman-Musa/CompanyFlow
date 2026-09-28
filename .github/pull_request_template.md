## What this PR does
<!-- One or two sentences. Example: "Adds hr-leave-request: Telegram /leave → manager approval → balance update." -->

## System & department
- **Department:** <!-- HR / Finance / IT Ops / Security / Sales / Marketing / Shared -->
- **System:** <!-- e.g. hr-attendance -->
- **Workflows added or changed:**
  - `workflows/<dept>/<system>/<name>.json`

## Trigger
<!-- Form / Gmail / Telegram router / Webhook / Schedule (how often?) / Called by another workflow -->

## Sheets
| Sheet → Tab | Reads | Writes |
|---|---|---|
| CF Master Data → Employees | ✅ | |
| CF HR → Leave Requests | ✅ | ✅ |

## Shared layer used
- [ ] AI gateway (prompt_id: `____`)
- [ ] shared-notify
- [ ] shared-audit-log (one row per automated decision)
- [ ] Error handler set in workflow settings
- [ ] Not applicable (explain why):

## Conventions checklist
- [ ] Workflow name follows `<s>-<action>` in kebab-case
- [ ] Sticky-note header: purpose, trigger, inputs, outputs, owner
- [ ] Idempotency check before creating records
- [ ] IDs taken from master data (no invented employee/vendor IDs)
- [ ] Sheet IDs come from Variables (`$vars.CF_SHEET_...`), not pasted into nodes
- [ ] Human approval step if it touches money, access or published content
- [ ] Schedule triggers are OFF or at a safe interval during development

## Data contracts
- [ ] No new or changed columns
- [ ] New/changed columns — updated `docs/data-contracts.md` and `data/sheet-templates/`

## Security check
- [ ] No API keys, tokens or passwords in any node (checked Set, Code and HTTP Request nodes)
- [ ] No real emails, phone numbers, names or student IDs in the JSON or sample data

## How I tested it
<!-- Example: "Ran with pinned data for 3 cases: normal leave, leave > balance, duplicate request. All wrote correct rows and audit entries." -->

## Screenshots
<!-- Workflow canvas + a successful execution. Drag and drop images here. -->

## Notes for reviewer
<!-- Anything unfinished, known issues, or what to look at first. -->
