--!strict
-- Match-wide tuning: economy, timings, caps. Pure data, safe to read on client and server.

local GameConfig = {
	MaxPlayers = 4,

	-- Timings (seconds)
	FirstIntermission = 10,
	Intermission = 8,
	GameOverDuration = 10,

	-- Points economy
	Points = {
		Start = 500,
		Hit = 10,
		Kill = 60,
		HeadshotKill = 100,
		WaveCompleteBase = 50, -- x wave number
		WaveCompleteCap = 1000,
	},

	-- Player
	Player = {
		WalkSpeed = 16,
		SprintSpeed = 23,
		MaxHealth = 100,
	},

	-- Max ammo refill at the end of each wave (PLACEHOLDER rule until ammo purchases exist in M2)
	RefillAmmoOnWaveEnd = true,
}

return GameConfig
