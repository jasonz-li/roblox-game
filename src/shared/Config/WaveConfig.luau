--!strict
-- Wave composition and difficulty formulas (see docs/GAME_DESIGN.md §4).

local WaveConfig = {}

local PLAYER_MULTIPLIER = { 1, 1.5, 2, 2.5 }

function WaveConfig.EnemyCount(wave: number, playerCount: number): number
	local mult = PLAYER_MULTIPLIER[math.clamp(playerCount, 1, 4)]
	return math.floor((6 + 3 * (wave - 1)) * mult)
end

function WaveConfig.HealthMultiplier(wave: number): number
	if wave <= 10 then
		return 1 + 0.2 * (wave - 1)
	end
	return (1 + 0.2 * 9) * 1.08 ^ (wave - 10)
end

function WaveConfig.DamageMultiplier(wave: number): number
	return 1 + 0.05 * (wave - 1)
end

-- Share of enemies that run instead of walk.
function WaveConfig.RunnerChance(wave: number): number
	if wave < 4 then
		return 0
	end
	return math.clamp(0.15 * (wave - 3), 0, 0.85)
end

-- Seconds between spawns while below the alive cap.
function WaveConfig.SpawnInterval(wave: number): number
	return math.max(0.35, 1.6 - 0.1 * wave)
end

return WaveConfig
