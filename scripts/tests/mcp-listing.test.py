#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# The listing-page law of check-mcp-tools.py, without a binary: a page's
# `tools/list` and `prompts/list` sentences must state the served counts and
# name exactly the served prompts.

import contextlib
import importlib.util
import io
import pathlib
import sys
import tempfile

SCRIPT = pathlib.Path(__file__).resolve().parent.parent / "check-mcp-tools.py"
spec = importlib.util.spec_from_file_location("check_mcp_tools", SCRIPT)
MODULE = importlib.util.module_from_spec(spec)
spec.loader.exec_module(MODULE)

TOOLS = {f"nika_{n}" for n in "canon catalog check examples explain inspect schema template tools".split()}
PROMPTS = set("capture check compile explain ideas permits trace".split())
GOOD = (
    "The oracle serves nine `nika_*` tools over `tools/list` and seven prompts\n"
    "over `prompts/list` (`check`, `explain`, `compile`, `trace`, `permits`,\n"
    "`ideas`, `capture`). The rest is a plugin feature.\n\n"
    "```sh\necho '3 prompts over `prompts/list`'\n```\n"
)


def verdict(page: str) -> tuple[bool, str]:
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        for rel in MODULE.LISTING_PAGES:
            (root / rel).parent.mkdir(parents=True, exist_ok=True)
            (root / rel).write_text(GOOD)
        (root / MODULE.LISTING_PAGES[0]).write_text(page)
        saved, MODULE.ROOT = MODULE.ROOT, root
        err = io.StringIO()
        try:
            with contextlib.redirect_stdout(io.StringIO()), contextlib.redirect_stderr(err):
                failed = MODULE.check_listing_pages(TOOLS, PROMPTS)
        finally:
            MODULE.ROOT = saved
        return failed, err.getvalue()


failed, err = verdict(GOOD)
assert not failed, err
claims = MODULE.listing_claims(GOOD, "prompts")
assert [(c, n) for _, c, n in claims] == [(7, PROMPTS)], claims
assert [c for _, c, _ in MODULE.listing_claims(GOOD, "tools")] == [9]
print("mcp listing pages agree with the wire: PASS")

failed, err = verdict(GOOD.replace("seven prompts", "six prompts"))
assert failed and "says 6 prompts" in err, err
failed, err = verdict(GOOD.replace("nine `nika_*` tools", "8 `nika_*` tools"))
assert failed and "says 8 tools" in err, err
print("a wrong count over tools/list or prompts/list is refused: PASS")

failed, err = verdict(GOOD.replace(", `capture`", ", `review`"))
assert failed and "'review'" in err, err
failed, err = verdict(GOOD.replace("`ideas`, ", ""))
assert failed and "names prompts" in err, err
print("a missing or phantom prompt name is refused: PASS")

failed, err = verdict(GOOD.replace(") The rest", ") Nine tools ride `tools/list`. The rest"))
assert not failed, err
print("a number word counts as a claim, a fenced block does not: PASS")
sys.exit(0)
