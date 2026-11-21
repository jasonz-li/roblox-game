--!strict
-- Throwables: the Ember Frag (G) and the Maneki Lure (T).
--   Frags: everyone starts with 2 and gets +2 every wave (max 4).
--   Lures: bought at the Lure Shrine (max 2 carried). A glowing beckoning-cat charm:
--   zombies near it forget you and crowd around it, then it bursts.
-- Damage scales with the wave's zombie health so they stay worth throwing late.

local ThrowableConfig = {
	Frag = {
		Id = "Frag",
		DisplayName = "Ember Frag",
		Key = "G",
		Attribute = "Frags",
		Start = 2,
		PerWave = 2,
		Max = 4,
		Fuse = 1.6,
		Speed = 48, -- throw speed along your aim (~25 studs aiming level, farther aiming up)
		Lift = 16, -- extra upward speed for an arc
		Radius = 13,
		DamageMult = 2.2, -- x a zombie's base health this wave at the center (half at the edge)
		SelfDamage = 30, -- to the thrower at the center (half at the edge): don't cook it at your feet
		Color = Color3.fromRGB(255, 120, 40),
		Cooldown = 0.6,
	},
	Lure = {
		Id = "Lure",
		DisplayName = "Maneki Lure",
		Key = "T",
		Attribute = "Lures",
		Start = 0,
		Max = 2,
		Cost = 1000,
		Speed = 55,
		Lift = 12,
		Duration = 7, -- seconds it calls zombies
		PullRadius = 75,
		Radius = 12, -- burst at the end
		DamageMult = 1.6,
		Color = Color3.fromRGB(255, 205, 90),
		Cooldown = 1,
	},
}

return ThrowableConfig
