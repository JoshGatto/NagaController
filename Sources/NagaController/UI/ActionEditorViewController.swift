import Cocoa
import UniformTypeIdentifiers

private final class KeyCaptureField: NSTextField {
    var onKeyCaptured: ((NSEvent) -> Void)?
    var onFocusChanged: ((Bool) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            currentEditor()?.selectAll(nil)
            onFocusChanged?(true)
        }
        return became
    }

    override func resignFirstResponder() -> Bool {
        let resigned = super.resignFirstResponder()
        if resigned {
            onFocusChanged?(false)
        }
        return resigned
    }

    override func keyDown(with event: NSEvent) {
        onKeyCaptured?(event)
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        onKeyCaptured?(event)
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }
}

private struct ShortcutPreset {
    let name: String
    let key: String
    let modifiers: [String]
    let isHeader: Bool
    
    static func header(_ name: String) -> ShortcutPreset {
        ShortcutPreset(name: name, key: "", modifiers: [], isHeader: true)
    }
}

final class ActionEditorViewController: NSViewController {
    private let buttonIndex: Int
    private let onComplete: (ActionType?) -> Void
    private var initialRemappingState: Bool = false
    
    private let segmented = NSSegmentedControl(labels: ["Key", "App", "Cmd", "Text", "Profile", "Hypershift"], trackingMode: .selectOne, target: nil, action: nil)
    private let layerSegmented = NSSegmentedControl(labels: ["Standard Layer", "Hypershift Layer"], trackingMode: .selectOne, target: nil, action: nil)
    
    // Temporary storage for edits before saving
    private var tempStandardAction: ActionType?
    private var tempHypershiftAction: ActionType?
    
    // Common
    private let descriptionField = NSTextField(string: "")

    // Key Sequence
    private let keyField = KeyCaptureField()
    private let modCmd = NSButton(checkboxWithTitle: "⌘", target: nil, action: nil)
    private let modAlt = NSButton(checkboxWithTitle: "⌥", target: nil, action: nil)
    private let modCtrl = NSButton(checkboxWithTitle: "⌃", target: nil, action: nil)
    private let modShift = NSButton(checkboxWithTitle: "⇧", target: nil, action: nil)

    // Application
    private let appPath = NSPathControl()

    // Command
    private let commandField = NSTextField(string: "")

    // Profile Switch
    private let profilePopup = NSPopUpButton(frame: .zero, pullsDown: false)

    // Presets
    private let presetsPopup = NSPopUpButton(frame: .zero, pullsDown: false)
    private let presets: [ShortcutPreset] = [
        .header("Editing"),
        ShortcutPreset(name: "Copy", key: "c", modifiers: ["cmd"], isHeader: false),
        ShortcutPreset(name: "Paste", key: "v", modifiers: ["cmd"], isHeader: false),
        ShortcutPreset(name: "Cut", key: "x", modifiers: ["cmd"], isHeader: false),
        ShortcutPreset(name: "Undo", key: "z", modifiers: ["cmd"], isHeader: false),
        ShortcutPreset(name: "Redo", key: "z", modifiers: ["cmd", "shift"], isHeader: false),
        ShortcutPreset(name: "Select All", key: "a", modifiers: ["cmd"], isHeader: false),
        
        .header("System"),
        ShortcutPreset(name: "Mission Control", key: "up arrow", modifiers: ["ctrl"], isHeader: false),
        ShortcutPreset(name: "Application Windows", key: "down arrow", modifiers: ["ctrl"], isHeader: false),
        ShortcutPreset(name: "Show Desktop", key: "f11", modifiers: [], isHeader: false),
        ShortcutPreset(name: "Spotlight", key: "space", modifiers: ["cmd"], isHeader: false),
        ShortcutPreset(name: "Siri", key: "space", modifiers: ["cmd"], isHeader: false), // Note: user might need to adjust
        
        .header("Navigation"),
        ShortcutPreset(name: "Switch App", key: "tab", modifiers: ["cmd"], isHeader: false),
        ShortcutPreset(name: "Switch Window", key: "`", modifiers: ["cmd"], isHeader: false),
        ShortcutPreset(name: "Back", key: "[", modifiers: ["cmd"], isHeader: false),
        ShortcutPreset(name: "Forward", key: "]", modifiers: ["cmd"], isHeader: false),
        
        .header("Function Keys"),
        ShortcutPreset(name: "F1", key: "f1", modifiers: [], isHeader: false),
        ShortcutPreset(name: "F2", key: "f2", modifiers: [], isHeader: false),
        ShortcutPreset(name: "F3", key: "f3", modifiers: [], isHeader: false),
        ShortcutPreset(name: "F4", key: "f4", modifiers: [], isHeader: false),
        ShortcutPreset(name: "F5", key: "f5", modifiers: [], isHeader: false),
        ShortcutPreset(name: "F6", key: "f6", modifiers: [], isHeader: false),
        ShortcutPreset(name: "F7", key: "f7", modifiers: [], isHeader: false),
        ShortcutPreset(name: "F8", key: "f8", modifiers: [], isHeader: false),
        ShortcutPreset(name: "F9", key: "f9", modifiers: [], isHeader: false),
        ShortcutPreset(name: "F10", key: "f10", modifiers: [], isHeader: false),
        ShortcutPreset(name: "F11", key: "f11", modifiers: [], isHeader: false),
        ShortcutPreset(name: "F12", key: "f12", modifiers: [], isHeader: false),
        
        .header("Modifier Keys"),
        ShortcutPreset(name: "Command", key: "command", modifiers: [], isHeader: false),
        ShortcutPreset(name: "Shift", key: "shift", modifiers: [], isHeader: false),
        ShortcutPreset(name: "Option", key: "option", modifiers: [], isHeader: false),
        ShortcutPreset(name: "Control", key: "control", modifiers: [], isHeader: false),
        ShortcutPreset(name: "Fn", key: "fn", modifiers: [], isHeader: false)
    ]

    // Text Snippet
    private let textSnippetView = NSTextView(frame: .zero)
    private let textSnippetScroll = NSScrollView(frame: .zero)

    private let contentStack = NSStackView()
    
    // Hardware Learning
    private let hardwareBindingLabel = NSTextField(labelWithString: "Trigger: (Default)")
    private let learnButton = NSButton(title: "Learn Hardware Trigger…", target: nil, action: nil)
    private let clearHardwareButton = NSButton(title: "", target: nil, action: nil)
    private var isLearningHardware = false

    private var recordedKeyCode: UInt16?
    private var recordedKeyIdentifier: String?

    init(buttonIndex: Int, onComplete: @escaping (ActionType?) -> Void) {
        self.buttonIndex = buttonIndex
        self.onComplete = onComplete
        
        let standardActionMap = ConfigManager.shared.mappingForCurrentProfile()
        let hypershiftActionMap = ConfigManager.shared.hypershiftMappingForCurrentProfile()
        
        self.tempStandardAction = standardActionMap[buttonIndex]
        self.tempHypershiftAction = hypershiftActionMap[buttonIndex]
        
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        self.view = NSView()

        let header = NSTextField(labelWithString: "Edit Action — Button \(buttonIndex)")
        header.font = .systemFont(ofSize: 15, weight: .semibold)
        
        layerSegmented.target = self
        layerSegmented.action = #selector(layerChanged)
        layerSegmented.selectedSegment = 0

        segmented.target = self
        segmented.action = #selector(segmentedChanged)
        segmented.selectedSegment = 0

        // Description
        let descLabel = NSTextField(labelWithString: "Description (optional):")
        descriptionField.placeholderString = "e.g. Copy"

        // Key UI
        keyField.translatesAutoresizingMaskIntoConstraints = false
        keyField.placeholderString = "Press a key"
        keyField.alignment = .center
        keyField.isEditable = false
        keyField.drawsBackground = false
        keyField.isBordered = false
        keyField.font = .systemFont(ofSize: 16, weight: .medium)
        keyField.wantsLayer = true
        keyField.layer?.cornerRadius = 8
        keyField.layer?.backgroundColor = NSColor.controlBackgroundColor.cgColor
        keyField.layer?.borderColor = NSColor.separatorColor.cgColor
        keyField.layer?.borderWidth = 1
        keyField.widthAnchor.constraint(greaterThanOrEqualToConstant: 120).isActive = true
        keyField.setContentHuggingPriority(.defaultLow, for: .horizontal)
        keyField.setContentCompressionResistancePriority(.required, for: .horizontal)
        keyField.onKeyCaptured = { [weak self] event in
            self?.capture(event: event)
        }
        keyField.onFocusChanged = { [weak keyField] focused in
            keyField?.layer?.borderColor = (focused ? NSColor.systemBlue.cgColor : NSColor.separatorColor.cgColor)
            keyField?.layer?.borderWidth = focused ? 2 : 1
        }

        [modCmd, modAlt, modCtrl, modShift].forEach { button in
            button.target = self
            button.action = #selector(modifierCheckboxChanged(_:))
        }

        let keyRow = NSStackView(views: [NSTextField(labelWithString: "Key:"), keyField, NSView()])
        keyRow.spacing = 8
        
        presetsPopup.addItem(withTitle: "Presets…")
        for p in presets {
            if p.isHeader {
                presetsPopup.menu?.addItem(NSMenuItem.separator())
                let item = NSMenuItem(title: p.name, action: nil, keyEquivalent: "")
                item.isEnabled = false
                presetsPopup.menu?.addItem(item)
            } else {
                presetsPopup.addItem(withTitle: p.name)
            }
        }
        presetsPopup.target = self
        presetsPopup.action = #selector(presetSelected)
        
        let modsRow = NSStackView(views: [NSTextField(labelWithString: "Modifiers:"), modCmd, modAlt, modCtrl, modShift, NSView(), presetsPopup])
        modsRow.spacing = 8
        let keyHint = NSTextField(labelWithString: "Click the capture box above, then press the keyboard shortcut you want to record (e.g. ⇧⌘4).")
        keyHint.font = .systemFont(ofSize: 11)
        keyHint.textColor = .secondaryLabelColor
        keyHint.lineBreakMode = .byWordWrapping
        keyHint.maximumNumberOfLines = 2
        let keyGroup = group("Key Sequence", views: [keyRow, modsRow, keyHint])

        // App UI
        appPath.url = nil
        appPath.pathStyle = .standard
        let browse = NSButton(title: "Browse…", target: self, action: #selector(browseApp))
        browse.image = UIStyle.symbol("folder", size: 13)
        browse.imagePosition = .imageLeading
        let appRow = NSStackView(views: [NSTextField(labelWithString: "Application:"), appPath, browse])
        appRow.spacing = 8
        let appGroup = group("Application", views: [appRow])

        // Command UI
        commandField.placeholderString = "e.g. say Hello or osascript …"
        if #available(macOS 10.15, *) {
            commandField.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        }
        let cmdRow = NSStackView(views: [NSTextField(labelWithString: "Command:"), commandField])
        cmdRow.spacing = 8
        let cmdGroup = group("System Command", views: [cmdRow])

        // Text Snippet UI
        textSnippetView.isAutomaticQuoteSubstitutionEnabled = false
        textSnippetView.isAutomaticDashSubstitutionEnabled = false
        textSnippetView.isAutomaticLinkDetectionEnabled = false
        textSnippetView.isRichText = false
        textSnippetView.font = .monospacedSystemFont(ofSize: NSFont.systemFontSize, weight: .regular)
        textSnippetView.textContainerInset = NSSize(width: 6, height: 6)
        textSnippetView.backgroundColor = .textBackgroundColor
        textSnippetView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)
        textSnippetView.isVerticallyResizable = true
        textSnippetView.isHorizontallyResizable = false
        textSnippetView.textContainer?.widthTracksTextView = true

        textSnippetScroll.documentView = textSnippetView
        textSnippetScroll.hasVerticalScroller = true
        textSnippetScroll.borderType = .bezelBorder
        textSnippetScroll.translatesAutoresizingMaskIntoConstraints = false
        textSnippetScroll.heightAnchor.constraint(equalToConstant: 120).isActive = true

        let textHint = NSTextField(labelWithString: "Type the text you want this button to output. It will be sent exactly as written when pressed.")
        textHint.font = .systemFont(ofSize: 11)
        textHint.textColor = .secondaryLabelColor
        textHint.lineBreakMode = .byWordWrapping
        textHint.maximumNumberOfLines = 2
        let textGroup = group("Text Snippet", views: [textSnippetScroll, textHint])

        // Profile UI
        let profLabel = NSTextField(labelWithString: "Profile:")
        profilePopup.addItems(withTitles: ConfigManager.shared.availableProfiles())
        let profRow = NSStackView(views: [profLabel, profilePopup])
        profRow.spacing = 8
        let profGroup = group("Profile Switch", views: [profRow])

        // Hypershift UI
        let hsHint = NSTextField(labelWithString: "This button will act as the Hypershift modifier. While held down, it unlocks the secondary set of functions on all other buttons.")
        hsHint.font = .systemFont(ofSize: 11)
        hsHint.textColor = .secondaryLabelColor
        hsHint.lineBreakMode = .byWordWrapping
        hsHint.maximumNumberOfLines = 3
        let hsGroup = group("Hypershift Modifier", views: [hsHint])

        // Content stack
        contentStack.orientation = .vertical
        contentStack.spacing = 10
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let descStack = NSStackView(views: [descLabel, descriptionField])
        descStack.spacing = 6

        let buttonsStack = NSStackView()
        buttonsStack.orientation = .horizontal
        buttonsStack.spacing = 8
        let cancel = NSButton(title: "Cancel", target: self, action: #selector(cancelTapped))
        cancel.image = UIStyle.symbol("xmark.circle", size: 14)
        cancel.imagePosition = .imageLeading
        cancel.keyEquivalent = "\u{1b}"
        cancel.toolTip = "Close without saving"

        let save = NSButton(title: "Save", target: self, action: #selector(saveTapped))
        save.image = UIStyle.symbol("tray.and.arrow.down", size: 14, weight: .semibold)
        save.imagePosition = .imageLeading
        save.keyEquivalent = "\r"
        save.toolTip = "Save changes"
        
        learnButton.target = self
        learnButton.action = #selector(learnHardwareTapped)
        learnButton.font = .systemFont(ofSize: 12)
        UIStyle.styleSecondaryButton(learnButton)
        
        clearHardwareButton.target = self
        clearHardwareButton.action = #selector(clearHardwareTapped)
        clearHardwareButton.image = UIStyle.symbol("xmark.circle.fill", size: 12)
        clearHardwareButton.isBordered = false
        clearHardwareButton.toolTip = "Reset to default button mapping"
        
        hardwareBindingLabel.font = .systemFont(ofSize: 11)
        hardwareBindingLabel.textColor = .secondaryLabelColor
        
        let hardwareStack = NSStackView(views: [hardwareBindingLabel, learnButton, clearHardwareButton])
        hardwareStack.spacing = 8

        buttonsStack.addArrangedSubview(hardwareStack)
        buttonsStack.addArrangedSubview(NSView())
        buttonsStack.addArrangedSubview(cancel)
        buttonsStack.addArrangedSubview(save)

        view.addSubview(header)
        view.addSubview(layerSegmented)
        view.addSubview(segmented)
        view.addSubview(descStack)
        view.addSubview(contentStack)
        view.addSubview(buttonsStack)

        for v in [header, layerSegmented, segmented, descStack, contentStack, buttonsStack] { v.translatesAutoresizingMaskIntoConstraints = false }

        NSLayoutConstraint.activate([
            header.topAnchor.constraint(equalTo: view.topAnchor, constant: 16),
            header.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
            
            layerSegmented.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 10),
            layerSegmented.centerXAnchor.constraint(equalTo: view.centerXAnchor),

            segmented.topAnchor.constraint(equalTo: layerSegmented.bottomAnchor, constant: 14),
            segmented.leadingAnchor.constraint(equalTo: header.leadingAnchor),

            descStack.topAnchor.constraint(equalTo: segmented.bottomAnchor, constant: 10),
            descStack.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            descStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            contentStack.topAnchor.constraint(equalTo: descStack.bottomAnchor, constant: 12),
            contentStack.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),

            buttonsStack.topAnchor.constraint(greaterThanOrEqualTo: contentStack.bottomAnchor, constant: 12),
            buttonsStack.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
            buttonsStack.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -12)
        ])

        // Add groups and show first
        contentStack.addArrangedSubview(keyGroup)
        contentStack.addArrangedSubview(appGroup)
        contentStack.addArrangedSubview(cmdGroup)
        contentStack.addArrangedSubview(textGroup)
        contentStack.addArrangedSubview(profGroup)
        contentStack.addArrangedSubview(hsGroup)
        selectGroup(index: 0)

        preloadCurrent()
        updateHardwareDisplay()
        
        initialRemappingState = !EventTapManager.shared.isListeningOnly
        EventTapManager.shared.start(listenOnly: true)
    }

    private func group(_ title: String, views: [NSView]) -> NSView {
        let stack = NSStackView()
        stack.orientation = .vertical
        stack.spacing = 6
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 12, weight: .medium)
        stack.addArrangedSubview(titleLabel)
        views.forEach { stack.addArrangedSubview($0) }
        return stack
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        if segmented.selectedSegment == 0 {
            view.window?.makeFirstResponder(keyField)
        } else if segmented.selectedSegment == 3 {
            view.window?.makeFirstResponder(textSnippetView)
        }
    }

    @objc private func layerChanged() {
        // Save current UI state to temp var
        let action = buildActionFromUI()
        if layerSegmented.selectedSegment == 1 {
            tempStandardAction = action // Switched to Hypershift, save Standard
        } else {
            tempHypershiftAction = action // Switched to Standard, save Hypershift
        }
        preloadCurrent()
    }

    @objc private func segmentedChanged() {
        selectGroup(index: segmented.selectedSegment)
        if segmented.selectedSegment == 0 {
            view.window?.makeFirstResponder(keyField)
        } else if segmented.selectedSegment == 3 {
            view.window?.makeFirstResponder(textSnippetView)
        }
    }

    private func selectGroup(index: Int) {
        for (i, v) in contentStack.arrangedSubviews.enumerated() {
            v.isHidden = (i != index)
        }
    }

    private func preloadCurrent() {
        let current = layerSegmented.selectedSegment == 0 ? tempStandardAction : tempHypershiftAction
        recordedKeyCode = nil
        recordedKeyIdentifier = nil
        updateKeyFieldDisplay()
        applyModifiers(from: [])
        textSnippetView.string = ""
        descriptionField.stringValue = ""
        
        guard let action = current else {
            segmented.selectedSegment = 0
            selectGroup(index: 0)
            return
        }
        
        switch action {
        case .keySequence(let keys, let d):
            if let first = keys.first {
                recordedKeyIdentifier = first.key
                recordedKeyCode = first.keyCode ?? KeyStroke.keyCode(for: first.key)
                applyModifiers(from: first.modifiers)
                updateKeyFieldDisplay()
            }
            descriptionField.stringValue = d ?? ""
            segmented.selectedSegment = 0
            selectGroup(index: 0)
        case .application(let path, let d):
            appPath.url = URL(fileURLWithPath: path)
            descriptionField.stringValue = d ?? ""
            segmented.selectedSegment = 1
            selectGroup(index: 1)
        case .systemCommand(let cmd, let d):
            commandField.stringValue = cmd
            descriptionField.stringValue = d ?? ""
            segmented.selectedSegment = 2
            selectGroup(index: 2)
        case .textSnippet(let text, let d):
            textSnippetView.string = text
            descriptionField.stringValue = d ?? ""
            segmented.selectedSegment = 3
            selectGroup(index: 3)
        case .profileSwitch(let profile, let d):
            profilePopup.selectItem(withTitle: profile)
            descriptionField.stringValue = d ?? ""
            segmented.selectedSegment = 4
            selectGroup(index: 4)
        case .hypershift:
            descriptionField.stringValue = ""
            segmented.selectedSegment = 5
            selectGroup(index: 5)
        case .macro:
            // Not supported in this lightweight editor yet
            break
        }
    }

    @objc private func cancelTapped() {
        dismiss(self)
        onComplete(nil)
    }

    @objc private func saveTapped() {
        // Save current UI state to temp
        let finalAction = buildActionFromUI()
        if layerSegmented.selectedSegment == 0 {
            tempStandardAction = finalAction
        } else {
            tempHypershiftAction = finalAction
        }
        
        // Save immediately bypassing onComplete wrapper or by calling setAction directly.
        // Wait, onComplete tells MappingViewController to clear the sheet and reload logic.
        // We'll call setHypershiftAction directly here, and use onComplete for standard action.
        ConfigManager.shared.setHypershiftAction(forButton: buttonIndex, action: tempHypershiftAction)
        
        onComplete(tempStandardAction)
        dismiss(self)
    }
    
    private func buildActionFromUI() -> ActionType? {
        let desc = descriptionField.stringValue.isEmpty ? nil : descriptionField.stringValue
        switch segmented.selectedSegment {
        case 0:
            guard let identifier = recordedKeyIdentifier, !identifier.isEmpty else {
                return nil
            }
            let mods = currentModifiers()
            let code = recordedKeyCode ?? KeyStroke.keyCode(for: identifier)
            let stroke = KeyStroke(key: identifier, modifiers: mods, keyCode: code)
            return .keySequence(keys: [stroke], description: desc)
        case 1:
            if let url = appPath.url {
                return .application(path: url.path, description: desc)
            } else {
                return nil
            }
        case 2:
            let cmd = commandField.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if cmd.isEmpty { return nil } else { return .systemCommand(command: cmd, description: desc) }
        case 3:
            let snippet = textSnippetView.string
            if snippet.trimmingCharacters(in: .newlines).isEmpty {
                return nil
            } else {
                return .textSnippet(text: snippet, description: desc)
            }
        case 4:
            if let title = profilePopup.titleOfSelectedItem { return .profileSwitch(profile: title, description: desc) } else { return nil }
        case 5:
            return .hypershift
        default:
            return nil
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        EventTapManager.shared.start(listenOnly: !initialRemappingState)
    }

    private func set(mod: NSButton, from on: Bool) { mod.state = on ? .on : .off }

    private func capture(event: NSEvent) {
        if isLearningHardware { return }
        if event.type == .flagsChanged {
            applyModifiers(from: event.modifierFlags)
            updateKeyFieldDisplay()
            return
        }

        guard event.type == .keyDown else { return }
        if event.isARepeat { return }

        applyModifiers(from: event.modifierFlags)

        let keyCode = UInt16(event.keyCode)
        let canonical = KeyStroke.canonicalKeyString(for: keyCode, characters: event.charactersIgnoringModifiers)
        guard !canonical.isEmpty else {
            NSSound.beep()
            return
        }

        recordedKeyCode = keyCode
        recordedKeyIdentifier = canonical
        updateKeyFieldDisplay()
    }

    private func updateKeyFieldDisplay() {
        if let identifier = recordedKeyIdentifier, !identifier.isEmpty {
            let mods = currentModifiers()
            let code = recordedKeyCode ?? KeyStroke.keyCode(for: identifier)
            let stroke = KeyStroke(key: identifier, modifiers: mods, keyCode: code)
            let display = stroke.formattedShortcut()
            keyField.stringValue = display
            keyField.toolTip = display
        } else {
            keyField.stringValue = ""
            keyField.toolTip = nil
        }
    }

    private func applyModifiers(from flags: NSEvent.ModifierFlags) {
        set(mod: modCmd, from: flags.contains(.command))
        set(mod: modAlt, from: flags.contains(.option))
        set(mod: modCtrl, from: flags.contains(.control))
        set(mod: modShift, from: flags.contains(.shift))
        updateKeyFieldDisplay()
    }

    private func applyModifiers(from identifiers: [String]) {
        let lower = Set(identifiers.map { $0.lowercased() })
        set(mod: modCmd, from: lower.contains("cmd") || lower.contains("command"))
        set(mod: modAlt, from: lower.contains("alt") || lower.contains("option"))
        set(mod: modCtrl, from: lower.contains("ctrl") || lower.contains("control"))
        set(mod: modShift, from: lower.contains("shift"))
        updateKeyFieldDisplay()
    }

    private func currentModifiers() -> [String] {
        var result: [String] = []
        if modCmd.state == .on { result.append("cmd") }
        if modAlt.state == .on { result.append("alt") }
        if modCtrl.state == .on { result.append("ctrl") }
        if modShift.state == .on { result.append("shift") }
        return result
    }

    @objc private func modifierCheckboxChanged(_ sender: NSButton) {
        updateKeyFieldDisplay()
    }

    @objc private func browseApp() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowedContentTypes = [.application]
        panel.beginSheetModal(for: self.view.window!) { [weak self] resp in
            guard resp == .OK, let url = panel.url else { return }
            self?.appPath.url = url
        }
    }

    @objc private func presetSelected() {
        let title = presetsPopup.titleOfSelectedItem
        presetsPopup.selectItem(at: 0) // Reset to "Presets..."
        
        guard let title = title, title != "Presets…" else { return }
        guard let preset = presets.first(where: { $0.name == title && !$0.isHeader }) else { return }
        
        recordedKeyIdentifier = preset.key
        recordedKeyCode = KeyStroke.keyCode(for: preset.key)
        applyModifiers(from: preset.modifiers)
        updateKeyFieldDisplay()
    }

    // MARK: - Hardware Learning

    private var pendingUsagePage: UInt32?
    private var pendingUsage: UInt32?
    private var pendingCookie: UInt32?
    private var pendingKeyCode: CGKeyCode?
    private var pendingValue: Int32?
    private var isFinalizingLearning = false

    @objc private func learnHardwareTapped() {
        isLearningHardware = true
        learnButton.title = "Press a button now..."
        learnButton.isEnabled = false
        
        pendingUsagePage = nil
        pendingUsage = nil
        pendingCookie = nil
        pendingKeyCode = nil
        pendingValue = nil
        isFinalizingLearning = false
        
        HIDListener.shared.setLearningCallback { [weak self] page, usage, cookie, value in
            DispatchQueue.main.async {
                self?.pendingUsagePage = page
                self?.pendingUsage = usage
                self?.pendingCookie = UInt32(cookie)
                self?.pendingValue = value
                self?.scheduleFinishLearning()
            }
        }
        
        EventTapManager.shared.setLearningCallback { [weak self] keyCode in
            DispatchQueue.main.async {
                self?.pendingKeyCode = keyCode
                self?.scheduleFinishLearning()
            }
        }
    }

    @objc private func clearHardwareTapped() {
        ConfigManager.shared.setHardwareBinding(forButton: buttonIndex, binding: nil)
        updateHardwareDisplay()
    }
    
    private func scheduleFinishLearning() {
        guard !isFinalizingLearning else { return }
        
        // If we have both, finish immediately
        if pendingUsage != nil && pendingKeyCode != nil {
            isFinalizingLearning = true
            finishLearning()
            return
        }
        
        // Timeout after 1 second if the other event doesn't arrive
        isFinalizingLearning = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            guard let self = self else { return }
            // Only finish if it hasn't somehow already been reset
            if self.isLearningHardware {
                self.finishLearning()
            }
        }
    }

    private func finishLearning() {
        HIDListener.shared.setLearningCallback(nil)
        EventTapManager.shared.setLearningCallback(nil)
        isLearningHardware = false
        learnButton.title = "Learn Hardware Trigger…"
        learnButton.isEnabled = true
        
        let binding = HardwareBinding(
            usagePage: pendingUsagePage,
            usage: pendingUsage,
            keyCode: pendingKeyCode.map { UInt16($0) },
            cookie: pendingCookie,
            value: pendingValue
        )
        ConfigManager.shared.setHardwareBinding(forButton: buttonIndex, binding: binding)
        updateHardwareDisplay()
        
        // Small delay to ensure any trailing events from the same press are ignored
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.isLearningHardware = false
        }
    }

    private func updateHardwareDisplay() {
        let bindings = ConfigManager.shared.hardwareBindingsForCurrentProfile()
        if let binding = bindings[buttonIndex] {
            if let code = binding.keyCode {
                hardwareBindingLabel.stringValue = "Trigger: KeyCode 0x\(String(code, radix: 16))"
            } else if let page = binding.usagePage, let usage = binding.usage {
                var desc = String(format: "Trigger: Page 0x%X, Usage 0x%X", page, usage)
                if let val = binding.value {
                    desc += " (Value: \(val))"
                }
                hardwareBindingLabel.stringValue = desc
            } else {
                hardwareBindingLabel.stringValue = "Trigger: Custom"
            }
            clearHardwareButton.isHidden = false
        } else {
            hardwareBindingLabel.stringValue = "Trigger: (Default)"
            clearHardwareButton.isHidden = true
        }
    }
}
