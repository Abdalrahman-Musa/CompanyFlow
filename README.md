# CompanyFlow

**A complete automated company system built entirely on [n8n](https://n8n.io).**

CompanyFlow automates six departments of a company — HR, Accounting & Finance, IT Operations, Cybersecurity, Sales & CRM and Marketing — as twelve independent n8n systems that share one master data layer and one set of conventions.

> DEPI (Digital Egypt Pioneers Initiative) — AI & Automation track — Graduation Project, 2026.

![n8n](https://img.shields.io/badge/built%20with-n8n-EA4B71)
![AI](https://img.shields.io/badge/AI-LLM%20assisted-8A2BE2)
![Google Workspace](https://img.shields.io/badge/data-Google%20Sheets-34A853)
![License](https://img.shields.io/badge/license-MIT-green)

---

## Table of Contents

- [Overview](#overview)
- [Team & Ownership](#team--ownership)
- [The Twelve Systems](#the-twelve-systems)
  - [HR](#hr)
  - [Accounting & Finance](#accounting--finance)
  - [IT Operations](#it-operations)
  - [Cybersecurity](#cybersecurity)
  - [Sales & CRM](#sales--crm)
  - [Marketing](#marketing)
- [Architecture](#architecture)
- [Optional Cross-System Integrations](#optional-cross-system-integrations)
- [Tech Stack](#tech-stack)
- [Repository Structure](#repository-structure)
- [Getting Started](#getting-started)
- [Workflow Conventions](#workflow-conventions)
- [Demo Scenarios](#demo-scenarios)
- [Roadmap](#roadmap)
- [Contributing](#contributing)
- [License](#license)

---

## Overview

Small and medium companies run on disconnected tools: a spreadsheet for leave, an inbox for invoices, a chat group for IT problems, and nothing at all watching for security issues. Work falls into the gaps between them.

CompanyFlow replaces that with twelve automated systems, two per department, each built as a set of n8n workflows. Every system works standalone — it has its own triggers, its own data and its own approvals — but all twelve follow the same naming, logging and master-data rules, so they can be connected without rewriting anything.

**Design principles**

- **Standalone first** — each system is complete on its own. Cross-system links are additions, never dependencies.
- **AI where rules fail** — LLMs handle CV screening, invoice extraction, ticket classification, alert triage and content generation instead of brittle keyword rules.
- **Human-in-the-loop** — anything touching money, access or published content stops for an approval step.
- **Shared master data** — one Employees sheet and one Vendors sheet, so an employee ID means the same thing in every system.
- **Auditable** — every automated decision writes a row with its inputs, its output and the workflow that produced it.

---

## Team & Ownership

Six members, one department each, both options built.

| Member | Role | Department | Systems | GitHub |
|---|---|---|---|---|
| Abdalrahman Atef | Leader | Cybersecurity | `sec-triage`, `sec-vuln` | [@Abdalrahman-Musa](https://github.com/Abdalrahman-Musa) |
| Mahmoud Ashraf Abdulhamid | Member | HR | `hr-lifecycle`, `hr-attendance` | [@mashraf-codingzone](https://github.com/mashraf-codingzone) |
| Khaled Mohamed Nsr | Member | Accounting & Finance | `fin-invoices`, `fin-expenses` | [@k01581012-blip](https://github.com/k01581012-blip) |
| Maged Mohammed Abdalkader | Member | IT Operations | `it-helpdesk`, `it-monitoring` | [@MagedZaky](https://github.com/MagedZaky) |
| Ahmed Kolaib | Member | Sales & CRM | `crm-leads`, `crm-quotes` | [@ahmedkolaib817-stack](https://github.com/ahmedkolaib817-stack) |
| Abdelftah Ibrahim Abdelfrah Emam | Member | Marketing | `mkt-content`, `mkt-campaigns` | [@AbdelftahX](https://github.com/AbdelftahX) |

The team leader additionally owns planning, milestones, overall architecture, the workflow contracts and final integration.

---

## The Twelve Systems

### HR

#### `hr-lifecycle` — Employee Lifecycle Hub
Covers hiring through exit: application intake, AI CV parsing and scoring, interview scheduling, offer letters, onboarding checklists and an offboarding flow.

- **Tools:** n8n Form, Gmail, Google Drive, LLM, Google Calendar, Google Sheets
- **Flow:** application intake → CV parsing → scoring → interview scheduling → offer/reject → onboarding tasks → offboarding

#### `hr-attendance` — Attendance, Leave & Payroll Prep
Check-in/out via bot, leave requests with manager approval and balance tracking, overtime and absence calculation, and a monthly payroll input sheet.

- **Tools:** Telegram, Google Sheets, Google Calendar, Gmail
- **Flow:** daily attendance log → leave request + approval → balance update → late/absence alerts → monthly payroll export

### Accounting & Finance

#### `fin-invoices` — Invoice & Payables Automation
Pulls supplier invoices from email, extracts data with a vision LLM, matches them to purchase orders, routes for approval by amount and tracks due dates.

- **Tools:** Gmail, Vision LLM, Google Drive, Google Sheets, Telegram
- **Flow:** invoice capture → data extraction → PO matching → approval by threshold → payment reminders → duplicate detection

#### `fin-expenses` — Expense Claims & Budget Control
Employees submit expenses with receipt photos, AI extracts and categorises them, policy rules auto-approve or flag, and department budgets are tracked with alerts.

- **Tools:** Telegram / n8n Form, Vision LLM, Google Sheets, Gmail, QuickChart
- **Flow:** claim submission → receipt OCR → policy check → approval → reimbursement log → budget dashboard and overspend alerts

### IT Operations

#### `it-helpdesk` — IT Helpdesk & Asset Management
Multi-channel ticket intake, AI classification and priority, auto-assignment to technicians, SLA timers, plus hardware and license inventory with renewal alerts.

- **Tools:** Gmail, Telegram, LLM, Google Sheets, Google Calendar
- **Flow:** ticket intake → triage → assignment → SLA monitoring → resolution + CSAT → asset register → renewal reminders

#### `it-monitoring` — Infrastructure Monitoring & Incident Response
Monitors servers, sites and services, detects downtime and slow responses, watches SSL and domain expiry, opens incidents, pages on-call staff and publishes a status page.

- **Tools:** HTTP Request, SSL/WHOIS checks, Google Sheets or Postgres, Slack/Telegram, LLM
- **Flow:** scheduled checks → failure confirmation with retries → incident creation → escalation → status page update → uptime report

### Cybersecurity

#### `sec-triage` — Security Alert Triage (mini SOC)
Ingests alerts from monitoring sources, enriches indicators with threat intelligence, AI summarises and scores severity, deduplicates and opens cases with on-call notification.

- **Tools:** Webhooks, VirusTotal / AbuseIPDB, LLM, Google Sheets or Jira, Telegram
- **Flow:** alert ingestion → normalisation + dedup → enrichment → AI triage and severity → case creation → escalation → daily digest

#### `sec-vuln` — Vulnerability & Compliance Tracker
Maintains a software and asset inventory, matches it daily against vulnerability feeds, prioritises by exploitability and asset criticality, and tracks patching to closure.

- **Tools:** Google Sheets or Postgres, NVD API, CISA KEV feed, LLM, Gmail
- **Flow:** inventory intake → daily feed pull → CVE matching → risk scoring → remediation tickets → overdue reminders → risk report

### Sales & CRM

#### `crm-leads` — Lead Capture & Pipeline Automation
Collects leads from forms, email and chat, deduplicates and enriches them, scores them with AI, assigns to reps by territory or load, and nudges on stale deals.

- **Tools:** n8n Form, Gmail, LLM, Google Sheets or HubSpot free tier, Telegram
- **Flow:** multi-source lead capture → dedup + enrichment → AI scoring → assignment → follow-up sequence → stale-deal alerts → pipeline dashboard

#### `crm-quotes` — Quotation & Contract Automation
Turns a quote request into a priced PDF quote with approval for discounts, sends it, tracks acceptance, and converts an accepted quote into an order with renewal reminders.

- **Tools:** n8n Form, Google Sheets (price list), Google Docs → PDF, Gmail, LLM
- **Flow:** quote request → pricing engine → discount approval → PDF generation and send → follow-up → acceptance → order handoff → renewal alerts

### Marketing

#### `mkt-content` — Content Production & Publishing Pipeline
Takes a brief or a long source (video, article), generates platform-specific posts and visuals, routes them for approval, then schedules, publishes and tracks engagement.

- **Tools:** LLM, image generation API, Google Sheets, Telegram, LinkedIn/X API or mock publisher
- **Flow:** brief/source intake → content generation per platform → visual generation → approval → scheduling and publishing → engagement tracking → weekly report

#### `mkt-campaigns` — Campaign & Email Marketing Automation
Manages subscriber lists and segments, runs behaviour-triggered drip campaigns, does A/B subject testing, and reports open and click performance.

- **Tools:** Gmail/SMTP, Google Sheets, LLM, tracking pixel or link-redirect webhook
- **Flow:** subscriber intake and segmentation → campaign builder → drip sequence with triggers → A/B split → open/click tracking → unsubscribe handling → analytics

---

## Architecture

```mermaid
flowchart TD
    subgraph Entry["Entry Points"]
        A1[n8n Forms]
        A2[Gmail Inboxes]
        A3[Telegram Bot]
        A4[Schedule Triggers]
        A5[Webhooks]
    end

    subgraph Shared["Shared Layer"]
        B1[(Master Data<br/>Employees · Vendors · Assets)]
        B2[AI Gateway<br/>prompts · model · retries]
        B3[Notification Sub-workflow<br/>email · Telegram]
        B4[Audit Log]
        B5[Error Handler Workflow]
    end

    subgraph Systems["Department Systems"]
        C1[HR<br/>lifecycle · attendance]
        C2[Finance<br/>invoices · expenses]
        C3[IT Ops<br/>helpdesk · monitoring]
        C4[Security<br/>triage · vulnerabilities]
        C5[Sales<br/>leads · quotes]
        C6[Marketing<br/>content · campaigns]
    end

    subgraph Out["Outputs"]
        D1[Dashboards]
        D2[Scheduled Reports]
        D3[PDF Documents]
    end

    Entry --> Systems
    Systems <--> B1
    Systems --> B2
    Systems --> B3
    Systems --> B4
    Systems -.on failure.-> B5
    B1 --> Out
    B4 --> Out
```

**The shared layer is the contract between the six members.** Each person builds their own department freely, as long as they:

1. Read and write people, vendors and assets through the **master data** sheets, never their own private copy.
2. Call the **AI gateway** sub-workflow instead of hitting an LLM API directly — this keeps prompts, model choice and retries in one place.
3. Send every message through the **notification** sub-workflow instead of wiring Gmail or Telegram nodes into each workflow.
4. Write one row to the **audit log** for every automated decision.
5. Set the **error handler** workflow in their workflow settings.

### Master data

| Sheet | Key | Owned by | Read by |
|---|---|---|---|
| `Employees` | `EMP-####` | HR | Finance, IT Ops, Security, Marketing |
| `Vendors` | `VEN-####` | Finance | Sales, IT Ops |
| `Assets` | `AST-####` | IT Ops | Security |
| `Audit Log` | auto | everyone | reporting |

---

## Optional Cross-System Integrations

Every system runs standalone. These links are optional and are only built if both sides are ready — they are the last milestone, not a prerequisite.

| Link | What it does | Owners | Status |
|---|---|---|---|
| HR → IT Operations | A new hire triggers account creation and asset assignment | HR + IT Ops | Planned |
| HR → Accounting | Approved leave and attendance feed the payroll input sheet | HR + Finance | Planned |
| IT Operations → Cybersecurity | The asset inventory becomes the input for the vulnerability tracker | IT Ops + Security | Planned |
| All systems → Master data | One shared Employees and Vendors sheet so IDs match everywhere | Leader | Committed |

> Two integrations from the original planning sheet — Procurement → Accounting and Sales → Inventory — are out of scope, since neither Procurement nor Inventory is one of the six selected departments.

---

## Tech Stack

| Layer | Technology |
|---|---|
| Automation engine | n8n Cloud — one shared instance, one project per member |
| Data store | Google Sheets (master data + per-system tables); Postgres optional for IT Ops and Security |
| AI | LLM via the AI gateway sub-workflow; vision LLM for invoice and receipt extraction |
| Messaging | Gmail / SMTP, Telegram bot, Slack (IT Ops alerts) |
| Documents | Google Docs → PDF, QuickChart for charts |
| External APIs | VirusTotal, AbuseIPDB, NVD, CISA KEV, WHOIS/SSL checks |
| Version control | Git — workflows exported as JSON |

---

## Repository Structure

```
CompanyFlow/
├── workflows/
│   ├── shared/              # AI gateway, notifications, audit log, error handler
│   ├── hr/                  # hr-lifecycle, hr-attendance
│   ├── finance/             # fin-invoices, fin-expenses
│   ├── it-ops/              # it-helpdesk, it-monitoring
│   ├── security/            # sec-triage, sec-vuln
│   ├── sales/               # crm-leads, crm-quotes
│   └── marketing/           # mkt-content, mkt-campaigns
├── data/
│   ├── sheet-templates/     # column headers for master data and per-system sheets
│   └── sample-data/         # demo rows for the presentation
├── prompts/                 # LLM prompt templates used by the AI gateway
├── docs/
│   ├── architecture.md
│   ├── data-contracts.md    # every shared sheet: columns, types, owner
│   ├── setup-guide.md
│   └── screenshots/
└── README.md
```

---

## Getting Started

### Prerequisites

- An **n8n Cloud** account, and membership of the team's shared workspace (see below)
- A Google account with Sheets, Drive, Gmail and Calendar access
- A Telegram bot token ([@BotFather](https://t.me/BotFather))
- An LLM API key (text + vision)

### How the workspace is organised

All six members work inside **one shared n8n Cloud instance**, each owning their own credentials and their own workflows:

| Space | Contents | Who can see it |
|---|---|---|
| `CompanyFlow — Shared` project | The `shared/` sub-workflows and the master-data credential | All six members |
| One project per department | That department's two systems and its own credentials | Its owner (+ leader) |

The team leader is the instance owner, invites the other five members, and creates the projects. Everyone builds in their own project; nobody edits another department's workflows.

Two limits worth knowing before you set this up:

- **Sharing and projects are Pro-plan features.** Workflow sharing between users of the same instance is available on Pro and Enterprise Cloud plans. On a Starter plan there is no multi-user sharing, so the team would be working in six separate instances instead of one.
- **Six separate accounts are six separate instances.** *Execute Workflow* only calls sub-workflows inside the same instance, so the shared AI-gateway and notification sub-workflows only work if everyone is a member of **one** workspace. If the team ends up on separate instances, each system has to call the shared logic over a webhook instead, and every member needs their own copy of it.

### 1. Clone the repo

```bash
git clone https://github.com/<org-or-user>/CompanyFlow.git
cd CompanyFlow
```

The repo holds the workflow JSON, the sheet templates and the prompts. The workflows themselves run in n8n Cloud — nothing here needs to be installed or served.

### 2. Set the workspace timezone

In n8n Cloud, open *Settings → Workflow settings* and set the default timezone to **Africa/Cairo**, so Schedule triggers fire at local time. Setting it once at workspace level saves overriding it per workflow.

### 3. Create the Google Sheets

Copy the templates in `data/sheet-templates/` into Drive, keeping the column headers exactly as they are — workflows reference columns by name.

Then record each sheet's ID where the workflows can read it:

- **Pro plan and above:** n8n Variables (*Settings → Variables*), using the names listed in `docs/setup-guide.md`.
- **Starter plan:** Variables are not available, so use the `shared-config` sub-workflow, which returns all sheet IDs from a single Set node. Call it instead of pasting IDs into individual nodes — one place to change when a sheet is replaced.

### 4. Create your own credentials

Each member creates their **own** credentials in their own project — your Google account, your Telegram bot, your API keys. Nobody shares secret values.

Name them `CF <Service> — <Dept>` so they stay distinguishable in the shared instance:

| Credential name | Type | Needed by |
|---|---|---|
| `CF Google Sheets — <Dept>` | Google Sheets OAuth2 | all |
| `CF Gmail — <Dept>` | Gmail OAuth2 | HR, Finance, IT Ops, Sales, Marketing |
| `CF Google Drive — <Dept>` | Google Drive OAuth2 | HR, Finance |
| `CF Google Calendar — <Dept>` | Google Calendar OAuth2 | HR, IT Ops |
| `CF Telegram — <Dept>` | Telegram | all |
| `CF LLM — <Dept>` | HTTP Header Auth | all |
| `CF Threat Intel — Security` | HTTP Header Auth | Security |

Two exceptions, both owned by the leader and shared into the `CompanyFlow — Shared` project:

- the credential that writes to the **master data** sheets, so employee and vendor IDs have one writer;
- the credential used by the shared **AI gateway**, so token usage is visible in one place.

When you import a workflow someone else exported, the credential references won't resolve — open each red-flagged node and pick your own credential. This is expected, not a broken export.

> Sharing a *workflow* also lets the editor use every credential inside it, even ones never explicitly shared. Keep personal API keys in your own project rather than the shared one.

### 5. Import the workflows

n8n Cloud has no CLI, so import through the editor: **Workflows → Add workflow → ⋮ menu → Import from File**, then pick the JSON from the matching folder under `workflows/`.

Import and activate the `shared/` workflows first — every department workflow calls them, and an *Execute Workflow* node pointing at a missing sub-workflow fails silently at runtime.

---

## Workflow Conventions

These rules are what keep six people's work mergeable:

- **Naming** — `<system>-<action>` in kebab-case: `hr-leave-request`, `sec-alert-ingest`, `fin-invoice-capture`.
- **Sticky note header** — every workflow opens with a note stating purpose, trigger, inputs, outputs and owner.
- **Sub-workflows** — shared logic lives in `workflows/shared/` and is called with *Execute Workflow*. No system duplicates AI or notification logic.
- **Idempotency** — check for an existing record before creating one. Triggers fire twice more often than you expect.
- **IDs** — never invent your own employee or vendor identifiers; take them from master data.
- **Secrets** — no API keys, tokens, real emails or personal data inside nodes. Credentials and variables only.
- **Export before you commit** — the JSON in `workflows/` is the source of truth, not what is sitting in the Cloud workspace. Export with **⋮ → Download** in the workflow editor, then save the file into your department folder under its `<system>-<action>.json` name.
- **One instance, six members** — you each own your own project, credentials and workflows, but you share one live instance. Build only inside your own project. Deactivate a workflow before a big rebuild so half-finished logic doesn't fire on a schedule, and never rename, move or delete anything in the shared project without telling the team — moving a workflow or credential between projects silently drops its existing sharing.

---

## Demo Scenarios

Scripted end-to-end runs for the project defense:

1. **Hire to first day** — a CV arrives, AI scores it, an interview is scheduled, an offer goes out, onboarding tasks are created, and IT provisions accounts and an asset.
2. **Invoice to payment** — a supplier invoice lands in Gmail, the vision LLM extracts it, PO matching runs, approval is requested by amount, and payment reminders schedule themselves.
3. **Alert to incident** — a security alert hits the webhook, indicators are enriched, AI scores severity, a case is opened and the on-call is paged.
4. **Vulnerability to patch** — the daily feed pull matches a KEV entry to a live asset, risk scoring runs, and a remediation ticket is tracked to closure.
5. **Lead to order** — a web lead is scored and assigned, a quote PDF is generated and sent, acceptance converts it to an order.
6. **Brief to published post** — one content brief becomes platform-specific posts and visuals, gets approved, publishes on schedule and reports its engagement.

---

## Roadmap

- [x] Department selection and ownership
- [x] Architecture, data contracts and workflow conventions
- [ ] Shared layer: AI gateway, notifications, audit log, error handler
- [ ] Six department systems, both options each
- [ ] Sample data and dashboards
- [ ] Optional cross-system integrations
- [ ] Demo run-through and presentation
- [ ] Arabic support in AI responses and notifications

---

## Contributing

1. Branch per system: `feature/sec-triage`.
2. Build and test in your own n8n instance.
3. Export to your department folder under `workflows/`.
4. Update `docs/data-contracts.md` if you added or changed a shared column.
5. Open a pull request describing the behaviour, the sheets it reads and the sheets it writes.

**Do not commit:** API keys or tokens, real customer or employee data, personal phone numbers, emails or student IDs. Exported workflow JSON contains credential *names* only, not their values — but check any Set or Code node you added before pushing.

---

## License

Released under the MIT License. See [LICENSE](LICENSE). Copyright held jointly by the CompanyFlow team members listed above.

---

## Acknowledgments

Built as the graduation project for the **Digital Egypt Pioneers Initiative (DEPI)** — AI & Automation track — under the Ministry of Communications and Information Technology.
