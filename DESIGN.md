# Loadout — Unified Design

> One native Swift app (macOS + iOS) that manages **running agents** (via Herdr),
> **installed skills**, and **MCP servers** — from a shared core. Consolidates the
> existing `loadout` (macOS) and `herdr-ios` apps into a single product called
> **Loadout**.

---

## 1. Vision

Loadout is the home base for agent work. It shows what your agents are *equipped
with* (skills, MCP servers, config drift) and what they're *doing right now*
(live panes, status, output), in one app that runs natively on macOS and iOS.

Three non-negotiable experience goals:

1. **Native speed against the local Herdr.** On the Mac, the app talks directly
   to the local Herdr Unix socket — no network, no relay, no daemon in the path.
   Managing your local session should feel instant.
2. **Easy keyboard shortcuts.** First-class keybindings for navigating
   workspaces/panes, sending input, and answering agent prompts.
3. **T3 Code–style rendering.** For agent panes, render structured content
   (messages, tool calls, diffs, plan, permission prompts) as clean native UI —
   not raw terminal scrollback — so it's genuinely nice to use.

---

## 2. What we're consolidating

### `loadout` (existing, macOS) — this repo
Native macOS SwiftUI app. Scans agent skill/MCP config across Claude Code,
OpenCode, Codex, Cursor, Pi at global + project scope; dedupes skills by
canonical (symlink-resolved) path; parses `SKILL.md` frontmatter (Yams); reads
`.skill-lock.json` provenance; surfaces declared-vs-wired drift. SwiftPM, signed/
notarized, Homebrew cask.

**Keep:** the scanners and the drift logic — that's its real value.

### `herdr-ios` (existing, iOS)
Native iOS SwiftUI client for Herdr. Clean two-layer split:
`HerdrKit` (platform-independent core: protocol, transport, client, models —
Foundation + concurrency, builds on macOS/Linux) and a thin SwiftUI app. Swappable
transport (`HerdrTransport`) with Mock + SSH (Citadel/SwiftNIO SSH) implementations.
Three render modes (`fit`, `scroll`, `reader`). Keychain creds, TOFU host pinning.

**Keep:** the entire architecture. `HerdrKit` is already the shared core we'd
otherwise have to design from scratch.

---

## 3. What the research established

### 3.1 Happy / T3 Code are nice *because of their data source*, not a render trick
Happy and T3 Code don't render terminals. They consume the agent's **structured
event stream** (typed messages, tool calls with parsed input/output, plan,
permission requests) and render each with a purpose-built native component (bash
card, diff view, todo list, markdown). There is no terminal-rendering path to a
T3 Code–style UI — it requires structured data.

### 3.2 Herdr is a control plane, not just a terminal to scrape
- **RPC is one-request-per-connection.** Open → one request → one reply → close.
  Only `events.subscribe` stays open (streams events).
- **`events.subscribe` pushes structured lifecycle events:** `pane.agent_status_changed`,
  topology (`workspace.*`, `tab.*`, `pane.*`), `worktree.*`. Status is pushed.
- **`agent_session` is exposed** on `pane.get`/`agent.get`/`pane.list`/`agent.list` —
  the pane → transcript correlation key. **(Confirmed live — see §7.)**
- **`foreground_cwd` is exposed** alongside it.
- **Output is pull-on-signal:** liveness via `pane.wait_for_output` (held-open,
  returns on a regex match).
- **`blocked` is screen-detected.** The *content* of the permission lives in the
  transcript; Herdr also exposes a reported `--message` on `report-agent`.
- **Input:** `pane.send_text` / `pane.send_keys` inject keystrokes into the TUI.
- **License:** Herdr is **AGPL-3.0-or-later**. A separate client talking to its
  documented socket is fine; do not bundle or derive from its code.

---

## 4. Conclusions

### 4.1 Structured rendering (Path B, no terminal fallback)
Agent panes render as a **T3 Code–style structured view** — the only renderer.
Resolve the transcript path from `agent_session`, tail the Claude Code JSONL, and
render native blocks (messages, tool calls, diffs, plan, permission prompts). No
terminal/scrollback view ships in the app. Non-agent panes (plain shells, dev
servers) appear only as a minimal status row in the workspace tree.

### 4.2 The four data planes (Herdr owns three)
| Plane | Source | Notes |
| --- | --- | --- |
| **Lifecycle / status** | Herdr `events.subscribe` + `*.list` | Consume; don't reimplement. |
| **Identity / correlation** | `agent_session` + `foreground_cwd` | Deterministic pane → session → JSONL. |
| **Content** | Claude Code JSONL transcript | Our part. Structured blocks. |
| **Input** | `send_text` / `send_keys` + per-agent keymap | Keystroke injection; `blocked` triggers the permission UI. |

### 4.3 No daemon on the remote — smarts live in the shared library
The only process on a remote machine is Herdr (plus `sshd`). All intelligence —
collapsing round-trips, `wait_for_output` loops, resolving `agent_session`,
tailing transcripts, merging streams — lives client-side in the shared Swift
packages. The remote stays commodity.

### 4.4 Transport: local-native now, SSH now, relay-ready later
| Transport | Use | Status |
| --- | --- | --- |
| `LocalSocketTransport` | macOS app → **local** Herdr Unix socket. Native speed. | Build now. |
| `SSHTransport` | Remote Herdr over SSH (control + content + loadout on one connection). | Exists; extend. |
| `MockTransport` | Dev / demo. | Exists. |
| `RelayTransport` | Future: outbound rendezvous. | Seam only. |

Local path connects straight to `~/.config/herdr/herdr.sock`. Remote: one SSH
connection does triple duty — **control** (exec channel → Unix socket),
**content** (`tail -f` the JSONL), **loadout** (`cat`/`find`/`skills list --json`).

### 4.5 Relay is deferred, the seam is honest
Herdr only listens on a local socket — it never dials out. So {no overlay, relay,
only-Herdr} can't all be true at once. A relay's outbound bridge lives **off the
remote** (a VPS) or **as a Herdr plugin**. Until then: SSH / direct, with
`RelayTransport` a drop-in we can add without touching the app or the core.

---

## 5. Package architecture

One repo, SwiftPM, thin app targets over shared packages.

```
Loadout/
├─ Packages/
│  ├─ HerdrKit/          # control plane core (from herdr-ios; bump past protocol 14 → 0.7.x)
│  │   ├─ Protocol/      # NDJSON JSON-RPC, Method, events (+ pane.get/agent.get, agent_session, worktree)
│  │   ├─ Transport/     # HerdrTransport protocol
│  │   ├─ Client/        # HerdrClient actor, event demux
│  │   └─ Models/        # Workspace/Tab/Pane/AgentStatus/AgentSession
│  ├─ Transports/        # LocalSocketTransport, SSHTransport, MockTransport, (RelayTransport later)
│  ├─ AgentContentKit/   # NEW: transcript tail + parse → structured blocks; per-agent keymaps
│  ├─ LoadoutKit/        # from this repo: skill/MCP scanners, SKILL.md (Yams), drift — behind a FileSource protocol
│  └─ LoadoutUI/         # shared SwiftUI: SessionModel, workspace/pane views, content blocks, theming, keymap/shortcuts
├─ Apps/
│  ├─ Loadout-macOS/     # local-socket default, Homebrew cask
│  └─ Loadout-iOS/       # key bar, TestFlight, SSH default
```

Key refactors:
- **`HerdrKit`** — add `pane.get`/`agent.get`, parse `agent_session`, subscribe to
  worktree events, bump protocol (herdr **0.7.0** live). Transport-agnostic
  transcript source so content composes the same over local/SSH/relay.
- **`LoadoutKit`** — replace hardcoded local-FS access with a `FileSource` protocol
  so scanners run unchanged against a remote over SSH.
- **`LoadoutUI`** — isolate platform divergences (menus, key bar, window chrome)
  behind `#if os(...)`.

**UI integration:** the existing app is a 3-column `NavigationSplitView` with a
segmented **Skills / MCP** kind-picker. Agents lands as a **third segment**,
reusing the same sidebar → list → detail shape and color discipline (grayscale
chrome; chroma only for agent-identity dots + the amber drift token). Mockup:
`~/.scratch/Dev/projects/tooling/loadout/agent-pane-mockup-v2.html`.

---

## 6. UX requirements

- **Native local speed:** macOS defaults to `LocalSocketTransport`; collapse the
  multi-round-trip refresh by issuing `*.list` concurrently and merging client-side.
  Convert `wait_for_output` into a single internal push feed the views observe.
- **Keyboard shortcuts:** shared shortcut layer — navigate workspaces/tabs/panes,
  focus input, submit, answer prompts (accept/deny) via the per-agent keymap.
  iOS keeps the sticky key bar; macOS uses real menu + key-equivalents.
- **T3 Code–style rendering:** structured blocks — message stream, tool-call cards,
  inline diffs, plan view, permission prompts as real buttons (wired to the keymap).
  This is the content surface; there is no terminal renderer.

---

## 7. Open questions — status

### 7.1 `agent_session` shape (keystone) — ✅ RESOLVED (live probe, herdr 0.7.0, 2026-06-21)
On every live Claude Code pane, `pane get` / `agent list` return:
```json
"agent_session": { "agent":"claude", "kind":"id", "source":"herdr:claude",
                   "value":"7671f37d-7258-4d2a-a51c-d5674bdb0afc" }
```
`kind:"id"` — a real session id, **not** an opaque restore token. It resolves
deterministically to the transcript:
`~/.claude/projects/<cwd-with-/→->/<value>.jsonl` — verified against a live
343 KB / 107-line JSONL. `agent_session` is present even on **idle** panes, so
correlation is not focus-gated. The reporting API also carries an explicit
`--agent-session-path` (`pane report-agent` / `report-agent-session`), so when an
integration reports the absolute path we use it directly; hash-derivation is the
fallback.

**Confirmed structured content** (same probe): the transcript carries `text`,
`thinking`, `tool_use`, `tool_result` blocks with structured input —
`Bash{command,description}`, `Edit{file_path,old_string,new_string}` (compute the
diff client-side), `Write`, `Skill`, `Agent`, `AskUserQuestion`, plus `TodoWrite`
for the plan view. Every block the mockup renders is real data already on disk.

### 7.2 Protocol bump — ✅ CONFIRMED NEEDED
Live herdr is **0.7.0**; `herdr-ios` `Method.swift` is pinned to "protocol 14".
Methods to wire: `pane get`, `agent get`/`list`, `report-agent-session`, worktree
subcommands. Verified available: `pane send-keys`/`send-text` (input),
`agent wait --status blocked`, `pane report-agent --state blocked --message`.

### 7.3 Transcript schema fragility — accepted risk
Claude Code's JSONL is unversioned (housekeeping records `last-prompt`, `mode`,
`attachment`, `file-history-snapshot` interleave with messages). Isolate all
parsing in `AgentContentKit`. Same risk Happy/T3 Code accept.

### 7.4 Per-agent keymaps
Start with Claude Code (accept/deny/menu keys); add others as needed. Input is
keystroke injection, not an `accept()` API — the least-robust piece; the keymap
must track the on-screen permission menu layout.

### 7.5 Worktree edge (new, from live probe)
A worktree pane has `cwd` = launch dir but `foreground_cwd` = the worktree path.
The transcript hash derives from the **launch `cwd`**, not `foreground_cwd` — or
just use the reported `agent_session_path` when present.

### 7.6 License hygiene
Keep every transport a clean, separate socket client of Herdr. Do not bundle or
derive from Herdr (AGPL).

---

## 8. Phased plan

1. **Monorepo + extraction.** SwiftPM workspace; move `HerdrKit` in as-is; extract
   `LoadoutKit` behind `FileSource`; create `LoadoutUI` from the existing SwiftUI.
2. **Local-native control.** `LocalSocketTransport`; macOS manages the local Herdr
   at native speed; concurrent-list refresh; internal output push feed.
3. **Structured content (vertical slice).** `AgentContentKit`: resolve
   `agent_session`, tail one Claude Code transcript, render a single thread with
   tool-call cards + plan + permission buttons. Validate it feels like T3 Code.
4. **Keyboard + rendering.** Shortcut layer; per-agent keymap; the full structured
   renderer (message stream, tool-call cards, diffs, plan, permission buttons).
5. **Remote over SSH.** Extend `SSHTransport` to carry control + content + loadout
   reads on one connection. iOS defaults here.
6. **Loadout views.** Surface skills/MCP/drift in-app, local and remote.
7. **Relay (later).** Add `RelayTransport` + an off-remote or plugin bridge if/when
   the no-port-forward tradeoff is worth it.

---

### One-line summary
Merge both apps into **Loadout**: a shared-package Swift app where `HerdrKit` +
`LoadoutKit` + `AgentContentKit` do the work client-side, the remote runs nothing
but Herdr, the Mac talks to the local socket at native speed, agent panes get a
T3 Code–style structured view, and the transport layer starts at local/SSH with a
clean seam for a future relay.

---

## 9. Known follow-ups (next cycle)

From the first build cycle's review (motif validator + Codex cross-model pass). The
in-scope correctness fixes were applied; these are deferred with the deferred scope:

- **`events()` cancellation doesn't unblock the blocking `read()`** (`LocalSocketTransport`).
  Latent until we wire the live topology subscription — fix together with that (close the
  fd on `onTermination` so the read loop exits). Tracks §8 phase 4.
- **Agents shows the shared remote Machine selector but always uses `LocalSocketTransport`.**
  Selecting a remote host can "lie." Gate the Machine picker for Agents until SSH lands (§8 phase 5).
- **`HerdrClient.eventStream` is single-consumer**, not a multicast bus (pre-existing upstream
  HerdrKit; the doc comment overstates it). Revisit when multiple views observe events.
- **`refresh()`/`select()` share one `status` field** — a late `refresh` can clear a detail
  error. Minor; split per-surface status if it bites.
