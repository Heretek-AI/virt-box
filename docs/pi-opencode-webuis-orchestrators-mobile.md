# Pi + OpenCode WebUIs, Orchestrators, Multi-Profile & Mobile Remote (Tailscale)

Research date: 2026-10-19. Primary sources only (GitHub, npm, official docs).

> `pi` = [earendil-works/pi](https://github.com/earendil-works/pi) (`@earendil-works/pi-coding-agent`, prev. `mariozechner/pi-coding-agent`, `badlogic/pi-mono`). Docs: https://pi.dev/docs/latest , install `curl -fsSL https://pi.dev/install.sh | sh` (Node >=22.19).
> `opencode` = upstream moved `sst/opencode` → community continuation [anomalyco/opencode](https://github.com/anomalyco/opencode). Docs: https://opencode.ai/docs/web/ , https://opencode.ai/docs/server/ , https://opencode.ai/docs/config/ , https://opencode.ai/docs/sdk/

## TL;DR

| Goal | Pick |
|---|---|
| Richest Pi-dedicated WebUI (single host) | `xing-shuyin/pi-web-ui` (`pi-web-ui` npm, v0.109.0) — SDK cockpit + SSH remotes + Docker/FRP |
| Pi persistent-session server (survives disconnect) | `jmfederico/pi-web` (`@jmfederico/pi-web`) — Machine→Project→Workspace→Session |
| Pi RPC WebUI with full pi↔browser interop + WebRTC remote | `mike-heunher/pipane` (`pipane` npm) |
| Lightweight mirror of running Pi TUI in browser | `kkkiio/pi-web-ui` (`@kkkiio/pi-web-ui`, `/webui`, `:3001`) |
| Pi desktop app | `Chasen-Liao/pi-agent-desktop` (Electron, MCP global/project editors, tool panel) |
| Multi-agent fleet driving **both Pi + OpenCode** from phone | **Paseo** (`getpaseo/paseo`, `@getpaseo/cli`) or **Happier** (`happier-dev/happier`) or **Orca** (`stablyai/orca`) |
| Multiple Pi profiles (`--extension/--skill/--tools`, MCP, prompts, separate dirs) with no custom code | `ppi` (`chaychoong/pi-profiles`) or `pi-profile` (`krzyzanowskim/pi-profiles`) + `PI_CODING_AGENT_DIR` — composable with any orchestrator |
| Multiple OpenCode profiles with no custom code | Stock opencode (`OPENCODE_CONFIG` + `OPENCODE_CONFIG_DIR` + `.opencode/`); add `kdcokenny/ocx` only for `profile add/use/clone` ergonomics |
| Native Android for OpenCode only | `alvarolorentedev/opencode-mobile` (Play `app.getopencode`, https://getopencode.app/) + `tailscale serve` + `opencode pair` |
| Zero-install mobile for opencode | `opencode web` + `OPENCODE_SERVER_PASSWORD` + `tailscale serve --bg 4096` |
| Zero-install mobile for Pi | Paseo web UI / `pipane` WebRTC / `pi-webui` DIY + `tailscale serve` / SSH+tmux fallback |
| Avoid for Pi | OpenChamber, OpenWork (`different-ai/openwork`), Happy (`slopus/happy`) — OpenCode-only or Claude/Codex/Grok-only, no Pi provider documented |

---

## 1. Pi WebUIs & orchestrators

### 1.1 `xing-shuyin/pi-web-ui` — flagship Pi cockpit (extension package)
- Repo: https://github.com/xing-shuyin/pi-web-ui — npm: https://www.npmjs.com/package/pi-web-ui (`0.109.0`, ~3k/wk) — pi.dev: https://pi.dev/packages/pi-web-ui — Type: `extension`, install `pi install npm:pi-web-ui`
- Features: realtime chat, sub-60ms WS snapshots, thinking/tool calls, `ask_user_question`, Page Picker Chrome ext, multi-conversation, prompt templates, `/new /model /compact /resume`, multi-root workspaces (1+8), file tree, SFTP, media preview, drag-drop→vision, remote SSH (`ssh://user@host:port/path`, AES-256-GCM store, auto-install Git/Node), server PTY (`node-pty`+`xterm.js`), visual Git, multi-engine hot-swap (pi/DSH/Claude, OpenAI/Anthropic/Gemini/DeepSeek/Ollama/OpenRouter/Azure), Goal Mode 2.0/Delegate/Plan/sandbox clones, plugin market (Slack/Discord/DingTalk/Feishu/WeChat, DB, Mermaid), 33+ UI slots, 25+ themes, i18n.
- Launch: standalone server, not in-TUI: `pi-web-ui [--port --host --cwd --data-dir --engine pi|dsh --no-browser]` (default `127.0.0.1:8787`), drives pi via SDK, state `~/.pi-web`, transcripts `~/.pi/agent/`. Docker mounts `~/.pi-web`, `~/.pi/agent`, `/workspace`. `pi-web-ui server install/status/restart/stop`, `pi-web-ui frp …`. Electron `.exe/.dmg/.AppImage`, Windows USB portable, `npx pi-web-ui`.
- Multi-profile: **no named-profile manager**. Isolation via `--cwd`, `--data-dir`, `--engine`, `~/.pi/agent` mount + preset import/export. Workaround: multiple `pi-web-ui --port N --cwd <repo> --data-dir <dir>` with distinct `PI_CODING_AGENT_DIR` (cf. `chaychoong/pi-profiles` Docker `-v ~/.pi/profiles/work:/root/.pi/agent`).
- Pros: most complete Pi WebUI; SSH+portable+Docker+FRP; multi-engine; sandbox/goal modes. Cons: heavyweight (+`node-pty` native build, needs `build-essential/python3`); one workspace/server per process; token optional (`PI_WEB_TOKEN`), bind `127.0.0.1` by default — explicit `0.0.0.0`/proxy care for remote.
```bash
npm i -g --allow-scripts=node-pty,@google/genai,protobufjs pi-web-ui@latest
pi-web-ui --port 8787 --cwd /path/to/repo
PI_WEB_PORT=9000 PI_WEB_DATA_DIR=~/.pi-web-work pi-web-ui --no-browser
docker run -d -p 8787:8787 -v ~/.pi-web:/root/.pi-web -v ~/.pi/agent:/root/.pi/agent -v $(pwd):/workspace -e PI_WEB_HOST=0.0.0.0 xing-shuyin/pi-web-ui:latest
```

### 1.2 `kkkiio/pi-web-ui` — lightweight in-process mirror (different project, same name)
- Repo: https://github.com/kkkiio/pi-web-ui (12★, forked `deflating/tau`) — npm `@kkkiio/pi-web-ui`, `pi install npm:@kkkiio/pi-web-ui`
- Features: mirrors running Pi TUI in browser (React/Vite/Tailwind/shadcn/AI Elements, Streamdown, streaming text/thinking/tools, image paste/drop, conversation-tree sidebar with search/branch, model+thinking picker, context viz, command palette).
- Launch: Pi extension, no separate server. Starts HTTP+WS (`127.0.0.1:3001`) inside Pi process, `/webui` opens browser, `/webui-stop|/webui-start`, `PI_WEB_UI_DISABLED=1`. Respects `PI_CODING_AGENT_DIR` / `PI_CODING_AGENT_SESSION_DIR`, `~/.pi/agent/settings.json` `{pi-web-ui:{port,host}}`.
- Pros: zero extra process, TUI+browser stay in sync, trivial install. Cons: single-session only, no fleet/SSH/PTY/Git/MCP editor, no auth — front with `tailscale serve`/reverse proxy.
```bash
pi install git:github.com/kkkiio/pi-web-ui
pi # then /webui
```

### 1.3 Paseo / `@getpaseo/cli` — multi-agent orchestrator with native Pi (+OMP) provider
- Repo: https://github.com/getpaseo/paseo (21.4k★, Apache-2.0) — npm https://www.npmjs.com/package/@getpaseo/cli (`0.12.0`) — Docs: https://paseo.sh/, https://paseo.sh/docs/supported-providers, https://paseo.sh/docs/agent-profiles, https://paseo.sh/pi, https://paseo.sh/docs/custom-providers, https://paseo.sh/docs/mcp, https://paseo.sh/docs/security, https://paseo.sh/docs/connectivity, https://paseo.sh/docs/web-ui
- Features: one UI for Claude/Codex/Copilot/OpenCode/**Pi**/Antigravity/Muse Code (+33 ACP), parallel agents in own worktrees, editor/terminals/diffs/PRs/browser split panes, voice, self-hosted, iOS/Android/desktop/web/CLI, E2E-encrypted relay, plugins on daemon (screens/sidebar/Command Center/slash/timeline/themes, change config/env/MCP, answer permissions), SDK+MCP+CLI automation.
- Launch: daemon (`packages/server`) spawns `pi`/`omp` per worktree, streams transcripts (not a TUI bridge). Native Pi provider (needs `pi` CLI authed); distinct `omp` provider drives `@oh-my-pi/pi-coding-agent` over RPC (`RpcFrameDecoder` — issues https://github.com/getpaseo/paseo/issues/1726, https://github.com/getpaseo/paseo/issues/2966, https://github.com/getpaseo/paseo/issues/3749 note skill-expand/protocol-v2/stop gaps).
- Multi-profile: **Paseo Agent Profiles** (provider/model/mode/thinking/features + When-to-use notes, per-host, model-picker selectable); provider `command`/`env` override in `~/.paseo/config.json` (`{agents:{providers:{<id>:{command,env}}}}`); plugin lifecycle can change env/MCP per turn; `paseoTools:{enabled,disabledTools}` per provider. No pi-native `--extension/--skill/--tools` picker — achieve via separate worktrees + `env:{PI_CODING_AGENT_DIR:~/.pi/profiles/work}` + repo-local `.pi/` or provider plugin.
- Pros: true fleet (parallel worktrees, cross-provider, mobile parity, relay); Pi+OMP first-class; scriptable. Cons: provider-level not pi-tool-level; per-host CLI auth; daemon ops.
```bash
npm install -g @getpaseo/cli; paseo
paseo run --provider pi "implement auth"
paseo run --worktree feature-x --provider codex/gpt-5.5 "…"
# ~/.paseo/config.json sketch:
{"agents":{"providers":{"pi-work":{"command":["ppi","use","work","--"],"env":{}}}}}
```

### 1.4 Orca / `orca` CLI — generic ADE, Pi via terminal
- Repo: https://github.com/stablyai/orca (97.9k★, MIT) — Docs `onorca.dev` — `brew install --cask stablyai/orca/orca`
- Features: parallel worktrees (1 prompt×N agents, compare+merge), Ghostty-class terminals (WebGL, splits, persistent scrollback), Design Mode (Chromium click→prompt), GitHub/Linear native, SSH worktrees, mobile companion + notifications, account switcher, Computer Use (`orca worktree create`, `snapshot`, `click`, `fill`). Explicitly lists **Pi** (`pi.dev`) and **oh-my-pi** alongside Claude/Codex/OpenCode: “if it runs in a terminal, it runs in Orca.”
- Launch: TUI-terminal wrap, not RPC/SDK. Each agent in native terminal split inside isolated worktree.
- Multi-profile: manual — `PI_CODING_AGENT_DIR=~/.pi/profiles/<name> pi …` inside Orca terminal/worktree, or `pi-profile <name>` launcher. No pi-semantic picker.
- Pros: best mixed-harness fleet UX; huge community; SSH/mobile/computer-use. Cons: no RPC event stream/tool toggles/session-tree ops.

### 1.5 NOT Pi managers (avoid confusion)
- **OpenChamber** https://github.com/openchamber/openchamber (11.9k★): “uses OpenCode to run coding agents… bundles matching OpenCode CLI.” No Pi/RPC bridge. Evaluate only if standardizing on OpenCode.
- **OpenWork** https://github.com/different-ai/openwork (24.2k★): Electron Cowork-clone on OpenCode, 50+ providers via OpenCode, `mcp.openwork` sharing. No Pi provider. No repo named `openwork-orchestrator` found — treat as unconfirmed.
- **Happy Coder / Happy** https://github.com/slopus/happy (24.2k★), https://happy.engineering/, https://happy.engineering/docs/faq/: Claude Code/Codex/Grok only, `npm install -g happy` + QR. No Pi. See Happier fork below for Pi support.

### 1.6 Other Pi frontends
- `jmfederico/pi-web` https://github.com/jmfederico/pi-web (892★) npm `@jmfederico/pi-web`, site `pi-web.dev`: Machine→Project→Workspace→Session, files/terminals/plugins/workflows, remote-machine fleet, survives disconnect. `npm install -g @jmfederico/pi-web --allow-scripts=node-pty; pi-web install; pi-web doctor; pi-web status/logs/restart/update/uninstall`, `http://127.0.0.1:8504`. Trusted-users-only; remote via VPN/SSH/auth proxy. Workspace separation; per-tool config manual.
- `mike-heunher/pipane` https://github.com/mike-heunher/pipane (38★) npm `pipane`: backend launches `pi` in **RPC mode** + WS, “open any pi conversation in pipane, open any pipane conversation in pi.” WS contract `docs/protocol.md`, lineage ext (`~/.pi/agent/extensions/pipane-session-lineage.ts`), `PIPANE_PARENT_SESSION="$PI_SESSION_FILE" pi -p …` delegation, remote via `pipane.dev` rendezvous+WebRTC (`pipane pair` QR, TURN/Metered), usage panel `@sreetej510/pi-usage`. `npm install -g pipane`.
- `Zetaphor/pi-webui` https://github.com/Zetaphor/pi-webui (14★): Lit + `@mariozechner/pi-web-ui` + Express+ws + Pi SDK `AgentSession`, `~/.pi/agent` auth, LiteLLM models, persistence/history, model+thinking pickers. `npm install; npm run build; PORT=8085 npm start`, served at `pi.zetaphor.space` via Caddy+Tailscale. No built-in auth — front with Tailscale Serve. Single-system-agent demo, real profiles in `~/.pi/agent/*` (extensions https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/extensions.md, MCP https://github.com/earendil-works/pi/blob/main/packages/coding-agent/docs/mcp.md `~/.pi/agent/mcp.json`+`.pi/mcp.json` `pi mcp add/list/login` exposure `direct/deferred/codemode/hidden`).
- `Chasen-Liao/pi-agent-desktop` https://github.com/Chasen-Liao/pi-agent-desktop (321★): Electron (`.exe/.dmg/.deb`), tray/orb/shortcuts, session browser by cwd, SSE streaming, queue/steer, branching/navigator, fork/clone, export HTML/MD, mid-chat model switch, quotas, Plan/Ask/Full modes, extension UI bridge, Project Trust 409, tool panel, SQLite LTM, MCP global+project editors, extensions/skills UI.
- `can1357/oh-my-pi` OMP https://github.com/can1357/oh-my-pi (35.9k★) npm `@oh-my-pi/pi-coding-agent`, `curl -fsSL https://omp.sh/install | sh`: batteries-included Pi fork (60+ providers, 31 tools, LSP/DAP/browser/computer, subagents, collab links, ACP). Not a WebUI, but the RPC provider Paseo uses. Config scope: https://github.com/can1357/oh-my-pi/blob/main/docs/config-usage.md

---

## 2. Multiple Pi / OpenCode profiles without custom software

### 2.1 Pi: profile launchers (direct answer)
Pi primitive: `PI_CODING_AGENT_DIR` moves whole agent dir (`~/.pi/agent`→custom: `auth.json`, `settings.json`, `extensions/`, `skills/`, `tools/`, `prompts/`, `sessions/`); `PI_CODING_AGENT_SESSION_DIR` overrides session storage. Evidence: `kkkiio/pi-web-ui` README, `chaychoong/pi-profiles`, `krzyzanowskim/pi-profiles`, oh-my-pi `docs/config-usage.md`.

- `chaychoong/pi-profiles` https://github.com/chaychoong/pi-profiles (23★, MIT) npm `pi-profiles`: `ppi create/use/list/set-default/delete`; each profile = full agentDir, auth symlinked (`--own-auth/--own-models` for isolation); `ProfileManager.resolve()` + `createAgentSession({agentDir})`. Composable `docker -v ~/.pi/profiles/work:/root/.pi/agent`.
```bash
npm install -g pi-profiles
ppi create work --from-base; ppi use work -p "fix bug"; ppi set-default work
PI_CODING_AGENT_DIR=~/.pi/profiles/frontend pi
```
- `krzyzanowskim/pi-profiles` https://github.com/krzyzanowskim/pi-profiles (6★) npm `@krzyzanowskim/pi-profiles`: `pi-profile <name>` sets `PI_CODING_AGENT_DIR` (+ shared `PI_CODING_AGENT_SESSION_DIR=~/.pi/agent/sessions` by default), `/auth-profile`, `/profile-sync`, per-profile model, `env` file for keys, `--allow-env-auth`. Do **not** `pi install`.
```bash
npm install -g @krzyzanowskim/pi-profiles
pi-profile personal; pi-profile work --model claude-sonnet-4-5
```

### 2.2 OpenCode: native, no manager needed
- `OPENCODE_CONFIG=/path/to/custom.json`, `OPENCODE_CONFIG_DIR=/path/to/dir` (searches `agents/ commands/ modes/ plugins/ skills/ tools/ themes/`), `OPENCODE_CONFIG_CONTENT='{…}'`, `OPENCODE_TUI_CONFIG`, per-project `opencode.json` + `.opencode/`. Merge semantics (not replace); precedence remote `.well-known/opencode`→global `~/.config/opencode/opencode.json`→`OPENCODE_CONFIG`→project→`.opencode`→`CONTENT`→managed `/etc/opencode/`. Sources: https://opencode.ai/docs/config/, https://opencode.ai/docs/cli/
- Per-agent isolation (`description, mode, model, prompt, temperature, steps, permission, color`), permissions gate `read/edit/glob/grep/bash/task/webfetch/websearch/lsp/skill/*` (`allow/ask/deny`, wildcards `"mymcp_*":"deny"`, `"git push":"ask"`). JSON + Markdown (`~/.config/opencode/agents/*.md`, `.opencode/agents/*.md`) forms. Sources: https://opencode.ai/docs/agents/ (`tools` deprecated in favor of `permission`), https://opencode.ai/docs/mcp-servers/, https://opencode.ai/docs/skills/
```bash
mkdir -p ~/oc-profiles/{work,review}/{agents,skills,commands}
OPENCODE_CONFIG=~/oc-profiles/work/opencode.json OPENCODE_CONFIG_DIR=~/oc-profiles/work opencode web --port 4096
OPENCODE_CONFIG=~/oc-profiles/review/opencode.json OPENCODE_CONFIG_DIR=~/oc-profiles/review opencode web --port 4097
```
- `kdcokenny/ocx` https://github.com/kdcokenny/ocx (978★) docs https://ocx.kdco.dev/docs: **only tool purpose-built for profile ergonomics** — `ocx profile add/use`, `ocx oc -p <profile>`, `ocx add <registry>/<component>`, `update --dry-run`, `verify`, `migrate`. Each profile = plain folder `~/.config/ocx/profiles/<name>/` with editable files. `ocx profile add work; ocx profile use work; ocx oc; ocx profile add personal --clone work; ocx oc -p personal`. Local launcher; combine with `opencode web --hostname 0.0.0.0` + password + Tailscale for remote. V1 users pinned `ocx@2.0.15`.
- Plugins (not fleet managers): `agnusdei1207/opencode-orchestrator` https://github.com/agnusdei1207/opencode-orchestrator (274★, Commander/Planner/Worker + `/task /plan /stop`, `customRendering:false` for OpenChamber); `opensoft/oh-my-opencode` https://github.com/opensoft/oh-my-opencode (1.3k★ fork, Sisyphus+Oracle/Librarian/Explore, `ultrawork`, 25+ hooks, `.opencode/oh-my-opencode.json`); retired V1 bundle `kdcokenny/opencode-workspace` https://github.com/kdcokenny/opencode-workspace (587★, archived). Index: https://opencode.ai/docs/ecosystem/

---

## 3. Official OpenCode web + community workspaces

| Command | Behavior (https://opencode.ai/docs/web/, https://opencode.ai/docs/server/, https://opencode.ai/docs/cli/, https://opencode.ai/docs/sdk/) |
|---|---|
| `opencode web` | Headless server **+ bundled UI**. Default `127.0.0.1` random port, auto-opens browser. Same sessions/state as TUI. |
| `opencode serve` | Headless server **without UI**. OpenAPI 3.1 at `<host>:<port>/doc`. For custom frontends. |
| `opencode attach <url>` / `run --attach <url>` | Attach TUI to existing (incl. remote) backend; avoids MCP cold-boot. |

```bash
opencode web --port 4096 --hostname 0.0.0.0 --mdns --cors https://example.com
OPENCODE_SERVER_PASSWORD=secret opencode web
# opencode.json: {"server":{"port":4096,"hostname":"0.0.0.0","mdns":true,"cors":["https://example.com"]}}
# LAN: --hostname 0.0.0.0 + password. No TLS/multi-user — put behind Tailscale/VPN/Cloudflare Access.
opencode web --port 4096 --hostname 0.0.0.0 # then: opencode attach http://10.20.30.40:4096
```
Server API: `/global/health`, `/session`, `/session/:id/message|prompt_async|shell|command|permissions`, `/file`, `/find/*`, `/agent`, `/mcp`, `/config`, `/event` (SSE), `/tui/*`, `/doc`. SDK: `npm install @opencode-ai/sdk`, `createOpencode()` (spawn) / `createOpencodeClient({baseUrl})` (attach). Types: https://github.com/anomalyco/opencode/blob/dev/packages/sdk/js/src/gen/types.gen.ts

- `openchamber/openchamber` https://github.com/openchamber/openchamber (11.9k★) https://openchamber.dev/: Desktop+Web/PWA+VS Code+iOS/Android+CLI/server, Goals (auto-continue), Multi-run (1 task×≤5 models, worktrees+Fusion), Changes Walkthrough, Preview+element picker, issue→PR, folders, cron, cost tracking. Uses opencode API. `curl -fsSL https://raw.githubusercontent.com/openchamber/openchamber/main/scripts/install.sh | bash; openchamber --ui-password …; openchamber connect-url --qr; openchamber tunnel start --provider cloudflare --mode quick --qr`. QR+Private Relay (E2E, no open ports), LAN/VPN, tunnels. Heaviest; needs Node 24.14+.
- `NeuralNomadsAI/CodeNomad` https://github.com/NeuralNomadsAI/CodeNomad (2.6k★): Electron+Tauri+ browser for OpenCode V2 (≥2.0.7, 2.0.21 rec., Node 24). Multi-project windows, nested sessions/forks, worktrees, rich chat, `@` files, SideCars (web tools as tabs), browser preview, voice, MCP/plugin UI, OpenTunnel relay Remote Control. `npx @neuralnomads/codenomad --password … --launch` (`--host 0.0.0.0`, self-signed HTTPS first boot).
- `hosenur/portal` (`openportal`) https://github.com/hosenur/portal (812★) https://openportal.space: React Router+IntentUI+Nitro+`@opencode-ai/sdk`, session CRUD, streaming, `@file`, model picker, dark/light, git, in-browser terminal, isolated workspaces. Built because official UI “not mobile responsive.” `bunx openportal` / `openportal run|stop|list|clean`, `openportal -d <dir> -p 3000 --opencode-port 4000 --hostname 0.0.0.0`. Spawns+drives opencode via SDK (:4000/:3000). Designed `Phone--(Tailscale)-->VPS(Portal+OpenCode)`. Chat-centric, smaller scope.
- `shuv1337/oc-web` https://github.com/shuv1337/oc-web (75★, **archived/deprecated**, ex-`kcrommett/opencode-web`): TanStack Start+React+Bun, SSE timeline, diffs, command deck, model/agent pickers, MCP/LSP, file browser, mobile-first PWA. `bunx opencode-web@latest`, proxy via `/api/*` to `OPENCODE_SERVER_URL`. **No built-in auth — do not expose directly.** Successor https://github.com/Latitudes-Dev/shuvcode (https://shuv.ai). Good reference architecture only.
- `zwaetschge/plum-code-webui` https://github.com/zwaetschge/plum-code-webui (28★): Express+Socket.IO+Postgres+React 18 + **native Kotlin/Compose Android + Wear OS companion** (same backend, not webview). Providers: Codex (default), **OpenCode (server-backed HTTP/SSE)**, Pi, Kimi, Claude. Per-session provider/model/permissions, git/GitHub panes, analytics, built-in MCPs, shared `/agents /skills /subagents`, PWA+bottom-nav. `git clone …; ./scripts/install.sh` / `docker compose up -d --build` (`http://localhost:4545`). OpenCode shape `opencode run --format json --model z-ai/glm-5.1 …`, per-user isolate `~/.opencode/users/<sha256>`. `FRONTEND_URL`, `AUTH_ALLOWED_EMAILS`, OAuth/GitHub+Google+basic, `ENCRYPTION_KEY`, `docker-compose.override.yml` (Traefik/Unraid). Only option with Wear approvals/widgets/offline outbox. Heaviest ops (Docker+Postgres).
- Indexes: https://opencode.ai/docs/ecosystem/, https://github.com/awesome-opencode/awesome-opencode, https://opencode.cafe

## 4. Android / mobile-friendly PWA remote (Tailscale-first)

### 4.1 Happier — Happy-fork adding Pi + OpenCode (native)
- Repo: https://github.com/happier-dev/happier (2.0k★, MIT) — https://happier.dev, https://docs.happier.dev — Play via https://happier.dev/playstore, APK https://happier.dev/apk, iOS `id6758554297`, web `cloud.happier.dev`
- Supports Claude/Codex/OpenCode/**Pi**/Cursor/Grok/Antigravity/Kimi +30, any ACP. Cross-agent subagents, mid-session switch, handoff machine-to-machine, worktrees, unified terminal mirroring. Wraps existing CLIs so `~/.pi/agent/*`, `opencode.json` agents/skills/MCP apply; plus Happier-level “MCP servers, configured once” + linked subs/keys.
- Security: E2E content (on-device encrypt before relay; relay sees IDs/timestamps/status). Self-host relay: `happier relay host install --mode system` (or `--ssh`, Docker, Proxmox). Model traffic CLI→provider.
- Integration: `curl -fsSL https://happier.dev/install | bash` (or desktop app sets up CLI+daemon), install `pi`/`opencode` per machine, `happier` → New session → machine/folder/agent (`happier opencode|claude|codex`), scan pairing on phone.
- Pros: only Happy-lineage native with Pi+OpenCode; mature sync/inbox/approvals/voice/Git/diffs. Cons: daemon+relay trust model.

### 4.2 Paseo — strongest multi-profile-from-mobile (native, not WebView)
- Repo https://github.com/getpaseo/paseo — https://paseo.sh — Play `sh.paseo` https://play.google.com/store/apps/details?id=sh.paseo, iOS `id6758887924`, web https://app.paseo.sh, desktop Electron, CLI `@getpaseo/cli`
- Supports Claude/Codex/Copilot/OpenCode/**Pi**/Antigravity/Muse Code +30 ACP (https://paseo.sh/docs/supported-providers, https://paseo.sh/pi, https://paseo.sh/opencode). **Agent profiles** https://paseo.sh/docs/agent-profiles (provider/model/mode/thinking/features + When-to-use, one tap), **custom providers** https://paseo.sh/docs/custom-providers (`agents.providers.<id>={extends,label,env,command,models,disallowedTools}` e.g. `claude-work` vs `claude-personal`), **per-provider tool policy** https://paseo.sh/docs/mcp (`paseoTools:{enabled,disabledTools}`), plugins on daemon (same UI everywhere), skills `/paseo /paseo-handoff /paseo-committee /paseo-advisor` (`npx skills add getpaseo/paseo`).
- Security https://paseo.sh/docs/security, https://paseo.sh/docs/connectivity: **Relay** (E2E Curve25519+NaCl `box`, daemon outbound to `getpaseo/paseo-relay`, `paseo daemon pair` QR) or **Tailscale direct** (bind `daemon.listen` to Tailscale IP `~/.paseo/config.json`, Bearer password, Direct `100.x:6767` in app, no relay) or SSH (`paseo --host ssh://user@host`, `daemon.hostnames` vs DNS-rebinding).
- Integration: `npm install -g @getpaseo/cli; paseo` (or desktop app auto-starts daemon), need one agent CLI authed; phone Add host → relay QR or Tailscale direct; New agent → provider/profile/model → parallel worktrees. Self-hosted web alt: `paseo daemon config set features.webUi.enabled true; paseo daemon start` → `http://localhost:6767/` → `tailscale serve --bg http://127.0.0.1:6767` (https://paseo.sh/docs/web-ui).
- Pros: only option with phone-first multi-profile + per-profile MCP/tool gating + plugins on mobile. Cons: Pi/OpenCode features limited to adapter.

### 4.3 Native Android for OpenCode
- `alvarolorentedev/opencode-mobile` https://github.com/alvarolorentedev/opencode-mobile (273★, Apache-2.0) https://getopencode.app/ https://getopencode.app/docs/getting-started/ https://getopencode.app/docs/guides/tailscale/: native Android+iOS (TestFlight https://testflight.apple.com/join/ddcE5Wzz, Play `app.getopencode` https://play.google.com/store/apps/details?id=app.getopencode, APK releases). React Native+Expo. Sessions, agent+model picker, approvals+Files Changed, workspaces/files, terminal PTY, voice, usage/cost, worktrees, multiple saved servers, notifications/widgets/deep-links. **Select not define** profiles (MCP/agents/skills in server `opencode.json`). Code stays on host; routes LAN/Tailscale/Cloudflare/reverse-proxy/SSH-forward/Cloud Link; Keychain/Keystore password.
```bash
curl -fsSL https://opencode.ai/v2/install | bash; opencode service set password '…'; opencode service set port 4096; opencode service start
tailscale serve --bg 4096  # keep service on 127.0.0.1
opencode pair --url https://<machine>.<tailnet>.ts.net # 5-min QR/link, scan in app
curl -u user:pass https://<host>/global/health
```
- `cc.agentlabs.opencode` https://play.google.com/store/apps/details?id=cc.agentlabs.opencode: separate “connect your phone to your opencode server” listing, no repo/docs verified — **unvetted**, prefer above.
- `tiann/hapi` HAPI https://github.com/tiann/hapi (5.3k★) https://hapi.run: native SwiftUI/UIKit+Kotlin Compose+Web/PWA+Telegram Mini, voice/workspace/handoff, supports Claude/Codex/Cursor/Grok/**OpenCode**/Kimi/Copilot/Antigravity/**Pi**/DeepSeek. `npx @twsxtd/hapi hub --relay` (WireGuard+TLS E2E relay, 2 QRs), self-host via Cloudflare/Tailscale, `hapi <agent>` direct. Local-first Happy alternative.
- `Shahfarzane/opencode-mobile` https://github.com/Shahfarzane/opencode-mobile (130★, Expo iOS): connects to **OpenChamber** server, SSE streaming, Face/Touch ID SecureStore, haptics, terminal, git+AI commits, LRU offline cache. QR pairing to `openchamber` server.
- Plum Android+Wear https://github.com/zwaetschge/plum-code-webui (`packages/android`, `packages/android/wear`): ~170-file Kotlin/Compose phone/tablet + watch tile/approvals complication/synced snapshots, widgets/push/voice/offline outbox. Same server account, `./gradlew assembleDebug`.
- OpenChamber Mobile (part of https://github.com/openchamber/openchamber): iOS/Android clients, PWA installable, completion alerts, touch terminal, QR+Private Relay (no open ports, E2E, revocable).
- CodeNomad Remote Control (part of https://github.com/NeuralNomadsAI/CodeNomad): phone/browser remote via OpenTunnel relay, no open ports.
- `mariustudor07/odysseus-companion-app` https://github.com/mariustudor07/odysseus-companion-app (2★): Capacitor+React thin client to Odysseus Agent (built on opencode) `/api/companion/*`, Android APK+mobile web, QR revocable chat-scoped token. Same Wi-Fi or Tailscale, `uvicorn app:app --host 0.0.0.0 --port 7000`.

### 4.4 Generic transport (works for both)
- **Tailscale Serve vs Funnel** https://tailscale.com/kb/1242/tailscale-serve: `tailscale serve --bg <port|localhost:port>` = **tailnet-only** HTTPS (auto cert, MagicDNS `https://<node>.<tail>.ts.net`); `funnel` = public internet. For phones use **Serve**. `tailscale serve status/off`, `--bg` persists reboot. Prefer `serve --bg http://127.0.0.1:<port>` over binding `0.0.0.0`; set daemon/service password; `curl` before blaming app.
- **SSH+terminal fallback** (full profile fidelity — you are in the shell where `pi`/`opencode.json` live): Termux + `tailscale` + `ssh user@100.x` + `tmux` + `pi`/`opencode`. iOS pattern ref QuickTUI https://quicktui.ai/guide/ (tmux/Herdr, Agent Wizard incl. YOLO warn, E2E phone↔server, Cloud relay or Tailscale `http://<tailscale-name>:8022`; Android equiv = Termux/Blink-style SSH).
- **Hosted shortcut (no home machine)**: Cosyra https://cosyra.com/guides/ai-coding-agents-mobile.html — native iOS+Android (https://apps.apple.com/us/app/cosyra/id6760034417, https://play.google.com/store/apps/details?id=com.portablesoftware.cosyra) → persistent Ubuntu (30GB) with Claude/Codex/**OpenCode**/`agy` preinstalled; `pi` = `npm i -g --ignore-scripts @earendil-works/pi-coding-agent`. ~$20/mo BYOK, code runs on their infra (opposite of Tailscale self-host).

---

## 5. Recommendation for Tailscale + multi-profile use

1. **Profiles:** stock `opencode` (`OPENCODE_CONFIG`+`OPENCODE_CONFIG_DIR`, per-agent `permission/model/prompt`) covers OpenCode; add **OCX** https://github.com/kdcokenny/ocx only for registry/switching ergonomics. For Pi use **`ppi`/`pi-profile`** (`PI_CODING_AGENT_DIR` isolation) — only solution giving per-profile `extensions/skills/tools/prompts/MCP/auth/sessions` without custom code. Compose with orchestrators via provider `command`/`env` overrides.
2. **Browser from LAN/Tailscale:** `opencode web --hostname 0.0.0.0` + `OPENCODE_SERVER_PASSWORD` suffices for 1 user; step up to **OpenChamber** for goals/multi-run/relay, **Portal** for minimal mobile-first, **CodeNomad** for worktree-heavy desk use. For Pi: `xing-shuyin/pi-web-ui` (richest) or `jmfederico/pi-web` (persistent) or `pipane` (RPC+WebRTC phone access), one instance per profile if hard separation needed.
3. **Phone:** **Paseo** + **OpenCode Mobile** (`app.getopencode`) on Android; **Happier/HAPI** if you want one multi-harness native app; **Plum** if you want Wear approvals. Keep SSH+tmux fallback. Front everything with `tailscale serve --bg …`, never raw public port, never mount Docker socket into WebUI.
