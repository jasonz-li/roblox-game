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
	DamageTakenMult: number?,
	Shatter: { [string]: any }?,
	Aura: { [string]: any }?,
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
	-- Reworked (2026-11-20): "freeze, then shatter". Frost Nova/Starfall felt weak.
	Mage = {
		Id = "Mage",
		Name = "Yuki",
		Title = "Frost Oracle",
		Color = Color3.fromRGB(150, 210, 255),
		Passive = "Shatter: frozen zombies take +50% damage and burst when killed",
		Shatter = { Radius = 7, Damage = 0.4 }, -- blast when a frozen zombie dies (was 0.5)
		Ability = {
			Name = "Glacial Lance",
			Desc = "Piercing ice spear where you aim: damages the whole line and freezes survivors",
			Cooldown = 9,
			Range = 70,
			Width = 3.5, -- hit radius around the spear's line
			Damage = 1.0,
			Freeze = 2.5, -- seconds frozen solid
		},
		Ultimate = {
			Name = "Absolute Zero",
			Desc = "A blizzard follows you: everything inside is battered and frozen",
			-- nerfed after playtest ("too broken"): was 6s / r18 / 0.2 dmg / 1.2s freeze
			Duration = 5,
			Interval = 0.5,
			Radius = 14,
			Damage = 0.12, -- per pulse
			Freeze = 0.9,
		},
	},
}

-- Co-op roles (up to 4 players): Ren = melee damage, Yuki = crowd control,
-- Kaida = tank, Mio = support.
Heroes.Tank = {
	Id = "Tank",
	Name = "Kaida",
	Title = "Iron Bastion",
	Color = Color3.fromRGB(255, 170, 70),
	Passive = "Takes 25% less damage",
	DamageTakenMult = 0.75,
	Ability = {
		Name = "War Cry",
		Desc = "Zombies nearby come for you, and you take half damage meanwhile",
		Cooldown = 14,
		Radius = 35,
		Duration = 5,
		DamageTakenMult = 0.5, -- on top of the passive while it lasts
	},
	Ultimate = {
		Name = "Fortress",
		Desc = "A dome zombies can't enter; everyone inside heals",
		Duration = 8,
		Radius = 12,
		HealPerSecond = 15,
	},
}

Heroes.Medic = {
	Id = "Medic",
	Name = "Mio",
	Title = "Spirit Warden",
	Color = Color3.fromRGB(140, 255, 190),
	Passive = "Mending Aura: allies near you (and you) slowly heal at all times",
	Aura = { Radius = 22, HealPerSecond = 4 },
	Ability = {
		Name = "Spirit Pulse",
		Desc = "Heal everyone near you and give them a burst of speed",
		Cooldown = 12,
		Radius = 25,
		Heal = 50,
		HasteMult = 1.3,
		HasteTime = 4,
	},
	Ultimate = {
		Name = "Kitsune Guardian",
		Desc = "A spirit fox fights beside you, zapping the nearest zombie",
		Duration = 10,
		Interval = 0.3,
		Range = 45,
		Damage = 0.35, -- per zap
	},
}

local HeroConfig = {
	Heroes = Heroes,
	Order = { "Swordsman", "Mage", "Tank", "Medic" },
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
