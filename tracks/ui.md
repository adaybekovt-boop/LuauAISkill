# Track: UI / UX

Use for: HUDs, menus, inventories, mobile/console UI, accessibility, settings.
Load: [UI/UX](../handbook/roblox/18-ui-ux.md) → [input](../handbook/roblox/19-input.md); chat UI/commands →
[chat & leaderboards](../handbook/roblox/26-chat-leaderboards.md).

Non-negotiables
- Scale + constraints (`UIAspectRatioConstraint`, `UISizeConstraint`, `UITextSizeConstraint`), `ScreenInsets`, no offset-only layouts.
- `Activated` (not `MouseButton1Click`) for mouse/touch/gamepad; Selectable controls; initial `SelectedObject` for gamepads.
- `ResetOnSpawn = false` for persistent UI; UI shows server state, never owns it.
- Accessibility: Reduced Motion, preferred text size/transparency, subtitles, colour-blind-safe cues.
- Test in Device Emulator (phone portrait/landscape) and with a controller.

Recipes: [settings-menu](../recipes/gameplay/settings-menu.md), [inventory](../recipes/gameplay/inventory.md). Evals: `evals/cases/ui.jsonl`.

Additional verified examples: [friend-global-leaderboard](../recipes/gameplay/friend-global-leaderboard.md).
