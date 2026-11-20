--!strict
-- Power-up drops from player kills (zombies-style).

export type PowerUp = { Id: string, DisplayName: string, Color: Color3, Weight: number, Duration: number? }

local PowerUps: { [string]: PowerUp } = {
	MaxAmmo = { Id = "MaxAmmo", DisplayName = "MAX AMMO", Color = Color3.fromRGB(120, 255, 140), Weight = 30 },
	DoublePoints = { Id = "DoublePoints", DisplayName = "DOUBLE POINTS", Color = Color3.fromRGB(255, 220, 80), Weight = 30, Duration = 30 },
	InstaKill = { Id = "InstaKill", DisplayName = "INSTA-KILL", Color = Color3.fromRGB(255, 70, 90), Weight = 25, Duration = 15 }, -- (was 30: too strong); never works on the Titan
	Nuke = { Id = "Nuke", DisplayName = "NUKE", Color = Color3.fromRGB(255, 140, 40), Weight = 15 },
}

return {
	PowerUps = PowerUps,
	DropChance = 0.03, -- per player kill
	MaxDropsPerWave = 4,
	MinSecondsBetweenDrops = 8,
	Lifetime = 20, -- seconds on the ground
	NukePoints = 400,
}
