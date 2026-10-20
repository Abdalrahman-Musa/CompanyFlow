-- =====================================================================
--  CompanyFlow — File 2 of 3 : database/02_seed.sql
--  Run SECOND (after 01_schema.sql). Re-runnable.
--  Creates: demo + test users, 6 open roles (3 pairs of look-alike roles),
--  8 anonymised hire patterns, 2 weeks of interview slots, and a clearly
--  flagged (is_demo = true) recruitment history so the dashboard is not
--  empty on day one. Toggle "Include demo history" off in the dashboard to
--  see only REAL activity.
--
--  !! The passwords below are DEMO passwords. Change them (re-run
--  !! cf_admin_create_user with a new password) before any real use.
-- =====================================================================

-- ---------------------------------------------------------------------
-- 1. Users
-- ---------------------------------------------------------------------
select public.cf_admin_create_user(x) from (values
  ('{"email":"hr@companyflow.test","full_name":"Nadia Farouk","role":"hr","department":"Human Resources","password":"HrDemo#2026"}'::jsonb),
  ('{"email":"recruiter@companyflow.test","full_name":"Sherif Mansour","role":"hr","department":"Human Resources","password":"RecDemo#2026"}'),
  ('{"email":"employee@companyflow.test","full_name":"Omar Khaled","role":"employee","department":"Data & Analytics","password":"EmpDemo#2026"}'),
  ('{"email":"candidate@companyflow.test","full_name":"Youssef Adel","role":"candidate","password":"CandDemo#2026"}'),
  -- test identities used ONLY by CF-08 Evaluation Suite (tokens are signed directly, passwords never used)
  ('{"email":"candidate.a@companyflow.test","full_name":"Test Candidate Alpha","role":"candidate","is_test":true,"password":"TestOnly#A-2026"}'),
  ('{"email":"candidate.b@companyflow.test","full_name":"Test Candidate Bravo","role":"candidate","is_test":true,"password":"TestOnly#B-2026"}'),
  ('{"email":"employee.test@companyflow.test","full_name":"Test Employee","role":"employee","department":"Operations","is_test":true,"password":"TestOnly#E-2026"}'),
  ('{"email":"hr.test@companyflow.test","full_name":"Test HR Reviewer","role":"hr","department":"Human Resources","is_test":true,"password":"TestOnly#H-2026"}')
) v(x);

-- ---------------------------------------------------------------------
-- 2. Jobs — three pairs of SIMILAR BUT DISTINCT roles
--    SOC-L1 vs SOC-L2 | DA-JR vs BI-DEV | CS-EN vs TS-L1
-- ---------------------------------------------------------------------
insert into public.jobs (id, title, department, role_family, seniority, openings, summary, description,
  distinguishing_notes, must_have_skills, nice_to_have_skills, preferred_certifications,
  language_requirements, education_requirement, experience_keywords, min_years)
values
('SOC-L1', 'SOC Analyst – Tier 1', 'Cybersecurity', 'security_operations', 'junior', 2,
 'Monitor security alerts 24/7, triage them, and escalate real incidents to Tier 2.',
 $jd$SOC Analyst – Tier 1 (Junior) — Cybersecurity Department, Cairo (Hybrid, rotating shifts)

About the role
You will be the first line of defence in the CompanyFlow Security Operations Center. You watch the SIEM, decide quickly whether an alert is a false positive or a real threat, document what you saw, and escalate confirmed incidents to Tier 2 with a clean, well-written ticket.

Responsibilities
- Monitor SIEM dashboards and alert queues (Splunk / Microsoft Sentinel) during your shift.
- Triage alerts: validate, enrich with threat intelligence, classify severity, close false positives with notes.
- Open and update incident tickets; escalate confirmed incidents to Tier 2 following the runbook.
- Analyse Windows event logs, firewall and proxy logs for suspicious activity.
- Handle reported phishing emails: header analysis, URL/attachment sandboxing, blocking indicators.
- Write a clear shift hand-over report.

Requirements (must have)
- SIEM monitoring experience (lab, internship or job).
- Alert triage and incident ticketing.
- Networking fundamentals (TCP/IP, DNS, HTTP, common ports).
- Windows event log analysis.
- Professional written English for tickets; Arabic native or fluent.

Nice to have
- Phishing email analysis, EDR console experience, basic Python or PowerShell scripting, MITRE ATT&CK familiarity, Linux command line.
- Certifications: CompTIA Security+, CyberOps Associate, BTL1, or SOC learning paths (TryHackMe / LetsDefend).

Experience: 0–2 years. Fresh graduates with strong hands-on SOC labs are encouraged to apply.$jd$,
 'Tier 1 MONITORS and TRIAGES alerts and ESCALATES; it does not lead investigations, threat hunting or containment (that is SOC-L2). 0–2 years. Shift-based.',
 '[{"label":"SIEM monitoring","aliases":["siem","splunk","qradar","microsoft sentinel","azure sentinel","sentinel","elastic siem","wazuh","arcsight","logrhythm"]},
   {"label":"Alert triage","aliases":["alert triage","triage","triaged","false positive","false positives","alert analysis","alert investigation"]},
   {"label":"Incident ticketing & escalation","aliases":["ticketing","incident ticket","escalation","escalated","servicenow","jira service","the hive","thehive","incident tickets"]},
   {"label":"Networking fundamentals","aliases":["tcp/ip","tcp ip","networking","dns","osi model","subnetting","ccna","network fundamentals"]},
   {"label":"Windows event log analysis","aliases":["windows event log","windows event logs","event viewer","sysmon","event id","windows logs"]}]',
 '[{"label":"Phishing analysis","aliases":["phishing","email header","email analysis"]},
   {"label":"EDR","aliases":["edr","crowdstrike","defender for endpoint","sentinelone","carbon black"]},
   {"label":"Scripting (Python/PowerShell)","aliases":["python","powershell","bash"]},
   {"label":"MITRE ATT&CK","aliases":["mitre","att&ck","attack framework"]},
   {"label":"Linux command line","aliases":["linux","bash","ubuntu","kali"]}]',
 '[{"label":"CompTIA Security+","aliases":["security+","security plus","sec+"]},
   {"label":"Cisco CyberOps Associate","aliases":["cyberops"]},
   {"label":"BTL1","aliases":["btl1","blue team level 1"]},
   {"label":"SOC learning path","aliases":["tryhackme","letsdefend","soc level 1"]}]',
 '[{"language":"english","min_level":"professional"},{"language":"arabic","min_level":"fluent"}]',
 '{"min_level":"bachelor","fields":["computer science","information security","cybersecurity","computer engineering","information technology","communications"],"required":false}',
 '["soc","security","cyber","noc","network","incident","siem","blue team","analyst"]', 0),

('SOC-L2', 'SOC Analyst – Tier 2 / Incident Responder', 'Cybersecurity', 'security_operations', 'mid', 1,
 'Investigate escalated incidents end to end, contain threats, hunt proactively and tune detections.',
 $jd$SOC Analyst – Tier 2 / Incident Responder (Mid-level) — Cybersecurity Department, Cairo (Hybrid)

About the role
Tier 2 owns the incident once Tier 1 escalates it. You investigate deeply, scope the impact, contain the threat with EDR and network controls, run threat hunts, and improve detections so the same attack is caught earlier next time. You mentor Tier 1 analysts.

Responsibilities
- Lead investigation of escalated incidents: timeline reconstruction, scoping, root cause.
- Containment and eradication using EDR (CrowdStrike / Defender for Endpoint) and firewall/proxy controls.
- Proactive threat hunting using hypotheses mapped to MITRE ATT&CK.
- Write and tune SIEM correlation rules and Sigma detections; reduce false positives.
- Malware triage (static and basic dynamic analysis) and IOC extraction.
- Produce incident reports and lessons learned; mentor Tier 1.

Requirements (must have)
- 3+ years in a SOC or incident response role.
- Incident response leadership (containment, eradication, recovery).
- Advanced SIEM querying and correlation rule writing (SPL, KQL, AQL).
- Threat hunting.
- EDR investigation and response.
- Professional English for incident reports.

Nice to have
- Digital forensics (memory/disk), malware analysis, YARA, Sigma, SOAR playbooks, cloud security logs (Azure/AWS).
- Certifications: GCIH, CySA+, BTL2, eCIR, GCFA.

Experience: 3–6 years.$jd$,
 'Tier 2 INVESTIGATES, CONTAINS and HUNTS; requires 3+ years. Pure alert monitoring/triage without investigation leadership fits SOC-L1, not this role.',
 '[{"label":"Incident response","aliases":["incident response","incident responder","containment","eradication","ir lead","incident handling","dfir"]},
   {"label":"Advanced SIEM querying & correlation rules","aliases":["correlation rule","correlation rules","spl","kql","aql","detection engineering","use case development","sigma"]},
   {"label":"Threat hunting","aliases":["threat hunting","threat hunt","hunting"]},
   {"label":"EDR investigation","aliases":["edr","crowdstrike","defender for endpoint","sentinelone","carbon black"]},
   {"label":"Log & timeline analysis","aliases":["log analysis","timeline","root cause","forensic timeline","scoping"]}]',
 '[{"label":"Digital forensics","aliases":["forensics","memory forensics","volatility","disk forensics","autopsy","ftk"]},
   {"label":"Malware analysis","aliases":["malware analysis","malware triage","reverse engineering","sandbox"]},
   {"label":"YARA","aliases":["yara"]},
   {"label":"SOAR","aliases":["soar","playbook","playbooks","xsoar","shuffle"]},
   {"label":"Cloud security logs","aliases":["azure","aws","cloudtrail","entra"]}]',
 '[{"label":"GCIH","aliases":["gcih"]},{"label":"CySA+","aliases":["cysa"]},{"label":"BTL2","aliases":["btl2"]},
   {"label":"eCIR","aliases":["ecir"]},{"label":"GCFA","aliases":["gcfa"]}]',
 '[{"language":"english","min_level":"professional"}]',
 '{"min_level":"bachelor","fields":["computer science","information security","cybersecurity","computer engineering","information technology"],"required":false}',
 '["soc","security","cyber","incident","responder","dfir","threat","siem","analyst"]', 3),

('DA-JR', 'Junior Data Analyst', 'Data & Analytics', 'data_analytics', 'junior', 2,
 'Turn business questions into SQL queries, clean data, and build clear dashboards and reports.',
 $jd$Junior Data Analyst — Data & Analytics, Cairo (Hybrid)

About the role
You will answer business questions for the Sales, Operations and HR teams. You pull data with SQL, clean it, analyse it in Excel or Python, and present the answer in a clear dashboard or short report. You are the person who explains WHAT the numbers mean.

Responsibilities
- Write SQL queries to extract and join data from the company databases.
- Clean and validate data; spot and explain anomalies.
- Build and maintain dashboards in Power BI or Tableau for business users.
- Run descriptive statistics, trend analysis and simple A/B test readouts.
- Present findings to non-technical stakeholders in plain language.

Requirements (must have)
- SQL (joins, aggregations, window functions are a plus).
- Excel (pivot tables, lookups, charts).
- Data visualisation in Power BI or Tableau.
- Basic statistics.
- Data cleaning.
- Professional English; Arabic fluent.

Nice to have
- Python (pandas), DAX, Google Analytics, A/B testing, storytelling with data.
- Certifications: Google Data Analytics, Microsoft PL-300.

Experience: 0–2 years. Internships and portfolio projects count.$jd$,
 'Data Analyst ANSWERS BUSINESS QUESTIONS with analysis and reports; it does NOT own data models, ETL pipelines or the data warehouse (that is BI-DEV). Not a machine-learning role.',
 '[{"label":"SQL","aliases":["sql","mysql","postgresql","postgres","sql server","t-sql","bigquery"]},
   {"label":"Excel","aliases":["excel","pivot table","pivot tables","vlookup","xlookup","spreadsheets"]},
   {"label":"Data visualisation (Power BI / Tableau)","aliases":["power bi","powerbi","tableau","looker studio","data visualization","data visualisation","dashboards","dashboard"]},
   {"label":"Basic statistics","aliases":["statistics","statistical","descriptive statistics","hypothesis testing","regression"]},
   {"label":"Data cleaning","aliases":["data cleaning","data cleansing","data wrangling","data preparation","data validation"]}]',
 '[{"label":"Python (pandas)","aliases":["pandas","python"]},
   {"label":"DAX","aliases":["dax"]},
   {"label":"Google Analytics","aliases":["google analytics","ga4"]},
   {"label":"A/B testing","aliases":["a/b test","a/b testing","ab testing","experimentation"]},
   {"label":"Data storytelling","aliases":["storytelling","presentation","presented findings","stakeholder"]}]',
 '[{"label":"Google Data Analytics","aliases":["google data analytics"]},{"label":"Microsoft PL-300","aliases":["pl-300","pl300","power bi data analyst associate"]}]',
 '[{"language":"english","min_level":"professional"},{"language":"arabic","min_level":"fluent"}]',
 '{"min_level":"bachelor","fields":["statistics","computer science","business","economics","commerce","mathematics","information systems","engineering"],"required":false}',
 '["data","analyst","analytics","reporting","business intelligence","bi","insights"]', 0),

('BI-DEV', 'BI Developer', 'Data & Analytics', 'data_analytics', 'mid', 1,
 'Design star-schema data models, build ETL pipelines and enterprise Power BI semantic models.',
 $jd$BI Developer (Mid-level) — Data & Analytics, Cairo (Hybrid)

About the role
You build the foundations that analysts use. You design dimensional data models, build and schedule ETL pipelines into the data warehouse, and publish governed Power BI semantic models with well-written DAX and row-level security. You are the person who makes the data RELIABLE, FAST and REUSABLE.

Responsibilities
- Design star-schema / dimensional models (facts, dimensions, slowly changing dimensions).
- Build ETL/ELT pipelines (SSIS, Azure Data Factory or similar) into the warehouse.
- Develop Power BI datasets/semantic models, complex DAX measures and row-level security.
- Optimise query and report performance; manage refresh schedules and gateways.
- Document data lineage and definitions.

Requirements (must have)
- 2+ years building BI solutions.
- Power BI development.
- DAX.
- Dimensional data modelling (star schema).
- Advanced SQL.
- ETL tools (SSIS / Azure Data Factory / similar).

Nice to have
- Azure Synapse / Fabric, dbt, Python, performance tuning, data warehouse design (Kimball).
- Certifications: Microsoft PL-300, DP-203 / DP-600.

Experience: 2–5 years.$jd$,
 'BI Developer BUILDS data models, ETL pipelines and semantic models (engineering of the BI layer); requires 2+ years. Ad-hoc analysis and reporting only fits DA-JR.',
 '[{"label":"Power BI development","aliases":["power bi","powerbi","power bi desktop","power bi service"]},
   {"label":"DAX","aliases":["dax"]},
   {"label":"Dimensional modelling (star schema)","aliases":["star schema","dimensional model","dimensional modelling","dimensional modeling","kimball","fact table","fact tables","snowflake schema"]},
   {"label":"Advanced SQL","aliases":["sql","t-sql","stored procedure","stored procedures","sql server"]},
   {"label":"ETL tools","aliases":["etl","elt","ssis","azure data factory","adf","informatica","talend","data pipeline","data pipelines"]}]',
 '[{"label":"Azure Synapse / Fabric","aliases":["synapse","microsoft fabric","fabric"]},
   {"label":"dbt","aliases":["dbt"]},
   {"label":"Python","aliases":["python"]},
   {"label":"Performance tuning","aliases":["performance tuning","query optimization","optimisation","indexing"]},
   {"label":"Data warehouse design","aliases":["data warehouse","warehouse","dwh"]}]',
 '[{"label":"Microsoft PL-300","aliases":["pl-300","pl300"]},{"label":"DP-203 / DP-600","aliases":["dp-203","dp203","dp-600","dp600"]}]',
 '[{"language":"english","min_level":"professional"}]',
 '{"min_level":"bachelor","fields":["computer science","information systems","engineering","statistics","computer engineering"],"required":false}',
 '["bi","business intelligence","data","etl","warehouse","power bi","developer","analytics"]', 2),

('CS-EN', 'Customer Service Representative – English Account', 'Customer Operations', 'customer_operations', 'junior', 5,
 'Handle inbound customer calls, chats and emails for an international English-speaking account.',
 $jd$Customer Service Representative – English Account (Junior) — Customer Operations (Outsourcing), Cairo (On-site, shifts)

About the role
You are the voice of our international client. You answer customers by phone, chat and email about orders, accounts and billing, solve their problem on first contact whenever possible, and log every interaction in the CRM.

Responsibilities
- Handle inbound calls, live chats and emails from English-speaking customers.
- Resolve account, order, delivery and billing questions; process refunds within policy.
- Log every interaction accurately in the CRM (Zendesk / Salesforce Service Cloud).
- Meet KPIs: CSAT, first-contact resolution, average handling time.
- Escalate complex cases to the right team.

Requirements (must have)
- Excellent spoken and written English (C1 or above).
- Customer communication skills (empathy, de-escalation).
- CRM / ticketing tool usage.
- Problem solving.
- Typing 35+ WPM.

Nice to have
- A second foreign language (German or French), previous call-centre / BPO experience, Zendesk or Salesforce, upselling.

Experience: 0–2 years. Fresh graduates with excellent English are welcome.$jd$,
 'Customer Service handles ACCOUNT, ORDER and BILLING questions with strong English; it does NOT troubleshoot technical problems (that is TS-L1).',
 '[{"label":"Excellent English (C1+)","aliases":["c1","c2","ielts","toefl","native english","fluent english","excellent english"]},
   {"label":"Customer communication","aliases":["customer service","customer support","customer care","customer facing","customer-facing","de-escalation","empathy","call center","call centre","contact center"]},
   {"label":"CRM / ticketing tools","aliases":["crm","zendesk","salesforce","freshdesk","hubspot","ticketing","servicenow"]},
   {"label":"Problem solving","aliases":["problem solving","problem-solving","resolved","resolution","first contact resolution","fcr"]},
   {"label":"Fast typing","aliases":["wpm","typing"]}]',
 '[{"label":"Second foreign language","aliases":["german","french","spanish","italian"]},
   {"label":"BPO / call-centre experience","aliases":["bpo","call center","call centre","contact center","outsourcing"]},
   {"label":"Zendesk / Salesforce","aliases":["zendesk","salesforce"]},
   {"label":"Upselling","aliases":["upsell","upselling","sales"]}]',
 '[]',
 '[{"language":"english","min_level":"fluent"}]',
 '{"min_level":"secondary","fields":[],"required":false}',
 '["customer","service","support","call","contact","bpo","agent","care","sales"]', 0),

('TS-L1', 'Technical Support Specialist – L1', 'IT Services', 'technical_support', 'junior', 2,
 'Troubleshoot hardware, software, account and network issues for client users and resolve tickets.',
 $jd$Technical Support Specialist – L1 (Junior) — IT Services (Outsourcing), Cairo (Hybrid, shifts)

About the role
You fix things. Client employees contact you when their laptop, Microsoft 365 account, VPN or printer stops working. You troubleshoot remotely, resolve the ticket or escalate it to L2 with clear notes, and keep the knowledge base up to date.

Responsibilities
- Troubleshoot Windows and macOS issues, Microsoft 365 / Outlook, VPN and Wi-Fi problems.
- Manage user accounts and password resets in Active Directory / Entra ID.
- Work tickets in ServiceNow or Jira Service Management within SLA.
- Remote support via remote-desktop tools; install and configure software.
- Document fixes in the knowledge base; escalate to L2 with clear notes.

Requirements (must have)
- 1+ year in IT/helpdesk/technical support.
- Windows/macOS troubleshooting.
- Active Directory / Microsoft 365 administration basics.
- Networking basics (IP, DNS, DHCP, VPN, Wi-Fi).
- Ticketing systems (ServiceNow / Jira).
- Professional English.

Nice to have
- CompTIA A+, ITIL Foundation, PowerShell scripting, Intune, basic Linux.

Experience: 1–3 years.$jd$,
 'Technical Support TROUBLESHOOTS devices, accounts and networks (technical fixes); requires 1+ year of IT support. Billing/order questions fit CS-EN.',
 '[{"label":"Windows / macOS troubleshooting","aliases":["troubleshooting","troubleshoot","troubleshot","windows","macos","desktop support","hardware"]},
   {"label":"Active Directory / Microsoft 365","aliases":["active directory","entra","azure ad","microsoft 365","office 365","o365","exchange online","password reset","password resets"]},
   {"label":"Networking basics","aliases":["dns","dhcp","vpn","wi-fi","wifi","tcp/ip","networking","lan"]},
   {"label":"Ticketing systems","aliases":["servicenow","jira","ticketing","freshservice","sla","tickets","helpdesk tickets"]},
   {"label":"Remote support","aliases":["remote support","remote desktop","teamviewer","anydesk","rdp"]}]',
 '[{"label":"PowerShell","aliases":["powershell"]},
   {"label":"Intune / endpoint management","aliases":["intune","sccm","endpoint manager"]},
   {"label":"Linux basics","aliases":["linux","ubuntu"]},
   {"label":"Knowledge base writing","aliases":["knowledge base","documentation","kb articles"]}]',
 '[{"label":"CompTIA A+","aliases":["a+","comptia a"]},{"label":"ITIL Foundation","aliases":["itil"]}]',
 '[{"language":"english","min_level":"professional"}]',
 '{"min_level":"diploma","fields":["computer science","information technology","engineering","computer engineering"],"required":false}',
 '["support","helpdesk","help desk","it","technical","service desk","desktop","technician","noc"]', 1)
on conflict (id) do update set
  title = excluded.title, department = excluded.department, role_family = excluded.role_family,
  seniority = excluded.seniority, openings = excluded.openings, summary = excluded.summary,
  description = excluded.description, distinguishing_notes = excluded.distinguishing_notes,
  must_have_skills = excluded.must_have_skills, nice_to_have_skills = excluded.nice_to_have_skills,
  preferred_certifications = excluded.preferred_certifications, language_requirements = excluded.language_requirements,
  education_requirement = excluded.education_requirement, experience_keywords = excluded.experience_keywords,
  min_years = excluded.min_years, status = 'open';

-- ---------------------------------------------------------------------
-- 3. Past successful hire PATTERNS (anonymised). Only skills/experience
--    patterns — no names, gender, age, university, address, photo.
-- ---------------------------------------------------------------------
insert into public.hire_patterns (id, role_family, job_id_hint, seniority, pattern_summary, key_skills, typical_years, success_signals, hired_year) values
('HP-001','security_operations','SOC-L1','junior',
 'Tier 1 analysts who passed probation quickly had hands-on SIEM practice (home lab or internship), wrote clear triage notes, and completed a structured blue-team learning path.',
 '["splunk","alert triage","windows event logs","phishing","tcp/ip","ticketing"]', 0.5,
 '["home lab with SIEM","SOC internship","clear incident write-ups","blue-team learning path completed"]', 2025),
('HP-002','security_operations','SOC-L1','junior',
 'Strong Tier 1 hires sometimes came from NOC roles: solid networking plus basic SIEM exposure; they ramped up fastest on network-based alerts.',
 '["networking","tcp/ip","siem","firewall logs","ticketing","escalation"]', 1.5,
 '["NOC shift experience","networking certification","comfortable with shift work"]', 2024),
('HP-003','security_operations','SOC-L2','mid',
 'Tier 2 responders who succeeded had led real incident containment with EDR, wrote detection rules, and could explain an incident timeline to management.',
 '["incident response","edr","threat hunting","correlation rules","kql","malware triage"]', 4,
 '["led containment of real incidents","authored detection rules","mentored juniors"]', 2025),
('HP-004','data_analytics','DA-JR','junior',
 'Junior analysts who performed well had a public portfolio of SQL + dashboard projects and could explain insights to non-technical managers.',
 '["sql","excel","power bi","data cleaning","statistics","storytelling"]', 0.5,
 '["portfolio of dashboards","presented findings to stakeholders","internship with real data"]', 2025),
('HP-005','data_analytics','BI-DEV','mid',
 'BI developers who succeeded had designed star schemas end-to-end, maintained scheduled ETL pipelines, and optimised slow Power BI models.',
 '["star schema","dax","power bi","ssis","azure data factory","sql"]', 3,
 '["owned a semantic model in production","reduced report refresh time","documented data lineage"]', 2024),
('HP-006','customer_operations','CS-EN','junior',
 'Customer service hires with the best CSAT combined C1+ English with prior customer-facing work (any industry) and calm de-escalation.',
 '["english c1","customer service","crm","de-escalation","problem solving"]', 1,
 '["customer-facing experience","high CSAT history","second language a plus"]', 2025),
('HP-007','technical_support','TS-L1','junior',
 'L1 technical support hires who ramped up quickly had helpdesk experience with Active Directory and Microsoft 365 and kept tidy ticket notes.',
 '["active directory","microsoft 365","troubleshooting","servicenow","vpn","remote support"]', 1.5,
 '["met SLA consistently","wrote knowledge-base articles","A+ or ITIL"]', 2024),
('HP-008','technical_support','TS-L1','junior',
 'Some strong L1 hires moved from customer service into technical support after self-study; customer empathy plus troubleshooting basics worked well.',
 '["troubleshooting","customer service","ticketing","windows","networking basics"]', 1,
 '["self-taught troubleshooting","customer empathy","certification in progress"]', 2025)
on conflict (id) do update set pattern_summary = excluded.pattern_summary, key_skills = excluded.key_skills,
  typical_years = excluded.typical_years, success_signals = excluded.success_signals;

-- ---------------------------------------------------------------------
-- 4. Interview slots for the next 14 days (Sun–Thu, 10:00/12:00/14:00 Cairo)
-- ---------------------------------------------------------------------
select public.cf_generate_slots('{"days":14,"interviewer_name":"Nadia Farouk (HR)","interviewer_email":"hr@companyflow.test","actor_role":"system"}');
select public.cf_generate_slots('{"days":14,"interviewer_name":"Sherif Mansour (Recruiter)","interviewer_email":"recruiter@companyflow.test","actor_role":"system"}');

-- ---------------------------------------------------------------------
-- 5. Fixture for the leak test: Candidate B owns one shortlisted application
-- ---------------------------------------------------------------------
do $$
declare v_cid bigint; v_aid bigint;
begin
  select c.id into v_cid from public.candidates c join public.app_users u on u.id = c.user_id
   where u.email = 'candidate.b@companyflow.test';
  if not exists (select 1 from public.applications where candidate_id = v_cid) then
    insert into public.applications(candidate_id, job_id, status, resume_text, resume_format, resume_chars,
           latest_score, latest_band, screened_at, shortlisted_at, is_test, hr_notes)
    values (v_cid, 'SOC-L1', 'shortlisted',
            'Test Candidate Bravo — SOC analyst intern. Splunk, alert triage, TCP/IP, Windows event logs, ticketing. Security+.',
            'text', 110, 91.0, 'Strong match', now() - interval '2 days', now() - interval '1 day', true,
            'CONFIDENTIAL HR NOTE: strong communicator — leak-test canary')
    returning id into v_aid;
    insert into public.application_events(application_id, from_status, to_status, actor_role, reason)
    values (v_aid, null, 'applied', 'candidate', 'fixture'), (v_aid, 'applied', 'shortlisted', 'hr', 'fixture');
  end if;
end $$;

-- ---------------------------------------------------------------------
-- 6. DEMO recruitment history (is_demo = true). ~70 applications over the
--    last 80 days with realistic stage progression and timings.
-- ---------------------------------------------------------------------
do $$
declare
  fm text[] := array['Ahmed','Mohamed','Omar','Youssef','Karim','Mostafa','Hassan','Ali','Tarek','Ziad','Amr','Khaled','Mahmoud','Seif'];
  ff text[] := array['Mariam','Nour','Salma','Habiba','Farida','Aya','Yasmin','Laila','Malak','Rana','Dina','Heba','Sara','Menna'];
  ln text[] := array['Hassan','Mahmoud','Ibrahim','Abdelrahman','El-Sayed','Fathy','Gamal','Saleh','Mansour','Kamel','Naguib','Rashad','Soliman','Zaki'];
  jb text[] := array['SOC-L1','SOC-L1','SOC-L2','DA-JR','DA-JR','BI-DEV','CS-EN','CS-EN','CS-EN','TS-L1','TS-L1'];
  i int; v_cid bigint; v_aid bigint; v_job text; v_name text;
  t_app timestamptz; t_scr timestamptz; t_sl timestamptz; t_int timestamptz; t_iv timestamptz; t_off timestamptz; t_hire timestamptz; t_rej timestamptz;
  v_score numeric; v_band text; v_status text;
begin
  if exists (select 1 from public.candidates where is_demo) then return; end if;
  perform setseed(0.2026);
  for i in 1..72 loop
    v_name := case when random() < 0.5 then fm[1 + floor(random()*14)::int] else ff[1 + floor(random()*14)::int] end
              || ' ' || ln[1 + floor(random()*14)::int];
    insert into public.candidates(full_name, email, is_demo, consent_given_at, consent_version)
    values (v_name, 'demo.candidate' || i || '@example.com', true, now(), 'v1') returning id into v_cid;

    v_job   := jb[1 + floor(random()*11)::int];
    t_app   := now() - ((random() * 78) + 1) * interval '1 day';
    t_scr   := t_app + (8 + random()*25) * interval '1 second';
    v_score := round((30 + random()*65)::numeric, 1);
    v_band  := case when v_score >= 75 then 'Strong match' when v_score >= 60 then 'Potential match'
                    when v_score >= 40 then 'Weak match' else 'Not a match' end;
    v_status := 'screened'; t_sl := null; t_int := null; t_iv := null; t_off := null; t_hire := null; t_rej := null;

    if v_score >= 62 and random() < 0.85 then
      t_sl := t_scr + (1 + random()*3) * interval '1 day';
      if t_sl < now() then v_status := 'shortlisted'; else t_sl := null; end if;
    elsif random() < 0.7 then
      t_rej := t_scr + (2 + random()*5) * interval '1 day';
      if t_rej < now() then v_status := 'rejected'; else t_rej := null; end if;
    end if;
    if t_sl is not null then
      t_int := t_sl + (1 + random()*3) * interval '1 day';
      if t_int < now() then v_status := 'interview_scheduled'; else t_int := null; end if;
    end if;
    if t_int is not null then
      t_iv := t_int + (2 + random()*5) * interval '1 day';
      if t_iv < now() then v_status := 'interviewed'; else t_iv := null; end if;
    end if;
    if t_iv is not null then
      if random() < 0.55 then
        t_off := t_iv + (1 + random()*4) * interval '1 day';
        if t_off < now() then v_status := 'offer'; else t_off := null; end if;
      else
        t_rej := t_iv + (1 + random()*3) * interval '1 day';
        if t_rej < now() then v_status := 'rejected'; else t_rej := null; end if;
      end if;
    end if;
    if t_off is not null then
      if random() < 0.8 then
        t_hire := t_off + (2 + random()*6) * interval '1 day';
        if t_hire < now() then v_status := 'hired'; else t_hire := null; end if;
      else
        t_rej := null; v_status := 'withdrawn';
      end if;
    end if;

    insert into public.applications(candidate_id, job_id, status, resume_text, resume_format, resume_chars, latest_score, latest_band,
           applied_at, screened_at, shortlisted_at, interview_scheduled_at, interviewed_at, offer_at, hired_at, rejected_at,
           withdrawn_at, status_updated_at, is_demo)
    values (v_cid, v_job, v_status, '[demo record — no résumé stored]', 'demo', 0, v_score, v_band,
            t_app, t_scr, t_sl, t_int, t_iv, t_off, t_hire, t_rej,
            case when v_status = 'withdrawn' then t_off + interval '2 days' end,
            greatest(t_app, t_scr, coalesce(t_sl, t_app), coalesce(t_int, t_app), coalesce(t_iv, t_app),
                     coalesce(t_off, t_app), coalesce(t_hire, t_app), coalesce(t_rej, t_app)), true)
    returning id into v_aid;

    insert into public.screening_results(application_id, job_id, score, band, recommendation, breakdown, explanation,
           rubric_version, model, duration_ms, is_demo, created_at)
    values (v_aid, v_job, v_score, v_band,
            case when v_score >= 75 then 'Shortlist for HR review' when v_score >= 60 then 'HR to review' else 'Low fit — HR to confirm' end,
            '{"demo":true}', 'Seeded demo record (no real screening).', 'cf-rubric-1.0', 'demo',
            (9000 + random()*19000)::int, true, t_scr);

    insert into public.application_events(application_id, from_status, to_status, actor_role, reason, review_seconds, at)
    select v_aid, s.f, s.t, s.r, 'demo', s.rv, s.at
      from (values (null::text, 'applied', 'candidate', null::int, t_app),
                   ('applied', 'screened', 'system', null, t_scr),
                   ('screened', 'shortlisted', 'hr', (60 + random()*180)::int, t_sl),
                   ('screened', 'rejected', 'hr', (40 + random()*120)::int, case when t_sl is null then t_rej end),
                   ('shortlisted', 'interview_scheduled', 'candidate', null, t_int),
                   ('interview_scheduled', 'interviewed', 'hr', null, t_iv),
                   ('interviewed', 'offer', 'hr', null, t_off),
                   ('interviewed', 'rejected', 'hr', null, case when t_sl is not null then t_rej end),
                   ('offer', 'hired', 'hr', null, t_hire)) s(f, t, r, rv, at)
     where s.at is not null;
  end loop;

  -- demo manual-baseline timings (replace with your REAL timing study via the CF-08 form)
  insert into public.baseline_timings(reviewer, resume_ref, job_id, minutes, decision, is_demo)
  select 'Demo reviewer ' || (1 + (g % 3)), 'DEMO-' || g, (array['SOC-L1','DA-JR','CS-EN'])[1 + (g % 3)],
         round((6 + random()*8)::numeric, 1), 'demo', true
    from generate_series(1, 15) g;
end $$;

select public.cf_audit(null, 'system', 'seed_loaded', 'system', '02_seed.sql', 'info',
         jsonb_build_object('jobs', (select count(*) from public.jobs), 'users', (select count(*) from public.app_users)));

-- Done. Next: run database/03_eval_seed.sql
