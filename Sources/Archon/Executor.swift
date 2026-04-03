import ApplicationServices
import AppKit
import Foundation

class Executor {

    private let keyCodes: [String: Int] = [
        "return": 36, "enter": 36, "tab": 48, "space": 49,
        "escape": 53, "esc": 53, "delete": 51, "backspace": 51,
        "forward_delete": 117,
        "up": 126, "down": 125, "left": 123, "right": 124,
        "a": 0, "b": 11, "c": 8, "d": 2, "e": 14, "f": 3, "g": 5, "h": 4,
        "i": 34, "j": 38, "k": 40, "l": 37, "m": 46, "n": 45, "o": 31, "p": 35,
        "q": 12, "r": 15, "s": 1, "t": 17, "u": 32, "v": 9, "w": 13, "x": 7,
        "y": 16, "z": 6,
        "0": 29, "1": 18, "2": 19, "3": 20, "4": 21, "5": 23, "6": 22, "7": 26,
        "8": 28, "9": 25,
        "f1": 122, "f2": 120, "f3": 99, "f4": 118, "f5": 96, "f6": 97,
        "f7": 98, "f8": 100, "f9": 101, "f10": 109, "f11": 103, "f12": 111,
        "volume_up": 72, "volume_down": 73, "mute": 74,
        "brightness_up": 144, "brightness_down": 145,
    ]

    func execute(_ action: Action) async throws {
        switch action {
        case .openApp(let app):       try openApp(app)
        case .keystroke(let t, _):    pasteText(t)
        case .keyPress(let k, let m): pressKey(k, mods: m)
        case .hotkey(let m, let k):   pressKey(k, mods: m)
        case .click(let target):      try clickElement(target)
        case .clickCoordinates(let x, let y): clickAt(CGPoint(x: x, y: y))
        case .scroll(let dir, let n): doScroll(dir, amount: n)
        case .typeText(let t):        typeChars(t)
        case .wait(let s):            try await Task.sleep(nanoseconds: UInt64(s * 1_000_000_000))
        case .selectMenu(let m, let i): try menuClick(m, item: i)
        case .focusWindow(let app):   try openApp(app)
        case .screenshot:             takeScreenshot()
        case .readScreen:             try dumpScreen()
        }
    }

    // MARK: - app launching

    private func openApp(_ name: String) throws {
        let ws = NSWorkspace.shared

        // already running? just bring it forward
        if let running = ws.runningApplications.first(where: {
            $0.localizedName?.lowercased() == name.lowercased()
        }) {
            running.activate()
            return
        }

        // applescript handles name resolution better than NSWorkspace
        let escaped = name.replacingOccurrences(of: "\"", with: "\\\"")
        try AppleScriptBridge.run("tell application \"\(escaped)\" to activate")
    }

    // MARK: - text input

    private func pasteText(_ text: String) {
        let pb = NSPasteboard.general
        let prev = pb.string(forType: .string)

        pb.clearContents()
        pb.setString(text, forType: .string)
        pressKey("v", mods: ["cmd"])

        // restore clipboard on main thread (NSPasteboard isn't thread-safe)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            pb.clearContents()
            if let old = prev { pb.setString(old, forType: .string) }
        }
    }

    private func typeChars(_ text: String) {
        let src = CGEventSource(stateID: .hidSystemState)
        for ch in text {
            let utf16 = Array(String(ch).utf16)
            if let down = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: true) {
                down.keyboardSetUnicodeString(stringLength: utf16.count, unicodeString: utf16)
                down.post(tap: .cghidEventTap)
            }
            if let up = CGEvent(keyboardEventSource: src, virtualKey: 0, keyDown: false) {
                up.post(tap: .cghidEventTap)
            }
            usleep(20_000)
        }
    }

    // MARK: - keys

    private func pressKey(_ key: String, mods: [String] = []) {
        guard let code = keyCodes[key.lowercased()] else {
            print("  [?] unknown key: \(key)")
            return
        }
        let flags = buildFlags(mods)
        let down = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: true)
        let up = CGEvent(keyboardEventSource: nil, virtualKey: CGKeyCode(code), keyDown: false)
        down?.flags = flags
        up?.flags = flags
        down?.post(tap: .cghidEventTap)
        usleep(10_000) // 10ms — some apps miss the keyup if it's instant
        up?.post(tap: .cghidEventTap)
    }

    private func buildFlags(_ mods: [String]) -> CGEventFlags {
        var f = CGEventFlags()
        for m in mods {
            switch m.lowercased() {
            case "cmd", "command": f.insert(.maskCommand)
            case "shift":         f.insert(.maskShift)
            case "option", "alt": f.insert(.maskAlternate)
            case "ctrl", "control": f.insert(.maskControl)
            default: break
            }
        }
        return f
    }

    // MARK: - clicking

    private func clickElement(_ target: String) throws {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw ArchonError.noApp
        }

        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let elements = AccessibilityTree.findElements(in: axApp)

        guard let hit = AccessibilityTree.findBestMatch(target: target, in: elements) else {
            // dump what we found so we can debug
            print("  [!] no match for '\(target)'. visible:")
            for el in elements.prefix(15) {
                print("      [\(el.role)] \(el.label)")
            }
            throw ArchonError.elementNotFound(target)
        }

        // try the accessibility press action first
        if AXUIElementPerformAction(hit, kAXPressAction as CFString) == .success {
            return
        }

        // fall back: get the position and synth a mouse click
        var posRef: CFTypeRef?, sizeRef: CFTypeRef?
        AXUIElementCopyAttributeValue(hit, kAXPositionAttribute as CFString, &posRef)
        AXUIElementCopyAttributeValue(hit, kAXSizeAttribute as CFString, &sizeRef)

        guard let pv = posRef, let sv = sizeRef else { return }
        var pos = CGPoint.zero
        var size = CGSize.zero
        AXValueGetValue(pv as! AXValue, .cgPoint, &pos)
        AXValueGetValue(sv as! AXValue, .cgSize, &size)

        clickAt(CGPoint(x: pos.x + size.width / 2, y: pos.y + size.height / 2))
    }

    private func clickAt(_ pt: CGPoint) {
        let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: pt, mouseButton: .left)
        let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: pt, mouseButton: .left)
        down?.post(tap: .cghidEventTap)
        usleep(30_000) // small gap so apps register it
        up?.post(tap: .cghidEventTap)
    }

    // MARK: - scroll

    private func doScroll(_ direction: String, amount: Int) {
        // 40px per unit feels right on retina — 10 was way too small
        let step = amount * 40
        var dy: Int32 = 0, dx: Int32 = 0
        switch direction.lowercased() {
        case "up":    dy = Int32(step)
        case "down":  dy = Int32(-step)
        case "left":  dx = Int32(step)
        case "right": dx = Int32(-step)
        default:      dy = Int32(-step)
        }
        if let ev = CGEvent(scrollWheelEvent2Source: nil, units: .pixel, wheelCount: 2, wheel1: dy, wheel2: dx, wheel3: 0) {
            ev.post(tap: .cghidEventTap)
        }
    }

    // MARK: - menu

    private func menuClick(_ menu: String, item: String) throws {
        guard let appName = NSWorkspace.shared.frontmostApplication?.localizedName else {
            throw ArchonError.noApp
        }
        let script = """
        tell application "System Events"
            tell process "\(appName)"
                click menu item "\(item)" of menu 1 of menu bar item "\(menu)" of menu bar 1
            end tell
        end tell
        """
        try AppleScriptBridge.run(script)
    }

    // MARK: - screenshot

    private func takeScreenshot() {
        let path = "/tmp/archon_\(Int(Date().timeIntervalSince1970)).png"
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: "/usr/sbin/screencapture")
        proc.arguments = ["-x", path]
        try? proc.run()
        proc.waitUntilExit()
        print("  screenshot: \(path)")
    }

    // MARK: - screen reading

    private func dumpScreen() throws {
        guard let app = NSWorkspace.shared.frontmostApplication else {
            throw ArchonError.noApp
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        let labels = AccessibilityTree.getAllLabels(in: axApp)
        print("  visible elements:")
        for l in labels.prefix(50) { print("    \(l)") }
    }
}
