import Cocoa
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem?
    private let appState = AppState.shared
    private var floatingBarController: FloatingBarController?
    private var resultPanelController: ResultPanelController?
    private var toastController: ToastController?
    private var detectionOverlayController: DetectionOverlayController?
    private var settingsWindowController: SettingsWindowController?
    private let menu = NSMenu()
    private let accessibilityItem = NSMenuItem(title: "Accessibility: —", action: nil, keyEquivalent: "")
    private let inputMonitoringItem = NSMenuItem(title: "Input Monitoring: —", action: nil, keyEquivalent: "")
    private let bundleIdItem = NSMenuItem(title: "Bundle ID: —", action: nil, keyEquivalent: "")

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        setupStatusItem()

        floatingBarController = FloatingBarController(appState: appState)
        resultPanelController = ResultPanelController(appState: appState)
        toastController = ToastController(appState: appState)
        detectionOverlayController = DetectionOverlayController(appState: appState)
        settingsWindowController = SettingsWindowController()
        appState.shouldIgnoreMouseUp = { [weak floatingBarController, weak resultPanelController] point in
            if let floatingBarController, floatingBarController.shouldIgnoreGlobalMouseUp(point: point) {
                return true
            }
            if let resultPanelController, resultPanelController.contains(point: point) {
                return true
            }
            return false
        }

        appState.start()
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        if let button = statusItem?.button {
            button.image = NSImage(systemSymbolName: "text.bubble", accessibilityDescription: "English Practice")
        }

        menu.delegate = self
        accessibilityItem.isEnabled = false
        inputMonitoringItem.isEnabled = false
        bundleIdItem.isEnabled = false

        menu.addItem(accessibilityItem)
        menu.addItem(inputMonitoringItem)
        menu.addItem(bundleIdItem)
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings…", action: #selector(openSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Request Permissions", action: #selector(openPermissions), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem?.menu = menu
    }

    func menuWillOpen(_ menu: NSMenu) {
        let access = PermissionCenter.accessibilityEnabled ? "✅" : "❌"
        let input = PermissionCenter.inputMonitoringEnabled ? "✅" : "❌"
        accessibilityItem.title = "Accessibility: \(access)"
        inputMonitoringItem.title = "Input Monitoring: \(input)"
        let bundleId = Bundle.main.bundleIdentifier ?? "Unknown"
        bundleIdItem.title = "Bundle ID: \(bundleId)"
    }

    @objc private func openSettings() {
        NSApp.activate(ignoringOtherApps: true)
        settingsWindowController?.showWindow(nil)
        settingsWindowController?.window?.makeKeyAndOrderFront(nil)
    }

    @objc private func openPermissions() {
        PermissionCenter.openPrivacySettings()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }
}

final class SettingsWindowController: NSWindowController {
    init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 560),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Settings"
        window.center()
        window.isReleasedWhenClosed = false
        window.contentView = NSHostingView(rootView: SettingsView(settings: SettingsStore.shared))
        super.init(window: window)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
}
