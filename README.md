# PillLab (standalone)

Isolated harness for the Local Cash pill — the vector coin (nods on
gains/losses, shakes "no" at zero) plus the cascading-digit balance
number in the map's Liquid Glass capsule. Fast builds and previews for
tuning the pill without the full app.

**Self-contained**: the pill sources are vendored under `Sources/`
(`LocalCashPill.swift`, `LocalCashCoin.swift`, `CascadeNumber.swift`,
`GlassModifiers.swift`), snapshotted from `squareup/neighbourhoods-tab`
at commit `76bb76b` ("Local Cash pill: the motion study lands"). This
copy does **not** track the app — the drift-proof harness that compiles
the app's files in place is `squareup/local-cash-pill-lab`, cloned as a
sibling of the app checkout.

## Setup

```
xcodegen generate
open PillLab.xcodeproj
```

Launch with the `-demo` argument to play a scripted balance sequence
(useful for headless recordings).
