# Screenshot harness (redesign swarm, wave 0)

Two commands cover the render-and-compare gate. Both write review artifacts to
`build/redesign/` — never committed, never compared as goldens.

## 1. Prototype screenshot (HTML → PNG)

Needs no npm install. Uses the cached Chromium binary directly (override with
`CHROMIUM=/path/to/chrome`).

```bash
# a phone from a design board, by CSS selector
node tool/prototype_shot.mjs \
  prototypes/cantiere-design.html \
  ".board .phone-card:nth-of-type(1) .phone" \
  build/redesign/prototype_cantiere_detail.png

# a list screen, by its id in list-screens.html
node tool/prototype_shot.mjs prototypes/list-screens.html cantieri \
  build/redesign/prototype_cantieri_list.png

# a master-data detail, by its name in other-details.html
node tool/prototype_shot.mjs prototypes/other-details.html Cliente \
  build/redesign/prototype_cliente_detail.png
```

Output is the phone / `.screen-card` alone at 390×844 CSS px, DPR 2 (so a
780×1688 PNG). Google Fonts are blocked: the box is often offline, and layout is
what the comparison is for — expect the system fallback font if the cache is
empty.

## 2. Flutter capture (screen → PNG)

```bash
fvm flutter test test/golden/redesign/cantiere_detail_demo_test.dart
# → build/redesign/cantiere_detail.png (780×1688, real bundled fonts)
```

Reusable helper: `test/golden/redesign/redesign_harness.dart`.

- `setUpAll(loadRedesignFonts)`
- `await captureRedesign(tester, '<screen>', child: <screen>, overrides: [...])`

The helper owns the 390×844 frame, DPR 2, `buildAppTheme()`, the
`ProviderScope`, and the `RepaintBoundary`. Pass fixtures/provider overrides as
usual. It never calls `pumpAndSettle` (screens may mount tickers) and drains real
async I/O briefly so Drift-backed names arrive before the capture.

These captures are **not** alchemist goldens: they are not compared and not
committed. The only committed goldens remain `test/golden/goldens/`.
