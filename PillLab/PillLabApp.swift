import SwiftUI

// PillLab — the Local Cash pill in isolation, for fast iteration.
// Standalone copy: LocalCashPill.swift, CascadeNumber.swift and
// LocalCashCoin.swift are vendored under Sources/ (snapshotted from the
// app repo — see project.yml), so this builds with no sibling checkout.
// Edits here do NOT flow back to the app.

@main
struct PillLabApp: App {
    var body: some Scene {
        WindowGroup {
            LabView()
        }
    }
}

struct LabView: View {
    @State private var value: Double = 20
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        ZStack {
            MapStandIn()

            LocalCashPill(value: value)
        }
        .safeAreaInset(edge: .bottom) {
            controls
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
        }
        // Headless-verification driver: `simctl launch ... -demo` plays a
        // fixed script so recordings land transitions at known timestamps.
        .task {
            guard ProcessInfo.processInfo.arguments.contains("-demo") else { return }
            for change in [180.0, -200.0, 200.0, -200.0] {
                try? await Task.sleep(for: .seconds(3))
                value = max(0, value + change)
            }
        }
    }

    private var controls: some View {
        HStack(spacing: 10) {
            control("+") { value += Double(Int.random(in: 1 ... 2500)) / 100 }
            control("−") { value = max(0, value - Double(Int.random(in: 1 ... 2500)) / 100) }
            control("0") { value = 0 }
            control("+100") { value += 100 } // force a column-count ripple
            control("+1¢") { value += 0.01 } // smallest possible change
        }
    }

    private func control(_ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 17, weight: .medium))
                .foregroundColor(.primary)
                .frame(minWidth: 44, minHeight: 44)
                .padding(.horizontal, 6)
                // Dark: the web study's control chips (white at 8%).
                .background(Capsule().fill(scheme == .dark
                    ? Color.white.opacity(0.08)
                    : Color.white.opacity(0.9)))
                .overlay(Capsule().strokeBorder(Color.black.opacity(scheme == .dark ? 0 : 0.08)))
        }
        .buttonStyle(.plain)
    }
}

// A flat stand-in for the map: same paper tone, a faint street grid so the
// eye has reference lines to judge the capsule's motion against.
// In dark mode: the web study's pure-black stage, no grid.
private struct MapStandIn: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if scheme == .dark {
            Color.black.ignoresSafeArea()
        } else {
            grid
        }
    }

    private var grid: some View {
        Canvas { ctx, size in
            ctx.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Color(red: 0.945, green: 0.941, blue: 0.930)))
            var grid = Path()
            for x in stride(from: 24.0, to: size.width, by: 72) {
                grid.move(to: CGPoint(x: x, y: 0))
                grid.addLine(to: CGPoint(x: x, y: size.height))
            }
            for y in stride(from: 30.0, to: size.height, by: 72) {
                grid.move(to: CGPoint(x: 0, y: y))
                grid.addLine(to: CGPoint(x: size.width, y: y))
            }
            ctx.stroke(grid, with: .color(.white), lineWidth: 6)
        }
        .ignoresSafeArea()
    }
}

#Preview {
    LabView()
}
