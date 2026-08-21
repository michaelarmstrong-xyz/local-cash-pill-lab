import SwiftUI

// The Local Cash pill — coin + cascade number + glass — as ONE unit.
// This exact file compiles in the app (LocalView+Chrome.swift) AND in
// PillLab (referenced in place via pill-lab/project.yml), so the two can't
// drift: what you tune in the lab is what ships on the map.
//
// Sizing matches the map tools (recenter / scan): those are a 24pt glyph in
// 10pt padding — a 44pt capsule — so the pill is the 24pt coin + number in
// the same 10pt padding, contents centered. The glass is the same modifier
// the tools use (`conditionalInteractiveGlass`), so the materials are
// identical by construction.
struct LocalCashPill: View {
    var value: Double

    var body: some View {
        HStack(spacing: 3.2) {
            // Animated Local Cash coin: the $ glyph nods up on gains, down on
            // losses, and shakes "no" on hitting zero (badge stays still).
            LocalCashCoin(value: value, size: 24)

            // Motion-study number: changed digits cascade left to right on a
            // spring, arriving from the direction the value is heading.
            CascadeNumber(
                value: value,
                uiFont: UIFont(name: "CashSans-Medium", size: 24)
                    ?? .systemFont(ofSize: 24, weight: .medium), // font not registered — check Info.plist
                textColor: .primary
            )
        }
        .padding(10)
        .contentShape(Capsule())
        .conditionalInteractiveGlass(in: Capsule())
    }
}

#Preview("Light") {
    ZStack {
        Color(red: 0.945, green: 0.941, blue: 0.930).ignoresSafeArea()
        LocalCashPill(value: 128.5)
    }
}

#Preview("Dark") {
    ZStack {
        Color.black.ignoresSafeArea()
        LocalCashPill(value: 128.5)
    }
    .preferredColorScheme(.dark)
}
