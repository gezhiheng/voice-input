import AppKit
import QuartzCore
import SwiftUI

@MainActor
final class FloatingPanelViewModel: ObservableObject {
    @Published var displayedText: String = "Listening…"
    @Published var waveformLevels: [Double] = Array(repeating: 0.12, count: 5)
    @Published var textWidth: CGFloat = 220

    let minimumTextWidth: CGFloat = 220
    let maximumTextWidth: CGFloat = 560
    let panelHeight: CGFloat = 56
    let extraWidth: CGFloat = 110

    func updateText(_ text: String) {
        let value = text.isEmpty ? "Listening…" : text
        displayedText = visibleText(for: value)
        textWidth = measuredWidth(for: displayedText)
    }

    func updateWaveform(_ levels: [Double]) {
        waveformLevels = levels
    }

    func measuredWidth(for text: String) -> CGFloat {
        min(max(rawMeasuredWidth(for: text) + 4, minimumTextWidth), maximumTextWidth)
    }

    func visibleText(for text: String) -> String {
        guard rawMeasuredWidth(for: text) + 4 >= maximumTextWidth else {
            return text
        }

        let ellipsis = "…"
        var visibleSuffix = text

        while !visibleSuffix.isEmpty {
            let candidate = ellipsis + visibleSuffix
            let candidateWidth = rawMeasuredWidth(for: candidate) + 4
            if candidateWidth <= maximumTextWidth || visibleSuffix.count == 1 {
                return candidate
            }

            visibleSuffix.removeFirst()
        }

        return ellipsis
    }

    private func rawMeasuredWidth(for text: String) -> CGFloat {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 17, weight: .semibold)
        ]
        return (text as NSString).size(withAttributes: attributes).width
    }

    var panelWidth: CGFloat {
        textWidth + extraWidth
    }
}

@MainActor
final class FloatingPanelController {
    private let viewModel = FloatingPanelViewModel()
    private var panel: NSPanel?

    func showListening() {
        ensurePanel()
        viewModel.updateText("Listening…")
        viewModel.updateWaveform(Array(repeating: 0.12, count: 5))
        positionPanel(animated: false)
        showPanel()
    }

    func updateTranscript(_ text: String) {
        ensurePanel()
        viewModel.updateText(text)
        positionPanel(animated: true)
    }

    func updateWaveform(_ levels: [Double]) {
        ensurePanel()
        viewModel.updateWaveform(levels)
    }

    func showRefining() {
        ensurePanel()
        viewModel.updateText("Refining…")
        positionPanel(animated: true)
    }

    func showStatus(_ text: String) {
        ensurePanel()
        viewModel.updateText(text)
        positionPanel(animated: true)
    }

    func dismiss() {
        guard let panel, let contentView = panel.contentView else {
            return
        }

        contentView.wantsLayer = true
        let animation = CABasicAnimation(keyPath: "transform.scale")
        animation.fromValue = 1
        animation.toValue = 0.92
        animation.duration = 0.22
        contentView.layer?.add(animation, forKey: "scaleOut")

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.22
            panel.animator().alphaValue = 0
        } completionHandler: {
            panel.orderOut(nil)
        }
    }

    private func ensurePanel() {
        guard panel == nil else {
            return
        }

        let initialFrame = NSRect(x: 0, y: 0, width: viewModel.panelWidth, height: viewModel.panelHeight)
        let panel = NSPanel(
            contentRect: initialFrame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle]
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hidesOnDeactivate = false
        panel.ignoresMouseEvents = true
        panel.animationBehavior = .utilityWindow

        let rootView = FloatingHUDRootView(viewModel: viewModel)
        let hostingView = NSHostingView(rootView: rootView)
        hostingView.frame = initialFrame
        hostingView.wantsLayer = true
        hostingView.layer?.backgroundColor = NSColor.clear.cgColor

        panel.contentView = hostingView
        self.panel = panel
    }

    private func positionPanel(animated: Bool) {
        guard let panel else {
            return
        }

        let width = viewModel.panelWidth
        let height = viewModel.panelHeight
        let frame = targetFrame(width: width, height: height)

        if animated {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
                panel.animator().setFrame(frame, display: true)
            }
        } else {
            panel.setFrame(frame, display: true)
        }
    }

    private func showPanel() {
        guard let panel, let contentView = panel.contentView else {
            return
        }

        positionPanel(animated: false)
        panel.alphaValue = 0
        panel.orderFrontRegardless()
        contentView.wantsLayer = true

        let animation = CASpringAnimation(keyPath: "transform.scale")
        animation.fromValue = 0.92
        animation.toValue = 1
        animation.damping = 16
        animation.stiffness = 170
        animation.mass = 0.9
        animation.initialVelocity = 6
        animation.duration = 0.35
        contentView.layer?.add(animation, forKey: "scaleIn")

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.35
            panel.animator().alphaValue = 1
        }
    }

    private func targetFrame(width: CGFloat, height: CGFloat) -> NSRect {
        let screen = activeScreen()
        let visible = screen.visibleFrame
        let x = visible.midX - width / 2
        let y = visible.minY + 88
        return NSRect(x: x, y: y, width: width, height: height)
    }

    private func activeScreen() -> NSScreen {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }) ?? NSScreen.main ?? NSScreen.screens[0]
    }
}

private struct FloatingHUDRootView: View {
    @ObservedObject var viewModel: FloatingPanelViewModel

    var body: some View {
        ZStack {
            HUDMaterialBackground()
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.035),
                            Color.black.opacity(0.055)
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )

            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 0.75)

            HStack(spacing: 14) {
                WaveformView(levels: viewModel.waveformLevels)
                    .frame(width: 42, height: 30)

                Text(viewModel.displayedText)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(Color.white.opacity(0.92))
                    .lineLimit(1)
                    .truncationMode(.head)
                    .frame(width: viewModel.textWidth, alignment: .leading)
                    .animation(.easeInOut(duration: 0.25), value: viewModel.textWidth)
            }
            .padding(.horizontal, 22)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .frame(height: 56)
    }
}

private struct WaveformView: View {
    var levels: [Double]

    var body: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            let height = geometry.size.height
            let barWidth = 6.4
            let spacing = (width - 5 * barWidth) / 4

            HStack(alignment: .center, spacing: spacing) {
                ForEach(Array(levels.enumerated()), id: \.offset) { _, level in
                    Capsule(style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [
                                    Color.white.opacity(0.96),
                                    Color.white.opacity(0.78)
                                ],
                                startPoint: .top,
                                endPoint: .bottom
                            )
                        )
                        .shadow(color: .white.opacity(0.18), radius: 1, y: 0)
                        .frame(width: barWidth, height: max(9, height * CGFloat(level)))
                        .animation(.easeInOut(duration: 0.12), value: level)
                }
            }
            .frame(width: width, height: height, alignment: .center)
        }
    }
}

private struct HUDMaterialBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        view.state = .active
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {
        nsView.material = .hudWindow
        nsView.blendingMode = .behindWindow
        nsView.state = .active
    }
}
