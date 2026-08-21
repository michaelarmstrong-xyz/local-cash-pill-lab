import SwiftUI
import UIKit

// MARK: - Liquid Glass View Modifiers
//
// Thin wrappers around `glassEffect(...)` so call sites stay readable and
// can opt out via the `isEnabled` parameter on a per-call basis.

extension View {

    /// Apply a regular Liquid Glass effect.
    @ViewBuilder
    func conditionalGlass(
        in shape: some Shape = .capsule,
        isEnabled: Bool = true
    ) -> some View {
        if isEnabled {
            self.glassEffect(.regular, in: shape)
        } else {
            self
        }
    }

    /// Apply a clear-variant Liquid Glass effect (more transparent than `.regular`).
    @ViewBuilder
    func conditionalClearGlass(
        in shape: some Shape = .capsule,
        isEnabled: Bool = true
    ) -> some View {
        if isEnabled {
            self.glassEffect(.clear, in: shape)
        } else {
            self
        }
    }

    /// Apply an interactive Liquid Glass effect (responds to touch/pointer).
    /// Best for buttons and tappable floating controls.
    @ViewBuilder
    func conditionalInteractiveGlass(
        in shape: some Shape = .capsule,
        isEnabled: Bool = true
    ) -> some View {
        if isEnabled {
            self.glassEffect(.regular.interactive(), in: shape)
        } else {
            self
        }
    }

    /// Liquid Glass for the green map scan control: **non-interactive** `.regular` glass so
    /// `.interactive()` doesn't wash the green out to neon on press; pair with
    /// `MapScanFloatingButtonStyle` for press feedback.
    @ViewBuilder
    func conditionalMapScanGlass(
        in shape: some Shape,
        isEnabled: Bool = true
    ) -> some View {
        if isEnabled {
            self.glassEffect(.regular, in: shape)
        } else {
            self
        }
    }
}

// MARK: - Glass-Aware Background Helper

extension View {

    /// Hide the background when `condition` is true (because Liquid Glass replaces
    /// solid backgrounds); apply the color background otherwise.
    @ViewBuilder
    func opaqueBackground(_ color: Color, when condition: Bool = true) -> some View {
        if condition {
            self
        } else {
            self.background(color)
        }
    }

    /// Liquid Glass background for sheet-style containers with rounded top corners.
    @ViewBuilder
    func sheetGlassBackground(cornerRadius: CGFloat = 44, bottomRadius: CGFloat = 58) -> some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: cornerRadius,
            bottomLeadingRadius: bottomRadius,
            bottomTrailingRadius: bottomRadius,
            topTrailingRadius: cornerRadius
        )
        self.glassEffect(.regular, in: shape)
    }
}

// MARK: - Map floating actions (Neighborhoods)

enum MapFloatingActionStyle {
    /// Figma / POS scan action green — keep identical when layering Liquid Glass on top.
    static let scanButtonGreen = Color(red: 0, green: 0.839, blue: 0.196)
}

/// Bounce + light dim on press for the scan chip (pairs with non-interactive scan glass).
struct MapScanFloatingButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay {
                Circle()
                    .fill(Color.black.opacity(configuration.isPressed ? 0.14 : 0))
            }
            .scaleEffect(configuration.isPressed ? 0.90 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.5), value: configuration.isPressed)
    }
}

extension View {
    /// Soft stacked shadow similar to map pin "pearl" lift; pairs with Liquid Glass floating controls.
    func mapFloatingPearlShadow() -> some View {
        self
            .shadow(color: .black.opacity(0.2), radius: 1, x: 0, y: 0.5)
            .shadow(color: .black.opacity(0.22), radius: 10, x: 0, y: 5)
    }
}
