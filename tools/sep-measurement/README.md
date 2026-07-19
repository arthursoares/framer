# SEP transfer-curve measurement kit

Black-box measurement of Silver Efex Pro 3's tonality engine, used to fit
the response laws in `Sources/FramerCore/Effects/Metal/BWFilm.metal`
(2026-07-19). SEP's algorithms are compiled and unreadable; instead we
drive its GUI, export a known gray ramp, and extract input→output curves.

## Pieces

- `uiclick.swift` — CGEvent driver (click/double-click, real-keycode
  numeric typing for Qt fields, key chords). Build: `swiftc -O uiclick.swift -o uiclick`.
  Requires Accessibility + Screen Recording permission for the shell host.
- `measure_one.sh <rowY> <value> <exportName>` — sets one slider by typed
  value (double-click its value field at logical (1454, rowY)), exports
  via File ▸ Save Image as…, resets to 0. Focus-guarded at every keystroke
  batch: aborts rather than typing into the wrong app. Row coordinates
  assume the fresh-launch panel layout on a 1512×982 logical display —
  re-derive from a screenshot if the layout differs.
- `extract_curve.py <image> [out.csv]` — reads an exported 1024×256 ramp
  (4 px per level, via sips→BMP, no deps) → 256-point `level,out` CSV.
- `curves/` — the measured dataset (baseline + 12 control curves).

## Measured laws (fit rms in /255 units)

| Control | Law | rms |
|---|---|---|
| Brightness ≥0 | gamma, exponent `2^(-b/50)` | 0.34 |
| Brightness <0 | gamma, exponent `2^(-b/50 × 1.19)` | 7.1 (approx.) |
| Contrast ≥0 | log-odds sigmoid `g^k/(g^k+(1-g)^k)`, `k = 3^(c/100)` | 0.76 |
| Contrast <0 | same, `k = 3^(c/100 × 0.86)` | 0.71 |
| Zone shadows | `Δ = s × 1.19·g^0.65·(1-g)^5.8` | 0.78 |
| Zone midtones | `Δ = s × 0.79·g^0.80·(1-g)^1.4` | 0.75 |
| Zone highlights | `Δ = s × 0.17·g^1.95·(1-g)^0.4` | 3.4 |

Universal finding: SEP pins BOTH endpoints for every tonality control.

Caveats: Amplify Whites/Blacks, Soft Contrast, and Dynamic Brightness are
content-adaptive — their ramp curves (in `curves/`) are conditioned on a
uniform histogram and NOT yet implemented as laws. Baseline (all-zero)
measured as exact identity, validating the rig end-to-end.

End-to-end parity after fitting (framer bwFilm render vs SEP export,
same ramp): Brightness +50 mean 0.18/255 · Contrast +50 mean 0.60/255 ·
Shadows +100 mean 0.48/255.
