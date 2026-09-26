# Input: Input Action System, ContextActionService, UserInputService

Read when: binding controls, rebinding, gamepad/touch support, menus vs gameplay input conflicts.
Related: [UI/UX](18-ui-ux.md), [server authority](05-server-authority.md) (requires InputActions for simulation input).

## Choose the API
| API | Status | Use |
|---|---|---|
| **Input Action System**: `InputContext` → `InputAction` → `InputBinding` (Instances, edit-time configurable) | current, stable (`InputActionLabel` and the Input Action Manager tool are beta) | new projects; cross-device bindings; required for server authority simulation input |
| `ContextActionService:BindAction(name, fn, createTouchButton, ...inputs)` | stable | action-style bindings in code, auto touch buttons, priority stacking (`BindActionAtPriority`) |
| `UserInputService` events (`InputBegan/Changed/Ended`, `GetMouseDelta`, `IsKeyDown`) | stable, low-level | raw input, mouse delta, device detection, text focus |
| `Player:GetMouse()` / `Mouse` object | legacy (events deprecated in favour of UIS) | avoid in new code |
Client-only: all input APIs work in LocalScripts / client Scripts.

## Input Action System essentials
- Hierarchy (usually in `ReplicatedStorage.Inputs` for client-only use; **must be under the `Player`** for server
  authority mode): `InputContext` (e.g. `PlayContext`, `MenuContext`) with `Enabled`, `Priority`, `Sink` (consume
  bound inputs so lower-priority contexts don't see them) → `InputAction` (`Type`: `Bool`, `Direction1D`,
  `Direction2D`, `Direction3D`, `ViewportPosition`) → `InputBinding`s (`KeyCode`, or composite `Up/Down/Left/Right/
  Forward/Backward`, `UIButton` for touch buttons, `Scale`, `PressedThreshold`, `DisplayName`, `DisplayImage`).
- Events: `Pressed`/`Released` (Bool only), `StateChanged` (all types, fires on change only); poll `GetState()`
  every frame for continuous analog input (thumbsticks, mouse delta) and multiply by `dt`.
- `InputAction.PreferredBinding` = binding matching current device → build hints; or `InputActionLabel` (beta).
- `Workspace.PlayerScriptsUseInputActionSystem` (Studio setting) makes default player scripts use it.
- Give every action a keyboard/mouse, gamepad and touch binding.
- Menu open → enable `MenuContext` with `Sink`/higher `Priority` (or disable `PlayContext`) → gameplay stops reacting.

## ContextActionService pattern
```luau
--!strict
local ContextActionService = game:GetService("ContextActionService")

local function onSprint(_name: string, state: Enum.UserInputState, _input: InputObject): Enum.ContextActionResult
	if state == Enum.UserInputState.Begin then
		print("sprint start")
	elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
		print("sprint stop")             -- Cancel happens when a higher-priority binding takes the input
	end
	return Enum.ContextActionResult.Sink
end

ContextActionService:BindAction("Sprint", onSprint, true, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL3)
ContextActionService:SetTitle("Sprint", "Run")
-- Later: ContextActionService:UnbindAction("Sprint")
```
Always handle `Cancel`/`End` (focus loss, menu opening, rebinding) — otherwise sprint stays "held".

## UserInputService essentials
- `InputBegan(input, gameProcessedEvent)`: **ignore when `gameProcessedEvent` is true** (typing in chat/TextBox,
  clicking UI).
- Mouse: `UserInputService.MouseBehavior` (`Default`, `LockCenter`, `LockCurrentPosition`), `GetMouseDelta()`,
  `MouseIconEnabled`, `MouseDeltaSensitivity` (user setting, read).
- Device detection: `TouchEnabled`, `KeyboardEnabled`, `GamepadEnabled`, `PreferredInput`,
  `GetLastInputType()`/`LastInputTypeChanged`. Players switch devices mid-session — adapt prompts live.
- Gamepad: `GamepadService` (virtual cursor), `UserInputService:GetConnectedGamepads()`, thumbstick dead zones
  (~0.15–0.2), `HapticService` for rumble (check support).
- Text input: `TextBox.FocusLost(enterPressed)`; `UserInputService:GetFocusedTextBox()`.
- `UserInputService.ModalEnabled` is deprecated → `GuiService.TouchControlsEnabled`.

## Rebinding
Store bindings as data (action → list of KeyCode names) in player settings; apply by setting `InputBinding.KeyCode`
(Input Action System) or re-binding CAS. Validate that one key isn't bound to two conflicting actions in the same
context. Persist via a server remote with validation (only known actions, only valid `Enum.KeyCode` names).

## Security
Input never reaches the server except through your remotes (or InputActions under server authority). The server
treats any action request as untrusted intent ([security](04-security.md)).

Sources: cd:input/index, cd:input/input-action-system, cd:input/mouse-and-keyboard, cd:input/gamepad, cd:input/mobile,
cd:reference/engine/classes/ContextActionService, cd:reference/engine/classes/UserInputService,
cd:reference/engine/classes/InputAction, cd:reference/engine/classes/InputContext, cd:reference/engine/classes/InputBinding,
cd:projects/server-authority/index.
