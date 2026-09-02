---
name: learning-routing
description: Classify learnings into memory, skills, or project records.
version: 0.1.0
author: Wesley Matos, Hermes Agent
license: MIT
platforms: [linux, macos, windows]
metadata:
  hermes:
    tags: [memory, skills, project-context, decisions, knowledge-management]
    related_skills: []
  canonical: https://skills.wesleymatos.dev/workflow/learning-routing/SKILL.md
---

# Learning Routing

Use a deliberate routing decision whenever feedback, an incident, or a solution could become durable knowledge. Keep global context compact; preserve detailed evidence where it remains useful.

## When to Use

- A user correction reveals a repeatable standard or preference.
- A bug fix or delivery taught a reusable lesson.
- A project has accumulated memories that may be candidates for Hermes memory or skills.
- You are about to write durable memory or create a skill.

Do not use this to migrate an entire project corpus wholesale.

## Procedure

1. **Separate the durable rule from the incident.**
   - Record what happened, exact system details, and evidence in the project record.
   - Extract only the broadly reusable rule for further classification.
   - Completion: the proposed global item stands alone without repo-specific identifiers.

2. **Decide scope.**
   - Use **user memory** for a compact, stable fact about the user or an enduring preference.
   - Use a **skill** for a reusable, multi-step procedure that needs on-demand instructions.
   - Use a **project record** for domain rules, infrastructure details, team conventions, credentials locations, current state, or a one-off incident.
   - Completion: choose one primary home; do not duplicate detailed content across all three.

3. **Decide delivery.**
   - Keep always-loaded memory to a short declarative fact.
   - Put conditional steps, examples, commands, and pitfalls in a skill.
   - Keep detailed reasoning, rejected alternatives, and evidence with the project.
   - Completion: the item will load only when its detail is useful.

4. **Check portability and sensitivity.**
   - Do not promote employer-, repository-, or account-specific details merely because they appear across related repositories.
   - Do not promote personal or sensitive information without a clear task benefit and user approval.
   - Completion: the destination does not disclose information beyond its intended scope.

5. **Preserve provenance.**
   - When promoting a rule, leave the project source intact or archive it rather than deleting it.
   - State what was promoted and what intentionally remained project-scoped.
   - Completion: a future agent can trace the global rule back to its evidence.

## Pitfalls

- A cross-repository fact is not automatically portable to unrelated projects.
- A large global memory or a giant skill reduces relevance and adherence.
- A passing test or a confident agent summary is evidence only when it proves the claimed behavior.

## Verification

Before finalizing a promotion, verify that each reviewed item is accounted for as **memory**, **skill**, **project record**, or **discarded as stale**. Report the count and the reason for each promoted item.
