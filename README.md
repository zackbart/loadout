# Loadout

A native macOS app that shows every AI-agent **skill** and **MCP server** configured on your
machine — across **Claude Code, OpenCode, Codex, Cursor, and Pi** — at both the global and
project level, with tight integration to the [skills.sh](https://skills.sh) / `npx skills`
ecosystem.

Stop digging through dotfiles to see what each agent is actually loaded with.

> Clean-room, MIT-licensed. Informed by `RESEARCH.md` (verified ecosystem research) and
> by Chops (`Shpigford/chops`) as a UX reference only — no code or assets are copied.

## What it does (v0.1)

- Scans each agent's global skill directories plus the `~/.agents/skills` canonical store.
- **Dedupes by canonical (symlink-resolved) path** — one skill, with badges for every agent
  that references it.
- Parses `SKILL.md` frontmatter with a real YAML parser (Yams).
- Reads `~/.agents/.skill-lock.json` for **provenance** (source repo, hash, timestamps).
- Surfaces **declared-vs-wired drift**: skills the `skills` CLI declares for an agent but that
  aren't actually symlinked on disk.
- Full-text search across name, description, and body.

## Roadmap

- Project scope (walk cwd → git root across `.claude/skills`, `.opencode/skills`,
  `.agents/skills`, `.codex/skills`, `.pi/skills`).
- Live FSEvents watching.
- Built-in `SKILL.md` editor.
- Active-state resolution (OpenCode permission rules, Pi project trust).
- Two-way mutations via the `skills` CLI (add / remove / update / init).

## Build

```bash
brew install xcodegen        # one-time
xcodegen generate            # generates Loadout.xcodeproj from project.yml
open Loadout.xcodeproj        # then ⌘R
```

The Xcode project is generated — edit `project.yml`, not the `.xcodeproj`.

## Requirements

- macOS 14+, Xcode 16+. Sole dependency: [Yams](https://github.com/jpsim/Yams) (via SPM).
- Runs non-sandboxed to read agent dotfiles in your home directory.

## License

MIT — see [LICENSE](LICENSE).
