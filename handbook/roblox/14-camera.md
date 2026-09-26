# Camera: first/third person, shoulder, bodycam, springs, shake, recoil, comfort

Read when: any custom camera, FPS/horror feel, cinematics, recoil/shake, VR-comfort-sensitive effects.
Related: [character controllers](13-character-controllers.md), graphics recipe [bodycam/CCTV/old camera looks](../../recipes/graphics/camera-aesthetics.md),
gameplay recipe [bodycam controller](../../recipes/gameplay/bodycam-camera.md).

## Facts
- `workspace.CurrentCamera` is **client-local** (not replicated). Only client code controls the view.
- `Camera.FieldOfView` = **vertical** FOV in degrees, clamped 1–120, default 70 (`FieldOfViewMode`,
  `DiagonalFieldOfView`, `MaxAxisFieldOfView` alternatives). 16:9 vertical 70° ≈ 102° horizontal.
- `CameraType`: `Custom` (default PlayerModule camera following `CameraSubject`), `Scriptable` (you set `CFrame`
  every frame), `Fixed`, `Attach`, `Watch`, `Track`, `Follow`, `Orbital`.
- First person: `player.CameraMode = Enum.CameraMode.LockFirstPerson` or `CameraMinZoomDistance =
  CameraMaxZoomDistance = 0.5`; mouse lock: `UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter`
  (must be re-applied each frame while in a custom camera, as default scripts reset it).
- Offsets on top of the default camera: `Humanoid.CameraOffset` (character-relative, simplest shoulder/crouch/lean).
- Per-frame camera code: `RunService:BindToRenderStep(name, Enum.RenderPriority.Camera.Value + 1, fn)` to run
  **after** the default camera (to add offsets) or `Enum.RenderPriority.Camera.Value - 1` to run before it. Unbind on cleanup.
- Ray from screen: `camera:ViewportPointToRay(x, y)` (ignores GUI inset) vs `ScreenPointToRay` (accounts for
  inset); world → screen: `WorldToViewportPoint` (returns position + onScreen).

## Architecture: one owner, layered offsets
Never let two scripts write `Camera.CFrame` each frame. One camera controller composes:
```text
base CFrame (default camera or your rig: head/shoulder/orbit)
  × recoil offset (spring)            -- gameplay feedback
  × shake offset (trauma/noise)       -- impacts, explosions
  × bob/sway offset (stride phase)    -- locomotion feel, reduced-motion aware
  × lean/crouch offset (spring)
FOV = baseFOV + sprintKick + aimZoom (springs)
```
Each layer returns a small offset built fresh every frame from its state (never multiply onto last frame's result →
drift).

## Springs and smoothing (framerate-independent)
```luau
--!strict
-- Critically damped spring (semi-implicit Euler). Stable at any dt if frequency * dt is small; clamp dt.
export type Spring = { position: number, velocity: number, target: number, frequency: number, damping: number }

local function newSpring(frequency: number, damping: number): Spring
	return { position = 0, velocity = 0, target = 0, frequency = frequency, damping = damping }
end

local function stepSpring(s: Spring, dt: number): number
	dt = math.min(dt, 1 / 30)                                    -- avoid explosions on hitches
	local w = s.frequency * 2 * math.pi
	local accel = w * w * (s.target - s.position) - 2 * s.damping * w * s.velocity
	s.velocity += accel * dt
	s.position += s.velocity * dt
	return s.position
end

-- Exponential smoothing toward a target (for simple follow): alpha depends on dt, not frame count.
local function smooth(current: number, target: number, sharpness: number, dt: number): number
	return current + (target - current) * (1 - math.exp(-sharpness * dt))
end

local fov = newSpring(4, 1)       -- 4 Hz, critically damped
fov.target = 8
print(stepSpring(fov, 1 / 60), smooth(0, 1, 10, 1 / 60))
```
`TweenService:SmoothDamp(current, target, velocity, smoothTime, maxSpeed, dt)` exists (returns new position and
velocity) and works for numbers/vectors — handy for follow cameras.

## Recoil
- Kick = impulse on a pitch/yaw spring (`velocity += kick`), not a direct CFrame jump. Randomize yaw slightly;
  pitch mostly up. Recover via spring back to 0 (or leave permanent aim climb as a design choice).
- Visual recoil (camera) is separate from gameplay spread (server-validated): the camera never decides hits.

## Shake (trauma model)
- `trauma` ∈ [0,1] increases on impacts, decays linearly (e.g. 1.5/s). Offset = maxAngle × trauma² × noise(t).
- Use `math.noise(t * freq, seed)` per axis (smooth), not `math.random` per frame (jittery).
- Rotational shake (small degrees) reads better than positional shake in first person. Cap max angles
  (≤ 2–3° typical), respect a "camera shake" setting (0–100 %).

## Head bob (don't default to sin(time))
- Drive from **stride phase** (distance travelled / stride length), amplitude from horizontal speed, zero when
  airborne/idle; vertical bob ×2 frequency of lateral sway. Small: 0.05–0.15 studs vertical, 0.5–1.0° roll.
- Smooth amplitude in/out with springs when starting/stopping.
- Provide a "view bobbing" toggle; default low. Many players get motion sick.

## Camera types in practice
| Camera | Recipe |
|---|---|
| FPS | LockFirstPerson + LockCenter; hide own body parts locally (`LocalTransparencyModifier = 1`) or use a viewmodel; layered offsets on `BindToRenderStep` after Camera |
| Third-person shoulder | `Humanoid.CameraOffset = Vector3.new(1.75, 0.5, 0)` + `AutoRotate` rules; or Scriptable orbit with collision (spherecast from pivot to desired position, pull in on hit) |
| Top-down / isometric | Scriptable; CFrame looking at player from fixed offset; smooth follow |
| Cinematic | Scriptable; tween along keyframes or `CFrame:Lerp` with eased alpha; restore previous CameraType/Subject after; skippable; disable player controls during |
| Spectator | `CameraSubject = otherHumanoid` with Custom camera |
| Bodycam | vertical FOV ~90–100 (very wide, ≈120°+ horizontal on 16:9), camera anchored to chest/shoulder attachment with lag spring, strong handheld noise at low frequency, slight roll, fisheye-like feel via FOV + DepthOfField/ColorCorrection/grain overlay — see recipe; keep a comfort toggle |

## Comfort (motion sickness)
Risky: large FOV changes, head bob, rolling, camera-induced acceleration not caused by player input, high-frequency
shake, forced camera turns. Mitigations: small amplitudes, springs (no instant snaps), a Reduced Motion / camera
shake slider, never move the camera in ways the player didn't cause except brief impacts, stable horizon by
default, FOV ≥ 70 in first person, allow FOV setting.

## Cleanup
Restore `CameraType = Custom`, `CameraSubject = humanoid`, `MouseBehavior = Default`, FOV and `CameraOffset` when
leaving custom modes, on death, and on UI menus. Unbind render steps. Re-acquire `workspace.CurrentCamera` if it
changes (`workspace:GetPropertyChangedSignal("CurrentCamera")`).

Sources: cd:workspace/camera/index, cd:reference/engine/classes/Camera, cd:reference/engine/classes/RunService,
cd:reference/engine/classes/TweenService, cd:reference/engine/classes/Player, cd:reference/engine/classes/UserInputService,
cd:production/publishing/accessibility.
