#!/usr/bin/env python3
"""Per-session health metrics in ~/.claude/.cdt-usage.json.

Account-wide subscription usage (`session` / `weekly` %) stays at the TOP LEVEL — it's shared across all
your terminals, which is correct (it's your account's rate limit). The PER-SESSION health metrics —
context-window size, session age, subagents fired — live under `sessions[<key>]` so two terminals working in
different projects don't clobber each other's numbers.

Key = the WORKSPACE path. Workspace is used (not session_id) because it's the one field present in EVERY
relevant hook payload — SessionStart, SubagentStop, and the status line — which guarantees all three writers
agree on the key. (Two sessions in the *same* project share a key — an accepted edge.) Stale sessions are
pruned 24 h after their last update so the file can't grow without bound. Display-only, fail-open.
"""
import os
import sys
import json
import time

CACHE = os.path.join(os.path.expanduser("~/.claude"), ".cdt-usage.json")
PRUNE = 86400   # seconds; a session's metrics are dropped 24 h after its last touch


def skey(workspace):
    return workspace or "default"


def _load():
    try:
        return json.load(open(CACHE))
    except Exception:
        return {}


def _save(d):
    tmp = CACHE + ".uc.%d.tmp" % os.getpid()
    try:
        with open(tmp, "w") as f:
            json.dump(d, f)
        os.replace(tmp, CACHE)
    except Exception:
        pass


def _prune(sessions, now):
    return {k: v for k, v in sessions.items()
            if isinstance(v, dict) and (now - v.get("ts", 0)) < PRUNE}


def get_session(key):
    """This session's health metrics ({} if none yet)."""
    return (_load().get("sessions") or {}).get(key) or {}


def _mutate(key, fn, glob=None):
    now = time.time()
    d = _load()
    if glob:
        d.update(glob)                      # top-level account-wide fields (session/weekly/ts)
    sessions = d.get("sessions") or {}
    s = sessions.get(key) or {}
    fn(s)
    s["ts"] = now
    sessions[key] = s
    d["sessions"] = _prune(sessions, now)
    _save(d)


def reset_session(key):
    """SessionStart / clear / compact: zero THIS session's health metrics."""
    _mutate(key, lambda s: s.update(
        {"session_start": int(time.time()), "agent_count": 0, "ctx_tokens": 0, "ctx_mtime": 0.0}))


def incr_agent(key):
    """SubagentStop: one more subagent finished in this session."""
    _mutate(key, lambda s: s.__setitem__("agent_count", s.get("agent_count", 0) + 1))


def update_ctx(key, ctx_tokens, ctx_mtime, glob):
    """Status line: refresh this session's context size + the account-wide usage % (top-level)."""
    _mutate(key, lambda s: s.update({"ctx_tokens": ctx_tokens, "ctx_mtime": ctx_mtime}), glob=glob)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    ws = sys.argv[2] if len(sys.argv) > 2 else ""
    k = skey(ws)
    if cmd == "reset":
        reset_session(k)
    elif cmd == "incr":
        incr_agent(k)
    elif cmd == "get":
        print(json.dumps(get_session(k)))


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass
