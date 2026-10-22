#!/usr/bin/env python3
"""Compare two PHPUnit JUnit reports of the same suite test by test.

    compare.py <project> <reference.xml> <candidate.xml>

Exits 1 if a test that passes on the reference fails, errors, or is missing
on the candidate. Appends a summary to $GITHUB_STEP_SUMMARY when set.
"""

import os
import sys
import xml.etree.ElementTree as ET


def load(path):
    results = {}
    for case in ET.parse(path).iter("testcase"):
        key = f"{case.get('class') or case.get('classname')}::{case.get('name')}"
        if case.find("failure") is not None or case.find("error") is not None:
            results[key] = "fail"
        elif case.find("skipped") is not None:
            results[key] = "skip"
        else:
            results[key] = "pass"
    return results


def counts(results):
    return {s: sum(1 for v in results.values() if v == s) for s in ("pass", "skip", "fail")}


def main():
    project, reference_path, candidate_path = sys.argv[1:]
    try:
        reference = load(reference_path)
    except (OSError, ET.ParseError) as e:
        print(f"{project}: no usable reference report ({e})")
        return 1
    try:
        candidate = load(candidate_path)
    except (OSError, ET.ParseError):
        candidate = {}

    regressions = sorted(t for t, s in reference.items() if s == "pass" and candidate.get(t) != "pass")
    fixed = sorted(t for t, s in candidate.items() if s == "pass" and reference.get(t) != "pass")
    ref, cand = counts(reference), counts(candidate)

    lines = [
        f"{project}: {len(reference)} tests",
        f"  reference  {ref['pass']} passed, {ref['skip']} skipped, {ref['fail']} failed",
        f"  candidate  {cand['pass']} passed, {cand['skip']} skipped, {cand['fail']} failed",
        f"  {len(regressions)} regressions, {len(fixed)} tests pass only on the candidate",
    ]
    lines += [f"  REGRESSION {t} ({candidate.get(t, 'missing')})" for t in regressions[:50]]
    print("\n".join(lines))

    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a") as f:
            mark = "✅" if not regressions else "❌"
            f.write(
                f"| {mark} {project} | {len(reference)} | {ref['pass']} / {ref['skip']} / {ref['fail']}"
                f" | {cand['pass']} / {cand['skip']} / {cand['fail']} | {len(regressions)} |\n"
            )

    return 1 if regressions else 0


if __name__ == "__main__":
    sys.exit(main())
