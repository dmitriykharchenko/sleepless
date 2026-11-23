import AppKit
import SleeplessCore

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let controller = SleepController(service: SystemPowerSettings())
    private var statusItem: NSStatusItem?
    private var refreshTimer: Timer?
    private var quitPending = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem = item
        if let button = item.button {
            button.target = self
            button.action = #selector(statusClicked)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        controller.onChange = { [weak self] in self?.updateStatus() }
        updateStatus()
        Task { await controller.start() }
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in await self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(workspaceWoke),
            name: NSWorkspace.didWakeNotification, object: nil
        )
    }

    private func updateStatus() {
        guard let button = statusItem?.button else { return }
        StatusItemPresentation.apply(to: button, state: controller.state, isBusy: controller.isBusy)
    }

    @objc private func statusClicked() {
        guard !quitPending else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            showMenu()
        } else {
            guard !controller.isBusy else { return }
            Task {
                await controller.toggle()
                showOperationErrorIfNeeded()
            }
        }
    }

    private func showMenu() {
        guard let button = statusItem?.button else { return }
        let menu = NSMenu()
        let status = NSMenuItem(title: controller.state.summary, action: nil, keyEquivalent: "")
        menu.addItem(status)
        if controller.isBusy {
            menu.addItem(NSMenuItem(title: "Checking or changing setting…", action: nil, keyEquivalent: ""))
        }
        if let error = controller.lastError {
            let errorItem = NSMenuItem(title: "Last attempt: \(error.localizedDescription)", action: nil, keyEquivalent: "")
            errorItem.toolTip = error.localizedDescription
            menu.addItem(errorItem)
        }
        menu.addItem(.separator())
        addMenuItem("Refresh Status", action: #selector(refreshClicked), to: menu, enabled: !controller.isBusy)
        addMenuItem("About Sleepless and Safety…", action: #selector(showHelp), to: menu)
        menu.addItem(.separator())
        addMenuItem("Quit Sleepless…", action: #selector(quitClicked), to: menu, enabled: !controller.isBusy)
        menu.popUp(positioning: nil, at: NSPoint(x: 0, y: button.bounds.minY), in: button)
    }

    private func addMenuItem(_ title: String, action: Selector, to menu: NSMenu, enabled: Bool = true) {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.isEnabled = enabled
        menu.autoenablesItems = false
        menu.addItem(item)
    }

    @objc private func refreshClicked() { Task { await refresh() } }
    @objc private func workspaceWoke() { Task { await refresh() } }

    private func refresh() async {
        guard !quitPending else { return }
        await controller.refresh()
    }

    @objc private func showHelp() {
        let alert = NSAlert()
        alert.messageText = "Sleepless"
        alert.informativeText = """
        Left-click the menu-bar text to toggle; right-click for options.

        SOMNIA: normal sleep is allowed. INSOMNIA: system sleep is disabled, including lid-close sleep. ?: the setting cannot be verified; left-click to retry reading without changing it. Status is checked every five seconds and on wake.

        Changes use macOS administrator approval. This is a global, persistent pmset setting, not a lid-only control. It is undocumented and may vary by Mac and macOS version.

        A closed, awake Mac can overheat in a bag and drain its battery. Keep it ventilated. Quitting or a crash does not reset the setting. Sleepless only offers normal-sleep restoration for no-sleep it enabled in this session; it leaves a pre-existing setting alone.

        If needed, restore normal sleep in Terminal: sudo pmset -a disablesleep 0
        """
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    private func showOperationErrorIfNeeded() {
        guard let error = controller.lastError, error != .authorizationCancelled else { return }
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Sleep change could not be verified"
        alert.informativeText = "\(error.localizedDescription)\n\n\(controller.state.summary). No further change will be made automatically."
        NSApp.activate(ignoringOtherApps: true)
        alert.runModal()
    }

    @objc private func quitClicked() { NSApp.terminate(nil) }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard !quitPending, !controller.isBusy else { return .terminateCancel }
        quitPending = true
        Task {
            // Refresh directly: ordinary polling is suspended during quit handling.
            await controller.refresh()
            let shouldQuit = await confirmQuit()
            quitPending = false
            sender.reply(toApplicationShouldTerminate: shouldQuit)
        }
        return .terminateLater
    }

    private func confirmQuit() async -> Bool {
        switch controller.restorationPolicy {
        case .none:
            return true
        case .stateUnknown:
            let alert = NSAlert()
            alert.alertStyle = .warning
            alert.messageText = "Sleep setting is unknown"
            alert.informativeText = "Sleepless previously enabled no-sleep, but cannot verify the current setting. It may remain enabled after quitting. No power setting will be changed automatically."
            alert.addButton(withTitle: "Quit Without Changing")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            return alert.runModal() == .alertFirstButtonReturn
        case .offerRestoration:
            let alert = NSAlert()
            alert.messageText = "Restore normal sleep before quitting?"
            alert.informativeText = "Sleepless enabled no-sleep during this session. It persists after quitting. Restoring normal sleep requires administrator approval and may let this Mac sleep immediately, including when its lid is closed."
            alert.addButton(withTitle: "Restore and Quit")
            alert.addButton(withTitle: "Quit Without Restoring")
            alert.addButton(withTitle: "Cancel")
            NSApp.activate(ignoringOtherApps: true)
            switch alert.runModal() {
            case .alertFirstButtonReturn:
                let restored = await controller.restoreNormalSleep()
                if !restored { showOperationErrorIfNeeded() }
                return restored
            case .alertSecondButtonReturn:
                return true
            default:
                return false
            }
        }
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()