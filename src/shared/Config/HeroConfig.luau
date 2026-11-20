--!strict
-- Heroes (Milestone 3). Original characters, PLACEHOLDER visuals (neon parts).
-- Each hero: a passive, an ability (Q, cooldown) and an ultimate (F, charged by kills).
-- Ability damage is in "zombie healths" at the current wave (1.0 = kills a normal
-- zombie), so abilities stay useful as waves scale.
-- Until the gacha/lobby exist (M8/M9), every hero is free to pick between waves (H).

local WaveConfig = require(script.Parent.WaveConfig)

export type Hero = {
	Id: string,
	Name: string,
	Title: string,
	Color: Color3,
	Passive: string,
	Ability: { [string]: any },
	Ultimate: { [string]: any },
	KnifeMult: number?,
	UltChargeMult: number?,
}

local Heroes: { [string]: Hero } = {
	Swordsman = {
		Id = "Swordsman",
		Name = "Ren",
		Title = "Storm Blade",
		Color = Color3.fromRGB(110, 200, 255),
		Passive = "Knife deals +60% damage",
		KnifeMult = 1.6,
		Ability = {
			Name = "Gale Step",
			Desc = "Dash forward, slashing every zombie in your path",
			Cooldown = 8,
			Range = 22, -- studs
			Width = 4.5, -- hit radius around the dash line
			Damage = 1.3,
		},
		Ultimate = {
			Name = "Tempest",
			Desc = "Four cyclone slashes tear through everything around you",
			Pulses = 4,
			Interval = 0.4,
			Radius = 17,
			Damage = 0.75, -- per pulse
		},
	},
	Mage = {
		Id = "Mage",
		Name = "Yuki",
		Title = "Frost Oracle",
		Color = Color3.fromRGB(190, 140, 255),
		Passive = "Ultimate charges 30% faster",
		UltChargeMult = 1.3,
		Ability = {
			Name = "Frost Nova",
			Desc = "Freeze-burst around you: damages and slows zombies",
			Cooldown = 12,
			Radius = 16,
			Damage = 0.5,
			Slow = 0.3, -- move at 30% speed
			SlowTime = 3.5,
		},
		Ultimate = {
			Name = "Starfall",
			Desc = "Call a star down where you aim",
			Range = 160,
			Radius = 19,
			Delay = 0.9,
			Damage = 3.2,
		},
	},
}

local HeroConfig = {
	Heroes = Heroes,
	Order = { "Swordsman", "Mage" },
	Default = "Swordsman",
	Ult = {
		Max = 100,
		KillCharge = 4,
		HeadshotKillCharge = 6,
		EliteKillCharge = 20,
	},
}

-- Damage for an ability multiplier at a given wave.
function HeroConfig.Damage(mult: number, wave: number): number
	return 100 * mult * WaveConfig.HealthMultiplier(math.max(1, wave))
end

function HeroConfig.Get(id: string?): Hero
	return Heroes[id or ""] or Heroes[HeroConfig.Default]
end

return HeroConfig
