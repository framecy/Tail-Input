import Cocoa

/// Sheet that lets the user browse all installed apps and assign an input method rule.
class AppPickerSheetController: NSWindowController {

    var completion: ((String, String, AppInputStrategy) -> Void)?

    private struct AppInfo {
        let name: String
        let bundleId: String
        let path: String
    }

    private var allApps: [AppInfo] = []
    private var filteredApps: [AppInfo] = []
    private let preselectedBundleId: String?

    private var tableView: NSTableView!
    private var searchField: NSSearchField!
    private var strategyControl: NSSegmentedControl!
    private var addButton: NSButton!
    private var iconCache: [String: NSImage] = [:]

    private var selectedStrategy: AppInputStrategy = .forceEnglish

    // MARK: - Init

    init(preselectedBundleId: String? = nil) {
        self.preselectedBundleId = preselectedBundleId

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 480),
            styleMask: [.docModalWindow],
            backing: .buffered,
            defer: false
        )
        window.backgroundColor = .clear
        window.isOpaque = false

        super.init(window: window)
        setupUI()
        loadAppsAsync()
    }

    required init?(coder: NSCoder) { fatalError() }

    // MARK: - UI

    private func setupUI() {
        guard let contentView = window?.contentView else { return }

        // Glass background
        let glass = NSVisualEffectView(frame: contentView.bounds)
        glass.autoresizingMask = [.width, .height]
        glass.blendingMode = .behindWindow
        glass.state = .active
        glass.material = .sidebar
        contentView.addSubview(glass)

        // Title
        let titleLabel = NSTextField(labelWithString: "选择应用")
        titleLabel.font = .systemFont(ofSize: 15, weight: .semibold)
        titleLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(titleLabel)

        // Search field
        searchField = NSSearchField()
        searchField.placeholderString = "搜索应用名称或 Bundle ID…"
        searchField.controlSize = .regular
        searchField.translatesAutoresizingMaskIntoConstraints = false
        searchField.delegate = self
        contentView.addSubview(searchField)

        // Separator
        let sep1 = NSBox(); sep1.boxType = .separator
        sep1.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sep1)

        // Scroll + table
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.borderType = .noBorder
        scrollView.autohidesScrollers = true
        scrollView.drawsBackground = false
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(scrollView)

        tableView = NSTableView()
        tableView.delegate = self
        tableView.dataSource = self
        tableView.rowHeight = 40
        tableView.headerView = nil
        tableView.backgroundColor = .clear
        tableView.selectionHighlightStyle = .regular
        tableView.intercellSpacing = .zero

        let col = NSTableColumn(identifier: .init("app"))
        col.resizingMask = .autoresizingMask
        tableView.addTableColumn(col)
        scrollView.documentView = tableView

        // Separator above controls
        let sep2 = NSBox(); sep2.boxType = .separator
        sep2.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(sep2)

        // Strategy label
        let stratLabel = NSTextField(labelWithString: "切换到此应用时")
        stratLabel.font = .systemFont(ofSize: 11.5)
        stratLabel.textColor = .secondaryLabelColor
        stratLabel.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(stratLabel)

        // Strategy segmented control — 3 explicit choices
        strategyControl = NSSegmentedControl(
            labels: ["切换为英文", "切换为中文", "保持不变"],
            trackingMode: .selectOne,
            target: self,
            action: #selector(strategySegmentChanged(_:))
        )
        strategyControl.selectedSegment = 0
        strategyControl.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(strategyControl)

        // Buttons row
        let cancelBtn = NSButton(title: "取消", target: self, action: #selector(cancel))
        cancelBtn.bezelStyle = .rounded
        cancelBtn.keyEquivalent = "\u{1b}"
        cancelBtn.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(cancelBtn)

        addButton = NSButton(title: "添加规则", target: self, action: #selector(addRule))
        addButton.bezelStyle = .rounded
        addButton.keyEquivalent = "\r"
        addButton.isEnabled = false
        addButton.translatesAutoresizingMaskIntoConstraints = false
        contentView.addSubview(addButton)

        NSLayoutConstraint.activate([
            // Title
            titleLabel.topAnchor.constraint(equalTo: contentView.topAnchor, constant: 16),
            titleLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),

            // Search
            searchField.topAnchor.constraint(equalTo: titleLabel.bottomAnchor, constant: 10),
            searchField.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            searchField.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),

            // sep1
            sep1.topAnchor.constraint(equalTo: searchField.bottomAnchor, constant: 8),
            sep1.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sep1.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),

            // Table
            scrollView.topAnchor.constraint(equalTo: sep1.bottomAnchor),
            scrollView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            scrollView.bottomAnchor.constraint(equalTo: sep2.topAnchor),

            // sep2
            sep2.leadingAnchor.constraint(equalTo: contentView.leadingAnchor),
            sep2.trailingAnchor.constraint(equalTo: contentView.trailingAnchor),
            sep2.bottomAnchor.constraint(equalTo: stratLabel.topAnchor, constant: -10),

            // Strategy label + control
            stratLabel.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            stratLabel.bottomAnchor.constraint(equalTo: strategyControl.topAnchor, constant: -4),

            strategyControl.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            strategyControl.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            strategyControl.bottomAnchor.constraint(equalTo: cancelBtn.topAnchor, constant: -12),

            // Buttons
            cancelBtn.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 12),
            cancelBtn.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),

            addButton.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -12),
            addButton.bottomAnchor.constraint(equalTo: contentView.bottomAnchor, constant: -14),
        ])
    }

    // MARK: - App Loading

    private func loadAppsAsync() {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            var apps = Self.enumerateApps()

            // Promote preselected app to the top
            if let bid = self.preselectedBundleId,
               let idx = apps.firstIndex(where: { $0.bundleId == bid }) {
                let pinned = apps.remove(at: idx)
                apps.insert(pinned, at: 0)
            }

            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.allApps = apps
                self.filteredApps = apps
                self.tableView.reloadData()

                // Pre-select the pinned row
                if self.preselectedBundleId != nil && !apps.isEmpty {
                    self.tableView.selectRowIndexes(IndexSet(integer: 0),
                                                    byExtendingSelection: false)
                    self.addButton.isEnabled = true
                }
            }
        }
    }

    private static func enumerateApps() -> [AppInfo] {
        let searchPaths = [
            "/Applications",
            NSHomeDirectory() + "/Applications",
            "/System/Applications",
            "/System/Applications/Utilities",
        ]
        var apps: [AppInfo] = []
        var seen = Set<String>()
        let fm = FileManager.default

        for dir in searchPaths {
            guard let entries = try? fm.contentsOfDirectory(atPath: dir) else { continue }
            for entry in entries where entry.hasSuffix(".app") {
                let path = dir + "/" + entry
                guard let bundle = Bundle(path: path),
                      let bid = bundle.bundleIdentifier,
                      !seen.contains(bid) else { continue }
                seen.insert(bid)
                let name = bundle.infoDictionary?["CFBundleDisplayName"] as? String
                    ?? bundle.infoDictionary?["CFBundleName"] as? String
                    ?? String(entry.dropLast(4))
                apps.append(AppInfo(name: name, bundleId: bid, path: path))
            }
        }

        return apps.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    // MARK: - Actions

    @objc private func strategySegmentChanged(_ sender: NSSegmentedControl) {
        switch sender.selectedSegment {
        case 0: selectedStrategy = .forceEnglish
        case 1: selectedStrategy = .forceChinese
        default: selectedStrategy = .keepCurrent
        }
    }

    @objc private func addRule() {
        let row = tableView.selectedRow
        guard row >= 0, row < filteredApps.count else { return }
        let app = filteredApps[row]
        window?.sheetParent?.endSheet(window!)
        completion?(app.bundleId, app.name, selectedStrategy)
    }

    @objc private func cancel() {
        window?.sheetParent?.endSheet(window!, returnCode: .cancel)
    }

    // MARK: - Icon

    private func icon(for path: String) -> NSImage {
        if let c = iconCache[path] { return c }
        let img = NSWorkspace.shared.icon(forFile: path)
        iconCache[path] = img
        return img
    }
}

// MARK: - NSTableView

extension AppPickerSheetController: NSTableViewDataSource, NSTableViewDelegate {
    func numberOfRows(in tableView: NSTableView) -> Int { filteredApps.count }

    func tableView(_ tableView: NSTableView,
                   viewFor tableColumn: NSTableColumn?,
                   row: Int) -> NSView? {
        let app = filteredApps[row]
        let id = NSUserInterfaceItemIdentifier("PickerRow")

        let cell: NSTableCellView
        if let r = tableView.makeView(withIdentifier: id, owner: nil) as? NSTableCellView {
            cell = r
        } else {
            cell = NSTableCellView(); cell.identifier = id

            let iv = NSImageView()
            iv.imageScaling = .scaleProportionallyUpOrDown
            iv.translatesAutoresizingMaskIntoConstraints = false
            cell.imageView = iv; cell.addSubview(iv)

            let nameField = NSTextField(labelWithString: "")
            nameField.font = .systemFont(ofSize: 13)
            nameField.lineBreakMode = .byTruncatingTail
            nameField.translatesAutoresizingMaskIntoConstraints = false
            cell.textField = nameField; cell.addSubview(nameField)

            let bidField = NSTextField(labelWithString: "")
            bidField.font = .systemFont(ofSize: 10.5)
            bidField.textColor = .tertiaryLabelColor
            bidField.lineBreakMode = .byTruncatingMiddle
            bidField.tag = 99
            bidField.translatesAutoresizingMaskIntoConstraints = false
            cell.addSubview(bidField)

            NSLayoutConstraint.activate([
                iv.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
                iv.centerYAnchor.constraint(equalTo: cell.centerYAnchor),
                iv.widthAnchor.constraint(equalToConstant: 26),
                iv.heightAnchor.constraint(equalToConstant: 26),

                nameField.leadingAnchor.constraint(equalTo: iv.trailingAnchor, constant: 9),
                nameField.bottomAnchor.constraint(equalTo: cell.centerYAnchor, constant: -1),
                nameField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),

                bidField.leadingAnchor.constraint(equalTo: nameField.leadingAnchor),
                bidField.topAnchor.constraint(equalTo: cell.centerYAnchor, constant: 1),
                bidField.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            ])
        }

        cell.imageView?.image = icon(for: app.path)
        cell.textField?.stringValue = app.name
        if let bidField = cell.viewWithTag(99) as? NSTextField {
            bidField.stringValue = app.bundleId
        }
        return cell
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat { 44 }

    func tableViewSelectionDidChange(_ notification: Notification) {
        addButton.isEnabled = tableView.selectedRow >= 0
    }
}

// MARK: - NSSearchFieldDelegate (live filter)

extension AppPickerSheetController: NSSearchFieldDelegate {
    func controlTextDidChange(_ obj: Notification) {
        guard let field = obj.object as? NSSearchField else { return }
        let q = field.stringValue.trimmingCharacters(in: .whitespaces)
        filteredApps = q.isEmpty ? allApps : allApps.filter {
            $0.name.localizedCaseInsensitiveContains(q) ||
            $0.bundleId.localizedCaseInsensitiveContains(q)
        }
        tableView.reloadData()
        addButton.isEnabled = tableView.selectedRow >= 0
    }
}
