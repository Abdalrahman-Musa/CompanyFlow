# CompanyFlow — How the matching logic avoids a named bias risk

**Deliverable:** "A short write-up on how the matching logic avoids a specific, named real bias risk."

## 1. The named risk: historical-hire bias that turns gender proxies into score penalties

**Real-world case.** In 2018 Reuters reported that Amazon scrapped an experimental AI recruiting engine. It had been
trained on ten years of the company's own past hires, most of them men, and it learned to **down-rank résumés containing
the word "women's"** (as in "women's chess club captain") and graduates of two all-women colleges. No one programmed it to
discriminate: it copied the pattern hidden in "what our past successful hires looked like."

**Why the risk is ours too.** The CompanyFlow brief asks for exactly the ingredient that broke Amazon's tool:
*"a (sample, anonymised) archive of past successful hire profile patterns."* Egyptian CVs also carry strong
**gender and age proxies** that most Western CVs do not:

| Proxy on Egyptian CVs | What it leaks |
|---|---|
| `Military status: Completed / Exempted` | gender (only men have one), sometimes age |
| Photo, `Mr./Mrs./Miss`, gendered pronouns | gender |
| `Date of birth`, `Age: 22` | age |
| `Marital status`, `Number of children` | gender + family status (maternity penalty) |
| `Religion`, `Nationality`, `National ID` | religion, origin, and (via the 14-digit ID) gender and birth date |

If any of these reach a model that also learns from past hires, the Amazon failure mode repeats.

## 2. How the matching logic blocks it — five design decisions

**① Redact before any AI sees the résumé (CF-03 · "Validate & Redact Résumé").**
Lines starting with date of birth, age, gender, marital or military status, religion, nationality, national ID,
children or address are **deleted**, in English and Arabic. Then emails, phones, links and 14-digit national IDs are
masked, honorifics and gendered words are neutralised, and the name line becomes `[CANDIDATE]`. The LLM and the
scorer only ever receive this redacted text. HR sees the same redacted text until the candidate is shortlisted.

**② The LLM extracts facts. It never scores (CF-03 · "Extract Résumé Profile").**
The model fills a fixed JSON schema (skills with *verbatim evidence quotes*, roles with months, education level,
languages) and is told the résumé is data, not instructions. A skill only counts if its evidence quote really exists in
the résumé text. That blocks hallucinated skills and résumé-embedded prompt injection.

**③ A deterministic, published rubric scores against the job's *stated* requirements (CF-03 · "Score Against Rubric").**

| Criterion | Max | Source |
|---|---|---|
| Must-have skills | 40 | `jobs.must_have_skills` |
| Relevant experience (months in matching roles) | 20 | `jobs.min_years`, `experience_keywords` |
| Nice-to-have skills | 15 | `jobs.nice_to_have_skills` |
| Languages (level vs requirement) | 10 | `jobs.language_requirements` |
| Education level + field (never the institution) | 6 | `jobs.education_requirement` |
| Preferred certifications | 4 | `jobs.preferred_certifications` |
| **Past-hire pattern alignment** | **5 (capped)** | `kb_hire_patterns` via RAG |

Every point is explainable (matched/missing items, evidence, years) and stored with the decision in the audit log.

**④ Past-hire data is skills-only, filtered and capped.**
The `hire_patterns` table has **no demographic columns at all**, only skill and experience patterns (for example
"Tier 1 hires had home-lab SIEM practice"). Retrieval is filtered to the job's role family, and the pattern criterion
can move a score by **at most 5 of 100 points**. It is a tie-breaker, never a reason to reject. Amazon's model learned
*everything* from history. Ours learns *nothing* from history except a bounded, inspectable skills hint.

**⑤ Humans decide, and the rules make proxy decisions hard.**
- No automatic rejection exists. Low scores say "HR to confirm".
- A rejection is refused by the database unless it carries a job-related reason (`cf_set_application_status`).
- No maximum-years penalty and no "over-qualified" rule (both are age proxies), and no university prestige.
- **Blind review:** HR sees `CAND-0042` until shortlisting. Revealing an identity earlier is a deliberate click that is
  logged as `pii_access`.
- The HR Copilot's system prompt forbids protected characteristics in reasoning. The planner forbids them in plans.

## 3. Evidence: a real counterfactual test (CF-08 · Fairness)

The evaluation suite screens **twin résumés** that are identical except for protected-attribute lines:

| Pair | Role | What differs between the twins | Pass rule |
|---|---|---|---|
| R01 vs R01F | SOC-L1 | name, gender, date of birth, marital status, **military status** | score difference ≤ 1 |
| R06 vs R06A | BI-DEV | date of birth (age 25 vs 45), **religion**, marital status, children | score difference ≤ 1 |

Because redaction removes those lines, both twins produce the **same redacted text**. The SHA-256 cache key then
matches, the same extracted profile is reused, and the scores are identical. In our offline test run both pairs scored
exactly the same (91.4 / 91.4 and 97.0 / 97.0). **Re-run the suite with live Gemini and record the result here before
submission.**

## 4. Residual risks we accept and monitor

- **Language requirements** (for example "Arabic fluent") can exclude non-native speakers. Each one must be
  justified by the job (customer contact, team language) and is published on the job card.
- **Graduation and job years stay in the text** because experience needs dates. Age can still be inferred, but the
  rubric gives no points for it in either direction.
- **Alias lists** (which words count as "SIEM") can favour some vocabularies. HR reviews them per role, and the LLM
  normalises paraphrases and Arabic terms into standard English skill names.
- **We cannot measure group outcomes directly** because we deliberately never store gender or age. A future step is
  voluntary, separately stored self-identification for an adverse-impact (four-fifths rule) check, kept away from
  screening.

*Sources:* Reuters via [Euronews](https://www.euronews.com/2018/10/10/amazon-scraps-secret-ai-recruiting-tool-that-showed-bias-against-women),
[AI Incident Database #611](https://incidentdatabase.ai/reports/611).
