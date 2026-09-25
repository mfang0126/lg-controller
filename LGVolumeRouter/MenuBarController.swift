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
    private let configureItem = NSMenuItem(title: "Set up TV… / 设置电视…", action: #selector(configureTV), keyEquivalent: ",")
    private let quitItem = NSMenuItem(title: "Quit / 退出", action: #selector(quit), keyEquivalent: "q")

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
        let label = NSTextField(labelWithString: "Control TV volume")
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.frame = NSRect(x: 16, y: 15, width: 164, height: 18)
        view.addSubview(label)

        let sublabel = NSTextField(labelWithString: "控制电视音量")
        sublabel.font = .systemFont(ofSize: 10.5)
        sublabel.textColor = .secondaryLabelColor
        sublabel.frame = NSRect(x: 16, y: 1, width: 164, height: 14)
        view.addSubview(sublabel)

        routingSwitch.controlSize = .small
        routingSwitch.frame = NSRect(x: 184, y: 7, width: 34, height: 24)
        routingSwitch.target = self
        routingSwitch.action = #selector(toggleRouting)
        routingSwitch.setAccessibilityLabel("Control TV volume / 控制电视音量")
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
        button.toolTip = "LG Controller — \(audioDescription()) · \(routingDescription())"
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
        "LG Controller — \(audioDescription())"
    }

    private func audioDescription() -> String {
        guard let latestAudioState else {
            return statusDescription(for: currentRouterStatus)
        }
        return latestAudioState.isMuted
            ? "TV muted / 电视已静音"
            : "TV volume \(latestAudioState.volume)% / 电视音量 \(latestAudioState.volume)%"
    }

    /// Plain-language routing state so the tooltip reads like a sentence.
    private func routingDescription() -> String {
        guard router.isEnabled else { return "Off / 已关闭" }
        switch settings.snapshot.routeOverride {
        case .always:
            return "On — always to TV / 已开启 — 总是控制电视"
        case .never:
            return "On — Mac keeps the keys / 已开启 — 音量键归 Mac"
        case .auto:
            guard let target = settings.snapshot.targetAudioDevice else {
                return "On — pick your TV first / 已开启 — 请先选择电视"
            }
            if let current = audioOutput.currentDefaultOutput(),
               !current.isAirPlay,
               target.matches(current) {
                return "On — controlling TV / 已开启 — 正在控制电视"
            }
            return "On — TV is not the sound output / 已开启 — 电视不是当前声音输出"
        }
    }

    private func refreshRoutingToggle() {
        routingSwitch.state = router.isEnabled ? .on : .off
    }

    private func statusDescription(for status: RouterStatus) -> String {
        switch status {
        case .disabled: return "TV volume not read / 未读到电视音量"
        case .ready: return "TV volume not read / 未读到电视音量"
        case .connecting: return "Checking TV… / 正在检查电视…"
        case .connected: return "TV volume not read / 未读到电视音量"
        case .unavailable: return "TV unavailable / 电视不可用"
        }
    }

    private func showAccessibilityRequired() {
        let alert = NSAlert()
        alert.messageText = "One-time permission / 需要一次授权"
        alert.informativeText = "macOS needs you to allow LG Controller once: System Settings → Privacy & Security → Accessibility. / 只需批准一次：系统设置 → 隐私与安全性 → 辅助功能，打开 LG Controller。"
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK / 好")
        alert.runModal()
    }

    private func showPairingMessage(_ message: String) {
        let alert = NSAlert()
        alert.messageText = "Approve pairing on your LG TV / 在电视上批准配对"
        alert.informativeText = message
        alert.alertStyle = .informational
        alert.addButton(withTitle: "OK / 好")
        alert.runModal()
    }

    private func showConfigurationWindow() {
        if let configurationWindow {
            NSApplication.shared.activate(ignoringOtherApps: true)
            configurationWindow.makeKeyAndOrderFront(nil)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "LG Controller"
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.delegate = self
        window.minSize = NSSize(width: 480, height: 316)
        window.maxSize = NSSize(width: 480, height: 440)

        let contentView = NSView(frame: NSRect(x: 0, y: 0, width: 480, height: 320))
        contentView.autoresizingMask = [.width, .height]
        window.contentView = contentView

        let heading = NSTextField(labelWithString: "LG Controller — LG 遥控器")
        heading.font = .systemFont(ofSize: 18, weight: .semibold)
        heading.frame = NSRect(x: 24, y: 0, width: 400, height: 24)
        heading.identifier = NSUserInterfaceItemIdentifier("heading")
        contentView.addSubview(heading)

        let subtitle = NSTextField(labelWithString: "Volume keys control what you’re hearing. / 音量键控制你正在听的设备。")
        subtitle.font = .systemFont(ofSize: 12)
        subtitle.textColor = .secondaryLabelColor
        subtitle.frame = NSRect(x: 24, y: 0, width: 432, height: 18)
        subtitle.identifier = NSUserInterfaceItemIdentifier("subtitle")
        contentView.addSubview(subtitle)

        let audioLabel = fieldLabel("Your LG webOS TV / 你的 LG webOS 电视")
        audioLabel.identifier = NSUserInterfaceItemIdentifier("audioLabel")
        contentView.addSubview(audioLabel)

        let audio = NSPopUpButton(frame: .zero, pullsDown: false)
        audioOptions = audioOutput.outputDevices()
        audioPlaceholderActive = false
        if audioOptions.isEmpty {
            audio.addItem(withTitle: "No output devices found / 未找到声音输出设备")
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
                    titles.append("\(target.name) (not connected) / (未连接)")
                    audioPlaceholderActive = true
                }
            } else if let current = audioOutput.currentDefaultOutput(),
                      let index = audioOptions.firstIndex(where: { current.matches($0) }) {
                // Default to the sound output the user is hearing right now.
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

        let audioHelper = NSTextField(labelWithString: "Choose your TV from the sound output list. / 从声音输出列表里选你正在用的 webOS 电视。")
        audioHelper.font = .systemFont(ofSize: 11)
        audioHelper.textColor = .secondaryLabelColor
        audioHelper.lineBreakMode = .byTruncatingTail
        audioHelper.identifier = NSUserInterfaceItemIdentifier("audioHelper")
        contentView.addSubview(audioHelper)

        let addressLabel = fieldLabel("TV address / 电视地址")
        addressLabel.identifier = NSUserInterfaceItemIdentifier("addressLabel")
        contentView.addSubview(addressLabel)

        let host = NSTextField(frame: .zero)
        host.stringValue = settings.host
        host.placeholderString = "192.168.1.50"
        host.identifier = NSUserInterfaceItemIdentifier("hostField")
        contentView.addSubview(host)
        hostField = host

        let test = NSButton(title: "Test / 测试", target: self, action: #selector(testConnection))
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

        let advanced = NSButton(title: "Advanced / 高级设置", target: self, action: #selector(toggleAdvanced))
        advanced.bezelStyle = .inline
        advanced.isBordered = false
        advanced.alignment = .left
        advanced.font = .systemFont(ofSize: 13, weight: .medium)
        advanced.imagePosition = .imageLeading
        advanced.image = disclosureImage(expanded: false)
        advanced.contentTintColor = .secondaryLabelColor
        advanced.setAccessibilityLabel("Show advanced settings / 显示高级设置")
        advanced.identifier = NSUserInterfaceItemIdentifier("advancedButton")
        contentView.addSubview(advanced)
        advancedButton = advanced

        let advancedContainer = NSView(frame: .zero)
        advancedContainer.isHidden = true
        advancedContainer.identifier = NSUserInterfaceItemIdentifier("advancedView")
        contentView.addSubview(advancedContainer)
        advancedView = advancedContainer

        let overrideLabel = fieldLabel("When to control the TV / 何时控制电视")
        overrideLabel.frame = NSRect(x: 0, y: 94, width: 320, height: 18)
        advancedContainer.addSubview(overrideLabel)

        let override = NSPopUpButton(frame: NSRect(x: 0, y: 66, width: 432, height: 26), pullsDown: false)
        override.addItems(withTitles: [
            "When the TV is the sound output / 电视是声音输出时",
            "Always to the TV / 总是控制电视",
            "Never to the TV / 从不控制电视"
        ])
        override.selectItem(at: settings.routeOverride.menuIndex)
        override.identifier = NSUserInterfaceItemIdentifier("overridePopup")
        advancedContainer.addSubview(override)
        overridePopup = override

        let schemeLabel = fieldLabel("Protocol / 协议")
        schemeLabel.frame = NSRect(x: 0, y: 36, width: 80, height: 18)
        advancedContainer.addSubview(schemeLabel)

        let scheme = NSPopUpButton(frame: NSRect(x: 86, y: 32, width: 84, height: 26), pullsDown: false)
        scheme.addItems(withTitles: ["wss", "ws"])
        scheme.selectItem(withTitle: settings.scheme)
        advancedContainer.addSubview(scheme)
        schemePopup = scheme

        let portLabel = fieldLabel("Port / 端口")
        portLabel.frame = NSRect(x: 196, y: 36, width: 70, height: 18)
        advancedContainer.addSubview(portLabel)

        let port = NSTextField(frame: NSRect(x: 246, y: 32, width: 78, height: 24))
        port.stringValue = String(settings.port)
        advancedContainer.addSubview(port)
        portField = port

        let repair = NSButton(title: "Forget TV pairing… / 取消配对…", target: self, action: #selector(resetPairing))
        repair.bezelStyle = .inline
        repair.contentTintColor = .secondaryLabelColor
        repair.frame = NSRect(x: -6, y: 2, width: 240, height: 22)
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
              let audioLabel = contentView.subviews.first(where: { $0.identifier?.rawValue == "audioLabel" }),
              let audioPopup,
              let audioHelper = contentView.subviews.first(where: { $0.identifier?.rawValue == "audioHelper" }),
              let addressLabel = contentView.subviews.first(where: { $0.identifier?.rawValue == "addressLabel" }),
              let hostField,
              let testButton,
              let testStatusLabel,
              let advancedButton,
              let advancedView else { return }

        // Advanced holds everything rarely changed: when-to-control mode,
        // protocol, port, and pairing reset.
        let advancedHeight: CGFloat = isAdvancedVisible ? 120 : 0
        advancedView.frame = NSRect(x: 24, y: 20, width: 432, height: advancedHeight)
        advancedButton.frame = NSRect(x: 24, y: 20 + advancedHeight, width: 432, height: 32)

        // TV address + Test on one row; result line underneath.
        testStatusLabel.frame = NSRect(x: 24, y: advancedButton.frame.maxY + 10, width: 432, height: 18)
        let rowY = testStatusLabel.frame.maxY + 8
        testButton.frame = NSRect(x: 320, y: rowY, width: 136, height: 32)
        hostField.frame = NSRect(x: 24, y: rowY + 3, width: 284, height: 26)
        addressLabel.frame = NSRect(x: 24, y: testButton.frame.maxY + 6, width: 240, height: 18)

        // Sound-output picker with a one-line explanation underneath.
        audioHelper.frame = NSRect(x: 24, y: addressLabel.frame.maxY + 12, width: 432, height: 18)
        audioPopup.frame = NSRect(x: 24, y: audioHelper.frame.maxY + 6, width: 432, height: 26)
        audioLabel.frame = NSRect(x: 24, y: audioPopup.frame.maxY + 6, width: 340, height: 18)

        subtitle.frame = NSRect(x: 24, y: audioLabel.frame.maxY + 14, width: 432, height: 18)
        heading.frame = NSRect(x: 24, y: subtitle.frame.maxY + 6, width: 400, height: 24)

        let contentHeight = heading.frame.maxY + 24
        window.setContentSize(NSSize(width: 480, height: contentHeight))

        advancedView.isHidden = !isAdvancedVisible
        advancedButton.title = "Advanced / 高级设置"
        advancedButton.image = disclosureImage(expanded: isAdvancedVisible)
        advancedButton.setAccessibilityLabel(
            isAdvancedVisible ? "Hide advanced settings / 隐藏高级设置" : "Show advanced settings / 显示高级设置"
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
        testButton?.title = "Testing… / 测试中…"
        setTestStatus("Checking TV… / 正在检查电视…", color: .secondaryLabelColor)

        provider.testConnection { [weak self] result in
            guard let self else { return }
            self.testButton?.isEnabled = true
            self.testButton?.title = "Test / 测试"
            switch result {
            case .success:
                self.setTestStatus("Connected — ready to control volume / 已连接，可以控制音量", color: .systemGreen)
            case .failure:
                self.setTestStatus("Couldn’t connect. Check the address and TV approval. / 连接不上：检查地址，并在电视上批准。", color: .secondaryLabelColor)
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
            setTestStatus("Enter the TV address. / 输入电视地址。", color: .secondaryLabelColor)
            return false
        }
        guard let port = Int(portField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)),
              (1...65_535).contains(port) else {
            isAdvancedVisible = true
            layoutConfigurationWindow(animated: true)
            portField.becomeFirstResponder()
            setTestStatus("Enter a valid port. / 端口不对，请输入 1–65535。", color: .secondaryLabelColor)
            return false
        }
        guard audioPopup.isEnabled,
              audioPopup.indexOfSelectedItem >= 0 else {
            setTestStatus("Choose your TV above. / 请在上面选择你的电视。", color: .secondaryLabelColor)
            return false
        }
        let selectedDevice: AudioOutputDevice
        if audioPlaceholderActive {
            guard audioPopup.indexOfSelectedItem > 0 else {
                setTestStatus("That TV is not connected — pick an output device. / 该电视未连接，请另选一个输出设备。", color: .secondaryLabelColor)
                return false
            }
            selectedDevice = audioOptions[audioPopup.indexOfSelectedItem - 1]
        } else {
            guard audioPopup.indexOfSelectedItem < audioOptions.count else {
                setTestStatus("Choose your TV above. / 请在上面选择你的电视。", color: .secondaryLabelColor)
                return false
            }
            selectedDevice = audioOptions[audioPopup.indexOfSelectedItem]
        }
        // The device list is a snapshot from when the window opened; devices can
        // hot-unplug meanwhile. Re-validate against live CoreAudio before saving.
        guard audioOutput.outputDevices().contains(where: { selectedDevice.matches($0) }) else {
            setTestStatus("That output device just disconnected — reopen this window. / 该设备刚断开，请重新打开窗口。", color: .secondaryLabelColor)
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
        alert.messageText = "Reset LG TV pairing? / 重置电视配对？"
        alert.informativeText = "The next test or volume key will need approval on the TV again. / 下次测试或调音量时需要在电视上重新批准。"
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Reset pairing / 重置配对")
        alert.addButton(withTitle: "Cancel / 取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        router.resetPairing()
        setTestStatus("Pairing reset. / 配对已重置。", color: .secondaryLabelColor)
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
