--!strict
-- Sound asset IDs.
-- PLACEHOLDER audio: free Creator Store uploads by other users plus Roblox built-in
-- rbxasset:// sounds. All verified to load in Studio on 2026-11-19. Replace with
-- original/licensed audio before launch (see docs/ROADMAP.md placeholder table).

export type SoundDef = { Ids: { string }, Volume: number, PitchVariance: number? }

local SoundConfig: { [string]: SoundDef } = {
	-- Weapons (client, 2D for the shooter)
	RifleShot = { Ids = { "rbxassetid://113450029049580" }, Volume = 0.45, PitchVariance = 0.06 },
	Reload = { Ids = { "rbxassetid://132828889771041" }, Volume = 0.6 },
	DryFire = { Ids = { "rbxasset://sounds/clickfast.wav" }, Volume = 0.5 },

	-- Feedback (client, 2D)
	Hitmarker = { Ids = { "rbxasset://sounds/clickfast.wav" }, Volume = 0.35, PitchVariance = 0.1 },
	KillConfirm = { Ids = { "rbxasset://sounds/electronicpingshort.wav" }, Volume = 0.35 },
	PlayerHurt = { Ids = { "rbxasset://sounds/swordslash.wav" }, Volume = 0.5, PitchVariance = 0.1 },
	WaveStart = { Ids = { "rbxassetid://6891548543" }, Volume = 0.5 },
	WaveComplete = { Ids = { "rbxasset://sounds/electronicpingshort.wav" }, Volume = 0.6 },

	-- Enemies (server, 3D positional on the enemy)
	ZombieGroan = {
		Ids = { "rbxassetid://129294628821291", "rbxassetid://130156156621885", "rbxassetid://106129958887908" },
		Volume = 0.7,
		PitchVariance = 0.12,
	},
	ZombieAttack = { Ids = { "rbxasset://sounds/swordslash.wav" }, Volume = 0.8, PitchVariance = 0.15 },
}

return SoundConfig
