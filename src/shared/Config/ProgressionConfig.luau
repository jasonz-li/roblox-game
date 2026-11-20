--!strict
-- In-run progression: kill streaks, upgrade picks between waves, elite zombies.
-- Upgrade counts live on the player as attributes (Upg_<Id> = stacks), set only by
-- the server; the helpers below are read by both server (enforcement) and client
-- (prediction: fire rate, reload, stamina, HUD).
-- Upgrades last the whole run (they survive going down) and reset on game over.

export type Upgrade = {
	Id: string,
	Name: string,
	Desc: string,
	Max: number,
	Color: Color3,
}

local Upgrades: { [string]: Upgrade } = {
	HollowPoints = { Id = "HollowPoints", Name = "Hollow Points", Desc = "+15% gun damage", Max = 5, Color = Color3.fromRGB(255, 120, 80) },
	Deadeye = { Id = "Deadeye", Name = "Deadeye", Desc = "+35% headshot damage", Max = 3, Color = Color3.fromRGB(255, 70, 90) },
	Bounty = { Id = "Bounty", Name = "Bounty Hunter", Desc = "+20% points from kills", Max = 3, Color = Color3.fromRGB(255, 220, 90) },
	Vitality = { Id = "Vitality", Name = "Vitality", Desc = "+25 max health", Max = 4, Color = Color3.fromRGB(110, 255, 160) },
	SecondWind = { Id = "SecondWind", Name = "Second Wind", Desc = "+40% stamina and regen", Max = 3, Color = Color3.fromRGB(80, 220, 255) },
	FastHands = { Id = "FastHands", Name = "Fast Hands", Desc = "Reload 12% faster", Max = 3, Color = Color3.fromRGB(120, 255, 120) },
	TriggerHappy = { Id = "TriggerHappy", Name = "Trigger Happy", Desc = "+8% fire rate", Max = 3, Color = Color3.fromRGB(255, 180, 60) },
	BladeDancer = { Id = "BladeDancer", Name = "Blade Dancer", Desc = "+75% knife damage", Max = 3, Color = Color3.fromRGB(200, 160, 255) },
	Bloodthirst = { Id = "Bloodthirst", Name = "Bloodthirst", Desc = "Heal 6 HP per kill", Max = 3, Color = Color3.fromRGB(220, 40, 70) },
	Momentum = { Id = "Momentum", Name = "Momentum", Desc = "Streaks last 1.5s longer", Max = 2, Color = Color3.fromRGB(255, 80, 170) },
}

local ProgressionConfig = {
	Upgrades = Upgrades,
	Offer = {
		EveryWaves = 2, -- after waves 2, 4, 6...
		Choices = 3,
		Seconds = 15, -- auto-picks at random if you don't choose
		ExtraIntermission = 5, -- longer break on pick waves
	},
	Streak = {
		Window = 3.5, -- seconds to land the next kill
		PerKill = 0.1, -- +0.1x per streak point
		HeadshotPoints = 2, -- headshot kills count double
		MaxMult = 2.5,
		BreakOnHit = true, -- getting hit by a zombie ends the streak
		-- Milestones pay Spirit Shards (saved, for the gacha) and in-run rewards.
		-- Past the last one, every RepeatEvery more kills pays RepeatShards again.
		Milestones = {
			{ At = 10, Shards = 5, Uav = 20, Label = "UAV ONLINE" },
			{ At = 20, Shards = 12, Uav = 30, Label = "ADVANCED UAV" },
			{ At = 30, Shards = 25, Label = "UNSTOPPABLE" },
			{ At = 50, Shards = 50, Label = "LEGENDARY" },
		},
		RepeatEvery = 25,
		RepeatShards = 50,
	},
	-- Spirit Shards from a run (besides streaks)
	Rewards = {
		ShardsPerWaveSurvived = 2,
		ShardsPerElite = 3,
	},
	-- Minimap radar: a sweep shows every zombie briefly; a streak UAV shows them live.
	Uav = {
		SweepEvery = 12, -- seconds between free sweeps
		SweepShows = 3, -- seconds the dots stay visible after a sweep
	},
	Elite = {
		StartWave = 3,
		BaseChance = 0.06, -- per spawn at StartWave
		ChancePerWave = 0.01,
		MaxChance = 0.15,
		EliteWaveEvery = 5, -- every 5th wave: triple the chance
		HealthMult = 4,
		DamageMult = 1.5,
		Scale = 1.35,
		Points = 300, -- bonus to the killer
		DropPowerUp = true,
	},
}

function ProgressionConfig.Count(player: Player, id: string): number
	return (player:GetAttribute("Upg_" .. id) :: number?) or 0
end

local count = ProgressionConfig.Count

function ProgressionConfig.DamageMult(player: Player): number
	return 1 + 0.15 * count(player, "HollowPoints")
end

function ProgressionConfig.HeadshotMult(player: Player): number
	return 1 + 0.35 * count(player, "Deadeye")
end

function ProgressionConfig.PointsMult(player: Player): number
	return 1 + 0.2 * count(player, "Bounty")
end

function ProgressionConfig.BonusHealth(player: Player): number
	return 25 * count(player, "Vitality")
end

function ProgressionConfig.StaminaMult(player: Player): number
	return 1 + 0.4 * count(player, "SecondWind")
end

function ProgressionConfig.ReloadMult(player: Player): number
	return 0.88 ^ count(player, "FastHands")
end

function ProgressionConfig.RpmMult(player: Player): number
	return 1 + 0.08 * count(player, "TriggerHappy")
end

function ProgressionConfig.KnifeMult(player: Player): number
	return 1 + 0.75 * count(player, "BladeDancer")
end

function ProgressionConfig.HealPerKill(player: Player): number
	return 6 * count(player, "Bloodthirst")
end

function ProgressionConfig.StreakWindow(player: Player): number
	return ProgressionConfig.Streak.Window + 1.5 * count(player, "Momentum")
end

function ProgressionConfig.EliteChance(wave: number): number
	local e = ProgressionConfig.Elite
	if wave < e.StartWave then
		return 0
	end
	local c = math.min(e.MaxChance, e.BaseChance + e.ChancePerWave * (wave - e.StartWave))
	if wave % e.EliteWaveEvery == 0 then
		c *= 3
	end
	return c
end

function ProgressionConfig.IsEliteWave(wave: number): boolean
	return wave >= ProgressionConfig.Elite.StartWave and wave % ProgressionConfig.Elite.EliteWaveEvery == 0
end

return ProgressionConfig
