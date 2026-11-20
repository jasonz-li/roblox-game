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
}

local PerkConfig = {
	Perks = Perks,
	MaxPerks = 4,
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
