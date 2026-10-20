-- =====================================================================
--  CompanyFlow — HR & Recruitment Screening Assistant
--  File 1 of 3 : database/01_schema.sql
--  Run FIRST in Supabase → SQL Editor → New query → paste → Run.
--  Safe to re-run (uses IF NOT EXISTS / CREATE OR REPLACE).
--
--  Convention: every function n8n calls has the signature
--      public.cf_<name>(p jsonb) returns jsonb
--  n8n always calls:  select public.cf_<name>($1::jsonb) as result
--  with Query Parameters = {{ [ JSON.stringify({...}) ] }}
--  (one JSON parameter → commas inside résumé text can never split it)
-- =====================================================================

create schema if not exists extensions;
create extension if not exists pgcrypto    with schema extensions;  -- bcrypt for passwords
create extension if not exists "uuid-ossp" with schema extensions;  -- used by LangChain PGVector
create extension if not exists vector      with schema extensions;  -- pgvector for RAG

set search_path = "$user", public, extensions;   -- this session (the rest of this script)

-- make sure every new session (n8n's pooled connections included) can resolve the
-- pgvector type/operators and pgcrypto functions that live in the "extensions" schema
do $$
begin
  execute format('alter database %I set search_path = "$user", public, extensions', current_database());
exception when others then
  raise notice 'search_path not changed (%), Supabase already includes extensions by default', sqlerrm;
end $$;

-- ---------------------------------------------------------------------
-- 0. Small helpers
-- ---------------------------------------------------------------------
create or replace function public.cf_try_uuid(t text) returns uuid
language plpgsql immutable as $$
begin
  return t::uuid;
exception when others then
  return null;
end $$;

create or replace function public.cf_try_bigint(t text) returns bigint
language plpgsql immutable as $$
begin
  return t::bigint;
exception when others then
  return null;
end $$;

create or replace function public.cf_app_code(id bigint) returns text
language sql immutable as $$ select 'APP-' || lpad(id::text, 5, '0') $$;

create or replace function public.cf_cand_code(id bigint) returns text
language sql immutable as $$ select 'CAND-' || lpad(id::text, 4, '0') $$;

create or replace function public.cf_cairo(ts timestamptz) returns text
language sql stable as $$
  select to_char(ts at time zone 'Africa/Cairo', 'Dy DD Mon YYYY, HH24:MI') || ' (Cairo)'
$$;

-- ---------------------------------------------------------------------
-- 1. Users (login identities) — roles: candidate | employee | hr
-- ---------------------------------------------------------------------
create table if not exists public.app_users (
  id             uuid primary key default gen_random_uuid(),
  email          text not null unique check (email = lower(email)),
  full_name      text not null,
  role           text not null check (role in ('candidate','employee','hr')),
  password_hash  text not null,                      -- bcrypt via pgcrypto crypt()
  department     text,
  is_active      boolean not null default true,
  is_test        boolean not null default false,
  failed_logins  int not null default 0,
  locked_until   timestamptz,
  last_login_at  timestamptz,
  created_at     timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 2. Jobs — structured requirements are the source of truth for scoring
--    must_have_skills / nice_to_have_skills / preferred_certifications:
--      [ {"label": "SIEM monitoring", "aliases": ["siem","splunk",...]} ]
--    language_requirements: [ {"language":"english","min_level":"professional"} ]
--    education_requirement: {"min_level":"bachelor","fields":[...],"required":false}
--    NOTE: there is deliberately NO max_years column (over-experience is never
--    penalised — it is an age proxy).
-- ---------------------------------------------------------------------
create table if not exists public.jobs (
  id                      text primary key,             -- e.g. SOC-L1
  title                   text not null,
  department              text not null,
  role_family             text not null,                -- e.g. security_operations
  seniority               text not null check (seniority in ('intern','junior','mid','senior','lead')),
  location                text not null default 'Cairo, Egypt (Hybrid)',
  employment_type         text not null default 'Full-time',
  status                  text not null default 'open' check (status in ('open','paused','closed')),
  openings                int  not null default 1,
  summary                 text not null,
  description             text not null,                -- full JD (embedded for RAG)
  distinguishing_notes    text,                         -- how this role differs from look-alike roles
  must_have_skills        jsonb not null default '[]',
  nice_to_have_skills     jsonb not null default '[]',
  preferred_certifications jsonb not null default '[]',
  language_requirements   jsonb not null default '[]',
  education_requirement   jsonb not null default '{}',
  experience_keywords     jsonb not null default '[]',  -- titles/domains that count as relevant experience
  min_years               numeric not null default 0,
  opened_at               timestamptz not null default now(),
  closed_at               timestamptz,
  created_at              timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 3. Candidates (PII lives here and in applications.resume_text only)
-- ---------------------------------------------------------------------
create table if not exists public.candidates (
  id                   bigserial primary key,
  user_id              uuid unique references public.app_users(id) on delete cascade,
  full_name            text not null,
  email                text,
  phone                text,
  consent_given_at     timestamptz,
  consent_version      text,
  interaction_count    int not null default 0,
  last_interaction_at  timestamptz,
  is_test              boolean not null default false,
  is_demo              boolean not null default false,
  erased_at            timestamptz,
  created_at           timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 4. Applications (one candidate × one job) + stage timestamps
-- ---------------------------------------------------------------------
create table if not exists public.applications (
  id                      bigserial primary key,
  candidate_id            bigint not null references public.candidates(id) on delete cascade,
  job_id                  text   not null references public.jobs(id),
  status                  text   not null default 'applied' check (status in (
                            'applied','screening','screened','needs_info','screening_error',
                            'shortlisted','interview_scheduled','interviewed','offer',
                            'hired','rejected','withdrawn')),
  source                  text not null default 'portal',
  resume_text             text,
  resume_format           text,          -- pdf | text | paste
  resume_file_name        text,
  resume_chars            int,
  latest_score            numeric(5,1),
  latest_band             text,
  screening_error_code    text,
  screening_issues        jsonb,
  hr_notes                text,
  applied_at              timestamptz not null default now(),
  screened_at             timestamptz,
  shortlisted_at          timestamptz,
  interview_scheduled_at  timestamptz,
  interviewed_at          timestamptz,
  offer_at                timestamptz,
  hired_at                timestamptz,
  rejected_at             timestamptz,
  withdrawn_at            timestamptz,
  status_updated_at       timestamptz not null default now(),
  is_test                 boolean not null default false,
  is_demo                 boolean not null default false
);
create unique index if not exists ux_one_active_application
  on public.applications(candidate_id, job_id)
  where status not in ('rejected','withdrawn');
create index if not exists ix_app_job_status on public.applications(job_id, status);

-- ---------------------------------------------------------------------
-- 5. Application events = the candidate's status memory across interactions
-- ---------------------------------------------------------------------
create table if not exists public.application_events (
  id              bigserial primary key,
  application_id  bigint not null references public.applications(id) on delete cascade,
  from_status     text,
  to_status       text not null,
  actor_id        uuid,
  actor_role      text,
  reason          text,
  review_seconds  int,                     -- HR time spent before deciding (efficiency metric)
  at              timestamptz not null default now()
);
create index if not exists ix_events_app on public.application_events(application_id, at);

-- ---------------------------------------------------------------------
-- 6. Screening results (explainable, one row per screening run)
-- ---------------------------------------------------------------------
create table if not exists public.screening_results (
  id               bigserial primary key,
  application_id   bigint not null references public.applications(id) on delete cascade,
  job_id           text not null references public.jobs(id),
  score            numeric(5,1) not null,
  band             text not null,
  recommendation   text,
  breakdown        jsonb not null default '{}',   -- per-criterion points, evidence, missing items
  explanation      text,
  profile          jsonb,                         -- redacted structured profile used for scoring
  flags            jsonb not null default '[]',
  alternatives     jsonb not null default '[]',   -- other open roles that fit
  redactions       jsonb,
  redacted_resume  text,
  rubric_version   text,
  model            text,
  resume_hash      text,
  from_cache       boolean not null default false,
  duration_ms      int,
  is_demo          boolean not null default false,
  created_at       timestamptz not null default now()
);
create index if not exists ix_screen_app on public.screening_results(application_id, created_at desc);

create table if not exists public.resume_profile_cache (
  resume_hash  text primary key,
  profile      jsonb not null,
  model        text,
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 7. Past successful hire PATTERNS (sample, anonymised — no demographic fields)
-- ---------------------------------------------------------------------
create table if not exists public.hire_patterns (
  id               text primary key,           -- HP-001
  role_family      text not null,
  job_id_hint      text,
  seniority        text,
  pattern_summary  text not null,
  key_skills       jsonb not null default '[]',
  typical_years    numeric,
  success_signals  jsonb not null default '[]',
  hired_year       int
);

-- ---------------------------------------------------------------------
-- 8. Interview slots & interviews
-- ---------------------------------------------------------------------
create table if not exists public.interview_slots (
  id                     bigserial primary key,
  job_id                 text references public.jobs(id),   -- null = any job
  interviewer_name       text not null,
  interviewer_email      text not null,
  starts_at              timestamptz not null,
  ends_at                timestamptz not null,
  mode                   text not null default 'online' check (mode in ('online','onsite')),
  location               text,
  status                 text not null default 'open' check (status in ('open','booked','cancelled')),
  booked_application_id  bigint references public.applications(id),
  created_at             timestamptz not null default now(),
  unique (interviewer_email, starts_at)
);

create table if not exists public.interviews (
  id                 bigserial primary key,
  application_id     bigint not null references public.applications(id) on delete cascade,
  slot_id            bigint unique references public.interview_slots(id),
  starts_at          timestamptz not null,
  ends_at            timestamptz not null,
  mode               text not null,
  location           text,
  interviewer_name   text,
  interviewer_email  text,
  calendar_event_id  text,
  meet_link          text,
  status             text not null default 'scheduled' check (status in ('scheduled','completed','cancelled','no_show')),
  created_at         timestamptz not null default now()
);

-- ---------------------------------------------------------------------
-- 9. HR Copilot plans (agent planning, human-in-the-loop)
-- ---------------------------------------------------------------------
create table if not exists public.agent_plans (
  id           bigserial primary key,
  created_by   uuid not null,
  request      text not null,
  plan         jsonb not null,
  status       text not null default 'proposed' check (status in ('proposed','executing','completed','failed','cancelled')),
  result       text,
  created_at   timestamptz not null default now(),
  executed_at  timestamptz,
  finished_at  timestamptz
);

-- ---------------------------------------------------------------------
-- 10. AUDIT LOG — append-only + SHA-256 hash chain (tamper-evident)
-- ---------------------------------------------------------------------
create sequence if not exists public.audit_log_id_seq;
create table if not exists public.audit_log (
  id            bigint primary key,            -- assigned by trigger AFTER the chain lock
  at            timestamptz not null default clock_timestamp(),
  actor_id      uuid,
  actor_role    text,
  action        text not null,
  entity_type   text,
  entity_id     text,
  outcome       text not null default 'success' check (outcome in ('success','denied','error','info')),
  details       jsonb not null default '{}',
  workflow      text,
  execution_id  text,
  prev_hash     text,
  row_hash      text
);
create index if not exists ix_audit_action on public.audit_log(action, at desc);
create index if not exists ix_audit_entity on public.audit_log(entity_type, entity_id);

create or replace function public.cf_audit_hash(
  p_prev text, p_id bigint, p_at timestamptz, p_actor uuid, p_role text, p_action text,
  p_etype text, p_eid text, p_outcome text, p_details jsonb)
returns text language sql stable set search_path = public, extensions as $$
  select encode(sha256(convert_to(
           coalesce(p_prev,'GENESIS') || '|' || p_id || '|' ||
           to_char(p_at at time zone 'UTC', 'YYYY-MM-DD"T"HH24:MI:SS.US') || '|' ||
           coalesce(p_actor::text,'') || '|' || coalesce(p_role,'') || '|' || p_action || '|' ||
           coalesce(p_etype,'') || '|' || coalesce(p_eid,'') || '|' || p_outcome || '|' ||
           coalesce(p_details::text,'{}'), 'UTF8')), 'hex')
$$;

create or replace function public.cf_audit_chain_trg() returns trigger
language plpgsql set search_path = public, extensions as $$
declare v_prev text;
begin
  perform pg_advisory_xact_lock(424242);                  -- serialise writers → linear chain
  new.id  := nextval('public.audit_log_id_seq');
  new.at  := clock_timestamp();
  select row_hash into v_prev from public.audit_log order by id desc limit 1;
  new.prev_hash := coalesce(v_prev, 'GENESIS');
  new.row_hash  := public.cf_audit_hash(new.prev_hash, new.id, new.at, new.actor_id, new.actor_role,
                     new.action, new.entity_type, new.entity_id, new.outcome, new.details);
  return new;
end $$;

create or replace function public.cf_audit_block_trg() returns trigger
language plpgsql as $$
begin
  raise exception 'audit_log is append-only (% blocked)', tg_op;
end $$;

drop trigger if exists trg_audit_chain on public.audit_log;
create trigger trg_audit_chain before insert on public.audit_log
  for each row execute function public.cf_audit_chain_trg();
drop trigger if exists trg_audit_no_change on public.audit_log;
create trigger trg_audit_no_change before update or delete on public.audit_log
  for each row execute function public.cf_audit_block_trg();
drop trigger if exists trg_audit_no_truncate on public.audit_log;
create trigger trg_audit_no_truncate before truncate on public.audit_log
  for each statement execute function public.cf_audit_block_trg();

-- internal helper used by every function below
create or replace function public.cf_audit(
  p_actor uuid, p_role text, p_action text, p_etype text, p_eid text,
  p_outcome text, p_details jsonb, p_workflow text default null, p_exec text default null)
returns bigint language plpgsql set search_path = public, extensions as $$
declare v_id bigint;
begin
  insert into public.audit_log(actor_id, actor_role, action, entity_type, entity_id, outcome, details, workflow, execution_id)
  values (p_actor, p_role, p_action, p_etype, p_eid, coalesce(p_outcome,'info'), coalesce(p_details,'{}'), p_workflow, p_exec)
  returning id into v_id;
  return v_id;
end $$;

-- ---------------------------------------------------------------------
-- 11. Knowledge-base vector tables (LangChain PGVector layout used by
--     n8n's "Postgres PGVector Store" node: id | text | metadata | embedding)
--     Three SEPARATE tables = three separate retrieval scopes per role.
-- ---------------------------------------------------------------------
create table if not exists public.kb_hr_policy (
  id uuid primary key default gen_random_uuid(), text text, metadata jsonb, embedding vector);
create table if not exists public.kb_job_descriptions (
  id uuid primary key default gen_random_uuid(), text text, metadata jsonb, embedding vector);
create table if not exists public.kb_hire_patterns (
  id uuid primary key default gen_random_uuid(), text text, metadata jsonb, embedding vector);

-- Chat memory table used by n8n "Postgres Chat Memory" (pre-created so RLS
-- and a retention timestamp exist). session_id = '<role>:<user_id>:<chat>'
create table if not exists public.n8n_chat_histories (
  id          serial primary key,
  session_id  varchar(255) not null,
  message     jsonb not null,
  created_at  timestamptz not null default now()
);
create index if not exists ix_chat_session on public.n8n_chat_histories(session_id);

-- ---------------------------------------------------------------------
-- 12. Evaluation & baseline tables
-- ---------------------------------------------------------------------
create table if not exists public.baseline_timings (
  id            bigserial primary key,
  reviewer      text not null,
  resume_ref    text not null,
  job_id        text,
  minutes       numeric(6,2) not null check (minutes > 0 and minutes < 240),
  decision      text,
  manual_score  numeric(5,1),
  is_demo       boolean not null default false,
  recorded_at   timestamptz not null default now()
);

create table if not exists public.eval_resumes (
  code         text primary key,          -- R01..R12
  label        text not null,
  resume_text  text not null
);
create table if not exists public.eval_ranking_cases (
  case_no         int primary key,
  job_id          text not null references public.jobs(id),
  resume_codes    text[] not null,
  expected_order  text[] not null,
  rationale       text
);
create table if not exists public.eval_fairness_pairs (
  pair_no          int primary key,
  job_id           text not null references public.jobs(id),
  code_a           text not null,
  code_b           text not null,
  varied_attributes text not null      -- what differs between A and B (only protected / proxy attributes)
);
create table if not exists public.eval_policy_questions (
  id              int primary key,
  question        text not null,
  must_include    jsonb not null,     -- [["21"],["working days","days"]] = AND of OR-groups
  kind            text not null default 'answerable' check (kind in ('answerable','out_of_scope')),
  source_section  text
);
create table if not exists public.eval_runs (
  id         bigserial primary key,
  suite      text not null,
  label      text,
  passed     int not null,
  total      int not null,
  pass_rate  numeric(5,1),
  details    jsonb,
  run_at     timestamptz not null default now()
);

-- =====================================================================
--  FUNCTIONS CALLED BY n8n   (all: cf_xxx(p jsonb) returns jsonb)
-- =====================================================================

-- ---------- generic audit insert (CF-00 and others) -------------------
create or replace function public.cf_log(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare v_id bigint;
begin
  v_id := public.cf_audit(public.cf_try_uuid(p->>'actor_id'), p->>'actor_role',
            coalesce(p->>'action','unknown'), p->>'entity_type', p->>'entity_id',
            case when p->>'outcome' in ('success','denied','error','info') then p->>'outcome' else 'info' end,
            coalesce(p->'details','{}'::jsonb), p->>'workflow', p->>'execution_id');
  return jsonb_build_object('ok', true, 'audit_id', v_id);
end $$;

-- ---------- AUTH: login (bcrypt + lockout + audit) --------------------
create or replace function public.cf_login(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare
  u        public.app_users%rowtype;
  v_email  text := lower(trim(coalesce(p->>'email','')));
  v_pw     text := coalesce(p->>'password','');
  v_ctx    jsonb := jsonb_build_object('ip', p->>'ip', 'user_agent', left(p->>'user_agent', 200));
begin
  select * into u from public.app_users where email = v_email;
  if not found then
    perform crypt(v_pw, '$2a$10$CwTycUXWue0Thq9StjUM0uJ8.wCm7aYlOZzqtwcLGrr5Ymh4Jx4k6'); -- equalise timing
    perform public.cf_audit(null, null, 'login', 'user', v_email, 'denied', v_ctx || '{"reason":"unknown_email"}');
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;

  if u.locked_until is not null and u.locked_until > now() then
    perform public.cf_audit(u.id, u.role, 'login', 'user', u.id::text, 'denied', v_ctx || '{"reason":"locked"}');
    return jsonb_build_object('ok', false, 'error', 'account_locked',
             'retry_after_minutes', ceil(extract(epoch from (u.locked_until - now())) / 60));
  end if;

  if not u.is_active or u.password_hash <> crypt(v_pw, u.password_hash) then
    update public.app_users
       set failed_logins = failed_logins + 1,
           locked_until  = case when failed_logins + 1 >= 5 then now() + interval '15 minutes' else locked_until end
     where id = u.id;
    perform public.cf_audit(u.id, u.role, 'login', 'user', u.id::text, 'denied',
              v_ctx || jsonb_build_object('reason', case when u.is_active then 'bad_password' else 'disabled' end,
                                          'failed_attempts', u.failed_logins + 1));
    return jsonb_build_object('ok', false, 'error', 'invalid_credentials');
  end if;

  update public.app_users set failed_logins = 0, locked_until = null, last_login_at = now() where id = u.id;
  perform public.cf_audit(u.id, u.role, 'login', 'user', u.id::text, 'success', v_ctx);
  return jsonb_build_object('ok', true, 'user', jsonb_build_object(
           'id', u.id, 'email', u.email, 'full_name', u.full_name, 'role', u.role, 'department', u.department));
end $$;

-- ---------- AUTH: candidate self-registration -------------------------
create or replace function public.cf_register_candidate(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare
  v_email text := lower(trim(coalesce(p->>'email','')));
  v_name  text := trim(coalesce(p->>'full_name',''));
  v_pw    text := coalesce(p->>'password','');
  v_uid   uuid;
begin
  if v_email !~ '^[^@\s]+@[^@\s]+\.[^@\s]+$' then
    return jsonb_build_object('ok', false, 'error', 'invalid_email');
  end if;
  if length(v_pw) < 10 or v_pw !~ '[A-Za-z]' or v_pw !~ '[0-9]' then
    return jsonb_build_object('ok', false, 'error', 'weak_password',
             'message', 'Use at least 10 characters with letters and numbers.');
  end if;
  if length(v_name) < 3 or length(v_name) > 120 then
    return jsonb_build_object('ok', false, 'error', 'invalid_name');
  end if;
  if exists (select 1 from public.app_users where email = v_email) then
    perform public.cf_audit(null, 'candidate', 'register', 'user', v_email, 'denied', '{"reason":"email_taken"}');
    return jsonb_build_object('ok', false, 'error', 'email_taken');
  end if;

  insert into public.app_users(email, full_name, role, password_hash)
  values (v_email, v_name, 'candidate', crypt(v_pw, gen_salt('bf', 10)))
  returning id into v_uid;
  insert into public.candidates(user_id, full_name, email, phone)
  values (v_uid, v_name, v_email, nullif(trim(coalesce(p->>'phone','')), ''));

  perform public.cf_audit(v_uid, 'candidate', 'register', 'user', v_uid::text, 'success',
            jsonb_build_object('ip', p->>'ip'));
  return jsonb_build_object('ok', true, 'user', jsonb_build_object(
           'id', v_uid, 'email', v_email, 'full_name', v_name, 'role', 'candidate', 'department', null));
end $$;

-- ---------- ADMIN: create staff/candidate users (SQL editor only) -----
create or replace function public.cf_admin_create_user(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare v_uid uuid; v_email text := lower(trim(p->>'email'));
begin
  insert into public.app_users(email, full_name, role, password_hash, department, is_test)
  values (v_email, p->>'full_name', p->>'role', crypt(p->>'password', gen_salt('bf', 10)),
          p->>'department', coalesce((p->>'is_test')::boolean, false))
  on conflict (email) do update
     set full_name = excluded.full_name, role = excluded.role, department = excluded.department,
         password_hash = excluded.password_hash, is_test = excluded.is_test,
         failed_logins = 0, locked_until = null
  returning id into v_uid;
  if p->>'role' = 'candidate' then
    insert into public.candidates(user_id, full_name, email, is_test)
    values (v_uid, p->>'full_name', v_email, coalesce((p->>'is_test')::boolean, false))
    on conflict (user_id) do nothing;
  end if;
  return jsonb_build_object('ok', true, 'user_id', v_uid);
end $$;

-- ---------- PUBLIC: open jobs (safe columns only) ---------------------
create or replace function public.cf_public_jobs(p jsonb default '{}') returns jsonb
language sql stable set search_path = public, extensions as $$
  select jsonb_build_object('ok', true, 'jobs', coalesce(jsonb_agg(jsonb_build_object(
           'id', j.id, 'title', j.title, 'department', j.department, 'seniority', j.seniority,
           'location', j.location, 'employment_type', j.employment_type, 'openings', j.openings,
           'summary', j.summary, 'min_years', j.min_years,
           'must_have', (select coalesce(jsonb_agg(x->>'label'), '[]') from jsonb_array_elements(j.must_have_skills) x),
           'nice_to_have', (select coalesce(jsonb_agg(x->>'label'), '[]') from jsonb_array_elements(j.nice_to_have_skills) x))
         order by j.department, j.title), '[]'::jsonb))
  from public.jobs j where j.status = 'open'
$$;

-- ---------- CANDIDATE: submit application -----------------------------
create or replace function public.cf_create_application(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare
  v_uid  uuid := public.cf_try_uuid(p->>'user_id');
  c      public.candidates%rowtype;
  j      public.jobs%rowtype;
  v_id   bigint;
  v_txt  text := p->>'resume_text';
  v_dup  bigint;
begin
  select * into c from public.candidates where user_id = v_uid;
  if not found then return jsonb_build_object('ok', false, 'error', 'candidate_profile_missing'); end if;
  select * into j from public.jobs where id = p->>'job_id';
  if not found then return jsonb_build_object('ok', false, 'error', 'job_not_found'); end if;
  if j.status <> 'open' then return jsonb_build_object('ok', false, 'error', 'job_closed'); end if;
  if coalesce(p->>'consent','false') <> 'true' then
    return jsonb_build_object('ok', false, 'error', 'consent_required');
  end if;
  if v_txt is null or length(trim(v_txt)) = 0 then
    return jsonb_build_object('ok', false, 'error', 'empty_resume');
  end if;
  select id into v_dup from public.applications
   where candidate_id = c.id and job_id = j.id and status not in ('rejected','withdrawn') limit 1;
  if v_dup is not null then
    return jsonb_build_object('ok', false, 'error', 'duplicate_application', 'app_code', public.cf_app_code(v_dup));
  end if;

  insert into public.applications(candidate_id, job_id, resume_text, resume_format, resume_file_name, resume_chars, is_test)
  values (c.id, j.id, v_txt, coalesce(p->>'resume_format','paste'), p->>'file_name', length(v_txt), c.is_test)
  returning id into v_id;
  insert into public.application_events(application_id, from_status, to_status, actor_id, actor_role, reason)
  values (v_id, null, 'applied', v_uid, 'candidate', 'Application submitted via portal');
  update public.candidates
     set consent_given_at = now(), consent_version = coalesce(p->>'consent_version','v1'),
         last_interaction_at = now(), interaction_count = interaction_count + 1
   where id = c.id;
  perform public.cf_audit(v_uid, 'candidate', 'application_submitted', 'application', v_id::text, 'success',
            jsonb_build_object('job_id', j.id, 'resume_format', p->>'resume_format', 'resume_chars', length(v_txt)));
  return jsonb_build_object('ok', true, 'application_id', v_id, 'app_code', public.cf_app_code(v_id),
           'job_id', j.id, 'job_title', j.title);
end $$;

-- ---------- SCREENING: load everything the engine needs ---------------
create or replace function public.cf_load_for_screening(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare
  a     public.applications%rowtype;
  v_id  bigint := public.cf_try_bigint(p->>'application_id');
  v_job jsonb;
  v_all jsonb;
begin
  select * into a from public.applications where id = v_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'application_not_found'); end if;
  if a.status = 'withdrawn' then return jsonb_build_object('ok', false, 'error', 'application_withdrawn'); end if;

  select to_jsonb(j) - 'created_at' into v_job from public.jobs j where j.id = a.job_id;
  select coalesce(jsonb_agg(to_jsonb(j) - 'created_at' - 'description'), '[]') into v_all
    from public.jobs j where j.status = 'open';

  if a.status in ('applied','needs_info','screening_error') then
    update public.applications set status = 'screening', status_updated_at = now() where id = a.id;
    insert into public.application_events(application_id, from_status, to_status, actor_role, reason)
    values (a.id, a.status, 'screening', 'system', coalesce(p->>'reason','Automated screening started'));
  end if;

  return jsonb_build_object('ok', true,
    'application', jsonb_build_object('id', a.id, 'app_code', public.cf_app_code(a.id), 'job_id', a.job_id,
                     'status', a.status, 'resume_text', a.resume_text, 'resume_format', a.resume_format,
                     'is_test', a.is_test),
    'job', v_job, 'open_jobs', v_all, 'rubric_version', 'cf-rubric-1.0');
end $$;

create or replace function public.cf_get_cached_profile(p jsonb) returns jsonb
language sql stable set search_path = public, extensions as $$
  -- the hash is computed server-side from the REDACTED text → identical redacted résumés
  -- (e.g. the fairness-test pairs) reuse one extracted profile → identical scores
  with h as (select encode(sha256(convert_to(coalesce(p->>'redacted_text',''), 'UTF8')), 'hex') as resume_hash)
  select coalesce(
    (select jsonb_build_object('found', true, 'resume_hash', h.resume_hash, 'profile', c.profile, 'model', c.model)
       from public.resume_profile_cache c where c.resume_hash = h.resume_hash),
    jsonb_build_object('found', false, 'resume_hash', h.resume_hash))
  from h
$$;

-- ---------- SCREENING: record decision (+ audit, + cache) -------------
create or replace function public.cf_record_screening(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare
  a        public.applications%rowtype;
  v_id     bigint := public.cf_try_bigint(p->>'application_id');
  v_out    text   := coalesce(p->>'outcome','screened');
  v_sid    bigint;
  v_new    text;
  v_actor  uuid   := public.cf_try_uuid(p->>'actor_id');
  v_role   text   := coalesce(p->>'actor_role','system');
begin
  select * into a from public.applications where id = v_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'application_not_found'); end if;

  if v_out = 'screened' then
    insert into public.screening_results(application_id, job_id, score, band, recommendation, breakdown, explanation,
           profile, flags, alternatives, redactions, redacted_resume, rubric_version, model, resume_hash, from_cache, duration_ms)
    values (a.id, a.job_id, (p->>'score')::numeric, p->>'band', p->>'recommendation',
            coalesce(p->'breakdown','{}'), p->>'explanation', p->'profile', coalesce(p->'flags','[]'),
            coalesce(p->'alternatives','[]'), p->'redactions', p->>'redacted_resume', p->>'rubric_version',
            p->>'model', p->>'resume_hash', coalesce((p->>'from_cache')::boolean, false),
            (p->>'duration_ms')::int)
    returning id into v_sid;

    v_new := case when a.status in ('applied','screening','screened','needs_info','screening_error')
                  then 'screened' else a.status end;
    update public.applications
       set latest_score = (p->>'score')::numeric, latest_band = p->>'band', screened_at = now(),
           screening_error_code = null, screening_issues = coalesce(p->'flags','[]'),
           status = v_new, status_updated_at = case when v_new <> a.status then now() else status_updated_at end
     where id = a.id;
    if v_new <> a.status then
      insert into public.application_events(application_id, from_status, to_status, actor_id, actor_role, reason)
      values (a.id, a.status, v_new, v_actor, v_role, 'Automated screening completed: ' || (p->>'band'));
    end if;
    if p->>'resume_hash' is not null and p->'profile' is not null and not coalesce((p->>'from_cache')::boolean,false) then
      insert into public.resume_profile_cache(resume_hash, profile, model)
      values (p->>'resume_hash', p->'profile', p->>'model') on conflict (resume_hash) do nothing;
    end if;
    perform public.cf_audit(v_actor, v_role, 'screening_decision', 'application', a.id::text, 'success',
      jsonb_build_object('job_id', a.job_id, 'score', (p->>'score')::numeric, 'band', p->>'band',
        'recommendation', p->>'recommendation', 'rubric_version', p->>'rubric_version', 'model', p->>'model',
        'resume_hash', p->>'resume_hash', 'from_cache', coalesce((p->>'from_cache')::boolean,false),
        'flags', coalesce(p->'flags','[]'), 'criteria', p->'breakdown'->'summary',
        'alternatives', (select coalesce(jsonb_agg(x->>'job_id'),'[]') from jsonb_array_elements(coalesce(p->'alternatives','[]')) x),
        'screening_id', v_sid, 'duration_ms', (p->>'duration_ms')::int),
      p->>'workflow', p->>'execution_id');
    return jsonb_build_object('ok', true, 'screening_id', v_sid, 'status', v_new);
  end if;

  -- failure outcomes: needs_info (bad/incomplete résumé) or screening_error (LLM/system failure)
  v_new := case when a.status in ('applied','screening','needs_info','screening_error') then v_out else a.status end;
  update public.applications
     set status = v_new, screening_error_code = p->>'error_code', screening_issues = coalesce(p->'issues','[]'),
         status_updated_at = now()
   where id = a.id;
  insert into public.application_events(application_id, from_status, to_status, actor_id, actor_role, reason)
  values (a.id, a.status, v_new, v_actor, v_role, 'Screening stopped: ' || coalesce(p->>'error_code','unknown'));
  perform public.cf_audit(v_actor, v_role, 'screening_failed', 'application', a.id::text, 'error',
    jsonb_build_object('job_id', a.job_id, 'outcome', v_out, 'error_code', p->>'error_code',
                       'issues', coalesce(p->'issues','[]'), 'detail', left(p->>'error_detail', 500)),
    p->>'workflow', p->>'execution_id');
  return jsonb_build_object('ok', true, 'status', v_new, 'error_code', p->>'error_code');
end $$;

-- ---------- STATUS CHANGES (HR decisions, candidate withdrawals) ------
create or replace function public.cf_set_application_status(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare
  a        public.applications%rowtype;
  v_id     bigint := public.cf_try_bigint(p->>'application_id');
  v_to     text   := p->>'new_status';
  v_role   text   := p->>'actor_role';
  v_actor  uuid   := public.cf_try_uuid(p->>'actor_id');
  v_reason text   := nullif(trim(coalesce(p->>'reason','')), '');
  v_allowed jsonb := '{
    "applied":["screening","screened","shortlisted","needs_info","rejected","withdrawn"],
    "screening":["screened","needs_info","screening_error","withdrawn"],
    "screened":["shortlisted","needs_info","rejected","withdrawn"],
    "needs_info":["applied","screening","rejected","withdrawn"],
    "screening_error":["screening","applied","rejected","withdrawn"],
    "shortlisted":["interview_scheduled","screened","rejected","withdrawn"],
    "interview_scheduled":["interviewed","shortlisted","rejected","withdrawn"],
    "interviewed":["offer","rejected","withdrawn"],
    "offer":["hired","rejected","withdrawn"],
    "rejected":["screened"],
    "hired":[], "withdrawn":[] }';
begin
  select * into a from public.applications where id = v_id for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'application_not_found'); end if;

  if v_role = 'candidate' then
    if v_to <> 'withdrawn' or not exists (select 1 from public.candidates c where c.id = a.candidate_id and c.user_id = v_actor) then
      perform public.cf_audit(v_actor, v_role, 'status_change', 'application', a.id::text, 'denied',
                jsonb_build_object('attempted', v_to));
      return jsonb_build_object('ok', false, 'error', 'forbidden');
    end if;
  elsif v_role is distinct from 'hr' then
    perform public.cf_audit(v_actor, v_role, 'status_change', 'application', a.id::text, 'denied',
              jsonb_build_object('attempted', v_to));
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;

  if not coalesce((v_allowed -> a.status) ? v_to, false) then
    return jsonb_build_object('ok', false, 'error', 'invalid_transition', 'from', a.status, 'to', v_to,
             'allowed', v_allowed -> a.status);
  end if;
  if v_role = 'hr' and v_to = 'rejected' and length(coalesce(v_reason,'')) < 5 then
    return jsonb_build_object('ok', false, 'error', 'reason_required',
             'message', 'A rejection must include a job-related reason (min 5 characters).');
  end if;

  update public.applications set
    status = v_to, status_updated_at = now(),
    shortlisted_at         = case when v_to = 'shortlisted'         then coalesce(shortlisted_at, now())         else shortlisted_at end,
    interview_scheduled_at = case when v_to = 'interview_scheduled' then coalesce(interview_scheduled_at, now()) else interview_scheduled_at end,
    interviewed_at         = case when v_to = 'interviewed'         then coalesce(interviewed_at, now())         else interviewed_at end,
    offer_at               = case when v_to = 'offer'               then coalesce(offer_at, now())               else offer_at end,
    hired_at               = case when v_to = 'hired'               then now()                                   else hired_at end,
    rejected_at            = case when v_to = 'rejected'            then now() when v_to = 'screened' then null  else rejected_at end,
    withdrawn_at           = case when v_to = 'withdrawn'           then now()                                   else withdrawn_at end,
    hr_notes               = case when v_role = 'hr' and v_reason is not null
                                  then concat_ws(E'\n', hr_notes, to_char(now(),'YYYY-MM-DD') || ' ' || v_to || ': ' || v_reason)
                                  else hr_notes end
  where id = a.id;

  insert into public.application_events(application_id, from_status, to_status, actor_id, actor_role, reason, review_seconds)
  values (a.id, a.status, v_to, v_actor, v_role, v_reason, public.cf_try_bigint(p->>'review_seconds')::int);

  perform public.cf_audit(v_actor, v_role, 'status_change', 'application', a.id::text, 'success',
            jsonb_build_object('from', a.status, 'to', v_to, 'reason', v_reason,
                               'review_seconds', public.cf_try_bigint(p->>'review_seconds'),
                               'via', coalesce(p->>'via','api')));
  return jsonb_build_object('ok', true, 'application_id', a.id, 'app_code', public.cf_app_code(a.id),
           'from', a.status, 'to', v_to);
end $$;

-- ---------- CANDIDATE: own status snapshot (NO scores, NO HR notes) ---
create or replace function public.cf_candidate_snapshot(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare
  c     public.candidates%rowtype;
  v_uid uuid := public.cf_try_uuid(p->>'user_id');
  v_apps jsonb;
begin
  select * into c from public.candidates where user_id = v_uid;
  if not found then return jsonb_build_object('ok', true, 'applications', '[]'::jsonb, 'note', 'no candidate profile'); end if;

  if coalesce(p->>'touch','false') = 'true' then
    update public.candidates set interaction_count = interaction_count + 1, last_interaction_at = now() where id = c.id;
  end if;

  select coalesce(jsonb_agg(jsonb_build_object(
           'application_id', a.id, 'app_code', public.cf_app_code(a.id),
           'job_id', a.job_id, 'job_title', j.title, 'status', a.status,
           'status_label', case a.status
              when 'applied'             then 'Received'
              when 'screening'           then 'Being reviewed'
              when 'screened'            then 'Under HR review'
              when 'needs_info'          then 'Action needed'
              when 'screening_error'     then 'Being reviewed'
              when 'shortlisted'         then 'Shortlisted'
              when 'interview_scheduled' then 'Interview scheduled'
              when 'interviewed'         then 'Interview completed'
              when 'offer'               then 'Offer extended'
              when 'hired'               then 'Hired'
              when 'rejected'            then 'Not selected this time'
              when 'withdrawn'           then 'Withdrawn' end,
           'next_step', case a.status
              when 'needs_info'  then 'We could not read enough of your résumé (' || coalesce(a.screening_error_code,'unreadable') ||
                                      '). Please re-apply with a text-based PDF or paste your résumé as text.'
              when 'shortlisted' then 'Please choose an interview slot — ask the assistant "show me interview slots".'
              when 'interview_scheduled' then 'Attend your interview at the scheduled time.'
              when 'interviewed' then 'HR will contact you with a decision.'
              when 'offer'       then 'Check your email for the offer letter.'
              when 'rejected'    then 'Thank you for applying. You are welcome to apply for other open roles.'
              when 'withdrawn'   then 'No further action.'
              when 'hired'       then 'Welcome to CompanyFlow!'
              else 'HR is reviewing your application. No action needed.' end,
           'applied_at', a.applied_at, 'last_update', a.status_updated_at,
           'interview', (select jsonb_build_object('when', public.cf_cairo(i.starts_at), 'starts_at', i.starts_at,
                                 'mode', i.mode, 'location', i.location, 'meet_link', i.meet_link)
                           from public.interviews i where i.application_id = a.id and i.status = 'scheduled'
                           order by i.starts_at desc limit 1),
           'history', (select coalesce(jsonb_agg(jsonb_build_object('at', e.at, 'status', e.to_status) order by e.at), '[]')
                         from public.application_events e where e.application_id = a.id
                          and e.to_status not in ('screening','screening_error')))
         order by a.applied_at desc), '[]')
    into v_apps
    from public.applications a join public.jobs j on j.id = a.job_id
   where a.candidate_id = c.id;

  return jsonb_build_object('ok', true, 'candidate_code', public.cf_cand_code(c.id),
           'first_name', split_part(c.full_name, ' ', 1), 'applications', v_apps,
           'interaction_count', c.interaction_count);
end $$;

-- ---------- SCHEDULER: list open slots for an application -------------
create or replace function public.cf_list_slots(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare
  a       public.applications%rowtype;
  v_owner uuid;
  v_actor uuid := public.cf_try_uuid(p->>'actor_id');
  v_role  text := p->>'actor_role';
  v_slots jsonb;
begin
  select * into a from public.applications where id = public.cf_try_bigint(p->>'application_id');
  if not found then return jsonb_build_object('ok', false, 'error', 'application_not_found'); end if;
  select user_id into v_owner from public.candidates where id = a.candidate_id;
  if v_role = 'candidate' and v_owner is distinct from v_actor then
    perform public.cf_audit(v_actor, v_role, 'slots_listed', 'application', a.id::text, 'denied', '{"reason":"not_owner"}');
    return jsonb_build_object('ok', false, 'error', 'not_your_application');
  end if;
  if v_role not in ('candidate','hr') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if a.status <> 'shortlisted' then
    return jsonb_build_object('ok', false, 'error', 'not_eligible', 'status', a.status,
             'message', 'Interview slots open after HR shortlists the application.');
  end if;
  select coalesce(jsonb_agg(jsonb_build_object('slot_id', s.id, 'when', public.cf_cairo(s.starts_at),
           'starts_at', s.starts_at, 'ends_at', s.ends_at, 'mode', s.mode, 'location', s.location,
           'interviewer', s.interviewer_name) order by s.starts_at), '[]')
    into v_slots
    from (select * from public.interview_slots
           where status = 'open' and starts_at > now() + interval '2 hours'
             and (job_id is null or job_id = a.job_id)
           order by starts_at limit 6) s;
  return jsonb_build_object('ok', true, 'application_id', a.id, 'app_code', public.cf_app_code(a.id), 'slots', v_slots);
end $$;

-- ---------- SCHEDULER: book a slot (row locks → no double booking) ----
create or replace function public.cf_book_slot(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare
  a       public.applications%rowtype;
  s       public.interview_slots%rowtype;
  c       public.candidates%rowtype;
  v_actor uuid := public.cf_try_uuid(p->>'actor_id');
  v_role  text := p->>'actor_role';
  v_iid   bigint;
  v_title text;
begin
  select * into a from public.applications where id = public.cf_try_bigint(p->>'application_id') for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'application_not_found'); end if;
  select * into c from public.candidates where id = a.candidate_id;
  if v_role = 'candidate' and c.user_id is distinct from v_actor then
    perform public.cf_audit(v_actor, v_role, 'interview_booked', 'application', a.id::text, 'denied', '{"reason":"not_owner"}');
    return jsonb_build_object('ok', false, 'error', 'not_your_application');
  end if;
  if v_role not in ('candidate','hr') then return jsonb_build_object('ok', false, 'error', 'forbidden'); end if;
  if a.status <> 'shortlisted' then
    return jsonb_build_object('ok', false, 'error', 'not_eligible', 'status', a.status);
  end if;

  select * into s from public.interview_slots where id = public.cf_try_bigint(p->>'slot_id') for update;
  if not found or s.status <> 'open' or s.starts_at <= now() then
    return jsonb_build_object('ok', false, 'error', 'slot_unavailable');
  end if;
  if s.job_id is not null and s.job_id <> a.job_id then
    return jsonb_build_object('ok', false, 'error', 'slot_not_for_this_job');
  end if;

  update public.interview_slots set status = 'booked', booked_application_id = a.id where id = s.id;
  insert into public.interviews(application_id, slot_id, starts_at, ends_at, mode, location, interviewer_name, interviewer_email)
  values (a.id, s.id, s.starts_at, s.ends_at, s.mode, s.location, s.interviewer_name, s.interviewer_email)
  returning id into v_iid;
  update public.applications set status = 'interview_scheduled', interview_scheduled_at = now(), status_updated_at = now()
   where id = a.id;
  insert into public.application_events(application_id, from_status, to_status, actor_id, actor_role, reason)
  values (a.id, a.status, 'interview_scheduled', v_actor, v_role, 'Interview booked for ' || public.cf_cairo(s.starts_at));
  select title into v_title from public.jobs where id = a.job_id;
  perform public.cf_audit(v_actor, v_role, 'interview_booked', 'application', a.id::text, 'success',
            jsonb_build_object('slot_id', s.id, 'interview_id', v_iid, 'starts_at', s.starts_at));
  return jsonb_build_object('ok', true, 'app_code', public.cf_app_code(a.id), 'job_title', v_title,
    'interview', jsonb_build_object('interview_id', v_iid, 'when', public.cf_cairo(s.starts_at),
                   'starts_at', s.starts_at, 'ends_at', s.ends_at, 'mode', s.mode, 'location', s.location,
                   'interviewer_name', s.interviewer_name, 'interviewer_email', s.interviewer_email),
    'candidate', jsonb_build_object('email', c.email, 'first_name', split_part(c.full_name,' ',1)));
end $$;

create or replace function public.cf_attach_calendar(p jsonb) returns jsonb
language sql set search_path = public, extensions as $$
  update public.interviews
     set calendar_event_id = coalesce(p->>'calendar_event_id', calendar_event_id),
         meet_link = coalesce(nullif(p->>'meet_link',''), meet_link)
   where id = public.cf_try_bigint(p->>'interview_id')
  returning jsonb_build_object('ok', true, 'interview_id', id, 'meet_link', meet_link)
$$;

-- ---------- SCHEDULER: generate future slots (Sun–Thu, Cairo time) ----
create or replace function public.cf_generate_slots(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare
  v_days  int  := coalesce(public.cf_try_bigint(p->>'days')::int, 14);
  v_name  text := coalesce(p->>'interviewer_name', 'Nadia Farouk (HR)');
  v_mail  text := coalesce(p->>'interviewer_email', 'hr@companyflow.test');
  v_job   text := nullif(p->>'job_id','');
  v_n     int;
begin
  insert into public.interview_slots(job_id, interviewer_name, interviewer_email, starts_at, ends_at, mode, location)
  select v_job, v_name, v_mail, t, t + interval '45 minutes',
         case when extract(hour from t at time zone 'Africa/Cairo') = 14 then 'onsite' else 'online' end,
         case when extract(hour from t at time zone 'Africa/Cairo') = 14 then 'CompanyFlow HQ, Smart Village, Giza'
              else 'Google Meet (link sent by email)' end
    from generate_series(current_date + 1, current_date + v_days, interval '1 day') d
    cross join (values (time '10:00'), (time '12:00'), (time '14:00')) h(hh)
    cross join lateral (select ((d::date + h.hh) at time zone 'Africa/Cairo') as t) x
   where extract(isodow from d) in (7,1,2,3,4)          -- Sunday..Thursday (Egyptian work week)
  on conflict (interviewer_email, starts_at) do nothing;
  get diagnostics v_n = row_count;
  perform public.cf_audit(public.cf_try_uuid(p->>'actor_id'), p->>'actor_role', 'slots_generated', 'interview_slots',
            coalesce(v_job,'all'), 'success', jsonb_build_object('created', v_n, 'days', v_days));
  return jsonb_build_object('ok', true, 'created', v_n);
end $$;

-- ---------- HR: dashboard metrics -------------------------------------
create or replace function public.cf_hr_dashboard(p jsonb default '{}') returns jsonb
language plpgsql stable set search_path = public, extensions as $$
declare
  v_demo boolean := coalesce((p->>'include_demo')::boolean, true);
  v jsonb;
begin
  with apps as (
    select a.*, j.title as job_title from public.applications a join public.jobs j on j.id = a.job_id
     where not a.is_test and (v_demo or not a.is_demo)),
  sr as (select s.* from public.screening_results s join apps a on a.id = s.application_id),
  bl as (select * from public.baseline_timings where v_demo or not is_demo),
  rv as (select e.review_seconds from public.application_events e join apps a on a.id = e.application_id
          where e.review_seconds is not null and e.review_seconds > 0)
  select jsonb_build_object(
    'generated_at', now(),
    'include_demo', v_demo,
    'kpis', jsonb_build_object(
      'open_roles',               (select count(*) from public.jobs where status = 'open'),
      'total_applications',       (select count(*) from apps),
      'applications_last_30d',    (select count(*) from apps where applied_at > now() - interval '30 days'),
      'screened_total',           (select count(*) from sr),
      'screened_last_7d',         (select count(*) from sr where created_at > now() - interval '7 days'),
      'avg_time_to_hire_days',    (select round((avg(extract(epoch from hired_at - applied_at)) / 86400)::numeric, 1) from apps where hired_at is not null),
      'median_time_to_hire_days', (select round((percentile_cont(0.5) within group (order by extract(epoch from hired_at - applied_at)) / 86400)::numeric, 1) from apps where hired_at is not null),
      'avg_time_to_shortlist_days',(select round((avg(extract(epoch from shortlisted_at - applied_at)) / 86400)::numeric, 1) from apps where shortlisted_at is not null),
      'avg_screening_seconds',    (select round(avg(duration_ms) / 1000.0, 1) from sr),
      'shortlist_rate_pct',       (select round(100.0 * count(*) filter (where shortlisted_at is not null) / nullif(count(*) filter (where screened_at is not null), 0), 1) from apps),
      'hires',                    (select count(*) from apps where hired_at is not null),
      'upcoming_interviews',      (select count(*) from public.interviews i join apps a on a.id = i.application_id where i.starts_at > now() and i.status = 'scheduled'),
      'needs_attention',          (select count(*) from apps where status in ('needs_info','screening_error'))),
    'screening_volume', (select jsonb_agg(jsonb_build_object('day', d::date, 'screened', coalesce(x.c, 0), 'applied', coalesce(y.c, 0)) order by d)
                           from generate_series(current_date - 29, current_date, interval '1 day') d
                           left join (select created_at::date dd, count(*) c from sr group by 1) x on x.dd = d::date
                           left join (select applied_at::date dd, count(*) c from apps group by 1) y on y.dd = d::date),
    'funnel', jsonb_build_array(
        jsonb_build_object('stage','Applied',     'count', (select count(*) from apps)),
        jsonb_build_object('stage','Screened',    'count', (select count(*) from apps where screened_at is not null)),
        jsonb_build_object('stage','Shortlisted', 'count', (select count(*) from apps where shortlisted_at is not null)),
        jsonb_build_object('stage','Interview',   'count', (select count(*) from apps where interview_scheduled_at is not null)),
        jsonb_build_object('stage','Offer',       'count', (select count(*) from apps where offer_at is not null)),
        jsonb_build_object('stage','Hired',       'count', (select count(*) from apps where hired_at is not null))),
    'by_status', (select coalesce(jsonb_object_agg(status, n), '{}') from (select status, count(*) n from apps group by status) t),
    'by_job', (select coalesce(jsonb_agg(jsonb_build_object(
                 'job_id', j.id, 'title', j.title, 'status', j.status,
                 'applicants',  (select count(*) from apps a where a.job_id = j.id),
                 'screened',    (select count(*) from apps a where a.job_id = j.id and a.screened_at is not null),
                 'shortlisted', (select count(*) from apps a where a.job_id = j.id and a.shortlisted_at is not null),
                 'interviews',  (select count(*) from apps a where a.job_id = j.id and a.interview_scheduled_at is not null),
                 'hired',       (select count(*) from apps a where a.job_id = j.id and a.hired_at is not null),
                 'avg_score',   (select round(avg(a.latest_score), 1) from apps a where a.job_id = j.id),
                 'avg_time_to_hire_days', (select round((avg(extract(epoch from a.hired_at - a.applied_at)) / 86400)::numeric, 1)
                                             from apps a where a.job_id = j.id and a.hired_at is not null))
               order by j.department, j.title), '[]') from public.jobs j),
    'score_bands', (select coalesce(jsonb_object_agg(band, n), '{}') from (select latest_band band, count(*) n from apps where latest_band is not null group by 1) t),
    'recent_decisions', (select coalesce(jsonb_agg(r order by r->>'at' desc), '[]') from (
        select jsonb_build_object('app_code', public.cf_app_code(s.application_id), 'job_id', s.job_id,
                 'score', s.score, 'band', s.band, 'at', s.created_at, 'from_cache', s.from_cache) r
          from sr s order by s.created_at desc limit 10) t),
    'efficiency', (select jsonb_build_object(
        'manual_avg_minutes_per_resume', m.manual_min,
        'manual_samples',                m.samples,
        'auto_avg_seconds_per_resume',   a.auto_sec,
        'hr_review_avg_seconds',         r.review_sec,
        'assisted_minutes_per_resume',   round(((coalesce(a.auto_sec,0) + coalesce(r.review_sec,0)) / 60.0)::numeric, 2),
        'reduction_pct', case when m.manual_min > 0 then
            round((100 * (1 - ((coalesce(a.auto_sec,0) + coalesce(r.review_sec,0)) / 60.0) / m.manual_min))::numeric, 1) end)
      from (select round(avg(minutes), 2) manual_min, count(*) samples from bl) m,
           (select round(avg(duration_ms) / 1000.0, 1) auto_sec from sr) a,
           (select round(avg(review_seconds), 0) review_sec from rv) r)
  ) into v;
  return v;
end $$;

-- ---------- HR: candidate list (blind until shortlisted) --------------
create or replace function public.cf_hr_candidates(p jsonb default '{}') returns jsonb
language plpgsql stable set search_path = public, extensions as $$
declare
  v_demo boolean := coalesce((p->>'include_demo')::boolean, true);
  v_job  text := nullif(p->>'job_id','');
  v_st   text := nullif(p->>'status','');
  v jsonb;
begin
  select coalesce(jsonb_agg(row order by (row->>'score')::numeric desc nulls last, row->>'applied_at' desc), '[]') into v
  from (
    select jsonb_build_object(
      'application_id', a.id, 'app_code', public.cf_app_code(a.id), 'candidate_code', public.cf_cand_code(c.id),
      'display_name', case when a.status in ('shortlisted','interview_scheduled','interviewed','offer','hired')
                           then c.full_name else public.cf_cand_code(c.id) end,
      'identity_revealed', a.status in ('shortlisted','interview_scheduled','interviewed','offer','hired'),
      'job_id', a.job_id, 'job_title', j.title, 'status', a.status, 'score', a.latest_score, 'band', a.latest_band,
      'applied_at', a.applied_at, 'last_update', a.status_updated_at, 'is_demo', a.is_demo,
      'flags', coalesce(a.screening_issues, '[]')) as row
    from public.applications a
    join public.candidates c on c.id = a.candidate_id
    join public.jobs j on j.id = a.job_id
    where not a.is_test and (v_demo or not a.is_demo)
      and (v_job is null or a.job_id = v_job) and (v_st is null or a.status = v_st)
    order by a.latest_score desc nulls last
    limit least(coalesce(public.cf_try_bigint(p->>'limit')::int, 300), 500)
  ) t;
  return jsonb_build_object('ok', true, 'candidates', v);
end $$;

-- ---------- HR: ranking for the copilot (top N for one job) -----------
create or replace function public.cf_hr_rank(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare v jsonb; v_job text := upper(trim(coalesce(p->>'job_id','')));
begin
  if not exists (select 1 from public.jobs where id = v_job) then
    return jsonb_build_object('ok', false, 'error', 'job_not_found', 'valid_job_ids', (select jsonb_agg(id) from public.jobs));
  end if;
  select coalesce(jsonb_agg(x order by (x->>'score')::numeric desc nulls last), '[]') into v from (
    select jsonb_build_object('application_id', a.id, 'app_code', public.cf_app_code(a.id),
             'candidate_code', public.cf_cand_code(a.candidate_id), 'status', a.status,
             'score', a.latest_score, 'band', a.latest_band,
             'must_have', s.breakdown->'summary'->>'must_have',
             'top_gaps', s.breakdown->'summary'->'missing_must_have',
             'recommendation', s.recommendation, 'flags', s.flags) x
      from public.applications a
      left join lateral (select * from public.screening_results r where r.application_id = a.id
                          order by r.created_at desc limit 1) s on true
     where a.job_id = v_job and a.status not in ('withdrawn') and not a.is_test
       and (coalesce((p->>'include_demo')::boolean, true) or not a.is_demo)
     order by a.latest_score desc nulls last
     limit least(greatest(coalesce(public.cf_try_bigint(p->>'limit')::int, 5), 1), 20)) t;
  perform public.cf_audit(public.cf_try_uuid(p->>'actor_id'), 'hr', 'ranking_viewed', 'job', v_job, 'success',
            jsonb_build_object('via', coalesce(p->>'via','copilot')));
  return jsonb_build_object('ok', true, 'job_id', v_job, 'ranking', v);
end $$;

-- ---------- HR: one application with full explanation + trail ---------
create or replace function public.cf_hr_application_detail(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare
  a        public.applications%rowtype;
  c        public.candidates%rowtype;
  v_reveal boolean;
  v_actor  uuid := public.cf_try_uuid(p->>'actor_id');
  s        public.screening_results%rowtype;
begin
  select * into a from public.applications where id = public.cf_try_bigint(p->>'application_id');
  if not found then return jsonb_build_object('ok', false, 'error', 'application_not_found'); end if;
  select * into c from public.candidates where id = a.candidate_id;
  select * into s from public.screening_results where application_id = a.id order by created_at desc limit 1;
  v_reveal := coalesce((p->>'reveal_identity')::boolean, false)
              or a.status in ('shortlisted','interview_scheduled','interviewed','offer','hired');

  perform public.cf_audit(v_actor, 'hr', case when v_reveal then 'pii_access' else 'application_viewed' end,
            'application', a.id::text, 'success',
            jsonb_build_object('identity_revealed', v_reveal, 'explicit_reveal', coalesce((p->>'reveal_identity')::boolean,false),
                               'via', coalesce(p->>'via','dashboard')));

  return jsonb_build_object('ok', true,
    'application', jsonb_build_object('application_id', a.id, 'app_code', public.cf_app_code(a.id), 'job_id', a.job_id,
        'job_title', (select title from public.jobs where id = a.job_id), 'status', a.status,
        'applied_at', a.applied_at, 'score', a.latest_score, 'band', a.latest_band, 'hr_notes', a.hr_notes,
        'error_code', a.screening_error_code, 'issues', a.screening_issues, 'is_demo', a.is_demo,
        'resume_format', a.resume_format, 'resume_chars', a.resume_chars),
    'candidate', case when v_reveal then jsonb_build_object('candidate_code', public.cf_cand_code(c.id),
                       'full_name', c.full_name, 'email', c.email, 'phone', c.phone, 'revealed', true)
                 else jsonb_build_object('candidate_code', public.cf_cand_code(c.id), 'revealed', false) end,
    'screening', case when s.id is null then null else jsonb_build_object('screening_id', s.id, 'score', s.score,
        'band', s.band, 'recommendation', s.recommendation, 'breakdown', s.breakdown, 'explanation', s.explanation,
        'flags', s.flags, 'alternatives', s.alternatives, 'profile', s.profile, 'rubric_version', s.rubric_version,
        'model', s.model, 'from_cache', s.from_cache, 'duration_ms', s.duration_ms, 'at', s.created_at,
        'redactions', s.redactions) end,
    'resume', case when v_reveal then a.resume_text else coalesce(s.redacted_resume, '[hidden until shortlisted or revealed]') end,
    'events', (select coalesce(jsonb_agg(jsonb_build_object('at', e.at, 'from', e.from_status, 'to', e.to_status,
                 'by', e.actor_role, 'reason', e.reason) order by e.at), '[]')
                 from public.application_events e where e.application_id = a.id),
    'interviews', (select coalesce(jsonb_agg(jsonb_build_object('when', public.cf_cairo(i.starts_at), 'mode', i.mode,
                 'interviewer', i.interviewer_name, 'status', i.status, 'meet_link', i.meet_link)), '[]')
                 from public.interviews i where i.application_id = a.id),
    'audit', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'at', l.at, 'action', l.action,
                 'actor_role', l.actor_role, 'outcome', l.outcome) order by l.id desc), '[]')
                 from (select * from public.audit_log where entity_type = 'application' and entity_id = a.id::text
                        order by id desc limit 25) l));
end $$;

-- ---------- HR: pipeline context for the copilot planner -------------
create or replace function public.cf_hr_context(p jsonb default '{}') returns jsonb
language sql stable set search_path = public, extensions as $$
  select jsonb_build_object('ok', true, 'jobs', coalesce(jsonb_agg(jsonb_build_object(
      'job_id', j.id, 'title', j.title, 'seniority', j.seniority, 'status', j.status, 'openings', j.openings,
      'pipeline', (select coalesce(jsonb_object_agg(status, n), '{}') from (
                     select a.status, count(*) n from public.applications a
                      where a.job_id = j.id and not a.is_test group by a.status) t),
      'unscreened', (select count(*) from public.applications a where a.job_id = j.id and not a.is_test
                       and a.status in ('applied','screening_error')),
      'open_slots', (select count(*) from public.interview_slots s where s.status = 'open' and s.starts_at > now()
                       and (s.job_id is null or s.job_id = j.id)))
    order by j.id), '[]'), 'now_cairo', public.cf_cairo(now()))
  from public.jobs j
$$;

-- ---------- HR: audit viewer & integrity check ------------------------
create or replace function public.cf_audit_recent(p jsonb default '{}') returns jsonb
language sql stable set search_path = public, extensions as $$
  select jsonb_build_object('ok', true, 'entries', coalesce(jsonb_agg(jsonb_build_object(
           'id', l.id, 'at', l.at, 'actor_role', l.actor_role, 'actor_id', l.actor_id, 'action', l.action,
           'entity_type', l.entity_type, 'entity_id', l.entity_id, 'outcome', l.outcome, 'details', l.details,
           'workflow', l.workflow, 'row_hash', left(l.row_hash, 12)) order by l.id desc), '[]'))
  from (select * from public.audit_log
         where (nullif(p->>'action','') is null or action = p->>'action')
           and (nullif(p->>'outcome','') is null or outcome = p->>'outcome')
         order by id desc
         limit least(coalesce(public.cf_try_bigint(p->>'limit')::int, 100), 500)) l
$$;

create or replace function public.cf_verify_audit_chain(p jsonb default '{}') returns jsonb
language plpgsql stable set search_path = public, extensions as $$
declare r record; v_prev text := 'GENESIS'; v_n int := 0;
begin
  for r in select * from public.audit_log order by id loop
    if r.prev_hash is distinct from v_prev
       or r.row_hash is distinct from public.cf_audit_hash(r.prev_hash, r.id, r.at, r.actor_id, r.actor_role,
                                        r.action, r.entity_type, r.entity_id, r.outcome, r.details) then
      return jsonb_build_object('ok', false, 'checked', v_n, 'broken_at_id', r.id);
    end if;
    v_prev := r.row_hash; v_n := v_n + 1;
  end loop;
  return jsonb_build_object('ok', true, 'checked', v_n, 'last_hash', left(v_prev, 16));
end $$;

-- ---------- HR COPILOT: plans -----------------------------------------
create or replace function public.cf_save_plan(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare v_id bigint; v_actor uuid := public.cf_try_uuid(p->>'actor_id');
begin
  if v_actor is null then return jsonb_build_object('ok', false, 'error', 'actor_required'); end if;
  insert into public.agent_plans(created_by, request, plan) values (v_actor, left(p->>'request', 2000), coalesce(p->'plan','{}'))
  returning id into v_id;
  perform public.cf_audit(v_actor, 'hr', 'plan_proposed', 'agent_plan', v_id::text, 'success',
            jsonb_build_object('steps', jsonb_array_length(coalesce(p->'plan'->'steps','[]'))));
  return jsonb_build_object('ok', true, 'plan_id', v_id);
end $$;

create or replace function public.cf_start_plan(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare r public.agent_plans%rowtype; v_actor uuid := public.cf_try_uuid(p->>'actor_id');
begin
  select * into r from public.agent_plans where id = public.cf_try_bigint(p->>'plan_id') for update;
  if not found then return jsonb_build_object('ok', false, 'error', 'plan_not_found'); end if;
  if r.created_by is distinct from v_actor then return jsonb_build_object('ok', false, 'error', 'not_your_plan'); end if;
  if r.status <> 'proposed' then return jsonb_build_object('ok', false, 'error', 'plan_already_' || r.status); end if;
  update public.agent_plans set status = 'executing', executed_at = now() where id = r.id;
  perform public.cf_audit(v_actor, 'hr', 'plan_approved', 'agent_plan', r.id::text, 'success', '{}');
  return jsonb_build_object('ok', true, 'plan_id', r.id, 'request', r.request, 'plan', r.plan);
end $$;

create or replace function public.cf_finish_plan(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare v_id bigint := public.cf_try_bigint(p->>'plan_id'); v_actor uuid := public.cf_try_uuid(p->>'actor_id');
begin
  if v_id is not null then
    update public.agent_plans set status = coalesce(p->>'status','completed'), result = left(p->>'result', 8000), finished_at = now()
     where id = v_id and created_by = v_actor and status = 'executing';
  end if;
  perform public.cf_audit(v_actor, 'hr', case when v_id is null then 'copilot_chat' else 'plan_executed' end,
            'agent_plan', coalesce(v_id::text, '-'), 'success',
            jsonb_build_object('mode', p->>'mode', 'tools_used', coalesce(p->'tools_used','[]'),
                               'message_chars', length(coalesce(p->>'message',''))));
  return jsonb_build_object('ok', true);
end $$;

-- ---------- BASELINE timing study (manual screening) ------------------
create or replace function public.cf_log_baseline(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare v_id bigint;
begin
  insert into public.baseline_timings(reviewer, resume_ref, job_id, minutes, decision, manual_score)
  values (left(p->>'reviewer',80), left(p->>'resume_ref',40), nullif(p->>'job_id',''),
          (p->>'minutes')::numeric, p->>'decision', nullif(p->>'manual_score','')::numeric)
  returning id into v_id;
  perform public.cf_audit(null, 'hr', 'baseline_logged', 'baseline', v_id::text, 'success',
            jsonb_build_object('minutes', (p->>'minutes')::numeric, 'resume_ref', p->>'resume_ref'));
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

-- ---------- DATA RETENTION (Egypt PDPL – data minimisation) -----------
create or replace function public.cf_retention_purge(p jsonb default '{}') returns jsonb
language plpgsql set search_path = public, extensions as $$
declare
  v_chat_days int := coalesce(public.cf_try_bigint(p->>'chat_days')::int, 90);
  v_cand_days int := coalesce(public.cf_try_bigint(p->>'candidate_days')::int, 365);
  v_chats int; v_cands int;
begin
  delete from public.n8n_chat_histories where created_at < now() - make_interval(days => v_chat_days);
  get diagnostics v_chats = row_count;
  with old as (
    select c.id from public.candidates c
     where c.erased_at is null and not c.is_demo and not c.is_test
       and not exists (select 1 from public.applications a where a.candidate_id = c.id
                        and (a.status not in ('rejected','withdrawn') or a.status_updated_at > now() - make_interval(days => v_cand_days)))
       and exists (select 1 from public.applications a where a.candidate_id = c.id))
  update public.candidates c set full_name = '[erased]', email = null, phone = null, erased_at = now()
    from old where c.id = old.id;
  get diagnostics v_cands = row_count;
  update public.applications a set resume_text = null
    from public.candidates c where c.id = a.candidate_id and c.erased_at is not null and a.resume_text is not null;
  update public.screening_results s set redacted_resume = null, profile = null
    from public.applications a join public.candidates c on c.id = a.candidate_id
   where s.application_id = a.id and c.erased_at is not null and s.redacted_resume is not null;
  perform public.cf_audit(null, 'system', 'retention_purge', 'system', '-', 'success',
            jsonb_build_object('chat_rows_deleted', v_chats, 'candidates_erased', v_cands));
  return jsonb_build_object('ok', true, 'chat_rows_deleted', v_chats, 'candidates_erased', v_cands);
end $$;

-- ---------- EVALUATION helpers (CF-08) --------------------------------
create or replace function public.cf_eval_prepare_ranking(p jsonb default '{}')
returns table(application_id bigint, resume_code text, job_id text)
language plpgsql set search_path = public, extensions as $$
declare r record; v_cid bigint; v_aid bigint;
begin
  -- close previous test applications so the unique index allows fresh ones
  update public.applications a set status = 'withdrawn', withdrawn_at = now(), status_updated_at = now()
    from public.candidates c
   where c.id = a.candidate_id and c.is_test and c.user_id is null and a.status <> 'withdrawn';

  for r in select distinct t.code, t.job_id from (
             select x.code, k.job_id from public.eval_ranking_cases k cross join lateral unnest(k.resume_codes) as x(code)
             union select f.code_a, f.job_id from public.eval_fairness_pairs f
             union select f.code_b, f.job_id from public.eval_fairness_pairs f) t
            order by 1, 2 loop
    select c.id into v_cid from public.candidates c where c.is_test and c.user_id is null and c.full_name = 'Eval ' || r.code;
    if v_cid is null then
      insert into public.candidates(full_name, email, is_test) values ('Eval ' || r.code, lower(r.code) || '@eval.companyflow.test', true)
      returning id into v_cid;
    end if;
    insert into public.applications(candidate_id, job_id, resume_text, resume_format, resume_chars, is_test, source)
    select v_cid, r.job_id, e.resume_text, 'text', length(e.resume_text), true, 'eval'
      from public.eval_resumes e where e.code = r.code
    returning id into v_aid;
    application_id := v_aid; resume_code := r.code; job_id := r.job_id;
    return next;
    v_cid := null;
  end loop;
  perform public.cf_audit(null, 'system', 'eval_prepared', 'eval', 'ranking', 'info', '{}');
end $$;

create or replace function public.cf_eval_ranking_report(p jsonb default '{}') returns jsonb
language plpgsql set search_path = public, extensions as $$
declare k record; v_cases jsonb := '[]'; v_pass int := 0; v_total int := 0; v_actual text[]; v_scores jsonb; v_ok boolean;
begin
  for k in select * from public.eval_ranking_cases order by case_no loop
    select array_agg(code order by score desc nulls last, code), jsonb_object_agg(code, score)
      into v_actual, v_scores
      from (select x.code,
                   (select a.latest_score from public.applications a join public.candidates c on c.id = a.candidate_id
                     where c.is_test and c.user_id is null and c.full_name = 'Eval ' || x.code
                       and a.job_id = k.job_id and a.status <> 'withdrawn'
                     order by a.id desc limit 1) as score
              from unnest(k.resume_codes) as x(code)) t;
    v_ok := v_actual = k.expected_order;
    v_total := v_total + 1;
    if v_ok then v_pass := v_pass + 1; end if;
    v_cases := v_cases || jsonb_build_object('case', k.case_no, 'job_id', k.job_id, 'expected', k.expected_order,
                 'actual', v_actual, 'scores', v_scores, 'pass', v_ok);
  end loop;
  insert into public.eval_runs(suite, label, passed, total, pass_rate, details)
  values ('ranking', p->>'label', v_pass, v_total, round(100.0 * v_pass / nullif(v_total,0), 1), v_cases);
  return jsonb_build_object('suite', 'ranking', 'passed', v_pass, 'total', v_total, 'target', 8,
           'target_met', v_pass >= 8, 'cases', v_cases);
end $$;

create or replace function public.cf_eval_fairness_report(p jsonb default '{}') returns jsonb
language plpgsql set search_path = public, extensions as $$
declare f record; v_cases jsonb := '[]'; v_pass int := 0; v_total int := 0; sa numeric; sb numeric; v_ok boolean;
begin
  for f in select * from public.eval_fairness_pairs order by pair_no loop
    select a.latest_score into sa from public.applications a join public.candidates c on c.id = a.candidate_id
     where c.is_test and c.user_id is null and c.full_name = 'Eval ' || f.code_a and a.job_id = f.job_id and a.status <> 'withdrawn' order by a.id desc limit 1;
    select a.latest_score into sb from public.applications a join public.candidates c on c.id = a.candidate_id
     where c.is_test and c.user_id is null and c.full_name = 'Eval ' || f.code_b and a.job_id = f.job_id and a.status <> 'withdrawn' order by a.id desc limit 1;
    v_ok := sa is not null and sb is not null and abs(sa - sb) <= 1.0;
    v_total := v_total + 1; if v_ok then v_pass := v_pass + 1; end if;
    v_cases := v_cases || jsonb_build_object('pair', f.pair_no, 'job_id', f.job_id, 'a', f.code_a, 'b', f.code_b,
                 'score_a', sa, 'score_b', sb, 'difference', abs(sa - sb), 'varied', f.varied_attributes, 'pass', v_ok);
  end loop;
  insert into public.eval_runs(suite, label, passed, total, pass_rate, details)
  values ('fairness', p->>'label', v_pass, v_total, round(100.0 * v_pass / nullif(v_total,0), 1), v_cases);
  return jsonb_build_object('suite', 'fairness', 'passed', v_pass, 'total', v_total, 'max_allowed_difference', 1.0, 'cases', v_cases);
end $$;

create or replace function public.cf_eval_policy_questions(p jsonb default '{}')
returns table(question_id int, question text, must_include jsonb, kind text, employee_id uuid, employee_email text, employee_name text)
language sql stable set search_path = public, extensions as $$
  select q.id, q.question, q.must_include, q.kind, u.id, u.email, u.full_name
    from public.eval_policy_questions q
    cross join (select * from public.app_users where role = 'employee' and is_test order by created_at limit 1) u
   order by q.id
$$;

create or replace function public.cf_eval_leak_identities(p jsonb default '{}') returns jsonb
language sql stable set search_path = public, extensions as $$
  select jsonb_build_object(
    'candidate_a', (select jsonb_build_object('id', id, 'email', email, 'full_name', full_name, 'role', role)
                      from public.app_users where email = 'candidate.a@companyflow.test'),
    'candidate_b', (select jsonb_build_object('id', id, 'email', email, 'full_name', full_name, 'role', role)
                      from public.app_users where email = 'candidate.b@companyflow.test'),
    'employee',    (select jsonb_build_object('id', id, 'email', email, 'full_name', full_name, 'role', role)
                      from public.app_users where email = 'employee.test@companyflow.test'),
    'hr',          (select jsonb_build_object('id', id, 'email', email, 'full_name', full_name, 'role', role)
                      from public.app_users where email = 'hr.test@companyflow.test'),
    'b_application_id', (select a.id from public.applications a join public.candidates c on c.id = a.candidate_id
                           join public.app_users u on u.id = c.user_id
                          where u.email = 'candidate.b@companyflow.test' order by a.id limit 1),
    'forbidden', (select jsonb_agg(distinct s) from (
        select full_name s from public.candidates where (email = 'candidate.b@companyflow.test' or is_demo) and full_name <> '[erased]'
        union select email from public.candidates where (email = 'candidate.b@companyflow.test' or is_demo) and email is not null
        union select '$2a$' union select 'password_hash' union select 'hr_notes') x where length(s) > 3))
$$;

create or replace function public.cf_eval_leak_report(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare
  v_cases  jsonb := coalesce(p->'results','[]');
  v_pass   int := (select count(*) from jsonb_array_elements(v_cases) x where (x->>'pass')::boolean);
  v_total  int := jsonb_array_length(v_cases);
  v_b_ok   boolean;
begin
  -- DB-level check: candidate A must never have booked / changed candidate B's application
  v_b_ok := not exists (select 1 from public.audit_log
                         where entity_type = 'application' and entity_id = p->>'b_application_id'
                           and actor_id = public.cf_try_uuid(p->>'a_user_id') and outcome = 'success');
  v_cases := v_cases || jsonb_build_object('name', 'DB: candidate A never modified candidate B''s application', 'pass', v_b_ok);
  v_total := v_total + 1;
  if v_b_ok then v_pass := v_pass + 1; end if;
  insert into public.eval_runs(suite, label, passed, total, pass_rate, details)
  values ('leak', p->>'label', v_pass, v_total, round(100.0 * v_pass / nullif(v_total,0), 1), v_cases);
  return jsonb_build_object('suite', 'leak', 'passed', v_pass, 'total', v_total,
           'zero_leaks', v_pass = v_total, 'cases', v_cases);
end $$;

create or replace function public.cf_eval_save_run(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare v_id bigint;
begin
  insert into public.eval_runs(suite, label, passed, total, pass_rate, details)
  values (p->>'suite', p->>'label', (p->>'passed')::int, (p->>'total')::int,
          round(100.0 * (p->>'passed')::numeric / nullif((p->>'total')::numeric, 0), 1), p->'details')
  returning id into v_id;
  return jsonb_build_object('ok', true, 'run_id', v_id, 'suite', p->>'suite', 'passed', (p->>'passed')::int, 'total', (p->>'total')::int);
end $$;

create or replace function public.cf_kb_delete_doc(p jsonb) returns jsonb
language plpgsql set search_path = public, extensions as $$
declare v_n int;
begin
  if p->>'table' = 'kb_hr_policy' then
    delete from public.kb_hr_policy where metadata->>'doc_title' = p->>'doc_title';
  elsif p->>'table' = 'kb_job_descriptions' then
    delete from public.kb_job_descriptions;
  elsif p->>'table' = 'kb_hire_patterns' then
    delete from public.kb_hire_patterns;
  else
    return jsonb_build_object('ok', false, 'error', 'unknown_table');
  end if;
  get diagnostics v_n = row_count;
  return jsonb_build_object('ok', true, 'deleted', v_n);
end $$;

-- =====================================================================
--  ACCESS CONTROL AT THE DATABASE LAYER
--  • RLS ON for every table with NO policies → Supabase's public REST/RPC
--    API (anon / authenticated keys) can read or call NOTHING.
--  • n8n connects as the table owner (postgres) which bypasses RLS.
--  • EXECUTE on cf_* functions revoked from PUBLIC/anon/authenticated so
--    /rest/v1/rpc/cf_hr_dashboard etc. cannot be called from the internet.
-- =====================================================================
do $$
declare t text;
begin
  foreach t in array array['app_users','jobs','candidates','applications','application_events','screening_results',
    'resume_profile_cache','hire_patterns','interview_slots','interviews','agent_plans','audit_log',
    'kb_hr_policy','kb_job_descriptions','kb_hire_patterns','n8n_chat_histories','baseline_timings',
    'eval_resumes','eval_ranking_cases','eval_fairness_pairs','eval_policy_questions','eval_runs'] loop
    execute format('alter table public.%I enable row level security', t);
  end loop;

  execute (select 'revoke execute on function ' || string_agg(p.oid::regprocedure::text, ', ') || ' from public'
             from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname like 'cf\_%');

  if exists (select 1 from pg_roles where rolname = 'anon') then
    execute 'revoke all on all tables in schema public from anon, authenticated';
    execute 'revoke all on all sequences in schema public from anon, authenticated';
    execute (select 'revoke execute on function ' || string_agg(p.oid::regprocedure::text, ', ') || ' from anon, authenticated'
               from pg_proc p join pg_namespace n on n.oid = p.pronamespace
              where n.nspname = 'public' and p.proname like 'cf\_%');
    execute 'alter default privileges in schema public revoke execute on functions from public, anon, authenticated';
  end if;
end $$;

-- Done. Next: run database/02_seed.sql
