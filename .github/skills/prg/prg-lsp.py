#!/usr/bin/env python3
"""prg-lsp.py — LSP-precise symbol edges (definition / references) with an
rg-assisted file preload, no LLM.

Tier-3 of the `prg` skill's grapher. Drives an installed language server over
stdio JSON-RPC:

    TS/JS  -> typescript-language-server --stdio   (tsserver)
    Python -> jedi-language-server

Why rg-assisted: a stock LSP only fully resolves references across files that
are *open*. So we (1) `rg` the symbol to find candidate files fast, (2)
`didOpen` them, (3) ask the server for `textDocument/references` at the
definition site. This yields semantic, cross-file edges (call vs mention
distinguished by the server) while `rg` does the cheap discovery.

Output (same schema as prg-graph.sh):
    edges.tsv :  src \t dst \t path \t line \t kind(def|ref)
    where src is the enclosing symbol at the ref site (documentSymbol),
          dst is the seed symbol.

Fallback contract: exit 3 if no server for the language / server missing /
handshake fails, so prg-graph.sh can drop to the lexical rg tier.

Usage:
    prg-lsp.py <symbol> <seed_file> [--root DIR] [--lang ts|py|auto]
               [--out /tmp/prg-graph] [--max-files 60]
"""
from __future__ import annotations
import json, os, subprocess, sys, threading, time, argparse, shutil, re

SERVERS = {
    "ts": ["typescript-language-server", "--stdio"],
    "py": ["jedi-language-server"],
}
LANG_ID = {"ts": "typescript", "py": "python"}
EXT_LANG = {".ts": "ts", ".tsx": "ts", ".js": "ts", ".jsx": "ts",
            ".mts": "ts", ".cts": "ts", ".py": "py", ".pyi": "py"}


class LSP:
    def __init__(self, cmd):
        self.p = subprocess.Popen(cmd, stdin=subprocess.PIPE,
                                  stdout=subprocess.PIPE, stderr=subprocess.DEVNULL)
        self.seen: dict[int, dict] = {}
        threading.Thread(target=self._read, daemon=True).start()

    def _read(self):
        buf = b""
        while True:
            ch = self.p.stdout.read(1)
            if not ch:
                break
            buf += ch
            if buf.endswith(b"\r\n\r\n"):
                try:
                    n = int(dict(l.split(b": ") for l in buf.strip().split(b"\r\n"))[b"Content-Length"])
                except Exception:
                    buf = b""; continue
                body = self.p.stdout.read(n)
                try:
                    m = json.loads(body)
                except Exception:
                    buf = b""; continue
                if isinstance(m.get("id"), int) and "method" not in m:
                    self.seen[m["id"]] = m
                buf = b""

    def send(self, msg):
        d = json.dumps(msg).encode()
        self.p.stdin.write(f"Content-Length: {len(d)}\r\n\r\n".encode() + d)
        self.p.stdin.flush()

    def wait(self, i, t=20):
        end = time.time() + t
        while time.time() < end:
            if i in self.seen:
                return self.seen[i]
            time.sleep(0.03)
        return None

    def close(self):
        try:
            self.p.terminate()
        except Exception:
            pass


def uri_of(path): return "file://" + os.path.abspath(path)
def unuri(u, root): return u.replace("file://" + root + "/", "").replace("file://", "")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("symbol")
    ap.add_argument("seed_file")
    ap.add_argument("--root", default=os.getcwd())
    ap.add_argument("--lang", default="auto")
    ap.add_argument("--out", default="/tmp/prg-graph")
    ap.add_argument("--max-files", type=int, default=60)
    a = ap.parse_args()

    root = os.path.abspath(a.root)
    lang = a.lang
    if lang == "auto":
        lang = EXT_LANG.get(os.path.splitext(a.seed_file)[1], "")
    if lang not in SERVERS:
        print(f"prg-lsp: no LSP for lang of {a.seed_file}", file=sys.stderr); sys.exit(3)
    if not shutil.which(SERVERS[lang][0]) and not os.path.exists(SERVERS[lang][0]):
        # jedi may live outside PATH
        alt = "/app/officepy/bin/jedi-language-server"
        if lang == "py" and os.path.exists(alt):
            SERVERS["py"][0] = alt
        else:
            print(f"prg-lsp: server {SERVERS[lang][0]} not found", file=sys.stderr); sys.exit(3)

    os.makedirs(a.out, exist_ok=True)
    edges = os.path.join(a.out, "edges.tsv")

    # 1) rg: candidate referencing files (fast discovery) + the definition site.
    globs = {"ts": ["-g", "*.ts", "-g", "*.tsx", "-g", "*.js", "-g", "*.jsx"],
             "py": ["-g", "*.py", "-g", "*.pyi"]}[lang]
    rg = ["rg", "-l", "--no-messages", r"\b" + re.escape(a.symbol) + r"\b",
          "-g", "!**/node_modules/**", "-g", "!**/dist/**", "-g", "!**/.git/**",
          *globs, root]
    files = subprocess.run(rg, capture_output=True, text=True).stdout.split()
    files = files[: a.max_files]
    if os.path.abspath(a.seed_file) not in map(os.path.abspath, files):
        files.insert(0, a.seed_file)

    srv = LSP(SERVERS[lang])
    srv.send({"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
        "processId": os.getpid(), "rootUri": uri_of(root),
        "workspaceFolders": [{"uri": uri_of(root), "name": "root"}],
        "capabilities": {"textDocument": {"references": {}, "definition": {},
                                          "documentSymbol": {}}}}})
    if not srv.wait(1, 20):
        srv.close(); print("prg-lsp: initialize failed", file=sys.stderr); sys.exit(3)
    srv.send({"jsonrpc": "2.0", "method": "initialized", "params": {}})

    # 2) open all candidate files so cross-file refs resolve.
    texts = {}
    for f in files:
        try:
            t = open(f, encoding="utf-8", errors="replace").read()
        except Exception:
            continue
        texts[os.path.abspath(f)] = t
        srv.send({"jsonrpc": "2.0", "method": "textDocument/didOpen", "params": {
            "textDocument": {"uri": uri_of(f), "languageId": LANG_ID[lang],
                             "version": 1, "text": t}}})
    time.sleep(min(1.0 + 0.05 * len(files), 6.0))  # let the program load

    # 3) find the definition position inside the seed file.
    seed = os.path.abspath(a.seed_file)
    seed_text = texts.get(seed, open(seed, encoding="utf-8", errors="replace").read())
    def_line = def_col = None
    for i, ln in enumerate(seed_text.splitlines()):
        c = ln.find(a.symbol)
        if c >= 0 and re.search(r"\b" + re.escape(a.symbol) + r"\b", ln) \
           and re.search(r"(def|function|const|class|interface|type|enum)\b", ln):
            def_line, def_col = i, c + 1
            break
    if def_line is None:  # fall back to first whole-word occurrence
        for i, ln in enumerate(seed_text.splitlines()):
            m = re.search(r"\b" + re.escape(a.symbol) + r"\b", ln)
            if m:
                def_line, def_col = i, m.start() + 1
                break
    if def_line is None:
        srv.close(); print("prg-lsp: symbol not found in seed", file=sys.stderr); sys.exit(3)

    # emit the def edge
    with open(edges, "a") as fh:
        fh.write(f"{a.symbol}\t\u00abdef\u00bb\t{unuri(uri_of(seed), root)}\t{def_line+1}\tdef\n")

    # 4) references at the definition site.
    srv.send({"jsonrpc": "2.0", "id": 2, "method": "textDocument/references", "params": {
        "textDocument": {"uri": uri_of(seed)},
        "position": {"line": def_line, "character": def_col},
        "context": {"includeDeclaration": False}}})
    r = srv.wait(2, 25)
    refs = (r or {}).get("result") or []

    # 5) for each ref, resolve the enclosing symbol via documentSymbol.
    doc_syms: dict[str, list] = {}

    def enclosing(path_uri, line):
        if path_uri not in doc_syms:
            rid = 1000 + len(doc_syms)
            srv.send({"jsonrpc": "2.0", "id": rid, "method": "textDocument/documentSymbol",
                      "params": {"textDocument": {"uri": path_uri}}})
            doc_syms[path_uri] = (srv.wait(rid, 10) or {}).get("result") or []
        best = None
        def rng(s): return s.get("range") or s.get("location", {}).get("range")
        def visit(sym):
            nonlocal best
            rr = rng(sym)
            if rr and rr["start"]["line"] <= line <= rr["end"]["line"]:
                best = sym.get("name", best)
                for ch in sym.get("children", []) or []:
                    visit(ch)
        for s in doc_syms[path_uri]:
            visit(s)
        return best

    n = 0
    with open(edges, "a") as fh:
        for x in refs:
            u = x["uri"]; line = x["range"]["start"]["line"]
            # some servers (jedi) return the declaration even with
            # includeDeclaration:False — drop the def-site self-ref.
            if os.path.abspath(unuri(u, root)) == seed and line == def_line:
                continue
            encl = enclosing(u, line) or "\u00abtoplevel\u00bb"
            fh.write(f"{encl}\t{a.symbol}\t{unuri(u, root)}\t{line+1}\tref\n")
            n += 1

    srv.close()
    print(f"prg-lsp: {a.symbol} lang={lang} files_opened={len(texts)} refs={n} -> {edges}")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise  # preserve explicit exit codes (3, etc.)
    except Exception as e:
        # never leak a traceback to the consumer; map to the fallback contract.
        print(f"prg-lsp: unexpected error ({type(e).__name__}: {e})",
              file=sys.stderr)
        sys.exit(3)
