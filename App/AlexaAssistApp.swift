import AppKit
import SwiftUI

@main
struct AlexaAssistApp: App {
    @NSApplicationDelegateAdaptor(AppController.self) private var controller

    var body: some Scene {
        Settings { EmptyView() }
    }
}


@MainActor
final class AppController: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private(set) lazy var model = AppModel()
    private var statusItem: NSStatusItem!
    private let popover = NSPopover()
    private var signInWindow: NSWindow?
    private var settingsWindow: NSWindow?
    private var ticker: Timer?
    private static let icon = NSImage(systemSymbolName: "homepodmini.fill", accessibilityDescription: "AlexaAssist")
    private static let warningIcon = NSImage(systemSymbolName: "exclamationmark.triangle.fill",
                                             accessibilityDescription: "AlexaAssist: sign in again")

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Hosting unit tests: no menu bar UI and no Keychain read.
        guard ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] == nil else { return }
        model.openSignIn = { [weak self] in self?.showSignIn() }
        model.openSettings = { [weak self] in self?.showSettings() }

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        let button = statusItem.button!
        button.image = Self.icon
        button.imagePosition = .imageLeading
        button.font = .monospacedDigitSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        button.target = self
        button.action = #selector(statusItemClicked)
        button.sendAction(on: [.leftMouseUp, .rightMouseUp])

        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self
        let panel = NSHostingController(rootView: PanelView().environment(model))
        panel.sizingOptions = .preferredContentSize  // popover shrinks and grows with the selected tab
        popover.contentViewController = panel

        // One cheap tick a second keeps the menu bar countdown current.
        ticker = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.updateTitle() }
        }
        Task {
            await model.restoreSession()
            if !model.isSignedIn { togglePopover() }
        }
    }

    @objc private func statusItemClicked() {
        if NSApp.currentEvent?.type == .rightMouseUp { showMenu() } else { togglePopover() }
    }

    private func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            NSApp.activate()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    private func showMenu() {
        let menu = NSMenu()
        menu.addItem(withTitle: "Open AlexaAssist", action: #selector(openPanel), keyEquivalent: "").target = self
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",").target = self
        menu.addItem(.separator())
        if model.isSignedIn {
            menu.addItem(withTitle: "Stop Ringing", action: #selector(stopRinging), keyEquivalent: "").target = self
            menu.addItem(withTitle: "Sign Out", action: #selector(signOut), keyEquivalent: "").target = self
        } else {
            menu.addItem(withTitle: "Sign In…", action: #selector(openSignIn), keyEquivalent: "").target = self
        }
        menu.addItem(withTitle: "Quit AlexaAssist", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        popover.performClose(nil)
        if let button = statusItem.button {
            menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.height + 4), in: button)
        }
    }

    @objc private func openPanel() { if !popover.isShown { togglePopover() } }
    @objc private func openSettings() { showSettings() }
    @objc private func openSignIn() { showSignIn() }
    @objc private func signOut() { model.signOut() }
    @objc private func stopRinging() { Task { await model.stopRinging() } }

    private func updateTitle() {
        guard let button = statusItem.button else { return }
        var title = ""
        if let fire = model.nextTimer?.fireDate {
            let left = max(0, Int(fire.timeIntervalSinceNow.rounded(.up)))
            title = left >= 3600
                ? String(format: " %d:%02d:%02d", left / 3600, left / 60 % 60, left % 60)
                : String(format: " %d:%02d", left / 60, left % 60)
        }
        if button.title != title { button.title = title }
        // A warning icon is the only cue when the session expires while the panel is closed.
        let image = model.banner?.needsSignIn == true ? Self.warningIcon : Self.icon
        if button.image !== image { button.image = image }
    }

    func popoverDidShow(_ notification: Notification) { model.isPanelOpen = true }
    func popoverDidClose(_ notification: Notification) { model.isPanelOpen = false }

    // MARK: - Windows

    private func showSignIn() {
        popover.performClose(nil)
        signInWindow?.close()
        let window = NSWindow(contentViewController: NSHostingController(
            rootView: SignInView { [weak self] in self?.signInWindow?.close() }.environment(model)))
        window.title = "Sign in to Amazon"
        window.styleMask = [.titled, .closable]
        window.isReleasedWhenClosed = false
        window.center()
        signInWindow = window
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func showSettings() {
        popover.performClose(nil)
        if settingsWindow == nil {
            let window = NSWindow(contentViewController: NSHostingController(rootView: SettingsView().environment(model)))
            window.title = "AlexaAssist Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }
}
