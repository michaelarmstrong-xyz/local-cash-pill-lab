import SwiftUI

// MARK: - Local Cash coin
//
// From the Local Cash Motion Study coin (squareup/local-cash-balance-odometer),
// simplified for app scale. The web study performs the full struck-metal show
// (perspective pitch/yaw, body translation, specular shine) — at 72px it
// reads; at the app's 24pt it collapsed into illegible micro-wobble. Here the
// badge is a still object and only the $ glyph moves inside it:
//
//  - Gain: the nod — the glyph sinks into the wind-up, pops up with the
//    flick, settles.
//  - Loss: the mirror — a hint of rise, then the dip.
//  - Zero (balance drained to exactly 0): the horizontal "no" shake —
//    the same gesture turned 90°, winding left, whipping right.
//
// The glyph's path is the brand Symbol Idle waveform (38 samples measured
// frame-by-frame from the brand video) on the study's 680ms clock, with the
// travel scaled up so the gesture is legible at 24pt.

struct LocalCashCoin: View {
    var value: Double
    var size: CGFloat = 36

    @State private var plan = GlyphPerformance.gain
    @State private var beat = 0 // keyframe trigger; bumps once per value event
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        // Travel is authored in the source's 120-unit viewBox space and
        // scaled by size/120 at render, so the gesture survives resizing.
        let u = size / 120
        ZStack {
            CoinBadgeShape()
                .fill(Color(red: 0, green: 224 / 255, blue: 19 / 255))

            CoinGlyphShape()
                .fill(.black)
                .keyframeAnimator(initialValue: GlyphMotion(), trigger: beat) { view, motion in
                    view.offset(x: motion.x * u, y: motion.y * u)
                } keyframes: { _ in
                    let p = reduceMotion ? GlyphPerformance.still : plan
                    KeyframeTrack(\.x) { GlyphKeyframes(amp: p.x, windup: p.windup) }
                    KeyframeTrack(\.y) { GlyphKeyframes(amp: p.y, windup: p.windup) }
                }
        }
        .frame(width: size, height: size)
        .onChange(of: value) { old, new in
            guard new != old else { return }
            let down = new < old
            let zero = down && new == 0
            plan = zero ? .zero : down ? .loss : .gain
            beat += 1
        }
        .accessibilityHidden(true)
    }
}

// MARK: - Motion

private struct GlyphMotion {
    var x: CGFloat = 0
    var y: CGFloat = 0
}

/// One performance = a signed amplitude per axis on the measured waveform,
/// plus how much of the wind-up survives.
private struct GlyphPerformance: Equatable {
    var x: CGFloat
    var y: CGFloat
    var windup: CGFloat = 1

    /// Travel multiplier on the brand waveform. The measured amplitude was
    /// tuned for a full-bleed brand video; at a 24pt coin it moves the glyph
    /// barely a point. 1.75 keeps the peak inside the badge's scallops
    /// (~11 of 120 units) while making the nod readable. Tune by feel.
    static let travel: CGFloat = 1.75

    /// The brand waveform winds up to FULL amplitude opposite the flick, so
    /// at pill size the nod read as ambiguous — as much down as up. Keep a
    /// hint of anticipation, spend the travel on the direction that matters.
    static let nodWindup: CGFloat = 0.3

    /// Sink a little, then the up-flick: the gain nod.
    static let gain = GlyphPerformance(x: 0, y: travel, windup: nodWindup)
    /// Mirrored: a hint of rise, then the dip.
    static let loss = GlyphPerformance(x: 0, y: -travel, windup: nodWindup)
    /// The "no" shake: the gesture turned 90°, winding left, whipping right.
    /// Full wind-up — a shake is symmetric, there's no direction to protect.
    static let zero = GlyphPerformance(x: -travel, y: 0)
    /// Reduced motion: the clock runs, nothing moves.
    static let still = GlyphPerformance(x: 0, y: 0)
}

/// The $'s travel, measured frame-by-frame from the brand Symbol Idle video
/// as a fraction of icon height, compressed onto the 680ms clock (samples
/// 1–15 across the wind-up, 16–20 the flick, 21–37 the settle). Linear
/// through the samples — 30fps captures interpolated linearly are
/// indistinguishable at this size.
private struct GlyphKeyframes: KeyframeTrackContent {
    var amp: CGFloat // +travel up-flick, −travel mirrored, 0 = track holds rest
    var windup: CGFloat = 1 // scale on the anticipation samples (0..<15) only

    static let wave: [CGFloat] = [
        0.017, 0.0263, 0.0317, 0.0367, 0.0405, 0.0424, 0.0451, 0.0473, 0.0478,
        0.0496, 0.051, 0.0517, 0.0518, 0.0521, 0.0522, -0.0114, -0.0337, -0.0459,
        -0.051, -0.0522, -0.0046, 0.0115, 0.0206, 0.0246, 0.0263, 0.0165, 0.0117,
        0.0101, 0.0078, 0.0055, 0.0053, 0.0026, 0.0012, 0.0012, 0.0006, 0.0004, 0, 0,
    ]

    static func dt(_ i: Int) -> Double {
        switch i {
        case 0 ..< 15: 0.22 / 15
        case 15 ..< 20: 0.16 / 5
        default: 0.30 / 18
        }
    }

    private func k(_ i: Int) -> LinearKeyframe<CGFloat> {
        LinearKeyframe(amp * (i < 15 ? windup : 1) * Self.wave[i] * 120, duration: Self.dt(i))
    }

    var body: some KeyframeTrackContent<CGFloat> {
        k(0); k(1); k(2); k(3); k(4); k(5); k(6); k(7); k(8); k(9)
        k(10); k(11); k(12); k(13); k(14); k(15); k(16); k(17); k(18); k(19)
        k(20); k(21); k(22); k(23); k(24); k(25); k(26); k(27); k(28); k(29)
        k(30); k(31); k(32); k(33); k(34); k(35); k(36); k(37)
    }
}

// MARK: - Shapes

/// The scalloped badge outline, from the brand SVG (viewBox 120×120).
struct CoinBadgeShape: Shape {
    func path(in rect: CGRect) -> Path {
        SVGPathCache.badge.scaled(toFit: rect)
    }
}

/// The $ glyph, from the brand SVG — drawn in the same 120×120 space so it
/// lands in place when both shapes fill the same frame.
struct CoinGlyphShape: Shape {
    func path(in rect: CGRect) -> Path {
        SVGPathCache.glyph.scaled(toFit: rect)
    }
}

private extension Path {
    /// Both source paths are authored in a 120×120 box; scale uniformly.
    func scaled(toFit rect: CGRect) -> Path {
        let s = min(rect.width, rect.height) / 120
        return applying(CGAffineTransform(scaleX: s, y: s))
    }
}

/// Parses the two path strings once. The paths use only absolute M/C/L/Z,
/// which is all this tiny parser understands — it traps in debug if the
/// artwork ever changes to something it can't read.
private enum SVGPathCache {
    static let badge = parse(badgeD)
    static let glyph = parse(glyphD)

    static let badgeD = "M51.2583 1.95237C54.0488 0.65359 57.0487 9.20892e-06 60.0571 9.20892e-06L60.0487 0.00838843C63.0571 0.00838843 66.0654 0.653589 68.8559 1.96075C72.5263 3.89635 75.4005 6.34309 79.5569 10.3903C80.0178 10.8427 80.6463 11.1025 81.2915 11.1109C87.1071 11.1863 90.878 11.4963 94.8752 12.7616C100.657 14.8648 105.224 19.4315 107.319 25.2131C108.551 29.1849 108.853 32.9472 108.928 38.7456C108.937 39.3908 109.196 40.0192 109.649 40.4801C113.73 44.6697 116.152 47.5438 118.045 51.2809C120.652 56.8447 120.66 63.3051 118.02 68.8438C116.118 72.5307 113.688 75.4047 109.649 79.5525C109.196 80.0133 108.937 80.6418 108.928 81.287C108.844 87.144 108.526 90.8896 107.227 94.8697C105.132 100.651 100.565 105.218 94.783 107.271C90.8278 108.528 87.0736 108.846 81.2915 108.922C80.6463 108.93 80.0178 109.19 79.5569 109.642C75.4173 113.673 72.5346 116.111 68.814 118.047C66.0235 119.345 63.0235 119.999 60.0152 119.999C57.0068 119.999 53.9985 119.354 51.208 118.047C47.5125 116.136 44.6382 113.689 40.4735 109.642C40.0126 109.19 39.3841 108.93 38.7388 108.922C32.9568 108.846 29.1942 108.536 25.1971 107.271C19.415 105.168 14.848 100.601 12.753 94.8194C11.4877 90.856 11.1776 87.0938 11.1022 81.287C11.0938 80.6418 10.8341 80.0133 10.3815 79.5525C6.33409 75.3964 3.88719 72.5139 1.95145 68.7851C-0.646292 63.2213 -0.654672 56.7609 1.95145 51.1887C3.88719 47.5103 6.31733 44.6529 10.3899 40.4801C10.8424 40.0192 11.1022 39.3908 11.1106 38.7456C11.186 32.9472 11.4961 29.1765 12.7614 25.1712C14.8564 19.3896 19.4234 14.8145 25.2054 12.7197C29.1775 11.4879 32.9149 11.1863 38.7472 11.1109C39.3925 11.1025 40.021 10.8427 40.4818 10.3903C44.6466 6.33471 47.5376 3.88797 51.2583 1.95237Z"

    static let glyphD = "M63.7337 53.8348C74.7381 56.1917 79.7667 60.8053 79.7667 68.5782C79.7667 78.3068 71.8993 85.4779 59.6009 86.2802L58.4059 92.0472C58.3064 92.5988 57.8082 93 57.211 93H47.7504C46.9536 93 46.4061 92.2478 46.5554 91.4956L48.049 85.0767C41.9742 83.3215 37.0446 79.9115 34.2068 75.7493C33.8584 75.1976 33.9579 74.4956 34.4556 74.0944L41.0281 68.9292C41.5761 68.4779 42.3724 68.6283 42.771 69.1799C46.2563 74.0944 51.6339 77.0029 58.1073 77.0029C63.9333 77.0029 68.3149 74.1445 68.3149 70.0325C68.3149 66.8732 66.1241 65.4189 58.705 63.8643C46.0578 61.1062 41.0286 56.3923 41.0286 48.6195C41.0286 39.5929 48.5472 32.823 59.9 31.9204L61.1447 25.9528C61.2442 25.4012 61.7424 25 62.3397 25H71.6509C72.398 25 72.9952 25.7021 72.8459 26.4543L71.4021 33.1239C76.2819 34.6283 80.2649 37.3363 82.7549 40.6962C83.153 41.1976 83.0535 41.9499 82.5558 42.351L76.5308 47.3156C75.9828 47.767 75.2363 47.6667 74.8376 47.115C71.7505 43.3038 66.9702 41.1475 61.7419 41.1475C55.916 41.1475 52.2814 43.705 52.2814 47.3156C52.1818 50.3245 55.0201 51.9292 63.7337 53.8348Z"

    static func parse(_ d: String) -> Path {
        var path = Path()
        let scanner = Scanner(string: d)
        scanner.charactersToBeSkipped = CharacterSet(charactersIn: " ,\n")

        func number() -> CGFloat? {
            scanner.scanDouble().map { CGFloat($0) }
        }
        func point() -> CGPoint? {
            guard let x = number(), let y = number() else { return nil }
            return CGPoint(x: x, y: y)
        }

        var command: Character = " "
        while !scanner.isAtEnd {
            let mark = scanner.currentIndex
            if let c = scanner.scanCharacter() {
                if "MCLZH".contains(c) {
                    command = c
                } else {
                    // A bare number continues the previous command (an M's
                    // trailing pairs behave as implicit L per the SVG spec).
                    scanner.currentIndex = mark
                    if command == "M" { command = "L" }
                }
            } else {
                break
            }
            switch command {
            case "M", "L":
                guard let p = point() else { assertionFailure("bad path"); return path }
                if command == "M" { path.move(to: p) } else { path.addLine(to: p) }
            case "C":
                guard let c1 = point(), let c2 = point(), let p = point() else {
                    assertionFailure("bad path")
                    return path
                }
                path.addCurve(to: p, control1: c1, control2: c2)
            case "H":
                guard let x = number(), let y = path.currentPoint?.y else {
                    assertionFailure("bad path")
                    return path
                }
                path.addLine(to: CGPoint(x: x, y: y))
            case "Z":
                path.closeSubpath()
            default:
                assertionFailure("unsupported path command \(command)")
                return path
            }
        }
        return path
    }
}

#Preview {
    struct Demo: View {
        @State private var value: Double = 20

        var body: some View {
            VStack(spacing: 32) {
                LocalCashCoin(value: value, size: 72)
                HStack(spacing: 16) {
                    Button("+5") { value += 5 }
                    Button("−5") { value = max(0, value - 5) }
                    Button("Zero") { value = 0 }
                }
            }
            .padding()
        }
    }
    return Demo()
}
