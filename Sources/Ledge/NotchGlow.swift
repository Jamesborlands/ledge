import AppKit
import SwiftUI

/// A click-through overlay that makes the notch glow as a drag approaches it,
/// and flare when the drag is close enough to open a shelf.
@MainActor
final class NotchGlow: ObservableObject {
    @Published var intensity: Double = 0
    @Published var armed = false

    private var window: NSPanel?
    var contentView: NSView? { window?.contentView }
    private var hideWork: DispatchWorkItem?
    private static let margin = NSSize(width: 90, height: 70)

    /// `proximity` is 0 (far) … 1 (touching the notch).
    func update(proximity: Double, zone: NSRect) {
        hideWork?.cancel()
        if window == nil || window?.frame != frame(for: zone) { makeWindow(for: zone) }
        window?.orderFrontRegardless()
        intensity = max(0, min(1, proximity))
    }

    /// The drag reached the notch: flare, then fade out once the shelf is up.
    func flare() {
        armed = true
        intensity = 1
    }

    func hide() {
        guard window != nil, hideWork == nil || hideWork!.isCancelled else { return }
        intensity = 0
        armed = false
        let work = DispatchWorkItem { [weak self] in
            self?.window?.orderOut(nil)
            self?.hideWork = nil
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: work)
    }

    private func frame(for zone: NSRect) -> NSRect {
        NSRect(x: zone.minX - Self.margin.width, y: zone.minY - Self.margin.height,
               width: zone.width + Self.margin.width * 2, height: zone.height + Self.margin.height)
    }

    private func makeWindow(for zone: NSRect) {
        window?.orderOut(nil)
        let panel = NSPanel(contentRect: frame(for: zone), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.level = .statusBar + 1
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = NSHostingView(rootView: NotchGlowView(glow: self, notch: zone.size, margin: Self.margin))
        window = panel
    }
}

struct NotchGlowView: View {
    @ObservedObject var glow: NotchGlow
    let notch: CGSize
    let margin: CGSize

    private let cyan = Color(red: 0.38, green: 0.86, blue: 1.0)
    private let violet = Color(red: 0.62, green: 0.45, blue: 1.0)

    var body: some View {
        let level = glow.intensity
        let shape = NotchShape(radius: min(12, notch.height / 2.5))
        ZStack(alignment: .top) {
            // Soft light pooling below the notch
            Ellipse()
                .fill(RadialGradient(colors: [cyan.opacity(0.55), violet.opacity(0.25), .clear],
                                     center: .top, startRadius: 0, endRadius: notch.width * 0.9))
                .frame(width: notch.width * 1.7, height: margin.height * 1.6)
                .offset(y: notch.height - margin.height * 0.35)
                .blur(radius: 14)
                .opacity(level * (glow.armed ? 1 : 0.7))
            // Glowing rim hugging the notch
            shape
                .stroke(LinearGradient(colors: [cyan, violet], startPoint: .leading, endPoint: .trailing),
                        lineWidth: glow.armed ? 3.5 : 1.5 + 2 * level)
                .frame(width: notch.width, height: notch.height)
                .shadow(color: cyan.opacity(level), radius: 4)
                .shadow(color: cyan.opacity(level * 0.9), radius: glow.armed ? 16 : 10)
                .shadow(color: violet.opacity(level * 0.8), radius: glow.armed ? 34 : 20)
                .opacity(level)
            // Fill the notch so the rim reads as its outline, not a floating line
            shape.fill(Color.black)
                .frame(width: notch.width, height: notch.height)
                .opacity(min(1, level * 3))
        }
        .scaleEffect(glow.armed ? 1.08 : 1, anchor: .top)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(.easeOut(duration: 0.15), value: level)
        .animation(.spring(response: 0.3, dampingFraction: 0.55), value: glow.armed)
    }
}

/// Flat top, straight sides, rounded bottom corners — the shape of the MacBook notch.
struct NotchShape: Shape {
    let radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY - radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + radius, y: rect.maxY), control: CGPoint(x: rect.minX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX - radius, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY - radius), control: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}
