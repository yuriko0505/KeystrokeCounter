import Cocoa
import ApplicationServices

final class KeystrokeCounterApp: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var totalCount: UInt64 = 0
    private var startDate: Date = Date()
    private var startTimeItem: NSMenuItem?
    private var resetItem: NSMenuItem?
    private let displayColor: NSColor = .systemBlue
    private let displayEmoji: String = "⌨️"
    private let startTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Asia/Tokyo")
        return formatter
    }()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.title = "\(displayEmoji) 0"

        let menu = NSMenu()
        let startTimeItem = NSMenuItem(title: "Started: -", action: nil, keyEquivalent: "")
        startTimeItem.isEnabled = false
        menu.addItem(startTimeItem)
        self.startTimeItem = startTimeItem

        let resetItem = NSMenuItem(title: "Reset Count", action: #selector(resetCount), keyEquivalent: "r")
        resetItem.target = self
        menu.addItem(resetItem)
        self.resetItem = resetItem

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(quit), keyEquivalent: "q"))
        statusItem.menu = menu

        setupEventTap()
        updateTitle()
        updateStartTimeItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        teardownEventTap()
    }

    @objc private func quit() {
        NSApp.terminate(nil)
    }

    @objc private func resetCount() {
        totalCount = 0
        startDate = Date()
        updateTitle()
        updateStartTimeItem()
    }

    private func updateTitle() {
        let text = "\(displayEmoji) \(totalCount)"
        if let button = statusItem.button {
            let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: displayColor]
            button.attributedTitle = NSAttributedString(string: text, attributes: attributes)
        } else {
            statusItem.button?.title = text
        }
    }

    private func updateStartTimeItem() {
        let formatted = startTimeFormatter.string(from: startDate)
        let text = "Started: \(formatted)"
        if let startTimeItem {
            let attributes: [NSAttributedString.Key: Any] = [.foregroundColor: displayColor]
            startTimeItem.attributedTitle = NSAttributedString(string: text, attributes: attributes)
        } else {
            startTimeItem?.title = text
        }
    }

    private func setupEventTap() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)

        let callback: CGEventTapCallBack = { proxy, type, event, userInfo in
            guard type == .keyDown else { return Unmanaged.passUnretained(event) }
            let app = Unmanaged<KeystrokeCounterApp>.fromOpaque(userInfo!).takeUnretainedValue()
            app.totalCount &+= 1
            DispatchQueue.main.async {
                app.updateTitle()
            }
            return Unmanaged.passUnretained(event)
        }

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        eventTap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: userInfo
        )

        guard let eventTap else {
            showPermissionsAlert()
            return
        }

        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, eventTap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
            CGEvent.tapEnable(tap: eventTap, enable: true)
        }
    }

    private func teardownEventTap() {
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
    }

    private func showPermissionsAlert() {
        let alert = NSAlert()
        alert.messageText = "Accessibility Permission Required"
        alert.informativeText = "To count keystrokes, enable Accessibility access for this app in System Settings → Privacy & Security → Accessibility."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Open Settings")
        alert.addButton(withTitle: "Quit")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
                NSWorkspace.shared.open(url)
            }
        }
        NSApp.terminate(nil)
    }
}

let app = NSApplication.shared
let delegate = KeystrokeCounterApp()
app.delegate = delegate
app.run()
