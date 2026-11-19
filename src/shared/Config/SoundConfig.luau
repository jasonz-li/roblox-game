--!strict
-- Sound asset IDs.
-- PLACEHOLDER audio: free Creator Store uploads by other users plus Roblox built-in
-- rbxasset:// sounds. All verified to load in Studio on 2026-11-19. Replace with
-- original/licensed audio before launch (see docs/ROADMAP.md placeholder table).

export type SoundDef = { Ids: { string }, Volume: number, PitchVariance: number? }

local SoundConfig: { [string]: SoundDef } = {
	-- Weapons (client, 2D for the shooter)
	-- Main gunshot. Pick the recording in-game with F6 (see GunshotCandidates below).
	RifleShot = { Ids = { "rbxassetid://107457358196366" }, Volume = 0.3, PitchVariance = 0.05 },
	HeavyShot = { Ids = { "rbxassetid://6975483207" }, Volume = 0.4, PitchVariance = 0.04 },
	-- Low "thump" layered under every shot for weight (toggle in-game with F7)
	ShotThump = { Ids = { "rbxassetid://9113632382" }, Volume = 0.1, PitchVariance = 0.08 },
	ShotgunShot = { Ids = { "rbxassetid://113543931016554" }, Volume = 0.35, PitchVariance = 0.05 },
	LaserShot = { Ids = { "rbxassetid://4400449399" }, Volume = 0.35, PitchVariance = 0.05 },
	WeaponSwitch = { Ids = { "rbxasset://sounds/clickfast.wav" }, Volume = 0.4 },

	-- Economy / map (Pro Sound Effects + APM: Roblox-licensed library audio)
	Purchase = { Ids = { "rbxassetid://9113728042" }, Volume = 0.5 },
	Denied = { Ids = { "rbxasset://sounds/clickfast.wav" }, Volume = 0.6, PitchVariance = 0 },
	DoorOpen = { Ids = { "rbxassetid://9120805690" }, Volume = 0.7 },
	BoxJingle = { Ids = { "rbxassetid://9042730928" }, Volume = 0.45 },
	PerkDrink = { Ids = { "rbxassetid://9042730364" }, Volume = 0.4 },
	PowerUp = { Ids = { "rbxassetid://9042730364" }, Volume = 0.55 },
	Nuke = { Ids = { "rbxassetid://138533090376585" }, Volume = 0.8 },
	Reload = { Ids = { "rbxassetid://132828889771041" }, Volume = 0.6 },
	DryFire = { Ids = { "rbxasset://sounds/clickfast.wav" }, Volume = 0.5 },

	-- Feedback (client, 2D)
	-- Hit feedback: a crisp tick on every confirmed hit + a wet flesh layer, a ding for headshots
	Hitmarker = { Ids = { "rbxasset://sounds/clickfast.wav" }, Volume = 0.6, PitchVariance = 0.05 },
	HitFlesh = { Ids = { "rbxassetid://9116197520", "rbxassetid://9116197517" }, Volume = 0.28, PitchVariance = 0.15 },
	HeadshotDing = { Ids = { "rbxasset://sounds/electronicpingshort.wav" }, Volume = 0.5, PitchVariance = 0.03 },
	KillConfirm = { Ids = { "rbxasset://sounds/electronicpingshort.wav" }, Volume = 0.4 },

	-- Knife
	KnifeSwing = { Ids = { "rbxasset://sounds/swordslash.wav" }, Volume = 0.6, PitchVariance = 0.1 },
	KnifeHit = { Ids = { "rbxassetid://9116197520", "rbxassetid://9116197517" }, Volume = 0.8, PitchVariance = 0.1 },
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
