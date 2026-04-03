import Foundation

enum ArchonError: Error, LocalizedError {
    case modelNotLoaded
    case whisperInitFailed
    case whisperTranscriptionFailed
    case vadInitFailed
    case audioSetupFailed
    case invalidActionJSON(String)
    case unknownAction(String)
    case elementNotFound(String)
    case noApp
    case appleScriptFailed(String)
    case permissionDenied(String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:             return "llm not loaded"
        case .whisperInitFailed:          return "whisper init failed"
        case .whisperTranscriptionFailed: return "transcription failed"
        case .vadInitFailed:              return "vad init failed"
        case .audioSetupFailed:           return "audio setup failed"
        case .invalidActionJSON(let s):   return "bad action json: \(s)"
        case .unknownAction(let s):       return "unknown action: \(s)"
        case .elementNotFound(let s):     return "element not found: \(s)"
        case .noApp:                      return "no frontmost app"
        case .appleScriptFailed(let s):   return "applescript: \(s)"
        case .permissionDenied(let s):    return "permission denied: \(s)"
        }
    }
}
