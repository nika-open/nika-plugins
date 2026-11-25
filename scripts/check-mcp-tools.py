#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# check-mcp-tools.py — the documented MCP tool set MUST equal what the binary
# serves. The marketplace README advertises "8 tools: nika_check · nika_explain
# · …"; those names are hand-written, so a future engine that adds or drops a
# tool would leave the marketplace lying. This asserts (a) the README's
# `nika_*` names are exactly the tools `nika mcp` exposes over the wire, and
# (b) every kit-native .md registered in mirror.json only advertises tool
# names the wire serves (subset — a pack may list fewer, never a phantom),
# and (c) each integration page that describes the wire states, wherever
# its prose counts tools or prompts, the counts the wire serves, and its
# `prompts/list` sentences name exactly the prompts the wire serves (earned
# 2026-11-25: three pages said "seven prompts" by hand and nothing compared
# them with the binary). A page with no readable count of either is refused
# too, so a rewording cannot turn the check off.
# Runs in CI after the latest released nika is installed; also runnable locally:
# NIKA_BIN=/path/to/nika python3 scripts/check-mcp-tools.py
#
# Exit 0 = surfaces ⟺ binary agree. Exit 1 = drift (names printed).

import json
import os
import pathlib
import re
import shutil
import subprocess
import sys

ROOT = pathlib.Path(__file__).resolve().parent.parent


NAME_RE = re.compile(r"(?:mcp__nika__)?nika_[a-z_]+")


def wire_name(name: str) -> str:
    """Normalize a documented name to the wire form. Packs legitimately show
    client-namespaced spellings: hermes prefixes `mcp__<server>__<tool>`,
    opencode prefixes `<server>_<tool>` (the oracle appears as nika_nika_*).
    """
    if name.startswith("mcp__nika__"):
        name = name[len("mcp__nika__"):]
    if name.startswith("nika_nika_"):
        name = name[len("nika_"):]
    return name


def documented_tools() -> set:
    """The `nika_*` tool names the marketplace README advertises."""
    readme = (ROOT / "README.md").read_text()
    return {wire_name(n) for n in NAME_RE.findall(readme)}


def kit_native_md_tools() -> dict:
    """Per kit-native .md (mirror.json), the wire-form names it advertises."""
    manifest = json.loads((ROOT / "mirror.json").read_text())
    paths = [e["path"] for e in manifest["entries"]
             if e["class"] == "kit-native" and e["path"].endswith(".md")]
    # the animated visuals advertise tool names too (the suite strip)
    paths += ["media/suite-dark.svg", "media/suite-light.svg"]
    out = {}
    for path in paths:
        names = {wire_name(n)
                 for n in NAME_RE.findall((ROOT / path).read_text())}
        if names:
            out[path] = names
    return out


def wire_listing(nika: str) -> tuple[set, set]:
    """The tool and prompt names `nika mcp` actually exposes (JSON-RPC
    tools/list and prompts/list). A binary that does not advertise the
    prompts capability serves no prompts."""
    handshake = "\n".join(json.dumps(m) for m in [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize",
         "params": {"protocolVersion": "2025-06-18", "capabilities": {},
                    "clientInfo": {"name": "gate", "version": "1"}}},
        {"jsonrpc": "2.0", "method": "notifications/initialized"},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
        {"jsonrpc": "2.0", "id": 3, "method": "prompts/list", "params": {}},
    ]) + "\n"
    out = subprocess.run([nika, "mcp"], input=handshake, text=True,
                         capture_output=True, timeout=30)
    replies = {}
    for line in out.stdout.splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        # a reply carries no `method`; a server request reusing an id is not one
        if "method" not in msg and msg.get("id") in (1, 2, 3):
            replies[msg["id"]] = msg
    stderr = out.stderr.strip()[:160]
    for rid, method in ((1, "initialize"), (2, "tools/list")):
        if "result" not in replies.get(rid, {}):
            raise SystemExit(f"check-mcp-tools: no {method} result from `nika mcp` "
                             f"(error: {replies.get(rid, {}).get('error')}, stderr: {stderr})")
    tools = {t["name"] for t in replies[2]["result"].get("tools", [])}
    prompts = set()
    if "prompts" in replies[1]["result"].get("capabilities", {}):
        if "result" not in replies.get(3, {}):
            raise SystemExit("check-mcp-tools: `nika mcp` advertises prompts but gave no "
                             f"prompts/list result (error: {replies.get(3, {}).get('error')}, "
                             f"stderr: {stderr})")
        prompts = {p["name"] for p in replies[3]["result"].get("prompts", [])}
    return tools, prompts


# The pages that describe what the oracle serves over the wire, in prose.
LISTING_PAGES = [
    "integrations/mcp/README.md",
    "integrations/openclaude/README.md",
    "integrations/opencode/README.md",
]
NUMBER_WORDS = {w: i for i, w in enumerate(
    "zero one two three four five six seven eight nine ten eleven twelve "
    "thirteen fourteen fifteen sixteen".split())}
COUNT_RE = {
    "tools": re.compile(r"\b(\d+|[a-z]+)\s+(?:`nika_\*`\s+)?tools\b", re.I),
    "prompts": re.compile(r"\b(\d+|[a-z]+)\s+prompts\b", re.I),
}
TICKED_RE = re.compile(r"`([^`]+)`")


def sentences(text: str) -> list[str]:
    """Paragraph-joined sentences, outside fenced code blocks."""
    prose = re.sub(r"```.*?```", "", text, flags=re.S)
    out = []
    for para in re.split(r"\n\s*\n", prose):
        out += re.split(r"(?<!e\.g\.)(?<!i\.e\.)(?<=[.!?])\s+", " ".join(para.split()))
    return out


def count_claims(text: str, kind: str) -> list[tuple[str, int]]:
    """Every count of `kind` the prose states, as digits or a number word,
    with its sentence. A word that is not a number ("the tools") states none."""
    claims = []
    for sentence in sentences(text):
        for m in COUNT_RE[kind].finditer(sentence):
            word = m.group(1).lower()
            if word.isdigit():
                claims.append((sentence, int(word)))
            elif word in NUMBER_WORDS:
                claims.append((sentence, NUMBER_WORDS[word]))
    return claims


def prompt_name_claims(text: str) -> list[tuple[str, set]]:
    """Every sentence naming `prompts/list` with the backticked names it lists."""
    claims = []
    for sentence in sentences(text):
        if "`prompts/list`" not in sentence:
            continue
        names = {t for t in TICKED_RE.findall(sentence)
                 if "/" not in t and not t.startswith("nika_") and "*" not in t}
        if names:
            claims.append((sentence, names))
    return claims


def check_listing_pages(tools: set, prompts: set) -> bool:
    failed = False
    for rel in LISTING_PAGES:
        text = (ROOT / rel).read_text(encoding="utf-8")
        page_failed = False
        for kind, wire in (("tools", tools), ("prompts", prompts)):
            claims = count_claims(text, kind)
            if not claims:
                page_failed = True
                print(f"✗ {rel}: states no readable count of {kind} — say how many "
                      f"`{kind}/list` serves, in digits or a number word", file=sys.stderr)
            for sentence, count in claims:
                if count != len(wire):
                    page_failed = True
                    print(f"✗ {rel}: says {count} {kind}, the wire serves {len(wire)}: "
                          f"{sentence[:120]}", file=sys.stderr)
        for sentence, names in prompt_name_claims(text):
            if names != prompts:
                page_failed = True
                print(f"✗ {rel}: names prompts {sorted(names)}, the wire serves "
                      f"{sorted(prompts)}: {sentence[:120]}", file=sys.stderr)
        if page_failed:
            failed = True
        else:
            print(f"✓ {rel} · {len(count_claims(text, 'tools'))} tool and "
                  f"{len(count_claims(text, 'prompts'))} prompt counts match the wire "
                  f"({len(tools)} tools, {len(prompts)} prompts)")
    return failed


def main() -> int:
    nika = os.environ.get("NIKA_BIN") or shutil.which("nika")
    if not nika:
        print("check-mcp-tools: nika not on PATH — install it first", file=sys.stderr)
        return 1
    documented = documented_tools()
    served, prompts = wire_listing(nika)
    failed = check_listing_pages(served, prompts)
    if documented == served:
        print(f"✓ README ⟺ nika mcp agree · {len(served)} tools: "
              f"{' · '.join(sorted(served))}")
    else:
        failed = True
        print("✗ MCP tool drift — the README and `nika mcp` disagree", file=sys.stderr)
        if missing := documented - served:
            print(f"  README claims, binary does NOT serve: {sorted(missing)}", file=sys.stderr)
        if extra := served - documented:
            print(f"  binary serves, README does NOT list: {sorted(extra)}", file=sys.stderr)
    for path, names in kit_native_md_tools().items():
        if phantom := names - served:
            failed = True
            print(f"✗ {path} advertises unserved tools: {sorted(phantom)}",
                  file=sys.stderr)
        else:
            print(f"✓ {path} · {len(names)} advertised tool names all served")
    # the README's written count ("8 tools:") is hand-typed — derive-check it
    for m in re.finditer(r"(\d+)\s+tools?:", (ROOT / "README.md").read_text()):
        if int(m.group(1)) != len(served):
            failed = True
            print(f"✗ README says '{m.group(0)}' but the wire serves "
                  f"{len(served)} — update the count with the names",
                  file=sys.stderr)
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
