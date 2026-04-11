# Codex Instructions

- Respond in French unless the user asks otherwise.
- Do not commit or push unless the user explicitly asks for it.
- After substantial Swift or Xcode changes, propose or run a build check. For minor edits, skip the build unless the user asks for it. When building, always prefer a filtered `xcodebuild` output that keeps errors and the final build status instead of pasting full logs.
- Keep investigations targeted: use `rg`, focused diffs, and only read files needed for the current task.
- Do not stage or revert unrelated local changes.
- Use skills only when the user names one or when the task clearly needs it; do not load skill files for routine edits.
