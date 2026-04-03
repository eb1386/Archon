import Foundation

enum Action: CustomStringConvertible {
    case openApp(app: String)
    case keystroke(text: String, modifiers: [String])
    case keyPress(key: String, modifiers: [String])
    case hotkey(modifiers: [String], key: String)
    case click(target: String)
    case clickCoordinates(x: Int, y: Int)
    case scroll(direction: String, amount: Int)
    case typeText(text: String)
    case wait(seconds: Float)
    case selectMenu(menu: String, item: String)
    case focusWindow(app: String)
    case screenshot
    case readScreen

    var description: String {
        switch self {
        case .openApp(let a):          return "open(\(a))"
        case .keystroke(let t, _):     return "keystroke(\(t))"
        case .keyPress(let k, let m):
            return m.isEmpty ? "key(\(k))" : "key(\(m.joined(separator: "+"))+\(k))"
        case .hotkey(let m, let k):    return "hotkey(\(m.joined(separator: "+"))+\(k))"
        case .click(let t):            return "click(\(t))"
        case .clickCoordinates(let x, let y): return "click(\(x),\(y))"
        case .scroll(let d, let n):    return "scroll(\(d) x\(n))"
        case .typeText(let t):         return "type(\(t))"
        case .wait(let s):             return "wait(\(s)s)"
        case .selectMenu(let m, let i): return "menu(\(m)>\(i))"
        case .focusWindow(let a):      return "focus(\(a))"
        case .screenshot:              return "screenshot"
        case .readScreen:              return "read_screen"
        }
    }
}

struct ActionParser {

    static func parse(json: String) throws -> [Action] {
        let s = json.trimmingCharacters(in: .whitespacesAndNewlines)

        // find the outermost [ ... ]
        guard let open = s.firstIndex(of: "["),
              let close = s.lastIndex(of: "]") else {
            throw ArchonError.invalidActionJSON(String(json.prefix(120)))
        }

        let slice = String(s[open...close])
        guard let data = slice.data(using: .utf8),
              let arr = try? JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ArchonError.invalidActionJSON(String(slice.prefix(120)))
        }

        return try arr.map { try parseOne($0) }
    }

    private static func parseOne(_ d: [String: Any]) throws -> Action {
        guard let type = d["action"] as? String else {
            throw ArchonError.invalidActionJSON("missing 'action' key")
        }
        switch type {
        case "open_app":
            return .openApp(app: try req(d, "app"))
        case "keystroke":
            return .keystroke(text: try req(d, "text"), modifiers: d["modifiers"] as? [String] ?? [])
        case "key_press":
            return .keyPress(key: try req(d, "key"), modifiers: d["modifiers"] as? [String] ?? [])
        case "hotkey":
            return .hotkey(modifiers: d["modifiers"] as? [String] ?? [], key: try req(d, "key"))
        case "click":
            return .click(target: try req(d, "target"))
        case "click_coordinates":
            guard let x = d["x"] as? Int, let y = d["y"] as? Int else {
                throw ArchonError.invalidActionJSON("click_coordinates needs x and y")
            }
            return .clickCoordinates(x: x, y: y)
        case "scroll":
            return .scroll(
                direction: d["direction"] as? String ?? "down",
                amount: d["amount"] as? Int ?? 3
            )
        case "type_text":
            return .typeText(text: try req(d, "text"))
        case "wait":
            // JSON numbers could come in as any numeric type
            let secs: Float
            if let v = d["seconds"] as? Double { secs = Float(v) }
            else if let v = d["seconds"] as? Int { secs = Float(v) }
            else { secs = 1.0 }
            return .wait(seconds: secs)
        case "select_menu":
            return .selectMenu(menu: try req(d, "menu"), item: try req(d, "item"))
        case "focus_window":
            return .focusWindow(app: try req(d, "app"))
        case "screenshot":
            return .screenshot
        case "read_screen":
            return .readScreen
        default:
            throw ArchonError.unknownAction(type)
        }
    }

    // helper to pull a required string field
    private static func req(_ d: [String: Any], _ key: String) throws -> String {
        guard let v = d[key] as? String else {
            throw ArchonError.invalidActionJSON("missing '\(key)'")
        }
        return v
    }
}
