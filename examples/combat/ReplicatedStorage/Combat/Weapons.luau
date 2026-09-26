--!strict
-- Weapon definitions (shared). Clients read them for prediction/visuals; the server uses the same numbers
-- as the authority. A Tool's "WeaponId" attribute selects the entry.
export type Hitscan = {
	kind: "Hitscan",
	damage: number,
	headMultiplier: number,
	range: number,
	falloffStart: number, -- studs; damage lerps to damage * minFalloff at `range`
	minFalloff: number,
	rpm: number,
	magazine: number,
	reloadTime: number,
}
export type Melee = {
	kind: "Melee",
	damage: number,
	reach: number, -- studs in front of the root
	halfAngle: number, -- degrees of the hit cone
	windup: number, -- seconds before the hit window (telegraph)
	active: number, -- hit window length
	recovery: number, -- after the window, before the next attack
}
export type Projectile = {
	kind: "Projectile",
	damage: number,
	speed: number,
	gravity: number, -- studs/s² downward (workspace default is 196.2)
	radius: number, -- 0 = raycast, > 0 = spherecast
	lifetime: number,
	splashRadius: number,
	rpm: number,
}
export type Weapon = Hitscan | Melee | Projectile

local Weapons: { [string]: Weapon } = {
	Pistol = {
		kind = "Hitscan",
		damage = 22,
		headMultiplier = 2,
		range = 300,
		falloffStart = 60,
		minFalloff = 0.5,
		rpm = 300,
		magazine = 12,
		reloadTime = 1.6,
	},
	Pipe = { kind = "Melee", damage = 30, reach = 6, halfAngle = 55, windup = 0.25, active = 0.15, recovery = 0.45 },
	FlareGun = {
		kind = "Projectile",
		damage = 45,
		speed = 120,
		gravity = 60,
		radius = 0.4,
		lifetime = 4,
		splashRadius = 8,
		rpm = 40,
	},
}

return table.freeze(Weapons)
