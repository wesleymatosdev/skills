# wesleymatosdev/skills

Personal agent-skill catalog. Authored and battle-tested in real agent loops.

Browse at <https://skills.wesleymatos.dev>.

---

## Installation

Install any skill directly from this repository with the [Skills CLI](https://github.com/nagyv/skills-cli):

```bash
# A specific skill
npx skills add wesleymatosdev/skills --skill proof-bearing-verification -y

# Everything
npx skills add wesleymatosdev/skills -y
```

Or fetch a single file directly:

```bash
curl -fsSL https://skills.wesleymatos.dev/standards/proof-bearing-verification/SKILL.md
```

---

## Catalog

### 🧭 Agent Workflow (`workflow/`)

* **[`learning-routing`](workflow/learning-routing/SKILL.md)** — Decide whether a learning belongs as durable user memory, a reusable skill, or a project-record, so global context stays compact and learnings compound instead of colliding.
* **[`ce-pickup`](workflow/ce-pickup/SKILL.md)** — Extract `ce-handoff/v1` documents from past Hermes sessions with a local Ollama model, then resume work without paying frontier-model context costs.

### 📐 Engineering Standards (`standards/`)

* **[`proof-bearing-verification`](standards/proof-bearing-verification/SKILL.md)** — A green command, static review, or agent self-report is not proof. Require evidence that exercises the claimed behavior at a real seam before calling work done.

---

## Repository layout

```
catalog.json     agentskills.io schema catalog
versions.json    semver + sha256 content hash per skill
llms.txt         LLM-readable flat index
LICENSE          MIT
<category>/<skill>/SKILL.md
www/             skills.wesleymatos.dev single-page app
```

---

## License

MIT © Wesley Matos. See [LICENSE](LICENSE).
