# claude-dev-team-toolkit

Deterministic-first TypeScript engine layer for the **Claude Dev Team (CDT)** plugin. It runs from any
project directory and writes all generated output into that project's `.claude/` directory.

It provides four binaries:

| Command | What it does |
|---|---|
| `cdt init` | Scaffold `.claude/{cdt.config.json,agents,templates,reports,specs,runtime}` in the current project. |
| `cdt status` | Report CDT state for the project (config, artifacts, last result, staging-guard warnings). |
| `cdt-prompt "<text>"` | Intake → routing → conditional local enhancement → write `TASK_BRIEF.md`, `ROUTING.json`, `NEXT_PROMPT.md`. |
| `cdt-spec <files...>` | Deterministic requirement/spec extraction → `.claude/specs/*`. |
| `cdt-verify -- <command>` | Run a command, capture its real exit code, and record the **only** trusted verification evidence. |
| `cdt enable` / `cdt disable` | Turn the toolkit on/off, **independently of core CDT** (`CDT_TOOLKIT_ENABLED`). |

## Enable / disable & toggles

The toolkit has its own switch, separate from core CDT (`cdt-config on|off`):

```sh
cdt enable | cdt disable                  # or: cdt-config toolkit on|off
cdt-config prompt-mode auto|always|off    # when Haiku enhancement fires
cdt-config prompt-enhance on|off
cdt-config spec-auto on|off               # auto-run cdt-spec on detected docs (default off)
cdt-config external-ai on|off             # external-AI doc review (default off; sensitive docs stay local)
cdt-config ocr on|off                     # local on-device OCR (default off)
cdt-config redact on|off                  # mask secrets/PII in artifacts (default on)
```

On macOS these are also in the menu bar (separate **Enabled (core CDT)** and **Toolkit engine** toggles +
a **Prompt enhance** submenu).

## Principles

- **Deterministic first.** Local heuristics do the routing; the Haiku enhancer (`claude -p`, existing
  login, no API key) is called only when a prompt is genuinely unclear and never when it is sensitive.
- **No fabricated verification.** `verification: passed` is earned only through `cdt-verify` (exit code 0).
- **Redaction always.** Every artifact passes through `redact.ts`; `ROUTING.json` stores only a redacted prompt
  plus an HMAC hash, never the raw text.
- **No notifications.** `TASK_RESULT.json` is local-only.

## Install / build

```sh
cd toolkit
npm install        # builds dist/ via the prepare script
npm run build
npm test
```

The CDT plugin invokes the built engine via `node "${CLAUDE_PLUGIN_ROOT}/toolkit/dist/..."`, so it works
without a global install. For terminal use you may also `npm install -g .`.

Configuration precedence: **packaged defaults < project `.claude/cdt.config.json` < env vars.** See
`.env.example`.
