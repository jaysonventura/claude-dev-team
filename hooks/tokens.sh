#!/usr/bin/env bash
# cdt-tokens — print the running total of input+output tokens used TODAY (summed from local Claude Code
# transcripts). Lets the orchestrator measure a PER-TASK cost as a delta:
#   K0=$(cdt-tokens); … do the task … ; used=$(( $(cdt-tokens) - K0 ))   # tokens for this task
# Pure python3 stdlib. Fail-open: prints 0 if it can't read anything.
set +e
command -v python3 >/dev/null 2>&1 || { echo 0; exit 0; }
python3 - <<'PY'
import os, json, glob, datetime
root = os.path.expanduser("~/.claude/projects")
today = datetime.date.today().isoformat()
total = 0
try:
    for path in glob.glob(os.path.join(root, "**", "*.jsonl"), recursive=True):
        try:
            if datetime.date.fromtimestamp(os.path.getmtime(path)).isoformat() < today:
                continue   # file untouched today can't hold today's usage
        except OSError:
            continue
        try:
            with open(path, encoding="utf-8", errors="ignore") as f:
                for line in f:
                    try:
                        d = json.loads(line)
                    except Exception:
                        continue
                    if not str(d.get("timestamp", "")).startswith(today):
                        continue
                    u = (d.get("message") or {}).get("usage") or {}
                    total += int(u.get("input_tokens") or 0) + int(u.get("output_tokens") or 0)
        except OSError:
            continue
except Exception:
    pass
print(total)
PY
exit 0
