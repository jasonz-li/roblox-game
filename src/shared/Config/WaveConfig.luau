--!strict
-- Wave composition and difficulty formulas (see docs/GAME_DESIGN.md §4).
-- Tuned (2026-11-19) for a faster, harder game: the starting pistol falls off
-- around wave 4-5, so buying guns/perks/the Forge matters.
--
--   wave:        1    3    5    8    10    15    20
--   zombies(1p): 8   16   24   36    44    64    84
--   health:     100  170  240  345   415   610   900
--   runners:     0%  40%  80%  90%   90%   90%   90%

local WaveConfig = {}

local PLAYER_MULTIPLIER = { 1, 1.5, 2, 2.5 }

function WaveConfig.EnemyCount(wave: number, playerCount: number): number
	local mult = PLAYER_MULTIPLIER[math.clamp(playerCount, 1, 4)]
	return math.floor((8 + 4 * (wave - 1)) * mult)
end

function WaveConfig.HealthMultiplier(wave: number): number
	if wave <= 10 then
		return 1 + 0.35 * (wave - 1)
	end
	return (1 + 0.35 * 9) * 1.08 ^ (wave - 10)
end

function WaveConfig.DamageMultiplier(wave: number): number
	return 1 + 0.08 * (wave - 1)
end

-- Share of enemies that run instead of walk.
function WaveConfig.RunnerChance(wave: number): number
	if wave < 2 then
		return 0
	end
	return math.clamp(0.2 * (wave - 1), 0, 0.9)
end

-- Seconds between spawns while below the alive cap.
function WaveConfig.SpawnInterval(wave: number): number
	return math.max(0.25, 1.1 - 0.08 * wave)
end

return WaveConfig
