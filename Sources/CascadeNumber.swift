import CoreText
import SwiftUI

// Port of the Local Cash Motion Study's number treatment (AnimatedNumber,
// mode "cascade") — as a FRAME-DRIVEN engine, the way the web version runs.
//
// The web build animates imperatively: every frame, JavaScript evaluates
// spring curves and writes each column's width and each glyph's
// y/blur/opacity. Nothing is delegated to a system animation engine. Four
// generations of this file tried to express that choreography through
// SwiftUI's declarative animation system and each one fell into a different
// hidden behavior — transitions freezing mid-reflow, scoped animations
// hijacking positions, Liquid Glass resizing on a private clock. This version
// ports the web's ENGINE, not just its parameters: a TimelineView ticks every
// frame, the same springs are evaluated analytically (the web's springParams
// is explicitly SwiftUI's Spring(duration:bounce:) parameterization, so
// Apple's Spring type IS the web's curve), and one Canvas draws everything
// from plain numbers. The pill, dot, digits, and clips all derive from a
// single clock, exactly like the web.
//
// Choreography (from AnimatedNumber.tsx, mode "cascade"):
// - No odometer rolling: every changed column goes straight to its final
//   digit, rising a short distance into place, staggered left to right.
//   Digits arrive from the direction the value is heading; the old digit
//   ghosts out the opposite way, blurring.
// - Column widths hug each digit's own advance and glide on a calmer layout
//   spring, undelayed, so the dot and the pill ride one curve.
// - Each column clips its glyphs to its animated box (the web's
//   overflow:hidden, inset 0) — a leaving ghost is swallowed by its own
//   collapsing cell instead of sliding out past the pill.
// - When the integer part gains or loses columns, every column moves — the
//   full-row ripple.
struct CascadeNumber: View {
    var value: Double
    var uiFont: UIFont
    var textColor: Color
    var decimals: Int = 2

    @State private var engine: Engine
    @State private var settled = true
    @State private var settleTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(value: Double, uiFont: UIFont, textColor: Color, decimals: Int = 2) {
        self.value = value
        self.uiFont = uiFont
        self.textColor = textColor
        self.decimals = decimals
        // Proportional figures, as on the web (fontVariantNumeric: normal).
        // Cash Sans already defaults to them; forcing the feature guards
        // against a font whose tabular default would pad every column.
        let descriptor = uiFont.fontDescriptor.addingAttributes([
            .featureSettings: [[
                UIFontDescriptor.FeatureKey.type: kNumberSpacingType,
                UIFontDescriptor.FeatureKey.selector: kProportionalNumbersSelector,
            ]],
        ])
        let numberFont = UIFont(descriptor: descriptor, size: uiFont.pointSize)
        _engine = State(initialValue: Engine(
            value: value, decimals: decimals, font: numberFont
        ))
    }

    var body: some View {
        // The engine is pure state + math; the TimelineView is the web's
        // requestAnimationFrame. When everything has settled the timeline
        // pauses and the canvas keeps drawing the final frame for free.
        TimelineView(.animation(minimumInterval: nil, paused: settled)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            Canvas { ctx, size in
                engine.draw(in: &ctx, size: size, at: t, color: textColor)
            }
            // The canvas carries vSlop of extra height top and bottom (its
            // bounds are a clip too); negative padding hands layout the
            // tight box, so the pill's height doesn't change.
            .frame(width: engine.width(at: t), height: engine.lineH + engine.vSlop * 2)
            .padding(.vertical, -engine.vSlop)
        }
        // Digits have no descenders, so their ink rides low in the line box.
        // Lift by the metric imbalance plus a measured optical constant
        // (~0.125 cap heights, from screenshots against the coin).
        .offset(y: engine.opticalLift)
        .onChange(of: value) { old, new in
            let now = Date().timeIntervalSinceReferenceDate
            engine.retarget(from: old, to: new, at: now, reduceMotion: reduceMotion)
            settled = reduceMotion
            settleTask?.cancel()
            let wait = engine.settleAt - now
            settleTask = Task {
                try? await Task.sleep(for: .seconds(max(0, wait)))
                guard !Task.isCancelled else { return }
                engine.cleanup()
                settled = true
            }
        }
        .accessibilityLabel(String(format: "%.\(decimals)f", value))
    }
}

// MARK: - Engine

// All animation state, evaluated (never stored) per frame. Mirrors the web
// driver's channels one to one:
// - column width:   layout spring from the width it had when retargeted
//                   (velocity discarded — the web cancels and restarts WAAPI
//                   width animations the same way), undelayed;
// - column opacity: 200ms linear fade on mount (the web's applyBox);
// - glyph arrival:  digit spring, per-column cascade delay, `fill:backwards`
//                   (holds the pre-flight pose through its delay);
// - glyph ghost:    digit spring, same delay, `fill:both` (holds identity
//                   through the delay, then exits and holds gone).
private struct Engine {
    // The study's tuning. The web's springParams() is explicitly SwiftUI's
    // Spring(duration:bounce:) parameterization, so these ARE its curves.
    static let digitSpring = Spring(duration: 0.55, bounce: 0.5)
    static let layoutSpring = Spring(duration: 0.55, bounce: 0.15)
    static let stagger = 0.04
    static let rise: CGFloat = 0.4
    static let maxBlur: CGFloat = 0.08

    // Channels snap to rest once the spring's remaining envelope falls below
    // what a pixel can show (~2% of glyph travel ≈ 0.15pt). The analytic tail
    // oscillates at sub-pixel amplitude long after the visible bounce, and
    // feeding that into per-frame text rasterization and layout reads as a
    // settle shimmer — the web never sees this because WAAPI translates an
    // already-rasterized layer instead of re-drawing glyphs.
    static let digitSettling = digitSpring.settlingDuration(
        fromValue: 0.0, toValue: 1.0, initialVelocity: 0.0, epsilon: 0.02
    )

    struct WidthAnim {
        var from: CGFloat
        var to: CGFloat
        var start: TimeInterval // .infinity = static at `to`
        let settle: TimeInterval // rest once the tail is under 0.1pt

        init(from: CGFloat, to: CGFloat, start: TimeInterval) {
            self.from = from
            self.to = to
            self.start = start
            settle = start.isFinite
                ? Engine.layoutSpring.settlingDuration(
                    fromValue: from, toValue: to, initialVelocity: 0.0, epsilon: 0.1
                )
                : 0
        }

        func at(_ t: TimeInterval) -> CGFloat {
            guard start.isFinite, t < start + settle else { return to }
            let p = CGFloat(Engine.layoutSpring.value(
                fromValue: 0.0, toValue: 1.0, initialVelocity: 0.0, time: max(0, t - start)
            ))
            return from + (to - from) * p
        }
    }

    struct GlyphAnim {
        var char: String
        var dir: CGFloat // +1 rises in on a gain, −1 sinks in on a loss
        var start: TimeInterval
        var delay: TimeInterval
        var entering: Bool // false = exit ghost

        // Eased progress 0→1 (overshoots on the bounce, like the sampled
        // linear() easing the web hands to WAAPI).
        func progress(_ t: TimeInterval) -> CGFloat {
            let local = t - start - delay
            guard local > 0 else { return 0 } // both fills hold the start pose
            guard local < Engine.digitSettling else { return 1 }
            return CGFloat(Engine.digitSpring.value(
                fromValue: 0.0, toValue: 1.0, initialVelocity: 0.0, time: local
            ))
        }

        func done(_ t: TimeInterval) -> Bool {
            t >= start + delay + Engine.digitSettling
        }

        // (yOffset in rise-units, blur in maxBlur-units, opacity)
        func pose(_ t: TimeInterval) -> (y: CGFloat, blur: CGFloat, opacity: CGFloat) {
            let p = progress(t)
            return entering
                ? (dir * (1 - p), max(0, 1 - p), min(max(p, 0), 1))
                : (-dir * p, max(0, p), min(max(1 - p, 0), 1))
        }
    }

    struct Cell {
        let place: Int // 1 = tens, 0 = ones, -1 = tenths…
        var char: String // settled digit ("" while entering or after leaving)
        var active: Bool // false = leaving, width collapsing to 0
        var width: WidthAnim
        var fadeStart: TimeInterval = .infinity // 200ms linear mount fade
        var arrival: GlyphAnim?
        var ghosts: [GlyphAnim] = []
    }

    private(set) var cells: [Cell]
    private(set) var settleAt: TimeInterval = 0
    let lineH: CGFloat
    let vSlop: CGFloat
    let opticalLift: CGFloat
    private let font: UIFont
    private let advances: [CGFloat]
    private let dotW: CGFloat

    init(value: Double, decimals: Int, font: UIFont) {
        self.font = font
        // The study's line box, NOT the font's: the web sets lineHeight to
        // s(94) = 94/120 of the font size (0.783em) where Cash Sans's own
        // box is 1.274em. Travel and blur scale from it, and it leaves the
        // digits shorter than the coin, restoring the study's headroom.
        lineH = font.pointSize * 94.0 / 120.0
        // The tight box is smaller than the glyph ink: a centered digit's
        // baseline lands just below the box bottom (round digits overshoot the
        // baseline further still — measured from the actual glyph bounds), and
        // the digit spring's settle bounce dips a landing digit below its rest
        // pose by its overshoot fraction of the travel. The web's clip shaves
        // both invisibly at 72px; at 24pt they read as a hard cut. So clips
        // get this much vertical slop — horizontal stays exact, which is the
        // edge that does the real work (collapsing cells swallowing ghosts).
        let ctFont = font as CTFont
        var inkBelowBaseline: CGFloat = 0
        for digit in "0123456789." {
            var unichar = [UniChar](String(digit).utf16)
            var glyph = [CGGlyph(0)]
            if CTFontGetGlyphsForCharacters(ctFont, &unichar, &glyph, 1) {
                var bounds = CGRect.zero
                CTFontGetBoundingRectsForGlyphs(ctFont, .default, glyph, &bounds, 1)
                inkBelowBaseline = max(inkBelowBaseline, -bounds.minY)
            }
        }
        let baselineBelowBox = max(0, (font.ascender - font.descender - lineH) / 2 + font.descender)
        let zeta = 1.0 - Self.digitSpring.bounce
        let springOvershoot = CGFloat(exp(-Double.pi * zeta / (1 - zeta * zeta).squareRoot()))
        vSlop = baselineBelowBox + inkBelowBaseline
            + springOvershoot * Self.rise * lineH + 0.75
        opticalLift = (font.ascender + font.descender - font.capHeight) / 2
            - font.capHeight * 0.125
        advances = (0 ... 9).map {
            ("\($0)" as NSString).size(withAttributes: [.font: font]).width
        }
        dotW = ("." as NSString).size(withAttributes: [.font: font]).width

        let cents = Self.cents(value, decimals)
        cells = ((-decimals) ..< Self.intDigits(cents: cents, decimals: decimals))
            .reversed()
            .map { place in
                let digit = Self.digitAt(cents: cents, place: place, decimals: decimals)
                return Cell(
                    place: place, char: digit, active: true,
                    width: WidthAnim(from: 0, to: 0, start: .infinity)
                )
            }
        for i in cells.indices {
            cells[i].width.to = advances[Int(cells[i].char) ?? 0]
        }
    }

    // MARK: Value plumbing

    private static func cents(_ v: Double, _ decimals: Int) -> Int {
        let pow10 = (0 ..< decimals).reduce(1.0) { n, _ in n * 10 }
        return Int((max(0, v) * pow10).rounded())
    }

    private static func intDigits(cents: Int, decimals: Int) -> Int {
        let pow10 = (0 ..< decimals).reduce(1) { n, _ in n * 10 }
        return max(1, String(cents / pow10).count)
    }

    private static func digitAt(cents: Int, place: Int, decimals: Int) -> String {
        let shift = place + decimals
        let pow10 = (0 ..< shift).reduce(1) { n, _ in n * 10 }
        return String((cents / pow10) % 10)
    }

    // MARK: Retarget — the web's useLayoutEffect pass, verbatim in spirit

    mutating func retarget(from old: Double, to new: Double, at now: TimeInterval, reduceMotion: Bool) {
        let cents = Self.cents(new, decimals)
        let oldCents = Self.cents(old, decimals)
        let newInt = Self.intDigits(cents: cents, decimals: decimals)
        let dir: CGFloat = cents > oldCents ? 1 : -1

        // Mount entering columns collapsed; they spring open below. The
        // 200ms fade matches the web's applyBox opacity ramp.
        let mountedInt = cells.map(\.place).max().map { $0 + 1 } ?? 1
        if newInt > mountedInt {
            cells.insert(
                contentsOf: (mountedInt ..< newInt).reversed().map {
                    var cell = Cell(
                        place: $0, char: "", active: false,
                        width: WidthAnim(from: 0, to: 0, start: .infinity)
                    )
                    cell.fadeStart = now
                    return cell
                },
                at: 0
            )
        }

        // Full-row ripple on any integer column-count change.
        let ripple = newInt != Self.intDigits(cents: oldCents, decimals: decimals)

        var movers = 0
        for i in cells.indices {
            let place = cells[i].place
            let leaving = place >= newInt
            let target = leaving ? "" : Self.digitAt(cents: cents, place: place, decimals: decimals)
            let isMover = ripple || target != cells[i].char || cells[i].active == leaving

            // Widths always retarget from the width rendered THIS frame,
            // velocity discarded (the web cancels the WAAPI animation and
            // starts over from getBoundingClientRect). Undelayed: layout is
            // one reflow the whole row shares.
            let targetW = leaving ? 0 : advances[Int(target) ?? 0]
            let currentW = cells[i].width.at(now)
            if abs(currentW - targetW) >= 0.15, !reduceMotion {
                cells[i].width = WidthAnim(from: currentW, to: targetW, start: now)
            } else {
                cells[i].width = WidthAnim(from: targetW, to: targetW, start: .infinity)
            }
            cells[i].active = !leaving

            guard isMover else { continue }
            let delay = Double(movers) * Self.stagger
            movers += 1

            if reduceMotion {
                cells[i].char = target
                cells[i].arrival = nil
                cells[i].ghosts = []
                continue
            }

            // The old digit ghosts out (fill:both — it holds still through
            // its cascade slot, so the column doesn't blank out waiting).
            // A mid-flight arrival is abandoned exactly like the web: the
            // ghost restarts from identity, the new arrival replaces it.
            if !cells[i].char.isEmpty || cells[i].arrival != nil {
                let outgoing = cells[i].arrival?.char ?? cells[i].char
                if !outgoing.isEmpty {
                    cells[i].ghosts.append(GlyphAnim(
                        char: outgoing, dir: dir, start: now, delay: delay, entering: false
                    ))
                }
            }
            cells[i].ghosts.removeAll { $0.done(now) }

            // The new digit arrives (fill:backwards — waits at its arrival
            // pose through the delay). A departing column has no successor;
            // its exit ghost is the whole show.
            if leaving {
                cells[i].char = ""
                cells[i].arrival = nil
            } else {
                cells[i].char = target
                cells[i].arrival = GlyphAnim(
                    char: target, dir: dir, start: now, delay: delay, entering: true
                )
            }
        }

        // Held columns release after the slower of the two clocks.
        let digitTotal = Engine.digitSettling
            + Double(max(0, movers - 1)) * Self.stagger
        let layoutTotal = cells.map(\.width.settle).max() ?? 0
        settleAt = now + (reduceMotion ? 0 : max(digitTotal, layoutTotal))
    }

    mutating func cleanup() {
        cells.removeAll { !$0.active }
        for i in cells.indices {
            cells[i].ghosts = []
            if let arrival = cells[i].arrival { cells[i].char = arrival.char }
            cells[i].arrival = nil
        }
    }

    private var decimals: Int { -(cells.last?.place ?? -2) }

    // MARK: Per-frame evaluation

    func width(at t: TimeInterval) -> CGFloat {
        cells.reduce(0) { total, cell in
            total + (cell.place == -1 ? dotW : 0) + cell.width.at(t)
        }
    }

    func draw(in ctx: inout GraphicsContext, size: CGSize, at t: TimeInterval, color: Color) {
        let swiftUIFont = Font(font)
        let midY = size.height / 2
        var x: CGFloat = 0

        for cell in cells {
            if cell.place == -1 {
                // The dot is a plain neighbor (the web's unclipped span);
                // it rides the same reflow because its x is downstream of
                // every animating width.
                ctx.draw(
                    Text(".").font(swiftUIFont).foregroundColor(color),
                    at: CGPoint(x: x + dotW / 2, y: midY), anchor: .center
                )
                x += dotW
            }

            let w = cell.width.at(t)
            let rect = CGRect(x: x, y: 0, width: w, height: size.height)
            x += w
            guard w > 0.01 else { continue }

            // Mount fade (web applyBox: 200ms linear, opacity only).
            let fade = cell.fadeStart.isFinite
                ? min(max((t - cell.fadeStart) / 0.2, 0), 1) : 1.0

            // Each column clips its glyphs to its animated box — the web's
            // overflow:hidden, inset 0. Glyphs are left-aligned in the box
            // (the web's position:absolute; left:0), so a collapsing cell
            // swallows its glyph from the right.
            var anims = cell.ghosts
            if let arrival = cell.arrival { anims.append(arrival) }
            let staticChar = cell.arrival == nil ? cell.char : ""

            ctx.drawLayer { layer in
                layer.clip(to: Path(rect))
                layer.opacity = fade

                for anim in anims {
                    let pose = anim.pose(t)
                    guard pose.opacity > 0.001 else { continue }
                    let advance = advances[Int(anim.char) ?? 0]
                    let at = CGPoint(
                        x: rect.minX + advance / 2,
                        y: midY + pose.y * Self.rise * lineH
                    )
                    let text = Text(anim.char).font(swiftUIFont).foregroundColor(color)
                    layer.drawLayer { glyph in
                        glyph.opacity = pose.opacity
                        if pose.blur > 0.01 {
                            glyph.addFilter(.blur(radius: pose.blur * Self.maxBlur * lineH))
                        }
                        glyph.draw(text, at: at, anchor: .center)
                    }
                }

                if !staticChar.isEmpty {
                    layer.draw(
                        Text(staticChar).font(swiftUIFont).foregroundColor(color),
                        at: CGPoint(x: rect.minX + advances[Int(staticChar) ?? 0] / 2, y: midY),
                        anchor: .center
                    )
                }
            }
        }
    }
}

#Preview {
    struct Demo: View {
        @State private var value: Double = 20

        var body: some View {
            VStack(spacing: 32) {
                CascadeNumber(
                    value: value,
                    uiFont: .systemFont(ofSize: 34, weight: .medium),
                    textColor: .primary
                )
                HStack(spacing: 16) {
                    Button("+5.25") { value += 5.25 }
                    Button("−3") { value = max(0, value - 3) }
                    Button("Zero") { value = 0 }
                    Button("+100") { value += 100 }
                }
            }
            .padding()
        }
    }
    return Demo()
}
