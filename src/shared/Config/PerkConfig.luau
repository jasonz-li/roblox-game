--!strict
-- Perk machines. Effects are applied server-side (PerkService/WeaponService);
-- the client reads the same multipliers for prediction (fire rate, reload, speed).
-- Perks are lost on death.

export type Perk = {
	Id: string,
	DisplayName: string,
	Description: string,
	Cost: number,
	Color: Color3,
	Letter: string,
}

local Perks: { [string]: Perk } = {
	IronBody = {
		Id = "IronBody", DisplayName = "Iron Body", Description = "Max health 100 → 250",
		Cost = 2500, Color = Color3.fromRGB(230, 60, 60), Letter = "I",
	},
	QuickHands = {
		Id = "QuickHands", DisplayName = "Quick Hands", Description = "Reload 50% faster",
		Cost = 2000, Color = Color3.fromRGB(80, 220, 120), Letter = "Q",
	},
	RapidFire = {
		Id = "RapidFire", DisplayName = "Rapid Fire", Description = "Fire rate +33%",
		Cost = 2000, Color = Color3.fromRGB(255, 190, 60), Letter = "R",
	},
	SwiftStep = {
		Id = "SwiftStep", DisplayName = "Swift Step", Description = "Move speed +12%",
		Cost = 1500, Color = Color3.fromRGB(80, 200, 255), Letter = "S",
	},
	-- Game-changers: strong enough to feel broken, each with a catch.
	StormCoil = {
		Id = "StormCoil", DisplayName = "Storm Coil", Description = "Reloading unleashes a lightning nova (emptier mag = bigger)",
		Cost = 2000, Color = Color3.fromRGB(110, 180, 255), Letter = "C",
	},
	Phoenix = {
		Id = "Phoenix", DisplayName = "Phoenix Draught", Description = "A killing blow revives you in a firestorm (one use)",
		Cost = 1500, Color = Color3.fromRGB(255, 120, 40), Letter = "P",
	},
	PackMule = {
		Id = "PackMule", DisplayName = "Pack Mule Tonic", Description = "Carry a third weapon [3]",
		Cost = 3000, Color = Color3.fromRGB(140, 220, 90), Letter = "M",
	},
	Hawkeye = {
		Id = "Hawkeye", DisplayName = "Hawkeye Elixir", Description = "+50% headshot damage, half hip-fire spread",
		Cost = 2000, Color = Color3.fromRGB(240, 240, 255), Letter = "H",
	},
}

local PerkConfig = {
	Perks = Perks,
	MaxPerks = 6,
	HawkeyeHeadMult = 1.5,
	HawkeyeSpreadMult = 0.5,
	IronBodyHealth = 250,
	QuickHandsReloadMult = 0.5,
	RapidFireRpmMult = 1.33,
	SwiftStepSpeedMult = 1.12,
}

function PerkConfig.AttributeName(perkId: string): string
	return "Perk_" .. perkId
end

-- Helpers shared by client prediction and server enforcement.
-- They also fold in the run's upgrade picks (ProgressionConfig).
local ProgressionConfig = require(script.Parent.ProgressionConfig)

function PerkConfig.ReloadMultiplier(player: Player): number
	return (player:GetAttribute("Perk_QuickHands") and PerkConfig.QuickHandsReloadMult or 1) * ProgressionConfig.ReloadMult(player)
end

function PerkConfig.RpmMultiplier(player: Player): number
	return (player:GetAttribute("Perk_RapidFire") and PerkConfig.RapidFireRpmMult or 1) * ProgressionConfig.RpmMult(player)
end

function PerkConfig.SpeedMultiplier(player: Player): number
	return player:GetAttribute("Perk_SwiftStep") and PerkConfig.SwiftStepSpeedMult or 1
end

return PerkConfig
