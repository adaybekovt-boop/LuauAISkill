# UI / UX: responsive, cross-device, accessible, performant

Read when: HUD, menus, inventory, settings, prompts, tooltips, localization, text input.
Related: [input](19-input.md), recipes [settings menu](../../recipes/gameplay/settings-menu.md),
[inventory](../../recipes/gameplay/inventory.md), [interaction system](../../recipes/gameplay/interaction-system.md).

## Foundations
- All screen UI runs on the **client**. `StarterGui` ScreenGuis clone into `PlayerGui` on spawn;
  `ResetOnSpawn = false` for persistent UI (HUD, menus) — otherwise it's destroyed and re-cloned every death.
- UI never changes authoritative state directly: buttons send intents; UI renders server-confirmed state (with
  optimistic "pending" states where helpful).
- One ScreenGui per layer (HUD, menus, modal, toasts) with explicit `DisplayOrder`; toggle `Enabled` instead of
  destroying/re-creating.

## Safe areas and insets
`ScreenGui.ScreenInsets`: `CoreUISafeInsets` (default; clear of top bar + notches — use for interactive UI),
`DeviceSafeInsets` (clear of notches only), `TopbarSafeInsets` (lives beside the top bar controls, flexes
horizontally), `None` (fullscreen, backgrounds only). `ScreenGui.SafeAreaCompatibility` handles cutout extension.
`IgnoreGuiInset` is the older mechanism — prefer `ScreenInsets`.

## Responsive layout rules
| Need | Tool |
|---|---|
| Size relative to screen | `UDim2` **scale** for containers; offset for small fixed details (borders, padding) |
| Keep proportions (square icons, cards) | `UIAspectRatioConstraint` |
| Min/max sizes | `UISizeConstraint`, `UITextSizeConstraint` (with `TextScaled`) |
| Global scale per device | one `UIScale` at the root, value computed from viewport size (e.g. `math.clamp(viewport.Y / 1080, 0.6, 1.4)`) |
| Rows/columns | `UIListLayout` (`FillDirection`, `Padding`, `HorizontalAlignment`, `Wraps`, `HorizontalFlex`/`VerticalFlex`) + `UIFlexItem` (`FlexMode`, `GrowRatio`, `ShrinkRatio`) for CSS-flex-like behaviour |
| Grids (inventory) | `UIGridLayout` (`CellSize`, `CellPadding`) or `UIListLayout` with `Wraps` |
| Content-sized frames | `AutomaticSize` (X/Y/XY) — avoid circular dependencies with scale-sized children |
| Scrolling | `ScrollingFrame` + `AutomaticCanvasSize` (or compute `CanvasSize`), `ScrollingDirection` |
| Spacing | `UIPadding` |
| Rounded corners / outline / gradient / shadow | `UICorner`, `UIStroke` (`ApplyStrokeMode`), `UIGradient`, `UIShadow` (new) |
| Fade/transform a whole panel | `CanvasGroup` (`GroupTransparency`) — renders to texture: costs memory; don't nest many |
| Anchor points | set `AnchorPoint` (0.5,0.5 for centered) before positioning |
Test in Studio's Device Emulator: phone portrait/landscape, tablet, 4K desktop, console (10-foot UI, larger text),
and with the top bar/chat open. Text must stay ≥ ~14 px effective on phones.

## Text
- Prefer fixed `TextSize` per style + `TextWrapped`; `TextScaled` produces inconsistent sizes across labels — if
  used, always add `UITextSizeConstraint` (max) and apply per group.
- `RichText = true` for inline styling; escape user strings (`<`, `>`, `&`) before inserting into rich text.
- Measure text: `TextService:GetTextBoundsAsync(params)`.
- **Filtering (mandatory)**: any text authored by a player and shown to others (signs, pet names, custom messages)
  must go through the server: `TextService:FilterStringAsync(text, fromUserId)` → `TextFilterResult`:
  `GetNonChatStringForBroadcastAsync()` (everyone) or `GetNonChatStringForUserAsync(toUserId)` (specific user). pcall,
  length-cap before calling, never show raw text on failure (show nothing/placeholder). Chat itself goes through
  `TextChatService` (filtered automatically); `TextChatService.ChatVersion` is not writable by game scripts.
- Localization: `AutoLocalize` on text objects + `LocalizationTable`s / automatic text capture; format numbers/dates
  per locale; leave 30–40 % extra width for German/Russian. Don't concatenate translated fragments — use keyed
  strings with parameters.

## Styling (StyleSheets) — CSS-like, engine-level
`StyleSheet` with `StyleRule`s (`Selector` like `"Frame"`, `".Tag"`, `"#Name"`, `":hover"`-style GuiState
selectors, `"::UICorner"` modifiers, `"@Query"` queries), tokens and themes via attributes on StyleSheets
(`"$Token"` references), `StyleDerive` to inherit, `StyleLink` to apply a sheet to a ScreenGui tree (one sheet per
tree), `StyleQuery` for conditional styles (screen size, input type). Great for themes (light/dark, colorblind)
without per-frame property writes. It's not full browser CSS — only documented selectors/properties work.

## Input across devices
- Buttons: use `GuiButton.Activated` (works for mouse, touch, gamepad select) — not `MouseButton1Click` alone.
- Gamepad: every interactive element `Selectable = true`; set `GuiService.SelectedObject` when a menu opens;
  `NextSelectionUp/Down/Left/Right` or `SelectionGroup` for navigation; close with ButtonB; show button glyphs
  (`UserInputService:GetImageForKeyCode`, `InputActionLabel` beta).
- Touch: hit targets ≥ 44–48 px; avoid bottom-left/right thumb zones used by the default joystick/jump button;
  `UserInputService.TouchEnabled` + last input type to adapt prompts.
- Track `UserInputService.LastInputTypeChanged` / `PreferredInput` to switch hints dynamically.

## HUD and common widgets (patterns)
| Widget | Pattern |
|---|---|
| Health/stamina bar | frame with inner fill sized by scale; tween size over 0.1–0.2 s; lag bar (white) trailing for damage feedback |
| Interaction prompt | `ProximityPrompt` (built-in, cross-device, customizable via `Style = Custom` + `PromptShown`); server validates on `Triggered` |
| Tooltip | single reusable tooltip frame repositioned to hovered element; delay 0.3–0.5 s; gamepad: show on selection |
| Inventory grid | virtualized/pooled cells for big inventories; data-driven from server snapshot |
| Toast/notifications | queue with max visible count; auto-dismiss |
| Settings | persist per player (server DataStore via remote, or local-only); apply immediately; include reduced motion, camera shake, FOV, sensitivity, graphics preset, audio sliders, colorblind-friendly highlights |
| Transitions | `TweenService` on position/transparency (client); `CanvasGroup` for group fades |

## Performance
- UI with thousands of instances or per-frame property changes costs CPU (layout recalculation). Batch updates,
  change only what changed, pool list items, avoid tweening layout-driving sizes of many items.
- Layout objects (`UIListLayout`, `UIGridLayout`, `AutomaticSize`) recompute when children change — build lists
  off-screen, then parent once.
- `ViewportFrame` (3D in UI) renders extra scenes — keep few, low-poly, update rarely.
- Avoid full-screen transparent overlays stacked (overdraw on mobile).

## Accessibility checklist
- [ ] Readable text size and contrast; don't encode information by color alone.
- [ ] Reduced motion setting respected (camera shake, bob, UI animations).
- [ ] All actions reachable by gamepad and touch.
- [ ] Captions/visual cues for important audio.
- [ ] No flashing effects above ~3 Hz full-screen.

Sources: cd:ui/index, cd:ui/on-screen-containers, cd:ui/position-and-size, cd:ui/size-modifiers, cd:ui/list-flex-layouts,
cd:ui/grid-table-layouts, cd:ui/scrolling-frames, cd:ui/appearance-modifiers, cd:ui/labels, cd:ui/rich-text,
cd:ui/text-filtering, cd:ui/styling/index, cd:ui/styling/css-comparisons, cd:ui/proximity-prompts,
cd:projects/cross-platform, cd:production/publishing/accessibility, cd:reference/engine/classes/ScreenGui,
cd:reference/engine/classes/TextService.
