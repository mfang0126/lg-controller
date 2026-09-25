import AppKit

final class MenuBarController: NSObject, NSMenuDelegate, NSWindowDelegate {
    private let settings: RouterSettings
    private let router: VolumeRouter
    private let provider: WebOSProvider
    private let audioOutput = AudioOutputResolver()

    private let statusItem: NSStatusItem
    private let statusMenu = NSMenu()
    private let routingMenuItem = NSMenuItem()
    private let routingSwitch = NSSwitch()
    private let configureItem = NSMenuItem(title: "Configure…", action: #selector(configureTV), keyEquivalent: ",")
    private let quitItem = NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q")

    private var configurationWindow: NSWindow?
    private var hostField: NSTextField?
    private var audioPopup: NSPopUpButton?
    private var audioOptions: [AudioOutputDevice] = []
    /// True when popup index 0 is a "(not connected)" placeholder for the stored
    /// target rather than a real device — real devices are then shifted by 1.
    private var audioPlaceholderActive = false
    private var overridePopup: NSPopUpButton?
    private var schemePopup: NSPopUpButton?
    private var portField: NSTextField?
    private var advancedButton: NSButton?
    private var advancedView: NSView?
    private var testButton: NSButton?
    private var testStatusLabel: NSTextField?
    private var isAdvancedVisible = false
    private var currentRouterStatus: RouterStatus = .disabled
    private var latestAudioState: WebOSAudioState?

    init(settings: RouterSettings, router: VolumeRouter, provider: WebOSProvider) {
        self.settings = settings
        self.router = router
        self.provider = provider
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        super.init()

        statusMenu.delegate = self
        statusMenu.autoenablesItems = false
        configureItem.target = self
        quitItem.target = self
        makeRoutingMenuItem()
        statusMenu.addItem(routingMenuItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(configureItem)
        statusMenu.addItem(.separator())
        statusMenu.addItem(quitItem)
        statusItem.menu = statusMenu
        if let button = statusItem.button {
            button.title = ""
            button.attributedTitle = NSAttributedString(string: "")
            button.imagePosition = .imageOnly
        }

        router.statusHandler = { [weak self] status in
            self?.updateStatus(status)
        }
        provider.audioStateHandler = { [weak self] audioState in
            self?.updateAudioState(audioState)
        }
        provider.pairingMessageHandler = { [weak self] message in
            self?.showPairingMessage(message)
        }
        updateStatus(router.status)
        provider.refreshAudioState()
    }

    func menuWillOpen(_ menu: NSMenu) {
        guard menu === statusMenu else { return }
        refreshRoutingToggle()
        provider.refreshAudioState()
    }

    private func makeRoutingMenuItem() {
        let view = NSView(frame: NSRect(x: 0, y: 0, width: 232, height: 38))
        let label = NSTextField(labelWithString: "Volume routing")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.frame = NSRect(x: 16, y: 9, width: 150, height: 20)
        view.addSubview(label)

        routingSwitch.controlSize = .small
        routingSwitch.frame = NSRect(x: 184, y: 7, width: 34, height: 24)
        routingSwitch.target = self
        routingSwitch.action = #selector(toggleRouting)
        routingSwitch.setAccessibilityLabel("Volume routing")
        view.addSubview(routingSwitch)
        routingMenuItem.view = view
    }

    @objc private func toggleRouting() {
        if routingSwitch.state == .on {
            guard settings.snapshot.isConfigured else {
                routingSwitch.state = .off
                showConfigurationWindow()
                return
            }
            guard router.enable() else {
                routingSwitch.state = .off
                showAccessibilityRequired()
                return
            }
        } else {
            router.disable()
        }
        refreshRoutingToggle()
    }

    @objc private func configureTV() {
        showConfigurationWindow()
    }

    @objc private func quit() {
        NSApplication.shared.terminate(nil)
    }

    private func updateStatus(_ status: RouterStatus) {
        currentRouterStatus = status
        refreshStatusItem()
        refreshRoutingToggle()
    }

    private func updateAudioState(_ audioState: WebOSAudioState) {
        latestAudioState = audioState
        refreshStatusItem()
    }

    private func refreshStatusItem() {
        guard let button = statusItem.button else { return }
        button.title = ""
        button.attributedTitle = NSAttributedString(string: "")
        button.imagePosition = .imageOnly
        button.image = NSImage(
            systemSymbolName: menuBarSymbolName(),
            accessibilityDescription: menuBarAccessibilityDescription()
        )
        button.toolTip = "LG Volume Router — \(audioDescription()) · \(routingDescription())"
    }

    private func menuBarSymbolName() -> String {
        guard let latestAudioState else { return "speaker" }
        if latestAudioState.isMuted { return "speaker.slash" }
        switch latestAudioState.volume {
        case 0...33: return "speaker.wave.1"
        case 34...66: return "speaker.wave.2"
        default: return "speaker.wave.3"
        }
    }

    private func menuBarAccessibilityDescription() -> String {
        "LG Volume Router — \(audioDescription())"
    }

    private func audioDescription() -> String {
        guard let latestAudioState else {
            return statusDescription(for: currentRouterStatus)
        }
        return latestAudioState.isMuted ? "TV muted" : "TV volume \(latestAudioState.volume)%"
    }

    /// Describes the routing decision so the tooltip reflects the sound-output rule.
    private func routingDescription() -> String {
        guard router.isEnabled else { return "Routing off" }
        switch settings.snapshot.routeOverride {
        case .always:
            return "Routing on — always to TV"
        case .never:
            return "Routing on — override never (macOS keeps volume keys)"
        case .auto:
            guard let target = settings.snapshot.targetAudioDevice else {
                return "Routing on — no TV sound output configured"
            }
            if let current = audioOutput.currentDefaultOutput(),
               !current.isAirPlay,
               target.matches(current) {
                return "Routing on — \(current.name) is the sound output"
            }
            return "Routing on — TV not the sound output"
        }
    }

    private func refreshRoutingToggle() {
        routingSwitch.state = router.isEnabled ? .on : .off
    }

    private func statusDescription(for status: RouterStatus) -> String {
        switch status {
        case .disabled: return "TV volume not read"
        case .ready: return "TV volume not read"
        case .connecting: return "Checking TV volume"
        case .connected: return "TV volume not read"
        case .unavailable: return "TV unavailable"
        }
    }

    private func showAccessibilityRequired() {
        let alert = NSAlert()
        alert.messageText = "Allow accessibility once"
        alert.informativeText = "macOS must allow LG Volume Router in Privacy & Security → Accessibility before it can route media keys."
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showPairingMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Approve pairing on your LG TV"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }

    private func showConfigurationWindow() {
        if let configurationWindow {
            NSApplication.shared.activate(ignoringOtherApps: true)
            configurationWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 385),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "LG Volume Router"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 480, height: 385)
        window.maxSize = NSSize(width: 480, height: 449)

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 385))
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        let heading = NSTextField(labelWithString: "LG Volume Router")
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        heading.frame = NSRect(x: 24, y: 0, width: 300, height: 24)
        heading.identifier = NSUserInterfaceItemIdentifier("heading")
        contentView.addSubview(heading)

        let subtitle = NSTextField(labelWithString: "Volume keys follow the Mac's sound output.")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 24, y: 0, width: 400, height: 20)
        subtitle.identifier = NSUserInterfaceItemIdentifier("subtitle")
        contentView.addSubview(subtitle)

        let addressLabel = fieldLabel("TV address")
        addressLabel.identifier = NSUserInterfaceItemIdentifier("addressLabel")
        contentView.addSubview(addressLabel)

        let host = NSTextField(frame: .zero)
        host.stringValue = settings.host
        host.placeholderString = "192.168.1.50"
        host.identifier = NSUserInterfaceItemIdentifier("hostField")
        contentView.addSubview(host)
        hostField = host

        let audioLabel = fieldLabel("TV sound output device")
        audioLabel.identifier = NSUserInterfaceItemIdentifier("audioLabel")
        contentView.addSubview(audioLabel)

        let audio = NSPopUpButton(frame: .zero, pullsDown: false)
        audioOptions = audioOutput.outputDevices()
        audioPlaceholderActive = false
        if audioOptions.isEmpty {
            audio.addItem(withTitle: "No output devices found")
            audio.isEnabled = false
        } else {
            var titles: [String] = []
            var preselectDeviceIndex: Int? = nil
            if let target = settings.targetAudioDevice {
                if let index = audioOptions.firstIndex(where: { target.matches($0) }) {
                    preselectDeviceIndex = index
                } else {
                    // Stored target is not connected (TV off / HDMI asleep). Show
                    // it as a placeholder instead of silently preselecting some
                    // other device — that would overwrite the stored target.
                    titles.append("\(target.name) (not connected)")
                    audioPlaceholderActive = true
                }
            } else if let current = audioOutput.currentDefaultOutput(),
                      let index = audioOptions.firstIndex(where: { current.matches($0) }) {
                // Convenience: preselect the current sound output, usually the TV.
                preselectDeviceIndex = index
            }
            titles += audioOptions.map { $0.isAirPlay ? "\($0.name) (AirPlay)" : $0.name }
            audio.addItems(withTitles: titles)
            if let preselectDeviceIndex {
                audio.selectItem(at: preselectDeviceIndex + (audioPlaceholderActive ? 1 : 0))
            } else if audioPlaceholderActive {
                audio.selectItem(at: 0)
            }
        }
        audio.identifier = NSUserInterfaceItemIdentifier("audioPopup")
        contentView.addSubview(audio)
        audioPopup = audio

        let overrideLabel = fieldLabel("Route volume keys")
        overrideLabel.identifier = NSUserInterfaceItemIdentifier("overrideLabel")
        contentView.addSubview(overrideLabel)

        let override = NSPopUpButton(frame: .zero, pullsDown: false)
        override.addItems(withTitles: [
            "When the TV is the sound output",
            "Always to the TV",
            "Never to the TV"
        ])
        override.selectItem(at: settings.routeOverride.menuIndex)
        override.identifier = NSUserInterfaceItemIdentifier("overridePopup")
        contentView.addSubview(override)
        overridePopup = override

        let test = NSButton(title: "Test connection", target: self, action: #selector(testConnection))
        test.bezelStyle = .rounded
        test.keyEquivalent = "\r"
        test.identifier = NSUserInterfaceItemIdentifier("testButton")
        contentView.addSubview(test)
        testButton = test

        let testStatus = NSTextField(labelWithString: "")
        testStatus.font = .systemFont(ofSize: 12)
        testStatus.textColor = .secondaryLabelColor
        testStatus.lineBreakMode = .byTruncatingTail
        testStatus.identifier = NSUserInterfaceItemIdentifier("testStatus")
        contentView.addSubview(testStatus)
        testStatusLabel = testStatus

        let advanced = NSButton(title: "Advanced settings", target: self, action: #selector(toggleAdvanced))
        advanced.bezelStyle = .inline
        advanced.isBordered = false
        advanced.alignment = .left
        advanced.font = .systemFont(ofSize: 13, weight: .medium)
        advanced.imagePosition = .imageLeading
        advanced.image = disclosureImage(expanded: false)
        advanced.contentTintColor = .secondaryLabelColor
        advanced.setAccessibilityLabel("Show advanced connection settings")
        advanced.identifier = NSUserInterfaceItemIdentifier("advancedButton")
        contentView.addSubview(advanced)
        advancedButton = advanced

        let advancedContainer = NSView(frame: .zero)
        advancedContainer.isHidden = true
        advancedContainer.identifier = NSUserInterfaceItemIdentifier("advancedView")
        contentView.addSubview(advancedContainer)
        advancedView = advancedContainer

        let schemeLabel = fieldLabel("Protocol")
        schemeLabel.frame = NSRect(x: 0, y: 36, width: 56, height: 18)
        advancedContainer.addSubview(schemeLabel)

        let scheme = NSPopUpButton(frame: NSRect(x: 62, y: 32, width: 84, height: 26), pullsDown: false)
        scheme.addItems(withTitles: ["wss", "ws"])
        scheme.selectItem(withTitle: settings.scheme)
        advancedContainer.addSubview(scheme)
        schemePopup = scheme

        let portLabel = fieldLabel("Port")
        portLabel.frame = NSRect(x: 182, y: 36, width: 34, height: 18)
        advancedContainer.addSubview(portLabel)

        let port = NSTextField(frame: NSRect(x: 222, y: 32, width: 78, height: 24))
        port.stringValue = String(settings.port)
        advancedContainer.addSubview(port)
        portField = port

        let repair = NSButton(title: "Forget TV pairing…", target: self, action: #selector(resetPairing))
        repair.bezelStyle = .inline
        repair.contentTintColor = .secondaryLabelColor
        repair.frame = NSRect(x: -6, y: 2, width: 132, height: 22)
        advancedContainer.addSubview(repair)

        configurationWindow = window
        layoutConfigurationWindow(animated: false)
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.center()
        window.makeKeyAndOrderFront(nil)
    }

    private func fieldLabel(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 12, weight: .medium)
        return label
    }

    private func disclosureImage(expanded: Bool) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 11, weight: .medium)
        return NSImage(
            systemSymbolName: expanded ? "chevron.down" : "chevron.right",
            accessibilityDescription: nil
        )?.withSymbolConfiguration(configuration)
    }

    private func layoutConfigurationWindow(animated: Bool) {
        guard let window = configurationWindow,
              let contentView = window.contentView,
              let heading = contentView.subviews.first(where: { $0.identifier?.rawValue == "heading" }),
              let subtitle = contentView.subviews.first(where: { $0.identifier?.rawValue == "subtitle" }),
              let addressLabel = contentView.subviews.first(where: { $0.identifier?.rawValue == "addressLabel" }),
              let hostField,
              let audioLabel = contentView.subviews.first(where: { $0.identifier?.rawValue == "audioLabel" }),
              let audioPopup,
              let overrideLabel = contentView.subviews.first(where: { $0.identifier?.rawValue == "overrideLabel" }),
              let overridePopup,
              let testButton,
              let testStatusLabel,
              let advancedButton,
              let advancedView else { return }

        let advancedHeight: CGFloat = isAdvancedVisible ? 64 : 0
        let contentHeight: CGFloat = 385 + advancedHeight
        window.setContentSize(NSSize(width: 480, height: contentHeight))

        advancedView.frame = NSRect(x: 24, y: 20, width: 432, height: advancedHeight)
        advancedButton.frame = NSRect(x: 24, y: 20 + advancedHeight, width: 432, height: 32)
        testButton.frame = NSRect(x: 24, y: advancedButton.frame.maxY + 16, width: 132, height: 32)
        testStatusLabel.frame = NSRect(x: 170, y: testButton.frame.minY + 7, width: 280, height: 18)
        overridePopup.frame = NSRect(x: 24, y: testButton.frame.maxY + 24, width: 432, height: 26)
        overrideLabel.frame = NSRect(x: 24, y: overridePopup.frame.maxY + 6, width: 260, height: 18)
        audioPopup.frame = NSRect(x: 24, y: overrideLabel.frame.maxY + 20, width: 432, height: 26)
        audioLabel.frame = NSRect(x: 24, y: audioPopup.frame.maxY + 6, width: 260, height: 18)
        hostField.frame = NSRect(x: 24, y: audioLabel.frame.maxY + 20, width: 432, height: 26)
        addressLabel.frame = NSRect(x: 24, y: hostField.frame.maxY + 6, width: 200, height: 18)
        subtitle.frame = NSRect(x: 24, y: addressLabel.frame.maxY + 14, width: 420, height: 18)
        heading.frame = NSRect(x: 24, y: subtitle.frame.maxY + 5, width: 320, height: 24)

        advancedView.isHidden = !isAdvancedVisible
        advancedButton.title = "Advanced settings"
        advancedButton.image = disclosureImage(expanded: isAdvancedVisible)
        advancedButton.setAccessibilityLabel(
            isAdvancedVisible ? "Hide advanced connection settings" : "Show advanced connection settings"
        )
        if animated {
            window.animator().alphaValue = 1
        }
    }

    @objc private func toggleAdvanced() {
        isAdvancedVisible.toggle()
        layoutConfigurationWindow(animated: true)
    }

    @objc private func testConnection() {
        guard applyConfiguration() else { return }
        testButton?.isEnabled = false
        testButton?.title = "Testing…"
        setTestStatus("Checking TV…", color: .secondaryLabelColor)

        provider.testConnection { [weak self] result in
            guard let self else { return }
            self.testButton?.isEnabled = true
            self.testButton?.title = "Test connection"
            switch result {
            case .success:
                self.setTestStatus("Connected · Audio control ready", color: .systemGreen)
            case .failure:
                self.setTestStatus("Couldn’t connect. Check the address and TV approval.", color: .secondaryLabelColor)
            }
        }
    }

    private func applyConfiguration() -> Bool {
        guard let hostField,
              let audioPopup,
              let overridePopup,
              let schemePopup,
              let portField else { return false }
        let host = hostField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !host.isEmpty else {
            hostField.becomeFirstResponder()
            setTestStatus("Enter the TV address.", color: .secondaryLabelColor)
            return false
        }
        guard let port = Int(portField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65_535).contains(port) else {
            isAdvancedVisible = true
            layoutConfigurationWindow(animated: true)
            portField.becomeFirstResponder()
            setTestStatus("Enter a valid port.", color: .secondaryLabelColor)
            return false
        }
        guard audioPopup.isEnabled,
              audioPopup.indexOfSelectedItem >= 0 else {
            setTestStatus("Choose the TV's sound output device.", color: .secondaryLabelColor)
            return false
        }
        let selectedDevice: AudioOutputDevice
        if audioPlaceholderActive {
            guard audioPopup.indexOfSelectedItem > 0 else {
                setTestStatus("The configured device is not connected — pick an output device.", color: .secondaryLabelColor)
                return false
            }
            selectedDevice = audioOptions[audioPopup.indexOfSelectedItem - 1]
        } else {
            guard audioPopup.indexOfSelectedItem < audioOptions.count else {
                setTestStatus("Choose the TV's sound output device.", color: .secondaryLabelColor)
                return false
            }
            selectedDevice = audioOptions[audioPopup.indexOfSelectedItem]
        }
        // The device list is a snapshot from when the window opened; devices can
        // hot-unplug meanwhile. Re-validate against live CoreAudio before saving.
        guard audioOutput.outputDevices().contains(where: { selectedDevice.matches($0) }) else {
            setTestStatus("That output device just disconnected — reopen Configure to refresh.", color: .secondaryLabelColor)
            return false
        }

        settings.update(
            tvName: settings.tvName.isEmpty ? "LG TV" : settings.tvName,
            host: host,
            scheme: schemePopup.titleOfSelectedItem ?? "wss",
            port: port,
            targetAudioDevice: selectedDevice,
            routeOverride: RouteOverride(menuIndex: overridePopup.indexOfSelectedItem)
        )
        router.reloadConfiguration()
        return true
    }

    private func setTestStatus(_ text: String, color: NSColor) {
        testStatusLabel?.stringValue = text
        testStatusLabel?.textColor = color
    }

    @objc private func resetPairing() {
        let alert = NSAlert()
        alert.messageText = "Reset LG TV pairing?"
        alert.informativeText = "The next connection test or routed volume key will need approval on the TV."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset pairing")
        alert.addButton(withTitle: "Cancel")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        router.resetPairing()
        setTestStatus("Pairing reset.", color: .secondaryLabelColor)
    }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow,
              window === configurationWindow else { return }
        configurationWindow = nil
        hostField = nil
        audioPopup = nil
        audioOptions.removeAll()
        overridePopup = nil
        schemePopup = nil
        portField = nil
        advancedButton = nil
        advancedView = nil
        testButton = nil
        testStatusLabel = nil
        isAdvancedVisible = false
    }
}
