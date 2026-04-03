import ApplicationServices
import Foundation

class AccessibilityTree {

    struct Element {
        let axElement: AXUIElement
        let label: String
        let role: String
    }

    static func findElements(in app: AXUIElement) -> [Element] {
        var out: [Element] = []
        walk(app, into: &out, depth: 0)
        return out
    }

    private static func walk(_ el: AXUIElement, into results: inout [Element], depth: Int) {
        if depth > 15 { return } // don't go too deep

        let role = axString(el, kAXRoleAttribute)
        let title = axString(el, kAXTitleAttribute)
        let desc = axString(el, kAXDescriptionAttribute)
        let value = axString(el, kAXValueAttribute)

        let label = [title, desc, value].filter { !$0.isEmpty }.joined(separator: " | ")
        if !label.isEmpty {
            results.append(Element(axElement: el, label: label, role: role))
        }

        // recurse into children
        var childRef: CFTypeRef?
        let status = AXUIElementCopyAttributeValue(el, kAXChildrenAttribute as CFString, &childRef)
        guard status == .success, let children = childRef as? [AXUIElement] else { return }
        for child in children {
            walk(child, into: &results, depth: depth + 1)
        }
    }

    // pull a string attribute, returns "" on failure
    private static func axString(_ el: AXUIElement, _ attr: String) -> String {
        var ref: CFTypeRef?
        AXUIElementCopyAttributeValue(el, attr as CFString, &ref)
        return (ref as? String) ?? ""
    }

    static func findBestMatch(target: String, in elements: [Element]) -> AXUIElement? {
        let needle = target.lowercased()

        // exact
        if let el = elements.first(where: { $0.label.lowercased() == needle }) {
            return el.axElement
        }
        // substring
        if let el = elements.first(where: { $0.label.lowercased().contains(needle) }) {
            return el.axElement
        }
        // reverse substring (target contains the label)
        if let el = elements.first(where: { !$0.label.isEmpty && needle.contains($0.label.lowercased()) }) {
            return el.axElement
        }
        // levenshtein fallback — only if reasonably close
        var bestEl: AXUIElement? = nil
        var bestDist = Int.max
        for e in elements {
            let d = levenshtein(e.label.lowercased(), needle)
            if d < bestDist { bestDist = d; bestEl = e.axElement }
        }
        if bestDist < target.count / 2 { return bestEl }

        return nil
    }

    static func getAllLabels(in app: AXUIElement) -> [String] {
        findElements(in: app).map { "[\($0.role)] \($0.label)" }
    }

    // standard levenshtein, nothing fancy
    private static func levenshtein(_ a: String, _ b: String) -> Int {
        let s = Array(a), t = Array(b)
        if s.isEmpty { return t.count }
        if t.isEmpty { return s.count }

        var matrix = [[Int]](repeating: [Int](repeating: 0, count: t.count + 1), count: s.count + 1)
        for i in 0...s.count { matrix[i][0] = i }
        for j in 0...t.count { matrix[0][j] = j }

        for i in 1...s.count {
            for j in 1...t.count {
                let cost = s[i-1] == t[j-1] ? 0 : 1
                matrix[i][j] = min(
                    matrix[i-1][j] + 1,
                    matrix[i][j-1] + 1,
                    matrix[i-1][j-1] + cost
                )
            }
        }
        return matrix[s.count][t.count]
    }
}
