# skills.wesleymatos.dev

Public showcase of my personal AI agent skills — genuinely authored or
meaningfully customized by me, not a dump of every installed skill.

Same visual identity as wesleymatos.dev: dark galaxy/starfield background,
warp-in intro, same gradient palette. Built as a static site (no SSG needed
— this isn't a blog, it's a curated card index).

## Status

🚧 **Private draft.** Reviewing structure and content before making public
or pointing the subdomain at it.

## Structure

```
www/
  index.html      — page shell + starfield (reuses starfield.js from social-assets)
  skills.json      — curated skill data (title, category, description, source)
  starfield.js     — shared component, copied from wesleymatos.dev/blog
```

## Curated skills (draft list, pending review)

1. `learning-routing` — classify learnings into memory/skills/project records
2. `proof-bearing-verification` — prove behavior before declaring work complete
3. `carousel` — LinkedIn carousel generator, customized with galaxy palette
4. `buffer` — social post scheduling via Buffer CLI
5. `social-copy` — editorial/anti-slop audit workflow for social copy

Excluded from public list: personal-data skills (e.g. writing-voice
profiles), unmodified third-party installs, and internal Hermes-specific
tooling skills.
