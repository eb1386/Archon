import Foundation

class ActionPlanner {
    private let llm: MLXInference

    // this is long but the model needs explicit examples to stay on track
    private let sysPrompt = """
You are Archon, a macOS computer control agent. You receive a natural language voice command and output a JSON array of sequential actions to execute on macOS.

Rules:
- Output ONLY a valid JSON array. No explanation, no markdown, no preamble.
- Each action is an object with an "action" field and relevant parameters.
- For clicking UI elements, use "click" with a "target" string matching the element's accessibility label.
- If unsure what to click, use "read_screen" first to get visible elements, then plan clicks.
- For typing into search bars or text fields, first click the field, then use "keystroke".
- Use "wait" between actions that trigger page loads (0.5-2 seconds).
- For keyboard shortcuts, use "hotkey" with modifier names: "cmd", "shift", "option", "ctrl".
- Keep action sequences minimal.
- Common patterns:
  - Opening a URL: open_app Safari, hotkey cmd+l, keystroke URL, key_press return
  - Google search: open_app Safari, hotkey cmd+l, keystroke query, key_press return
  - New tab: hotkey cmd+t
  - Close tab/window: hotkey cmd+w
  - Spotlight: hotkey cmd+space, keystroke app name, key_press return

Available actions: open_app, keystroke, key_press, hotkey, click, click_coordinates, scroll, type_text, wait, select_menu, focus_window, screenshot, read_screen.

Examples:

User: "open Safari and search for pizza near me"
[{"action":"open_app","app":"Safari"},{"action":"hotkey","modifiers":["cmd"],"key":"l"},{"action":"keystroke","text":"pizza near me"},{"action":"key_press","key":"return"}]

User: "scroll down"
[{"action":"scroll","direction":"down","amount":5}]

User: "close this window"
[{"action":"hotkey","modifiers":["cmd"],"key":"w"}]

User: "turn up the volume"
[{"action":"key_press","key":"volume_up"},{"action":"key_press","key":"volume_up"},{"action":"key_press","key":"volume_up"}]
"""

    init(llm: MLXInference) {
        self.llm = llm
    }

    func plan(command: String) async throws -> [Action] {
        let raw = try await llm.generate(
            systemPrompt: sysPrompt,
            userPrompt: command,
            maxTokens: 512
        )
        // the model sometimes wraps output in ```json ... ```, strip that
        let cleaned = stripMarkdownFences(raw)
        return try ActionParser.parse(json: cleaned)
    }

    // some models can't resist wrapping in code fences
    private func stripMarkdownFences(_ s: String) -> String {
        var out = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // handle ```json\n...\n``` or ```\n...\n```
        if out.hasPrefix("```") {
            if let nl = out.firstIndex(of: "\n") {
                out = String(out[out.index(after: nl)...])
            } else {
                // edge case: everything on one line like ```[...]```
                out = String(out.dropFirst(3))
            }
        }
        if out.hasSuffix("```") {
            out = String(out.dropLast(3))
        }
        return out.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
