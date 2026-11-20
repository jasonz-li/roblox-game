--!strict
-- Match-wide tuning: economy, timings, caps. Pure data, safe to read on client and server.

local GameConfig = {
	MaxPlayers = 4,

	-- Which layout in src/server/Maps to load ("Dustwater" or the old "ShrineDistrict" test map)
	ActiveMap = "Dustwater",

	-- A run is a level: survive RunWaves waves; the last wave is a boss finale.
	Run = {
		Waves = 10,
		BossWave = 10,
		VictoryShards = 80, -- Spirit Shards for clearing the level (on top of per-wave shards)
	},

	-- Timings (seconds)
	FirstIntermission = 6,
	Intermission = 6, -- shorter breaks = faster pace
	GameOverDuration = 12,

	-- Points economy. Tightened (was Kill 80 / Headshot 130 / wave 100x): points were
	-- so plentiful that boarding windows was pointless. Early on, repairs now matter.
	Points = {
		Start = 500,
		Hit = 10,
		Kill = 50,
		HeadshotKill = 90,
		WaveCompleteBase = 50, -- x wave number
		WaveCompleteCap = 500,
	},

	-- Player
	Player = {
		WalkSpeed = 16,
		SprintSpeed = 25,
		MaxHealth = 100,
		-- Health regen: after this long without being hit, heal quickly back to full
		RegenDelay = 3.5,
		RegenPerSecond = 30, -- empty -> full in ~3.3s
	},

	-- Sprint stamina (client-side movement; the bar is on the HUD)
	Stamina = {
		Max = 100,
		DrainPerSecond = 12, -- ~8s of continuous sprint (was ~4s)
		RegenPerSecond = 30, -- empty -> full in ~3.3s
		RegenDelay = 0.6, -- seconds after you stop sprinting
		MinToRestart = 15, -- once empty, must recover to this before sprinting again
		SwiftStepDrainMult = 0.5, -- Swift Step perk: sprint lasts twice as long
	},

	-- Knife (V)
	Melee = {
		Damage = 150, -- one-hit kills through wave 3
		Range = 6.5, -- studs from your head
		LungeRange = 9, -- client lunges toward targets this close
		LungeSpeed = 55,
		Cooldown = 0.7,
		KillPoints = 100,
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

	-- Boarded windows (zombie entry points)
	Barrier = {
		Boards = 6,
		TearInterval = 1.5, -- seconds per board when a player is near: a full window holds ~9s
		TearIntervalUnwatched = 0.5, -- nobody within UnwatchedRange: they rip through (~3s)
		UnwatchedRange = 35,
		RepairInterval = 0.6, -- hold E: one board back every this many seconds
		RepairPoints = 15, -- per board rebuilt (big early on with the tighter economy)
		SealBonus = 50, -- extra for putting the LAST board back (window fully sealed)
		RepairPointsCapPerWave = 800, -- per player; only stops endless farming
		VaultTime = 0.6,
		BarrierSpawnChance = 0.7, -- windows are the main way in; ground spawns add other angles
	},
}

return GameConfig
