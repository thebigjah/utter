import AppKit

/// The floating pill at the bottom of the screen (Wispr calls theirs the Flow bar).
final class Overlay {
    enum Mode: Equatable {
        case hidden
        case idle
        case listening(locked: Bool)
        case processing
        case message(String)
    }

    private let panel: NSPanel
    private let view = PillView()
    private var timer: Timer?
    private var messageWork: DispatchWorkItem?
    private(set) var mode: Mode = .hidden
    var showWhenIdle = true

    init() {
        panel = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered, defer: true)
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        panel.contentView = view
    }

    func pushLevel(_ level: Float) {
        view.levels.removeFirst()
        view.levels.append(CGFloat(level))
    }

    func show(_ mode: Mode) {
        messageWork?.cancel()
        self.mode = mode
        view.mode = mode
        if case .message = mode {
            let work = DispatchWorkItem { [weak self] in self?.show(.idle) }
            messageWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.8, execute: work)
        }

        let visible: Bool
        switch mode {
        case .hidden: visible = false
        case .idle: visible = showWhenIdle
        default: visible = true
        }
        guard visible else {
            panel.orderOut(nil)
            stopAnimating()
            return
        }

        let size = view.preferredSize
        let screen = NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main
        let area = screen?.visibleFrame ?? .zero
        let frame = CGRect(x: area.midX - size.width / 2, y: area.minY + 14, width: size.width, height: size.height)
        panel.setFrame(frame, display: true, animate: panel.isVisible)
        panel.orderFrontRegardless()

        if mode == .idle { stopAnimating() } else { startAnimating() }
        view.needsDisplay = true
    }

    private func startAnimating() {
        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            self?.view.phase += 1
            self?.view.needsDisplay = true
        }
    }

    private func stopAnimating() {
        timer?.invalidate()
        timer = nil
    }
}

private final class PillView: NSView {
    var mode: Overlay.Mode = .idle
    var levels = [CGFloat](repeating: 0, count: 14)
    var phase = 0

    var preferredSize: CGSize {
        switch mode {
        case .hidden, .idle: return CGSize(width: 44, height: 10)
        case .listening(let locked): return CGSize(width: locked ? 132 : 108, height: 34)
        case .processing: return CGSize(width: 72, height: 34)
        case .message(let text):
            let width = (text as NSString).size(withAttributes: [.font: Self.font]).width
            return CGSize(width: min(520, width + 36), height: 34)
        }
    }

    static let font = NSFont.systemFont(ofSize: 12.5, weight: .medium)

    override func draw(_ dirtyRect: NSRect) {
        let bounds = self.bounds
        let pill = NSBezierPath(roundedRect: bounds, xRadius: bounds.height / 2, yRadius: bounds.height / 2)
        switch mode {
        case .hidden:
            return
        case .idle:
            Brand.ink.withAlphaComponent(0.55).setFill()
            pill.fill()
            Brand.cream.withAlphaComponent(0.35).setStroke()
            pill.lineWidth = 1
            pill.stroke()
        case .listening(let locked):
            Brand.ink.setFill()
            pill.fill()
            var barsRect = bounds.insetBy(dx: 18, dy: 9)
            if locked {
                Brand.coral.setFill()
                NSBezierPath(ovalIn: CGRect(x: bounds.maxX - 24, y: bounds.midY - 4, width: 8, height: 8)).fill()
                barsRect.size.width -= 22
            }
            drawLevels(in: barsRect)
        case .processing:
            Brand.ink.setFill()
            pill.fill()
            for i in 0..<3 {
                let lift = sin(Double(phase) / 4 - Double(i) * 0.9) * 3
                let dot = CGRect(x: bounds.midX - 16 + CGFloat(i) * 13, y: bounds.midY - 3 + CGFloat(lift), width: 6, height: 6)
                (i == 1 ? Brand.coral : Brand.cream).setFill()
                NSBezierPath(ovalIn: dot).fill()
            }
        case .message(let text):
            Brand.ink.setFill()
            pill.fill()
            let attrs: [NSAttributedString.Key: Any] = [.font: Self.font, .foregroundColor: Brand.cream]
            let size = (text as NSString).size(withAttributes: attrs)
            (text as NSString).draw(at: CGPoint(x: bounds.midX - size.width / 2, y: bounds.midY - size.height / 2), withAttributes: attrs)
        }
    }

    private func drawLevels(in rect: CGRect) {
        let count = CGFloat(levels.count)
        let barWidth = rect.width / (count * 2 - 1)
        for (i, level) in levels.enumerated() {
            let height = max(barWidth, rect.height * max(0.12, level))
            let bar = CGRect(x: rect.minX + CGFloat(i) * barWidth * 2, y: rect.midY - height / 2, width: barWidth, height: height)
            Brand.cream.setFill()
            NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
        }
    }
}
