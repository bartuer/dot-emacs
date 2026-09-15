// silo: one binary. scout (route) + cells + formulas + charts, single open.
//
// THREE cell axes, because one number cannot honestly answer both
// "how much DATA is here" and "how many cells are OCCUPIED":
//
//   cells    values-only. Non-empty cells in the VALUE range. A formula
//            saved without a cached <v> is Data::Empty here, so it does
//            NOT count. This is the historical axis; kept stable.
//   formulas non-empty cells in the FORMULA range (formula TEXT).
//   used     OCCUPANCY = |value-nonempty UNION formula-nonempty|. The two
//            ranges are DISJOINT in the common case (uncached formulas)
//            but MAY overlap (a formula WITH a cached result appears in
//            both), so this is a real union, not cells+formulas.
//
// Why the union matters, measured (see fix.archive/silo-image-regression-
// 2026-08-20.md): on `Weekly Sales Data.xlsx` every one of 3,864 formulas
// is stored with no cached <v>, so cells=17,527 while occupancy=21,391.
// Reporting `cells` as occupancy under-counts that file by 18%.
//
// NB `used_cells()` is EXACTLY the old hand-written
// `.cells().filter(|(_,_,v)| **v != Data::Empty)` -- UsedCells::next does
// `find(|(_,v)| v != &T::default())` and Data::default() is Data::Empty
// (datatype.rs:109). Switching to it changes no count; it removes a
// hand-rolled predicate that could drift from calamine's own notion of
// emptiness. The NEW information is `used`, not the rename.
//
// EMPTY-STRING CELLS (`is_blank`). `used_cells()` filters only Data::Empty,
// but a cell can be present-and-yet-blank in two ways that both decode to
// Data::String(""):
//   1. `<c t="s"><v>N</v></c>` where sharedStrings entry N is the EMPTY
//      string. Measured: one workbook had 12,920 cells all pointing at the
//      same empty shared string (1_253-22_input.xlsx).
//   2. `<c t="str"><v></v></c>` -- a literal empty inline value, typically
//      a formula result that was cached as blank (1_49490_answer.xlsx:
//      6,970 cells).
// Excel shows both as blank and openpyxl drops both; counting them
// inflated occupancy on 70/1817 workbooks by 46,634 cells. We therefore
// treat whitespace-only strings as unoccupied in the VALUE range.
//
// The FORMULA range is deliberately NOT filtered this way: there the value
// IS the formula text, and `used_cells()`'s Data::Empty test already
// removes the blanks. A cell holding a formula is occupied even when that
// formula's cached result is the empty string.
// open_workbook_auto dispatches on extension to the Xls / Xlsb / Ods / Xlsx
// reader.  The old code pinned `Xlsx`, which drives the ZIP reader
// unconditionally -- so every .xls (an OLE2 compound file, NOT a zip) died
// with "invalid Zip archive: Could not find EOCD".  Charts stay xlsx-only
// because calamine only implements them there.
use calamine::{open_workbook_auto, Data, Reader, Sheets};
use std::collections::HashSet;
use std::time::Instant;

/// A cell that is PRESENT in the sheet XML but renders blank in Excel.
/// `used_cells()` has already dropped Data::Empty; this additionally drops
/// the empty/whitespace-only STRING, which is how both an empty
/// sharedStrings entry and a literal `<v></v>` decode. See the header note.
fn is_blank(v: &Data) -> bool {
    match v {
        Data::Empty => true,
        // ONLY the truly empty string is blank.  Two earlier rules were both
        // wrong: trim().is_empty() dropped a lone form-feed (_x000C_) as
        // whitespace, and treating ASCII spaces as blank dropped 2,311 cells
        // holding a single space -- Excel stores those and openpyxl reports
        // them, so they are CONTENT.  A cell is unoccupied only when it
        // carries no characters at all; the empty-sharedString and <v></v>
        // shapes this helper exists for both decode to exactly "".
        Data::String(s) => s.is_empty(),
        _ => false,
    }
}

/// Python's `time.isoformat()`: HH:MM:SS, with `.ffffff` appended ONLY when
/// the microsecond part is non-zero.  Excel carries at most millisecond
/// precision, so the fraction is always the ms padded to 6 digits.
fn fmt_time(h: u8, mi: u8, s: u8, ms: u16) -> String {
    if ms == 0 {
        format!("{h:02}:{mi:02}:{s:02}")
    } else {
        format!("{h:02}:{mi:02}:{s:02}.{:06}", ms as u32 * 1000)
    }
}

/// Python's `str(datetime.timedelta)` for an Excel duration serial (a count
/// of DAYS).  Format is `[D day[s], ]H:MM:SS[.ffffff]` -- note the hour is
/// NOT zero-padded, unlike time.isoformat().
fn py_timedelta(days: f64) -> String {
    let total_ms = (days * 86_400_000.0).round() as i64;
    let neg = total_ms < 0;
    let a = total_ms.abs();
    let (d, rem) = (a / 86_400_000, a % 86_400_000);
    let (h, rem) = (rem / 3_600_000, rem % 3_600_000);
    let (m, rem) = (rem / 60_000, rem % 60_000);
    let (s, ms) = (rem / 1000, rem % 1000);
    let mut out = String::new();
    if neg {
        out.push('-');
    }
    if d != 0 {
        out.push_str(&format!("{d} day{}, ", if d == 1 { "" } else { "s" }));
    }
    out.push_str(&format!("{h}:{m:02}:{s:02}"));
    if ms != 0 {
        out.push_str(&format!(".{:06}", ms * 1000));
    }
    out
}

/// Canonical scalar rendering for VALUE-level diffing against another
/// engine. Numbers are normalised (12.0 -> "12") so that a float/int
/// representation difference is not reported as a data difference; that is
/// a rendering artifact, not a wrong cell.
fn render(v: &Data) -> String {
    match v {
        Data::Empty => String::new(),
        // NO trim(): Rust's trim() is Unicode-whitespace aware and so eats
        // U+000B/U+000C -- real content that OOXML deliberately escaped as
        // _x000B_/_x000C_.  Excel preserves leading/trailing whitespace, so
        // trimming here silently altered cell values.  Blank DETECTION still
        // trims (is_blank), but that is a separate judgement from rendering.
        Data::String(s) => s.to_string(),
        Data::Float(f) => {
            if f.fract() == 0.0 && f.abs() < 1e15 {
                format!("{}", *f as i64)
            } else {
                format!("{f}")
            }
        }
        Data::Int(i) => format!("{i}"),
        Data::Bool(b) => if *b { "TRUE" } else { "FALSE" }.to_string(),
        // `{}` NOT `{:?}`: calamine's Display for CellErrorType emits the
        // Excel literal (#N/A, #VALUE!, #REF!, lib.rs:173-180) whereas Debug
        // emits the Rust variant name (NA, Value, Ref).  Using Debug here
        // silently mis-rendered every error cell -- 2,212 in one workbook.
        Data::Error(e) => format!("{e}"),
        // Excel stores dates/times as a serial float; printing that float
        // (the previous behaviour) disagreed with every other reader on
        // 249,337 cells.  NOTE: Data::DateTime is NOT behind the `chrono`
        // feature and to_ymd_hms_milli() is always available, so no feature
        // flag is needed -- the value was arriving correctly and was being
        // mis-RENDERED.  We reproduce openpyxl's from_excel() dispatch
        // (utils/datetime.py) so the two agree literally:
        //   * duration format ([hh]:mm:ss) -> timedelta, str()'d by Python
        //   * 0 <= serial < 1              -> time.isoformat()
        //   * otherwise                    -> datetime.isoformat()
        // Python omits the fractional part entirely when it is zero.
        Data::DateTime(d) => {
            let v = d.as_f64();
            if d.is_duration() {
                py_timedelta(v)
            } else if (0.0..1.0).contains(&v) {
                let (_, _, _, h, mi, s, ms) = d.to_ymd_hms_milli();
                fmt_time(h, mi, s, ms)
            } else if v < 0.0 {
                // NEGATIVE serial (e.g. `=B9-TIME(0,30,0)` crossing midnight,
                // cached as -0.0104166).  calamine's to_ymd_hms_milli() does
                // not handle negatives and clamps to the epoch, which printed
                // 1899-12-31T00:00:00 for 49 distinct real values.  openpyxl
                // just adds a signed timedelta to the epoch, so do the same.
                // Excel itself renders these as ####; openpyxl's reading is
                // the faithful one, so we match it.
                epoch_offset(v)
            } else {
                let (y, mo, da, h, mi, s, ms) = d.to_ymd_hms_milli();
                format!("{y:04}-{mo:02}-{da:02}T{}", fmt_time(h, mi, s, ms))
            }
        }
        Data::DateTimeIso(s) | Data::DurationIso(s) => s.to_string(),
        Data::RichText(r) => r.plain_text().to_string(),
    }
}

/// `WINDOWS_EPOCH (1899-12-30) + timedelta(days=serial)`, i.e. openpyxl's
/// from_excel() for serials the 1900-leap-bug correction does not apply to.
/// Used for NEGATIVE serials, which calamine's to_ymd_hms_milli() clamps.
/// Pure civil-date arithmetic (Howard Hinnant's days-from-civil, inverted)
/// so no chrono dependency is required.
fn epoch_offset(days: f64) -> String {
    let total_ms = (days * 86_400_000.0).round() as i64;
    // Excel epoch 1899-12-30 = -25569 days from the Unix epoch (Unix epoch
    // 1970-01-01 is Excel serial 25569).
    let mut z = -25569 + total_ms.div_euclid(86_400_000);
    let rem = total_ms.rem_euclid(86_400_000);
    // days-from-civil, inverted (civil_from_days).
    z += 719_468;
    let era = z.div_euclid(146_097);
    let doe = z.rem_euclid(146_097);
    let yoe = (doe - doe / 1460 + doe / 36_524 - doe / 146_096) / 365;
    let y = yoe + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let da = doy - (153 * mp + 2) / 5 + 1;
    let mo = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = if mo <= 2 { y + 1 } else { y };
    let (h, r) = (rem / 3_600_000, rem % 3_600_000);
    let (mi, r) = (r / 60_000, r % 60_000);
    let (s, ms) = (r / 1000, r % 1000);
    format!(
        "{y:04}-{mo:02}-{da:02}T{}",
        fmt_time(h as u8, mi as u8, s as u8, ms as u16)
    )
}

/// Escape a value so one cell always occupies exactly one TSV row while
/// remaining LOSSLESS.  The first version replaced \t\r\n with a space,
/// which silently destroyed the distinction between a real newline and a
/// real space -- that alone accounted for ~250 phantom "differences" across
/// the corpus.  A diff harness must never mutate the data it compares.
fn esc(s: &str) -> String {
    let mut o = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '\\' => o.push_str("\\\\"),
            '\t' => o.push_str("\\t"),
            '\n' => o.push_str("\\n"),
            '\r' => o.push_str("\\r"),
            // Any OTHER control character must be escaped too.  OOXML carries
            // them via _xNNNN_ (calamine decodes per spec), so a decoded
            // U+000B / U+000C / U+0007 would otherwise be emitted RAW into the
            // TSV and corrupt the row -- the same class of harness bug as the
            // newline mangling: the diff tool damaging the data it compares.
            c if (c as u32) < 0x20 || (c as u32) == 0x7f => {
                o.push_str(&format!("\\x{:02X}", c as u32))
            }
            _ => o.push(c),
        }
    }
    o
}

/// `--dump <file>`: emit one TSV row per OCCUPIED cell,
/// `sheet \t row \t col \t value` on ABSOLUTE 1-based coordinates, so a
/// second engine's dump can be diffed cell-for-cell. Counts alone cannot
/// catch a false-gain that cancels a false-loss; values can.
fn dump(p: &str) {
    dump_mode(p, DumpMode::Values)
}

#[derive(Clone, Copy, PartialEq)]
enum DumpMode {
    Values,
    /// Formula TEXT per cell -- the gate names "formula value" as its own
    /// axis, and a values-only dump cannot catch a formula that silo reads
    /// differently from openpyxl (shared/array formula expansion in
    /// particular).
    Formulas,
    /// One row per sheet, then one per chart: the "meta" and "chart value"
    /// axes.  Sheet ORDER is significant, so it is emitted as an index.
    Meta,
}

/// Charts are implemented on the Xlsx reader only.  For .xls/.xlsb/.ods
/// calamine exposes no chart API at all, so report none rather than
/// pretending -- a legacy file with charts is a KNOWN gap, not a zero.
fn charts_of(wb: &mut Sheets<std::io::BufReader<std::fs::File>>, s: &str) -> Vec<calamine::Chart> {
    match wb {
        Sheets::Xlsx(x) => x.worksheet_charts(s).unwrap_or_default(),
        _ => vec![],
    }
}

/// Excel column index (0-based) -> A1 letters. 0->A, 25->Z, 26->AA.
/// This is what makes a cell addressable by the OfficeJS layer (G5): a
/// {row,col} pair is useless to `Range("D2")` without it.
fn a1_col(mut c: u32) -> String {
    let mut out = Vec::new();
    loop {
        out.push(b'A' + (c % 26) as u8);
        if c < 26 {
            break;
        }
        c = c / 26 - 1;
    }
    out.reverse();
    String::from_utf8(out).unwrap()
}

/// The type TAG for a cell, preserving the distinction `render()` destroys.
/// Measured over 400 workbooks / 629,760 cells: 295,862 rendered values are
/// type-AMBIGUOUS once flattened to a string, so a consumer cannot recover
/// this by re-inference -- and must not try: 4,970 cells hold strings like
/// "01"/"02" that any numeric re-inference would corrupt.
fn type_tag(v: &Data) -> &'static str {
    match v {
        Data::Empty => "z",
        Data::String(_) => "s",
        Data::RichText(_) => "s",
        Data::Float(_) => "n",
        Data::Int(_) => "n",
        Data::Bool(_) => "b",
        Data::Error(_) => "e",
        // ckp1.3: JSON has NO date type.  A date MUST carry an explicit tag
        // or it is indistinguishable from the string it serialises to.
        Data::DateTime(d) => {
            if d.is_duration() {
                "t"
            } else {
                "d"
            }
        }
        Data::DateTimeIso(_) => "d",
        Data::DurationIso(_) => "t",
    }
}

/// The JSON `v` payload. Numbers stay NUMBERS so jq can do arithmetic
/// without a tonumber() dance; everything else is a string whose text is
/// byte-identical to the green TSV dump, so the closed gate still applies.
///
/// serde_json formats f64 via its shortest-round-trip float writer, which
/// is why this is NOT `format!("{}")`: the latter expands 1e308 into 309
/// digits.  660 cells in the corpus carry >15 significant digits.
fn json_value(v: &Data) -> serde_json::Value {
    use serde_json::Value as J;
    match v {
        // An Int is exact; emitting it through f64 would risk >2^53.
        Data::Int(i) => J::from(*i),
        Data::Float(f) => {
            // Match render()'s integral-float normalisation so the TSV and
            // JSON dumps agree cell-for-cell, then let serde emit the number.
            if f.fract() == 0.0 && f.abs() < 1e15 {
                J::from(*f as i64)
            } else {
                serde_json::Number::from_f64(*f).map(J::Number).unwrap_or(J::Null)
            }
        }
        Data::Bool(b) => J::Bool(*b),
        _ => J::String(render(v)),
    }
}

fn dump_json(p: &str) {
    let mut wb = match open_workbook_auto(p) {
        Ok(w) => w,
        Err(e) => {
            eprintln!("dump: cannot open {p}: {e}");
            std::process::exit(1);
        }
    };
    let names = wb.sheet_names().to_vec();
    for s in names {
        // Formulas live in a SEPARATE range with a different element type,
        // so collect them first and join by coordinate -- this is the whole
        // point of the JSON form: TSV needed two passes the consumer had to
        // re-join itself.
        let mut fx: std::collections::HashMap<(u32, u32), String> =
            std::collections::HashMap::new();
        if let Ok(fr) = wb.worksheet_formula(&s) {
            if let Some((r0, c0)) = fr.start() {
                for (row, col, f) in fr.used_cells() {
                    if !f.is_empty() {
                        fx.insert((r0 + row as u32, c0 + col as u32), f.to_string());
                    }
                }
            }
        }
        if let Ok(r) = wb.worksheet_range(&s) {
            if let Some((r0, c0)) = r.start() {
                for (row, col, v) in r.used_cells() {
                    if is_blank(v) {
                        continue;
                    }
                    let (ar, ac) = (r0 + row as u32, c0 + col as u32);
                    let mut o = serde_json::Map::new();
                    o.insert("s".into(), serde_json::Value::String(s.clone()));
                    o.insert("r".into(), serde_json::Value::from(ar + 1));
                    o.insert("c".into(), serde_json::Value::from(ac + 1));
                    o.insert(
                        "a".into(),
                        serde_json::Value::String(format!("{}{}", a1_col(ac), ar + 1)),
                    );
                    o.insert(
                        "t".into(),
                        serde_json::Value::String(type_tag(v).into()),
                    );
                    o.insert("v".into(), json_value(v));
                    if let Some(f) = fx.get(&(ar, ac)) {
                        o.insert("f".into(), serde_json::Value::String(f.clone()));
                        // A formula cell's `t` describes its CACHED value;
                        // the presence of `f` is what marks it a formula.
                    }
                    // to_string() on a Value cannot emit malformed JSON --
                    // that is the whole answer to :frontier-2:.
                    println!("{}", serde_json::Value::Object(o));
                }
            }
        }
    }
}

fn dump_mode(p: &str, mode: DumpMode) {
    let mut wb = match open_workbook_auto(p) {
        Ok(w) => w,
        Err(e) => {
            eprintln!("dump: cannot open {p}: {e}");
            std::process::exit(1);
        }
    };
    let names = wb.sheet_names().to_vec();
    if mode == DumpMode::Meta {
        for (i, s) in names.iter().enumerate() {
            println!("sheet\t{}\t{}", i + 1, esc(s));
        }
        for s in &names {
            {
                let cs = charts_of(&mut wb, s);
                for (i, c) in cs.iter().enumerate() {
                    println!(
                        "chart\t{}\t{}\t{:?}",
                        esc(s),
                        i + 1,
                        c.chart_type()
                    );
                }
            }
        }
        return;
    }
    for s in names {
        // The two ranges have DIFFERENT element types (Data vs String), so
        // they cannot share one loop body.
        if mode == DumpMode::Formulas {
            if let Ok(r) = wb.worksheet_formula(&s) {
                if let Some((r0, c0)) = r.start() {
                    for (row, col, f) in r.used_cells() {
                        if f.is_empty() {
                            continue;
                        }
                        println!(
                            "{}\t{}\t{}\t{}",
                            s,
                            r0 + row as u32 + 1,
                            c0 + col as u32 + 1,
                            esc(f)
                        );
                    }
                }
            }
            continue;
        }
        if let Ok(r) = wb.worksheet_range(&s) {
            if let Some((r0, c0)) = r.start() {
                for (row, col, v) in r.used_cells() {
                    if is_blank(v) {
                        continue;
                    }
                    println!(
                        "{}\t{}\t{}\t{}",
                        s,
                        r0 + row as u32 + 1,
                        c0 + col as u32 + 1,
                        esc(&render(v))
                    );
                }
            }
        }
    }
}

fn main() {
    // Rust sets SIGPIPE to SIG_IGN before main, so a write to a closed pipe
    // returns EPIPE; println! cannot report that and panics (exit 101).
    // A CLI filter wants the Unix default: die quietly when the reader exits.
    // Bites `| head`, `jq -n input`, and `jq 'first(inputs)'` alike.
    #[cfg(unix)]
    unsafe {
        libc::signal(libc::SIGPIPE, libc::SIG_DFL);
    }
    let argv: Vec<String> = std::env::args().skip(1).collect();
    match argv.first().map(|s| s.as_str()) {
        Some("--dump") => {
            for p in &argv[1..] {
                dump(p);
            }
            return;
        }
        Some("--dump-json") => {
            for p in &argv[1..] {
                dump_json(p);
            }
            return;
        }
        Some("--dump-formulas") => {
            for p in &argv[1..] {
                dump_mode(p, DumpMode::Formulas);
            }
            return;
        }
        Some("--dump-meta") => {
            for p in &argv[1..] {
                dump_mode(p, DumpMode::Meta);
            }
            return;
        }
        _ => {}
    }
    for p in std::env::args().skip(1) {
        let t = Instant::now();
        let mut wb = match open_workbook_auto(&p) {
            Ok(w) => w,
            Err(e) => {
                // G1: never silently drop. Name the reason.
                let why = if e.to_string().contains("assword") || e.to_string().contains("ncrypt") {
                    "ole-encrypted"
                } else {
                    "unreadable"
                };
                println!(
                    "{{\"path\":{:?},\"degraded\":{:?},\"err\":{:?}}}",
                    p,
                    why,
                    e.to_string()
                );
                continue;
            }
        };
        let names = wb.sheet_names().to_vec();
        let (mut cells, mut fx, mut used, mut charts, mut titles) =
            (0usize, 0usize, 0usize, 0usize, 0usize);
        let mut kinds: Vec<String> = vec![];
        for s in &names {
            // Absolute (row, col) of every populated cell on THIS sheet, so
            // the union is computed per-sheet and cannot collide across
            // sheets. Ranges are relative to their own start(), and the
            // value range and formula range need NOT share an origin --
            // hence the absolute rebase before inserting.
            let mut occupied: HashSet<(u32, u32)> = HashSet::new();

            if let Ok(r) = wb.worksheet_range(s) {
                if let Some((r0, c0)) = r.start() {
                    for (row, col, v) in r.used_cells() {
                        if is_blank(v) {
                            continue;
                        }
                        cells += 1;
                        occupied.insert((r0 + row as u32, c0 + col as u32));
                    }
                }
            }
            if let Ok(r) = wb.worksheet_formula(s) {
                if let Some((r0, c0)) = r.start() {
                    for (row, col, _) in r.used_cells() {
                        fx += 1;
                        occupied.insert((r0 + row as u32, c0 + col as u32));
                    }
                }
            }
            used += occupied.len();

            {
                let cs = charts_of(&mut wb, s);
                for c in cs {
                    charts += 1;
                    kinds.push(format!("{:?}", c.chart_type()));
                    if c.title.is_some() {
                        titles += 1;
                    }
                }
            }
        }
        let route = if charts > 0 {
            "chart"
        } else if fx > 0 {
            "formula"
        } else {
            "bulk"
        };
        println!("{{\"path\":{:?},\"route\":{:?},\"sheets\":{},\"cells\":{},\"formulas\":{},\"used\":{},\"charts\":{},\"titles\":{},\"kinds\":{:?},\"sec\":{:.4}}}",
      p,route,names.len(),cells,fx,used,charts,titles,kinds,t.elapsed().as_secs_f64());
    }
}
