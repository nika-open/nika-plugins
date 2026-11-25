#!/usr/bin/env python3
# SPDX-License-Identifier: Apache-2.0
#
# The listing-page law of check-mcp-tools.py, without a binary: every count
# of tools or prompts a page's prose states must equal what the wire serves,
# a page must state one of each, and its `prompts/list` sentences must name
# exactly the served prompts.

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
    "At 0.125.1 the oracle serves nine `nika_*` tools over `tools/list` and\n"
    "seven prompts over `prompts/list` (`check`, `explain`, `compile`, `trace`,\n"
    "`permits`, `ideas`, `capture`). The rest is a plugin feature, e.g. the\n"
    "hooks.\n\n"
    "```sh\necho '3 prompts over `prompts/list`'\n```\n"
)


def verdict(page: str) -> tuple[bool, str]:
    with tempfile.TemporaryDirectory() as tmp:
        root = pathlib.Path(tmp)
        for rel in MODULE.LISTING_PAGES:
            (root / rel).parent.mkdir(parents=True, exist_ok=True)
            (root / rel).write_text(GOOD)
        (root / MODULE.LISTING_PAGES[-1]).write_text(page)
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
assert [c for _, c in MODULE.count_claims(GOOD, "tools")] == [9]
assert [c for _, c in MODULE.count_claims(GOOD, "prompts")] == [7], "the fenced 3 was read"
assert [n for _, n in MODULE.prompt_name_claims(GOOD)] == [PROMPTS]
print("mcp listing pages agree with the wire: PASS")

for wrong, said in (("seven prompts", "says 6 prompts"), ("nine `nika_*` tools", "says 8 tools")):
    page = GOOD.replace(wrong, "six prompts" if "prompts" in wrong else "8 `nika_*` tools")
    failed, err = verdict(page)
    assert failed and said in err, err
failed, err = verdict(GOOD + "\nEight tools ride `tools/list`.\n")
assert failed and "says 8 tools" in err, err
failed, err = verdict(GOOD + "\nA client that loads the stanza alone gets those six prompts.\n")
assert failed and "says 6 prompts" in err, "a count outside the `prompts/list` sentence was missed"
print("a wrong count anywhere in the prose is refused: PASS")

failed, err = verdict(GOOD.replace(", `capture`", ", `review`"))
assert failed and "'review'" in err, err
failed, err = verdict(GOOD.replace("`ideas`, ", ""))
assert failed and "names prompts" in err, err
print("a missing or phantom prompt name is refused: PASS")

failed, err = verdict(GOOD.replace("nine `nika_*` tools", "the `nika_*` tools"))
assert failed and "no readable count of tools" in err, err
failed, err = verdict(GOOD.replace("seven prompts", "its prompts"))
assert failed and "no readable count of prompts" in err, err
print("a page that states no count is refused, so a rewording cannot silence it: PASS")

split = MODULE.sentences(GOOD)
assert split[0].startswith("At 0.125.1 the oracle") and split[0].endswith("`capture`)."), split
assert split[1] == "The rest is a plugin feature, e.g. the hooks.", split
print("sentences keep version numbers and e.g. whole: PASS")
sys.exit(0)
