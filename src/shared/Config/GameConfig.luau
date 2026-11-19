--!strict
-- Match-wide tuning: economy, timings, caps. Pure data, safe to read on client and server.

local GameConfig = {
	MaxPlayers = 4,

	-- Which layout in src/server/Maps to load ("Dustwater" or the old "ShrineDistrict" test map)
	ActiveMap = "Dustwater",

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

	-- Sprint stamina (client-side movement; the bar is on the HUD)
	Stamina = {
		Max = 100,
		DrainPerSecond = 24, -- ~4s of continuous sprint
		RegenPerSecond = 20,
		RegenDelay = 1.0, -- seconds after you stop sprinting
		MinToRestart = 25, -- once empty, must recover to this before sprinting again
		SwiftStepDrainMult = 0.6, -- Swift Step perk: sprint lasts longer
	},

	-- Knife (V)
	Melee = {
		Damage = 150, -- one-hit kills through wave 3
		Range = 6.5, -- studs from your head
		LungeRange = 9, -- client lunges toward targets this close
		LungeSpeed = 55,
		Cooldown = 0.7,
		KillPoints = 130,
	},

	-- M1 placeholder rule, now off: ammo comes from wall-buys and Max Ammo drops.
	RefillAmmoOnWaveEnd = false,

	MysteryBox = {
		Cost = 950,
		RollTime = 3.5, -- seconds of cycling
		TakeTime = 9, -- seconds the result is offered
		MinUsesBeforeMove = 4,
		MaxUsesBeforeMove = 8,
		MoveDelay = 4,
	},

	InteractCooldown = 0.3, -- per player, any station
}

return GameConfig
