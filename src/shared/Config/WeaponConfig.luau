--!strict
-- Weapon stat tables. The server uses these as the source of truth; the client
-- uses the same values only for prediction and feedback.

export type WeaponStats = {
	Id: string,
	DisplayName: string,
	Class: string,
	FireMode: "Auto" | "Semi",
	Damage: number,
	HeadshotMultiplier: number,
	RPM: number, -- rounds per minute
	MagSize: number,
	ReserveAmmo: number,
	ReloadTime: number,
	Range: number,
	HipSpread: number, -- degrees
	AdsSpread: number,
	RecoilKick: number, -- camera pitch kick per shot (degrees)
	RecoilSide: number,
	AdsFov: number,
}

local Weapons: { [string]: WeaponStats } = {
	StarterRifle = {
		Id = "StarterRifle",
		DisplayName = "PLACEHOLDER Rifle",
		Class = "AssaultRifle",
		FireMode = "Auto",
		Damage = 34,
		HeadshotMultiplier = 2.0,
		RPM = 600,
		MagSize = 30,
		ReserveAmmo = 180,
		ReloadTime = 2.0,
		Range = 600,
		HipSpread = 1.6,
		AdsSpread = 0.25,
		RecoilKick = 0.55,
		RecoilSide = 0.25,
		AdsFov = 55,
	},
}

local WeaponConfig = {
	Weapons = Weapons,
	Default = "StarterRifle",
}

function WeaponConfig.Get(id: string): WeaponStats?
	return Weapons[id]
end

return WeaponConfig
