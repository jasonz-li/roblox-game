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
	Rarity: string, -- "Common" | "Rare" | "Legendary" | "Cursed"
}

local C = Color3.fromRGB
local Upgrades: { [string]: Upgrade } = {
	-- COMMON: solid stat boosts
	HollowPoints = { Id = "HollowPoints", Rarity = "Common", Name = "Hollow Points", Desc = "+20% gun damage", Max = 5, Color = C(255, 120, 80) },
	Deadeye = { Id = "Deadeye", Rarity = "Common", Name = "Deadeye", Desc = "+40% headshot damage", Max = 3, Color = C(255, 70, 90) },
	Bounty = { Id = "Bounty", Rarity = "Common", Name = "Bounty Hunter", Desc = "+25% points from kills", Max = 3, Color = C(255, 220, 90) },
	Vitality = { Id = "Vitality", Rarity = "Common", Name = "Vitality", Desc = "+25 max health", Max = 4, Color = C(110, 255, 160) },
	SecondWind = { Id = "SecondWind", Rarity = "Common", Name = "Second Wind", Desc = "+40% stamina and regen", Max = 3, Color = C(80, 220, 255) },
	FastHands = { Id = "FastHands", Rarity = "Common", Name = "Fast Hands", Desc = "Reload 15% faster", Max = 3, Color = C(120, 255, 120) },
	TriggerHappy = { Id = "TriggerHappy", Rarity = "Common", Name = "Trigger Happy", Desc = "+10% fire rate", Max = 3, Color = C(255, 180, 60) },
	BladeDancer = { Id = "BladeDancer", Rarity = "Common", Name = "Blade Dancer", Desc = "+75% knife damage", Max = 3, Color = C(200, 160, 255) },
	Bloodthirst = { Id = "Bloodthirst", Rarity = "Common", Name = "Bloodthirst", Desc = "Heal 6 HP per kill", Max = 3, Color = C(220, 40, 70) },
	Momentum = { Id = "Momentum", Rarity = "Common", Name = "Momentum", Desc = "Streaks last 1.5s longer", Max = 2, Color = C(255, 80, 170) },

	-- RARE: change how you play
	Volatile = { Id = "Volatile", Rarity = "Rare", Name = "Volatile Rounds", Desc = "Your kills explode, damaging zombies nearby", Max = 2, Color = C(255, 140, 40) },
	Ricochet = { Id = "Ricochet", Rarity = "Rare", Name = "Ricochet", Desc = "Headshots bounce to another zombie (+1 per rank)", Max = 3, Color = C(120, 220, 255) },
	Adrenaline = { Id = "Adrenaline", Rarity = "Rare", Name = "Adrenaline", Desc = "Kills give +20% move speed for 3s", Max = 2, Color = C(120, 255, 200) },
	Scavenger = { Id = "Scavenger", Rarity = "Rare", Name = "Scavenger", Desc = "Kills have a 30% chance to load 3 rounds", Max = 2, Color = C(220, 200, 140) },
	VampiricEdge = { Id = "VampiricEdge", Rarity = "Rare", Name = "Vampiric Edge", Desc = "Knife kills heal 25 HP and cut your ability cooldown by 2s", Max = 2, Color = C(200, 30, 80) },

	-- LEGENDARY: run-defining
	ChainReaction = { Id = "ChainReaction", Rarity = "Legendary", Name = "Chain Reaction", Desc = "Explosion kills explode too, and blasts are 40% bigger", Max = 1, Color = C(255, 90, 30) },
	Executioner = { Id = "Executioner", Rarity = "Legendary", Name = "Executioner", Desc = "Zombies under 25% health die to any hit", Max = 1, Color = C(255, 40, 60) },
	SecondChance = { Id = "SecondChance", Rarity = "Legendary", Name = "Second Chance", Desc = "Once per wave, a lethal hit instead heals you and blasts everything near you", Max = 1, Color = C(255, 230, 120) },
	Overclock = { Id = "Overclock", Rarity = "Legendary", Name = "Overclock", Desc = "Ability cooldown -40%, ultimate charges 50% faster", Max = 1, Color = C(160, 120, 255) },

	-- CURSED: big upside, real cost
	GlassCannon = { Id = "GlassCannon", Rarity = "Cursed", Name = "Glass Cannon", Desc = "+80% gun damage, but -40 max health", Max = 1, Color = C(180, 60, 255) },
	MidasCurse = { Id = "MidasCurse", Rarity = "Cursed", Name = "Midas Curse", Desc = "+75% points from kills, but health regen takes twice as long", Max = 1, Color = C(255, 200, 40) },
}

local ProgressionConfig = {
	Upgrades = Upgrades,
	Offer = {
		EveryWaves = 1, -- a pick after every wave (9 per 10-wave run)
		Choices = 3,
		Seconds = 12, -- auto-picks at random if you don't choose
		ExtraIntermission = 3, -- a little more break time to choose
	},
	-- Per-card rarity roll. Legendary odds grow +1 per wave.
	Rarity = {
		Weights = { Common = 60, Rare = 30, Legendary = 6, Cursed = 6 },
		LegendaryPerWave = 1,
		Colors = { Common = C(200, 200, 210), Rare = C(80, 170, 255), Legendary = C(255, 190, 40), Cursed = C(190, 70, 255) },
	},
	Streak = {
		Window = 3.5, -- seconds to land the next kill
		PerKill = 0.08, -- +0.08x per streak point
		HeadshotPoints = 2, -- headshot kills count double
		MaxMult = 2.0,
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
		DropChance = 0.35, -- (was a guaranteed drop: too many free power-ups)
		DropPool = { "MaxAmmo", "DoublePoints" }, -- elites never drop Insta-Kill or Nuke
	},
}

function ProgressionConfig.Count(player: Player, id: string): number
	return (player:GetAttribute("Upg_" .. id) :: number?) or 0
end

local count = ProgressionConfig.Count

function ProgressionConfig.DamageMult(player: Player): number
	return (1 + 0.2 * count(player, "HollowPoints")) * (count(player, "GlassCannon") > 0 and 1.8 or 1)
end

function ProgressionConfig.HeadshotMult(player: Player): number
	return 1 + 0.4 * count(player, "Deadeye")
end

function ProgressionConfig.PointsMult(player: Player): number
	return (1 + 0.25 * count(player, "Bounty")) * (count(player, "MidasCurse") > 0 and 1.75 or 1)
end

function ProgressionConfig.BonusHealth(player: Player): number
	return 25 * count(player, "Vitality") - (count(player, "GlassCannon") > 0 and 40 or 0)
end

-- Seconds before health regen starts (Midas Curse doubles it)
function ProgressionConfig.RegenDelayMult(player: Player): number
	return count(player, "MidasCurse") > 0 and 2 or 1
end

-- Ability cooldown / ultimate charge (Overclock)
function ProgressionConfig.CooldownMult(player: Player): number
	return count(player, "Overclock") > 0 and 0.6 or 1
end

function ProgressionConfig.UltChargeMult(player: Player): number
	return count(player, "Overclock") > 0 and 1.5 or 1
end

-- Move-speed multiplier while Adrenaline is active (client reads AdrenalineUntil)
function ProgressionConfig.AdrenalineMult(player: Player): number
	local n = count(player, "Adrenaline")
	if n == 0 then
		return 1
	end
	local untilT = (player:GetAttribute("AdrenalineUntil") :: number?) or 0
	return workspace:GetServerTimeNow() < untilT and (1 + 0.2 * n) or 1
end

-- Explosion radius multiplier (Chain Reaction)
function ProgressionConfig.BlastRadiusMult(player: Player): number
	return count(player, "ChainReaction") > 0 and 1.4 or 1
end

function ProgressionConfig.StaminaMult(player: Player): number
	return 1 + 0.4 * count(player, "SecondWind")
end

function ProgressionConfig.ReloadMult(player: Player): number
	return 0.85 ^ count(player, "FastHands")
end

function ProgressionConfig.RpmMult(player: Player): number
	return 1 + 0.1 * count(player, "TriggerHappy")
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
