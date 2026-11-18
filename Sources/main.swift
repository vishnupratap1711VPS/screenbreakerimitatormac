import AppKit
import SwiftUI
import Carbon
import ServiceManagement

@main
struct LCDPrankOverlayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var launchAtLoginItem: NSMenuItem?
    private var overlayWindows: [NSWindow] = []
    private var isShowing = true
    private var intensity: Double = 0.72
    private var hotKeyRef: EventHotKeyRef?
    private var eventHandler: EventHandlerRef?
    private var workspaceObserver: NSObjectProtocol?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        buildMenu()
        configureLaunchAtLogin()
        installHotKey()
        workspaceObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.bringOverlayToFront()
        }
        showOverlay()
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let hotKeyRef { UnregisterEventHotKey(hotKeyRef) }
        if let eventHandler { RemoveEventHandler(eventHandler) }
        if let workspaceObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(workspaceObserver)
        }
    }

    func applicationDidResignActive(_ notification: Notification) {
        bringOverlayToFront()
    }

    private func bringOverlayToFront() {
        guard isShowing else { return }
        DispatchQueue.main.async { [weak self] in
            guard let self, self.isShowing else { return }
            self.overlayWindows.forEach { $0.orderFrontRegardless() }
        }
    }

    private func buildMenu() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.title = "▧"
        let menu = NSMenu()

        let toggle = NSMenuItem(title: "Hide damage  (⌘⇧F10)", action: #selector(toggleOverlay), keyEquivalent: "")
        toggle.target = self
        toggle.tag = 100
        menu.addItem(toggle)

        let intensityMenu = NSMenu()
        for (title, value) in [("Subtle", 0.42), ("Medium", 0.72), ("Heavy", 1.0)] {
            let item = NSMenuItem(title: title, action: #selector(setIntensity(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = value
            intensityMenu.addItem(item)
        }
        let intensityItem = NSMenuItem(title: "Damage intensity", action: nil, keyEquivalent: "")
        intensityItem.submenu = intensityMenu
        menu.addItem(intensityItem)

        menu.addItem(.separator())
        let launchAtLogin = NSMenuItem(title: "Open at Login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLogin.target = self
        menu.addItem(launchAtLogin)
        launchAtLoginItem = launchAtLogin

        let quit = NSMenuItem(title: "Quit LCD Prank Overlay", action: #selector(quitApp), keyEquivalent: "q")
        quit.target = self
        menu.addItem(quit)
        statusItem.menu = menu
    }

    private func configureLaunchAtLogin() {
        let service = SMAppService.mainApp
        do {
            if service.status == .notRegistered {
                try service.register()
            }
        } catch {
            showLaunchAtLoginError(error.localizedDescription)
        }

        updateLaunchAtLoginState()
        if service.status == .requiresApproval {
            showLoginItemsApprovalAlert()
        }
    }

    private func updateLaunchAtLoginState() {
        let status = SMAppService.mainApp.status
        launchAtLoginItem?.state = status == .enabled ? .on : .off
        launchAtLoginItem?.title = status == .requiresApproval
            ? "Open at Login (approval required)"
            : "Open at Login"
    }

    @objc private func toggleLaunchAtLogin() {
        let service = SMAppService.mainApp
        if service.status == .requiresApproval {
            openLoginItemsSettings()
            return
        }

        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            showLaunchAtLoginError(error.localizedDescription)
        }

        updateLaunchAtLoginState()
        if service.status == .requiresApproval {
            showLoginItemsApprovalAlert()
        }
    }

    private func showLoginItemsApprovalAlert() {
        let alert = NSAlert()
        alert.messageText = "Allow LCD Prank Overlay at Login"
        alert.informativeText = "Enable LCD Prank Overlay in System Settings → General → Login Items to show its menu-bar icon after restart."
        alert.runModal()
    }

    private func openLoginItemsSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.LoginItems-Settings.extension"),
              NSWorkspace.shared.open(url) else {
            showLaunchAtLoginError("Could not open Login Items settings.")
            return
        }
    }

    private func showLaunchAtLoginError(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Could Not Update Login Item"
        alert.informativeText = "\(message)\n\nYou can enable LCD Prank Overlay in System Settings → General → Login Items."
        alert.runModal()
    }

    @objc private func toggleOverlay() {
        isShowing.toggle()
        if isShowing {
            showOverlay()
        } else {
            hideOverlay()
        }
        if let item = statusItem.menu?.item(withTag: 100) {
            item.title = isShowing ? "Hide damage  (⌘⇧F10)" : "Show damage  (⌘⇧F10)"
        }
    }

    @objc private func setIntensity(_ sender: NSMenuItem) {
        guard let value = sender.representedObject as? Double else { return }
        intensity = value
        if isShowing { showOverlay() }
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func showOverlay() {
        hideOverlay()
        for screen in NSScreen.screens {
            let window = NSWindow(
                contentRect: screen.frame,
                styleMask: [.borderless],
                backing: .buffered,
                defer: false,
                screen: screen
            )
            window.isOpaque = false
            window.backgroundColor = .clear
            window.hasShadow = false
            window.ignoresMouseEvents = true
            window.hidesOnDeactivate = false
            window.level = .statusBar
            window.collectionBehavior = [
                .canJoinAllSpaces,
                .stationary,
                .ignoresCycle,
                .fullScreenAuxiliary
            ]
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: DamageView(intensity: intensity))
            window.orderFrontRegardless()
            overlayWindows.append(window)
        }
    }

    private func hideOverlay() {
        overlayWindows.forEach { $0.orderOut(nil) }
        overlayWindows.removeAll()
    }

    private func installHotKey() {
        var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let callback: EventHandlerProcPtr = { _, _, userData in
            guard let userData else { return noErr }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async { delegate.toggleOverlay() }
            return noErr
        }
        InstallEventHandler(
            GetApplicationEventTarget(),
            callback,
            1,
            &eventType,
            Unmanaged.passUnretained(self).toOpaque(),
            &eventHandler
        )
        var hotKeyID = EventHotKeyID(signature: OSType(0x4C434442), id: 1)
        RegisterEventHotKey(
            UInt32(kVK_F10),
            UInt32(cmdKey | shiftKey),
            hotKeyID,
            GetApplicationEventTarget(),
            0,
            &hotKeyRef
        )
    }
}

struct DamageView: View {
    let intensity: Double

    var body: some View {
        GeometryReader { proxy in
            Canvas { context, size in
                let w = size.width
                let h = size.height
                let strength = intensity

                // Small, irregular LCD bleed anchored to the lower-right edge.
                var bleed = Path()
                bleed.move(to: CGPoint(x: w * 0.965, y: h * 0.53))
                bleed.addCurve(to: CGPoint(x: w, y: h * 0.49),
                               control1: CGPoint(x: w * 0.982, y: h * 0.57),
                               control2: CGPoint(x: w * 0.99, y: h * 0.51))
                bleed.addLine(to: CGPoint(x: w, y: h))
                bleed.addLine(to: CGPoint(x: w * 0.82, y: h))
                bleed.addCurve(to: CGPoint(x: w * 0.89, y: h * 0.79),
                               control1: CGPoint(x: w * 0.84, y: h * 0.95),
                               control2: CGPoint(x: w * 0.88, y: h * 0.88))
                bleed.addCurve(to: CGPoint(x: w * 0.965, y: h * 0.53),
                               control1: CGPoint(x: w * 0.91, y: h * 0.69),
                               control2: CGPoint(x: w * 0.94, y: h * 0.60))
                bleed.closeSubpath()
                context.fill(bleed, with: .color(Color(red: 0.025, green: 0.008, blue: 0.07).opacity(0.82 * strength)))

                var purple = Path()
                purple.move(to: CGPoint(x: w * 0.91, y: h * 0.57))
                purple.addCurve(to: CGPoint(x: w, y: h * 0.51),
                                control1: CGPoint(x: w * 0.95, y: h * 0.58),
                                control2: CGPoint(x: w * 0.98, y: h * 0.54))
                purple.addLine(to: CGPoint(x: w, y: h * 0.86))
                purple.addCurve(to: CGPoint(x: w * 0.86, y: h * 0.77),
                                control1: CGPoint(x: w * 0.96, y: h * 0.84),
                                control2: CGPoint(x: w * 0.89, y: h * 0.82))
                purple.closeSubpath()
                context.fill(purple, with: .color(Color.purple.opacity(0.28 * strength)))

                // Fine coloured columns, strongest near the right edge.
                let columns: [(CGFloat, Color, CGFloat)] = [
                    (0.842, .cyan, 1.0), (0.861, .purple, 1.2), (0.878, .blue, 0.8),
                    (0.901, .green, 0.9), (0.925, .pink, 1.0), (0.946, .cyan, 0.7),
                    (0.969, .red, 1.1), (0.986, .purple, 1.3), (0.996, .white, 0.7)
                ]
                for (x, color, width) in columns {
                    var line = Path()
                    line.move(to: CGPoint(x: w * x, y: 0))
                    line.addLine(to: CGPoint(x: w * x, y: h))
                    context.stroke(line, with: .color(color.opacity(0.65 * strength)), lineWidth: width)
                }

                // A few faint horizontal scan distortions near the damaged area.
                for i in 0..<7 {
                    let y = h * (0.72 + CGFloat(i) * 0.035)
                    var line = Path()
                    line.move(to: CGPoint(x: w * 0.77, y: y))
                    line.addLine(to: CGPoint(x: w, y: y + (i.isMultiple(of: 2) ? 1.5 : -1.0)))
                    context.stroke(line, with: .color(Color.cyan.opacity(0.18 * strength)), lineWidth: 0.7)
                }
            }
            .frame(width: proxy.size.width, height: proxy.size.height)
            .allowsHitTesting(false)
        }
        .ignoresSafeArea()
    }
}
