//
//  telepromptApp.swift
//  teleprompt
//
//  Creates a borderless, always-on-top panel that floats just under the notch.
//

import SwiftUI
import AppKit

@main
struct telepromptApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    var body: some Scene {
        // No standard window — the panel is created by the AppDelegate.
        Settings { EmptyView() }
    }
}

/// Borderless panel that can still become key (so the text editor accepts input).
final class FloatingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var panel: FloatingPanel?
    private let model = TeleprompterModel()

    static let collapsedHeight: CGFloat = 110
    static let expandedHeight: CGFloat = 320
    static let width: CGFloat = 820

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar / overlay app: no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.width, height: Self.collapsedHeight),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isMovableByWindowBackground = true
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = true
        panel.hidesOnDeactivate = false

        let root = TeleprompterView(model: model)
            .environmentObject(model)
        panel.contentView = NSHostingView(rootView: root)

        self.panel = panel
        positionUnderNotch(height: Self.collapsedHeight)
        panel.makeKeyAndOrderFront(nil)

        // Grow/shrink the panel when entering/leaving edit mode, keeping the
        // top edge fixed so it stays pinned near the notch.
        model.onEditingChange = { [weak self] editing in
            self?.positionUnderNotch(height: editing ? Self.expandedHeight : Self.collapsedHeight)
        }
        model.onQuit = { NSApp.terminate(nil) }
        model.requestFront = { [weak self] in self?.panel?.makeKeyAndOrderFront(nil) }
    }

    /// Center horizontally and pin just below the menu bar / notch.
    private func positionUnderNotch(height: CGFloat) {
        guard let panel, let screen = NSScreen.main else { return }
        let full = screen.frame
        let visible = screen.visibleFrame
        let topOfContent = visible.maxY   // just under the menu bar
        let x = full.minX + (full.width - Self.width) / 2
        let y = topOfContent - height
        panel.setFrame(NSRect(x: x, y: y, width: Self.width, height: height),
                       display: true, animate: true)
    }
}
