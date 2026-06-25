#!/usr/bin/env python3
"""obsidian_recall.py — pure-stdlib BM25 ranker over an Obsidian vault's markdown.

Usage: obsidian_recall.py <root> <query> [N]
Prints the top-N most relevant notes as markdown items:

    - **<title>** — `<relpath>`
      > <snippet>

No third-party deps, no embeddings, no network. Fail-open: any problem -> exit 0
with no output, so a caller (cdt-recall / cdt-obsidian) is never disrupted.
"""
import math
import os
import re
import sys

# Same stopword/tokenize convention as hooks/recall.sh (keep ranking consistent across CDT).
STOP = set(
    "the a an and or of to in is for on with by it this that be are as at from "
    "your you our we i if then so not no run use used using when where what how".split()
)


def toks(s):
    return [t for t in re.split(r"[^a-z0-9]+", s.lower()) if len(t) > 2 and t not in STOP]


def main():
    if len(sys.argv) < 3:
        return
    root, query = sys.argv[1], sys.argv[2]
    try:
        n = max(1, int(sys.argv[3])) if len(sys.argv) > 3 else 5
    except ValueError:
        n = 5

    qt = toks(query)
    if not qt or not os.path.isdir(root):
        return
    qset = set(qt)

    # Collect markdown docs.
    docs = []  # (path, raw, tokens)
    for dirpath, _dirs, files in os.walk(root):
        for fn in files:
            if not fn.lower().endswith(".md"):
                continue
            fp = os.path.join(dirpath, fn)
            try:
                with open(fp, "r", encoding="utf-8", errors="ignore") as fh:
                    raw = fh.read()
            except OSError:
                continue
            docs.append((fp, raw, toks(raw)))
    if not docs:
        return

    n_docs = len(docs)
    avgdl = sum(len(t) for _, _, t in docs) / n_docs or 1.0
    df = {}
    for _, _, t in docs:
        for term in set(t) & qset:
            df[term] = df.get(term, 0) + 1

    k1, b = 1.5, 0.75
    scored = []
    for fp, raw, t in docs:
        if not t:
            continue
        dl = len(t)
        score = 0.0
        for term in qt:
            f = t.count(term)
            if not f:
                continue
            idf = math.log((n_docs - df.get(term, 0) + 0.5) / (df.get(term, 0) + 0.5) + 1.0)
            score += idf * (f * (k1 + 1)) / (f + k1 * (1 - b + b * dl / avgdl))
        if score > 0:
            scored.append((score, fp, raw))

    scored.sort(key=lambda x: x[0], reverse=True)
    out = []
    for _score, fp, raw in scored[:n]:
        out.append("- **%s** — `%s`" % (title_of(raw, fp), os.path.relpath(fp, root)))
        snip = snippet_of(raw, qset)
        if snip:
            out.append("  > %s" % snip)
    if out:
        print("\n".join(out))


def title_of(raw, fp):
    for line in raw.splitlines():
        m = re.match(r"^#\s+(.*\S)", line)
        if m:
            return m.group(1).strip()
    return os.path.splitext(os.path.basename(fp))[0]


def snippet_of(raw, qset, width=160):
    best, best_hits = "", 0
    for line in raw.splitlines():
        s = line.strip().lstrip("#").strip()
        if not s:
            continue
        hits = sum(1 for w in set(toks(s)) if w in qset)
        if hits > best_hits:
            best, best_hits = s, hits
    if not best:
        return ""
    return best[: width - 1].rstrip() + "…" if len(best) > width else best


if __name__ == "__main__":
    try:
        main()
    except Exception:
        pass  # fail-open: never raise into a caller
