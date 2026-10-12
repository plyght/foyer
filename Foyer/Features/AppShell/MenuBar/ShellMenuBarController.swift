import AppKit
import Defaults

/// The menu-bar item (lead §4, Part D §5.3): **Display ›** screen chooser, a
/// disabled "Version x.y.z" row, **Settings…** (⌘,) and **Quit Foyer** (⌘Q).
/// Hidden while `hideMenuBarIcon` is on; reopening the app (Finder, Spotlight)
/// then shows Settings instead.
@MainActor
final class ShellMenuBarController: NSObject, NSMenuDelegate {
    static let shared = ShellMenuBarController()

    private var statusItem: NSStatusItem?
    private var observation: Defaults.Observation?

    private override init() {
        super.init()
    }

    func start() {
        setVisible(!Defaults[.hideMenuBarIcon])
        observation = Defaults.observe(.hideMenuBarIcon, options: []) { change in
            let hidden = change.newValue
            Task { @MainActor in
                ShellMenuBarController.shared.setVisible(!hidden)
            }
        }
    }

    func setVisible(_ visible: Bool) {
        if visible {
            guard statusItem == nil else { return }
            let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
            item.autosaveName = "Foyer"
            if let button = item.button {
                button.image = Self.statusImage()
                button.imagePosition = .imageOnly
                button.setAccessibilityTitle("Foyer")
                button.toolTip = "Foyer"
            }
            let menu = NSMenu(title: "Foyer")
            menu.delegate = self
            menu.autoenablesItems = false
            item.menu = menu
            statusItem = item
        } else if let item = statusItem {
            NSStatusBar.system.removeStatusItem(item)
            statusItem = nil
        }
    }

    private static func statusImage() -> NSImage? {
        let candidates = ["capsule.tophalf.filled", "rectangle.topthird.inset.filled", "macbook"]
        let configuration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        for name in candidates {
            if let image = NSImage(systemSymbolName: name, accessibilityDescription: "Foyer") {
                let configured = image.withSymbolConfiguration(configuration) ?? image
                configured.isTemplate = true
                return configured
            }
        }
        return nil
    }

    // MARK: NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()

        let display = NSMenuItem(title: "Display", action: nil, keyEquivalent: "")
        display.image = NSImage(systemSymbolName: "display", accessibilityDescription: nil)
        display.submenu = makeDisplayMenu()
        menu.addItem(display)

        menu.addItem(.separator())

        let version = NSMenuItem(title: "Version \(ShellAppInfo.version)", action: nil, keyEquivalent: "")
        version.isEnabled = false
        menu.addItem(version)

        if case .available(let newVersion) = ShellUpdateManager.shared.state {
            let update = NSMenuItem(title: "Install Update \(newVersion)…", action: #selector(installUpdate(_:)), keyEquivalent: "")
            update.target = self
            menu.addItem(update)
        }

        let settings = NSMenuItem(title: "Settings…", action: #selector(openSettings(_:)), keyEquivalent: ",")
        settings.keyEquivalentModifierMask = [.command]
        settings.target = self
        menu.addItem(settings)

        menu.addItem(.separator())

        let quit = NSMenuItem(title: "Quit Foyer", action: #selector(quit(_:)), keyEquivalent: "q")
        quit.keyEquivalentModifierMask = [.command]
        quit.target = self
        menu.addItem(quit)
    }

    private func makeDisplayMenu() -> NSMenu {
        let menu = NSMenu(title: "Display")
        menu.autoenablesItems = false
        let current = Defaults[.showOnDisplay]

        let main = NSMenuItem(title: "Main display", action: #selector(selectMainDisplay(_:)), keyEquivalent: "")
        main.target = self
        main.state = current == .mainScreen ? .on : .off
        menu.addItem(main)

        let all = NSMenuItem(title: "All displays", action: #selector(selectAllDisplays(_:)), keyEquivalent: "")
        all.target = self
        all.state = current == .allDisplays ? .on : .off
        menu.addItem(all)

        if ShellDisplaySelection.hasBuiltInDisplay {
            let builtIn = NSMenuItem(title: "Built-in display", action: #selector(selectBuiltInDisplay(_:)), keyEquivalent: "")
            builtIn.target = self
            builtIn.state = current == .builtInDisplay ? .on : .off
            menu.addItem(builtIn)
        }

        menu.addItem(.separator())

        for screen in NSScreen.screens {
            guard let uuid = screen.displayUUID else { continue }
            let item = NSMenuItem(title: screen.localizedName, action: #selector(selectScreen(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = uuid
            item.image = NSImage(systemSymbolName: screen.chooserSymbol, accessibilityDescription: nil)
            item.state = ShellDisplaySelection.isSelected(screen: screen) ? .on : .off
            menu.addItem(item)
        }

        // A chosen display that is currently disconnected stays listed.
        if current == .specificDisplay,
           let uuid = Defaults[.showOnDisplayUUID],
           !NSScreen.screens.contains(where: { $0.displayUUID == uuid }) {
            let name = Defaults[.showOnDisplayName] ?? "Display"
            let item = NSMenuItem(title: "\(name) (disconnected)", action: nil, keyEquivalent: "")
            item.image = NSImage(systemSymbolName: Defaults[.showOnDisplaySymbol] ?? "display", accessibilityDescription: nil)
            item.state = .on
            item.isEnabled = false
            menu.addItem(item)
        }
        return menu
    }

    // MARK: Actions

    @objc private func selectMainDisplay(_ sender: NSMenuItem) {
        ShellDisplaySelection.selectMain()
    }

    @objc private func selectAllDisplays(_ sender: NSMenuItem) {
        ShellDisplaySelection.selectAll()
    }

    @objc private func selectBuiltInDisplay(_ sender: NSMenuItem) {
        ShellDisplaySelection.selectBuiltIn()
    }

    @objc private func selectScreen(_ sender: NSMenuItem) {
        guard let uuid = sender.representedObject as? String else { return }
        ShellDisplaySelection.select(tag: ShellDisplaySelection.uuidPrefix + uuid)
    }

    @objc private func openSettings(_ sender: NSMenuItem) {
        AppShellModule.openSettings()
    }

    @objc private func installUpdate(_ sender: NSMenuItem) {
        SettingsWindowController.shared.show(tab: .about)
        Task { @MainActor in
            await ShellUpdateManager.shared.downloadAndInstall()
        }
    }

    @objc private func quit(_ sender: NSMenuItem) {
        NSApp.terminate(nil)
    }
}

/// Bundle version helpers.
enum ShellAppInfo {
    static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.0.0"
    }

    static var build: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "0"
    }

    static let repositoryURL = URL(string: "https://github.com/\(Constants.updateRepository)")!
    static let issuesURL = URL(string: "https://github.com/\(Constants.updateRepository)/issues/new")!
    static let releasesURL = URL(string: "https://github.com/\(Constants.updateRepository)/releases")!
}
