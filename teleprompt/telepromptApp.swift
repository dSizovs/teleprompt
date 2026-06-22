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

    static let initialWidth: CGFloat = 820
    static let initialHeight: CGFloat = 130
    static let minWidth: CGFloat = 320
    static let minHeight: CGFloat = 70
    static let editMinHeight: CGFloat = 240

    /// Captured at the start of a corner-grip resize.
    private var resizeStartFrame: NSRect = .zero
    /// Frame remembered before we grew the panel to fit the editor.
    private var frameBeforeEdit: NSRect?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Menu-bar / overlay app: no Dock icon.
        NSApp.setActivationPolicy(.accessory)

        let panel = FloatingPanel(
            contentRect: NSRect(x: 0, y: 0, width: Self.initialWidth, height: Self.initialHeight),
            styleMask: [.borderless, .nonactivatingPanel, .resizable],
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
        panel.minSize = NSSize(width: Self.minWidth, height: Self.minHeight)
        panel.maxSize = NSSize(width: 100_000, height: 100_000)

        let root = TeleprompterView(model: model)
            .environmentObject(model)
        panel.contentView = NSHostingView(rootView: root)

        self.panel = panel
        positionUnderNotch(width: Self.initialWidth, height: Self.initialHeight)
        panel.makeKeyAndOrderFront(nil)

        // Make sure the editor has room: grow if the box is too short, then
        // restore the user's chosen size when editing ends.
        model.onEditingChange = { [weak self] editing in
            guard let self, let panel = self.panel else { return }
            if editing {
                if panel.frame.height < Self.editMinHeight {
                    self.frameBeforeEdit = panel.frame
                    self.setHeightKeepingTop(Self.editMinHeight)
                }
            } else if let prior = self.frameBeforeEdit {
                panel.setFrame(prior, display: true, animate: true)
                self.frameBeforeEdit = nil
            }
        }
        model.onQuit = { NSApp.terminate(nil) }
        model.requestFront = { [weak self] in self?.panel?.makeKeyAndOrderFront(nil) }

        // Corner-grip resize: grow right & down, keeping the top edge pinned.
        model.beginResize = { [weak self] in
            guard let self, let panel = self.panel else { return }
            self.resizeStartFrame = panel.frame
        }
        model.updateResize = { [weak self] translation in
            guard let self, let panel = self.panel else { return }
            let f = self.resizeStartFrame
            let newW = max(Self.minWidth, f.width + translation.width)
            let newH = max(Self.minHeight, f.height + translation.height)
            panel.setFrame(NSRect(x: f.minX, y: f.maxY - newH, width: newW, height: newH),
                           display: true)
        }
    }

    private func setHeightKeepingTop(_ height: CGFloat) {
        guard let panel else { return }
        let f = panel.frame
        panel.setFrame(NSRect(x: f.minX, y: f.maxY - height, width: f.width, height: height),
                       display: true, animate: true)
    }

    /// Center horizontally and pin just below the menu bar / notch.
    private func positionUnderNotch(width: CGFloat, height: CGFloat) {
        guard let panel, let screen = NSScreen.main else { return }
        let full = screen.frame
        let visible = screen.visibleFrame
        let topOfContent = visible.maxY   // just under the menu bar
        let x = full.minX + (full.width - width) / 2
        let y = topOfContent - height
        panel.setFrame(NSRect(x: x, y: y, width: width, height: height),
                       display: true, animate: true)
    }
}
