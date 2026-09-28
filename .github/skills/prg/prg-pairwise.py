#!/usr/bin/env python3
"""prg-pairwise.py — paired significance test for two ssg bench runs.  NO LLM.

Two ssg run dirs that graded the SAME cases (typically the same skill under
two MODELS, or one skill before/after a fix) produce PAIRED PASS/FAIL
outcomes: each case is observed in both runs.  The correct significance test
for paired binary outcomes is McNemar's, NOT a two-proportion z-test — the
z-test assumes independent samples and discards the pairing that carries most
of the information.

This tool reads each run's report.json, aligns cases by `id`, and reports:
  - the 2x2 paired concordance table (both-pass / both-fail / A-only / B-only)
  - McNemar EXACT binomial p (two-sided) on the discordant pairs
  - the continuity-corrected chi-square as a cross-check
  - the per-case flip lists, so the reader sees WHICH cases moved

Whether a difference is "significant" is a claim about the DISCORDANT pairs
only: concordant cases (both agree) say the case is easy or hard, not which
run is better.  A large concordant fraction means the SKILL, not the varied
factor, decides most outcomes.

Agent-first: stable report to stdout; a one-line VERDICT to stderr.
Exit: 0 = ran clean (regardless of significance)
      1 = a difference WAS significant at alpha (use in a gate if you want it)
      2 = bad args / unreadable report
      3 = case-set mismatch (the runs did not grade the same cases)

Usage:
  prg-pairwise.py <runA_dir> <runB_dir> [--alpha 0.05] [--gate]

  --gate  make exit 1 mean "significant" (default: 0 whether or not sig, so a
          plain comparison never trips a CI step).
"""
from __future__ import annotations

import argparse
import json
import sys
from math import comb
from pathlib import Path


def _load(run_dir: Path) -> tuple[str, dict[str, str]]:
    report = run_dir / "report.json"
    if not report.is_file():
        print(f"prg-pairwise: no report.json under {run_dir}", file=sys.stderr)
        raise SystemExit(2)
    try:
        d = json.loads(report.read_text())
    except (OSError, ValueError) as exc:
        print(f"prg-pairwise: cannot read {report}: {exc}", file=sys.stderr)
        raise SystemExit(2)
    # summary.model is the model that ACTUALLY answered; fall back to the run
    # dir name so the label is never empty.
    model = (d.get("summary") or {}).get("model") or run_dir.name
    cases = d.get("cases")
    if not isinstance(cases, list) or not cases:
        print(f"prg-pairwise: {report} has no cases[]", file=sys.stderr)
        raise SystemExit(2)
    verdicts = {c["id"]: c.get("verdict", "FAIL") for c in cases}
    return model, verdicts


def mcnemar_exact_two_sided(b: int, c: int) -> float:
    """Exact binomial McNemar: under H0 each discordant pair is a fair coin.
    p = 2 * P(X <= min(b,c)) with X~Binom(n=b+c, 0.5), clamped to 1."""
    n = b + c
    if n == 0:
        return 1.0
    k = min(b, c)
    tail = sum(comb(n, i) for i in range(k + 1)) / (2 ** n)
    return min(1.0, 2 * tail)


def mcnemar_chi2_cc(b: int, c: int) -> float:
    """Continuity-corrected chi-square statistic (1 dof)."""
    if b + c == 0:
        return 0.0
    return (abs(b - c) - 1) ** 2 / (b + c)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(prog="prg-pairwise.py", add_help=True)
    ap.add_argument("runA")
    ap.add_argument("runB")
    ap.add_argument("--alpha", type=float, default=0.05)
    ap.add_argument("--gate", action="store_true",
                    help="exit 1 when the difference is significant")
    args = ap.parse_args(argv)

    mA, A = _load(Path(args.runA))
    mB, B = _load(Path(args.runB))

    ids = sorted(set(A) & set(B))
    if len(A) != len(B) or len(ids) != len(A):
        print(f"prg-pairwise: case-set mismatch — A has {len(A)}, B has "
              f"{len(B)}, shared {len(ids)}. Runs must grade the SAME cases.",
              file=sys.stderr)
        return 3

    both_pass = both_fail = 0
    a_only: list[str] = []   # A PASS, B FAIL
    b_only: list[str] = []   # B PASS, A FAIL
    for cid in ids:
        ap_ = A[cid] == "PASS"
        bp_ = B[cid] == "PASS"
        if ap_ and bp_:
            both_pass += 1
        elif not ap_ and not bp_:
            both_fail += 1
        elif ap_ and not bp_:
            a_only.append(cid)
        else:
            b_only.append(cid)

    n = len(ids)
    b = len(a_only)   # discordant: A wins
    c = len(b_only)   # discordant: B wins
    a_pass = both_pass + b
    b_pass = both_pass + c

    p_exact = mcnemar_exact_two_sided(b, c)
    chi2 = mcnemar_chi2_cc(b, c)
    sig = p_exact < args.alpha

    # ---- stable report to stdout ------------------------------------------
    print(f"cases: {n}   concordant: {both_pass + both_fail} "
          f"({(both_pass + both_fail) / n:.0%})   discordant: {b + c}")
    print(f"  A  {mA:16s} pass: {a_pass}/{n}  ({a_pass / n:.1%})")
    print(f"  B  {mB:16s} pass: {b_pass}/{n}  ({b_pass / n:.1%})")
    print(f"  delta (B - A): {b_pass - a_pass:+d} cases "
          f"({(b_pass - a_pass) / n:+.1%})")
    print()
    print("  paired 2x2 concordance:")
    print(f"                       B PASS   B FAIL")
    print(f"    A PASS              {both_pass:6d}  {b:6d}")
    print(f"    A FAIL              {c:6d}  {both_fail:6d}")
    print()
    print(f"  discordant: b(A-only)={b}, c(B-only)={c}")
    print(f"  McNemar exact binomial p (two-sided): {p_exact:.4f}")
    print(f"  McNemar chi-square (cc, 1 dof):       {chi2:.3f}  "
          f"(crit 3.841 @ .05)")
    print(f"  => {'SIGNIFICANT' if sig else 'NOT significant'} "
          f"at alpha={args.alpha} (exact test)")
    print()
    print(f"  A-only wins ({b}): " + (", ".join(a_only) if a_only else "—"))
    print(f"  B-only wins ({c}): " + (", ".join(b_only) if b_only else "—"))

    # ---- one-line VERDICT to stderr ---------------------------------------
    print(f"VERDICT: {'SIGNIFICANT' if sig else 'ns'} "
          f"(p={p_exact:.3f}, delta={b_pass - a_pass:+d}/{n})", file=sys.stderr)

    return 1 if (sig and args.gate) else 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
