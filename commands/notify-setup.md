---
description: Configure Discord/Telegram status notifications without hand-editing .env. Paste a webhook URL or bot token.
argument-hint: [discord <webhook-url>] | [telegram <token> <chat_id>]
allowed-tools: Bash
---

Configure the notifier via the `cdt-setup` CLI (writes `~/.claude/claude-dev-team.env`, chmod 600 — no
manual file editing).

Arguments: $ARGUMENTS

- If arguments contain a Discord webhook URL, run:
  `~/.claude/bin/cdt-setup --discord "<url>"` then `~/.claude/bin/cdt-setup --test`.
- If they contain a Telegram token + chat id, run:
  `~/.claude/bin/cdt-setup --telegram "<token>" "<chat_id>"` then `--test`.
- If **no arguments** were given (so no secret is pasted into the chat), tell me to run it securely in my
  terminal instead — it prompts with hidden input:

  ```
  !~/.claude/bin/cdt-setup
  ```

After configuring, run `~/.claude/bin/cdt-setup --show` to confirm (values are masked) and report the
result. Never echo the raw secret back.
