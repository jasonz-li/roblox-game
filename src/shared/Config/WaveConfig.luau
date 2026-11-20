--!strict
-- Wave composition and difficulty formulas (see docs/GAME_DESIGN.md §4).
-- Tuned (2026-11-20): gentler first waves for new players, still a real climb.
-- The starting pistol falls off around wave 5-6; elites from wave 4.
--
--   wave:        1    3    5    8    10    15    20
--   zombies(1p): 8   14   20   29    35    50    65
--   health:     100  160  220  310   370   544   800
--   runners:     0%  15%  45%  80%   80%   80%   80%
--   zombie hit:  20   22   23   25    26    30    34   (player has 100 + regen)

local WaveConfig = {}

local PLAYER_MULTIPLIER = { 1, 1.5, 2, 2.5 }

function WaveConfig.EnemyCount(wave: number, playerCount: number): number
	local mult = PLAYER_MULTIPLIER[math.clamp(playerCount, 1, 4)]
	return math.floor((8 + 3 * (wave - 1)) * mult)
end

function WaveConfig.HealthMultiplier(wave: number): number
	if wave <= 10 then
		return 1 + 0.3 * (wave - 1)
	end
	return (1 + 0.3 * 9) * 1.08 ^ (wave - 10)
end

function WaveConfig.DamageMultiplier(wave: number): number
	return 1 + 0.04 * (wave - 1)
end

-- Share of enemies that run instead of walk.
function WaveConfig.RunnerChance(wave: number): number
	if wave < 3 then
		return 0
	end
	return math.clamp(0.15 * (wave - 2), 0, 0.8)
end

-- Seconds between spawns while below the alive cap.
function WaveConfig.SpawnInterval(wave: number): number
	return math.max(0.3, 1.2 - 0.08 * wave)
end

return WaveConfig
