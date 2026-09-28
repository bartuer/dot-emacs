# Table-discovery bench — corpus, rubric, and known limits

## Why this bench exists

The earlier gold set (`../gold.tables.jsonl`, 563 rectangles) has two defects
that make it unusable for scoring:

1. **69% of it is unpinned.** 390 of 563 rectangles come from
   `evn_artifacts/artifacts/53261189`, a CI automation dump with no manifest
   and no sha256s. Nobody else can reproduce it.
2. **It double-counts.** 57 SpreadsheetBench case IDs appear as both
   `_input` and `_answer`. Measured on 40 pairs: **39/40 have byte-identical
   table geometry.** For table discovery those are one sample, not two.

This bench is built only on `/workspace/datasets/SpreadsheetBench`, which is
sha256-pinned to a canonical upstream, and uses the **case** as the sample
unit (input arm only).

## Sample unit

`(file, sheet)` — the same unit as the positive rectangles.
One arm per case: `inputs/<case>_input.xlsx`. The answer arm is discarded.

## Positive class — machine-derived, no human judgement

`gold.positives.jsonl`: every `table` (ListObject) or `af` (autoFilter)
rectangle declared by the workbook itself, via `silo --dump-meta-json`.
146 rectangles / 132 (file,sheet) pairs / 115 files. Reproducible by rerunning
the extractor; no labelling required.

## Negative class — hand-labelled, and it has to be

`gold.negatives.jsonl`: sheets containing **no tabular region at all**.

**"No declaration" does NOT mean "no table."** Only 115 of 905 cases declare
anything; the other 790 are mostly undeclared *tables*. Auto-labelling the
undeclared pool as negative would poison the set. Measured base rate in a
60-sheet hand-labelled sample: **37 have a table, 23 do not** — so a naive
auto-label would have been wrong 62% of the time.

### Labelling rubric

A sheet is `label:"none"` (table-free) when it has **no** contiguous region of
≥2 data rows × ≥2 columns where a header-like first row names fields that the
rows below populate positionally.

Table-free, with the forms seen in this corpus:

| pattern            | example                                            |
|--------------------|----------------------------------------------------|
| label:value form   | `Order No: …` / `Invoice No: …` blocks stacked     |
| legend + calendar  | attendance sheets: `A - ABSENT`, `L - LEAVE` keys  |
| single column      | bare ID or numeric column, no header, no fields    |
| scatter / puzzle   | word-per-cell spreads, `dog/cat` literals          |
| placeholder grid   | the literal string `Header` repeated               |
| lookup source      | a dropdown's 2-3 value list                        |
| calendar grid      | weekday headers over date cells, not records       |

Explicitly **NOT** table-free (all seen and labelled positive here):

- **Sparse wide tables.** `1_147-7` `Step1` is an 18-column GST table whose
  rows populate only 2 cells. Sparsity is not form-ness — see below.
- **Small tables.** `Name`/`amount` + 3 rows is a table at 8 cells.
- **Multi-block sheets.** Two side-by-side header+record blocks are tables.

### Discarded heuristic — recorded so it is not retried

`thin_ratio` = fraction of rows with ≤2 populated cells, intended as a form
detector. **It does not work.** It scored 1.00 on `1_147-7` `Step1`, a plain
18-column table. Enrichment measured: 43% negatives in the high arm vs 33% in
the low arm — barely better than chance. Both arms are therefore retained in
the sample and `thin_ratio` is **not** used as a label input, only as a
sampling stratifier. It is carried in the `arm` field for audit.

### Near-duplicate cap

Template workbooks repeat one layout across many sheets (`1_11842` has the
same attendance form in 7 monthly sheets). Uncapped, one workbook would supply
7 of 23 negatives and the class would measure a single layout. **Cap: 2 sheets
per file.** 23 labelled negatives → **18 kept, from 14 distinct files.**

## Leakage

Verified zero overlap between classes at both `(file,sheet)` and case level.
Since positives come only from declared workbooks and negatives only from
undeclared ones, the classes are disjoint by construction; the check guards
against regressions in the extractor.

## Known limits — read before quoting a number

- **The negative class is small (18).** Precision on it has wide error bars;
  treat it as a smoke test for "does the detector fire on non-tables," not as
  a precise precision estimate.
- **The positive class is declaration-derived**, so it inherits Excel's own
  choices. A detector that finds a *real* table nobody declared is scored as a
  false positive here. That is a floor on measurable precision, not a bug in
  the detector.
- **Undeclared tables are absent from the positive class**, and they are the
  overwhelming majority of the corpus. This bench measures discovery on
  declared shapes plus rejection of non-tables. It does **not** measure recall
  over undeclared tables — that needs a much larger hand-labelled positive set.

## Reproducing

```bash
sha256sum -c <(awk '!/^#/{print $1"  /workspace/datasets/"$3}' MANIFEST.sha256)
./score.sh <detector-cmd>
```
