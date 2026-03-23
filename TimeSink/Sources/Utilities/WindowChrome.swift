import AppKit
import SwiftUI

struct WindowMaterialBackground: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView {
        let container = NSView()

        let effectView = NSVisualEffectView()
        effectView.blendingMode = .behindWindow
        effectView.material = .underWindowBackground
        effectView.state = .active
        effectView.translatesAutoresizingMaskIntoConstraints = false

        let tintView = NSView()
        tintView.wantsLayer = true
        tintView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.72).cgColor
        tintView.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(effectView)
        container.addSubview(tintView)

        NSLayoutConstraint.activate([
            effectView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            effectView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            effectView.topAnchor.constraint(equalTo: container.topAnchor),
            effectView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            tintView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            tintView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            tintView.topAnchor.constraint(equalTo: container.topAnchor),
            tintView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        return container
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        if let effectView = nsView.subviews.compactMap({ $0 as? NSVisualEffectView }).first {
            effectView.material = .underWindowBackground
            effectView.state = .active
        }

        if let tintView = nsView.subviews.last {
            tintView.layer?.backgroundColor = NSColor.windowBackgroundColor.withAlphaComponent(0.72).cgColor
        }

        DispatchQueue.main.async {
            guard let window = nsView.window else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
        }
    }
}
