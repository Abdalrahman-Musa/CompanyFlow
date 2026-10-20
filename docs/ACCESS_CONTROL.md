# CompanyFlow — Access Control, Secrets & Audit

**Deliverable:** "Documented, real access control separating candidate and HR-staff views." It also covers the
deployment pillar (real access control, secrets management, audit logging, error handling).

## 1. Data classification

| Class | Examples | Who may read |
|---|---|---|
| Public | open job postings (`v_public_jobs` fields), job-description RAG | everyone with an account |
| Internal | Employee Handbook (`kb_hr_policy`) | employees, HR |
| Candidate-own | the candidate's own applications, status, interview time | that candidate, HR |
| Confidential | résumés, PII, scores, breakdowns, HR notes, hire patterns, audit log | HR only |

## 2. Roles and what each can do

| Capability | candidate | employee | hr |
|---|:-:|:-:|:-:|
| Log in / register | ✓ (self-register) | ✓ (created by admin) | ✓ (created by admin) |
| `POST /cf/portal` — jobs | ✓ | ✓ | ✗ 403 |
| `POST /cf/portal` — apply, my_applications, withdraw | ✓ own only | ✗ 403 | ✗ 403 |
| `POST /cf/portal` — chat | Careers Assistant | HR Policy Assistant | ✗ 403 |
| `POST /cf/hr` — dashboard, pipeline, application, set_status, audit… | ✗ 403 | ✗ 403 | ✓ |
| `POST /cf/hr/copilot` — plan / execute / chat | ✗ 403 | ✗ 403 | ✓ (own plans only) |
| Upload HR policy (CF-02 form) | ✗ | ✗ | form login (Basic Auth credential) |

The UI hides tabs by role, but that is only a convenience. **Every rule above is enforced server-side**, so
calling the API directly with a candidate token still gets 403, as the leak test proves.

## 3. Enforcement layers (defence in depth)

1. **Authentication: signed JWT (CF-01).** Passwords are bcrypt-hashed and compared *inside Postgres*
   (`crypt()`). Unknown emails take the same time as wrong passwords (no user enumeration). 5 failures lock the
   account for 15 minutes. Tokens are HS256, `iss=companyflow`, `aud=companyflow-portal`, 4 h for candidates and
   8 h for staff. The portal keeps the token **in memory only**.
2. **Verification on every request.** Each API workflow starts with *Verify Session Token* (signature, expiry,
   pinned algorithm). Any failure goes to the error output, an `auth_rejected` audit row and a 401.
3. **Authorization (Code node "Authorize …").** An explicit role → action allow-list. The identity
   (`user_id`, `role`) comes **only from the verified token**, never from the request body or the LLM.
4. **Agent tool scoping.** Each agent gets only the tools its role needs:

   | Tool | Careers Assistant | HR Policy Assistant | HR Copilot |
   |---|:-:|:-:|:-:|
   | list_open_jobs, search_job_descriptions | ✓ | ✓ | ✓ (job_requirements_search) |
   | my_applications (identity fixed from token) | ✓ | | |
   | interview_slots (actor fixed from token) | ✓ own only | | ✓ |
   | hr_policy_search | | ✓ | ✓ |
   | rank / details / update status / screen / hire patterns | | | ✓ |

   A prompt-injected agent still cannot read data its tools cannot reach. Tool queries are fixed,
   parameterised SQL functions, never LLM-written SQL.
5. **Database rules.** Ownership and transition checks run inside SQL functions (`cf_list_slots`,
   `cf_book_slot`, `cf_set_application_status`, `cf_start_plan`). For example, a candidate can only *withdraw*
   their own application, and a plan can only be executed once and only by its author.
6. **Supabase lock-down.** RLS is enabled on every table with **no policies**, and `EXECUTE` on every `cf_*`
   function is revoked from `anon` / `authenticated` / `public`. Supabase's auto-generated REST and RPC API
   therefore exposes nothing. Only n8n's server-side Postgres connection can reach the data.
7. **Blind screening and PII minimisation.** HR sees candidate codes until shortlisting. Revealing earlier is
   logged as `pii_access`. Results returned to AI agents exclude candidate emails. Error logs scrub emails, JWTs and
   passwords. Chat memory is keyed `role:user_id:chat_id`.

## 4. Secrets management (n8n Cloud)

- All secrets live in **n8n's encrypted credential store**: Postgres password, Gemini API key, JWT signing secret,
  form Basic-Auth password and Google OAuth tokens. Exported workflow JSON contains **only credential names**, so
  the GitHub repo never holds a secret.
- The JWT secret is ≥ 32 random characters, generated once and stored only in the credential "CF JWT Signing Key".
  Rotating it invalidates all sessions immediately.
- The portal holds no API key at all, only a short-lived user token.
- The Auth workflow does **not save execution data** (it would contain passwords). In production, also set
  CF-05 to save only failed executions (they contain résumés).
- n8n project roles: only the team lead owns credentials. Other members *use* them without seeing their values.
- `.env` files and keys are never committed. `.gitignore` covers `*.env` and `credentials*.json`.

## 5. Audit logging

`audit_log` is **append-only** (UPDATE/DELETE/TRUNCATE raise an exception) and **hash-chained**: every row stores
`prev_hash` and `row_hash = SHA-256(prev_hash | id | time | actor | action | entity | outcome | details)`.
`cf_verify_audit_chain()` (the "Verify chain integrity" button) recomputes the chain and reports the first broken row.

Logged events: `login` (success/denied + reason), `register`, `auth_rejected`, `access_denied`,
`application_submitted`, **`screening_decision`** (score, band, rubric version, model, résumé hash, flags, criteria
summary, duration), `screening_failed`, `status_change` (from/to, reason, review seconds), `application_viewed`,
`pii_access`, `ranking_viewed`, `interview_booked`, `slots_listed` (denied), `plan_proposed/approved/executed`,
`copilot_chat`, `chat_turn`, `kb_document_indexed`, `kb_synced`, `workflow_error`, `retention_purge`, `baseline_logged`.

## 6. Error handling for incomplete / malformed résumé data

| Situation | Where | Result |
|---|---|---|
| No consent / no job / no résumé | CF-05 Validate Application | 400 with clear code |
| File > 5 MB | CF-05 | 413 `FILE_TOO_LARGE` |
| Word / image / other format | CF-05 | 415 `UNSUPPORTED_FORMAT` |
| Corrupt PDF | CF-05 Extract PDF (error output) | 422 `unreadable_resume` |
| Scanned PDF without text | CF-05 Merge Résumé Text | 422 `SCANNED_PDF_NO_TEXT` |
| Duplicate active application / closed job | `cf_create_application` | 409 / 410 |
| Empty, < 300 chars or garbled text | CF-03 Validate | status `needs_info`, candidate told what to fix |
| Missing sections | CF-03 | flag `MISSING_SECTIONS`, screening continues |
| Prompt injection inside résumé | CF-03 | paragraph removed, flag, "manual review required" |
| LLM failure after 3 retries | CF-03 error output | status `screening_error`, audited |
| Any unexpected workflow failure | CF-00 | PII-free audit row + team e-mail |

## 7. Verification

Run **CF-08 → Leak test**: 14 attacks plus one database check. They cover no token, tampered token, expired
token, wrong roles on every HR endpoint, prompt-injection attempts to list candidates, asking for another candidate's
score and HR note, booking an interview for another candidate, and an employee asking for candidate data. The pass
rule is the expected status **and** none of the forbidden strings (other candidates' names and emails, the HR-note
canary, password hashes) in any response. Target: **15/15 = zero leaks**.
