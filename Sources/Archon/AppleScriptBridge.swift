import Foundation

class AppleScriptBridge: @unchecked Sendable {

    @discardableResult
    static func run(_ source: String) throws -> String? {
        var errInfo: NSDictionary?
        let script = NSAppleScript(source: source)
        let result = script?.executeAndReturnError(&errInfo)

        if let err = errInfo {
            let msg = err[NSAppleScript.errorMessage] as? String ?? "unknown error"
            throw ArchonError.appleScriptFailed(msg)
        }
        return result?.stringValue
    }

    static func activateApp(_ name: String) throws {
        let safe = name.replacingOccurrences(of: "\"", with: "\\\"")
        try run("tell application \"\(safe)\" to activate")
    }
}
