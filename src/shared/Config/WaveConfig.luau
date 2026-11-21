--!strict
-- Wave composition and difficulty formulas (see docs/GAME_DESIGN.md §4).
-- Tuned (2026-11-20) for a 10-wave level: a gentle start, a steep climb, wave 5 is an
-- Elite Wave and wave 10 is the Dust Titan boss finale (plus an escort).
--
--   wave:        1    2    3    5    7    9    10 (boss)
--   zombies(1p): 10   14   18   26   34   42   20 + Titan
--   health:     100  155  210  320  430  540  595
--   runners:     0%  10%  20%  40%  60%  80%  80%
--   zombie hit:  20   21   22   25   27   30   31

local WaveConfig = {}

local PLAYER_MULTIPLIER = { 1, 1.5, 2, 2.5 }

function WaveConfig.EnemyCount(wave: number, playerCount: number): number
	local mult = PLAYER_MULTIPLIER[math.clamp(playerCount, 1, 4)]
	if wave >= 10 then
		return math.floor(20 * mult) -- boss wave: the Titan's escort
	end
	return math.floor((10 + 4 * (wave - 1)) * mult)
end

function WaveConfig.HealthMultiplier(wave: number): number
	return 1 + 0.55 * (wave - 1)
end

function WaveConfig.DamageMultiplier(wave: number): number
	return 1 + 0.06 * (wave - 1)
end

-- Share of enemies that run instead of walk.
function WaveConfig.RunnerChance(wave: number): number
	if wave < 2 then
		return 0
	end
	return math.clamp(0.1 * (wave - 1), 0, 0.8)
end

-- How many of a wave's zombies may be alive at once. Keeping most of the wave
-- queued means a Nuke clears the current group but never wins the round outright
-- (zombies-style); the rest keep coming.
function WaveConfig.AliveCap(total: number): number
	return math.clamp(math.ceil(total * 0.6), 8, 24) -- (was 40%: too much downtime)
end

-- Special zombie mix: chance per spawn of each type, by the wave it starts.
--   wave 3: crawlers   4: brutes   5: spitters   6: exploders
--   ~10% specials at wave 3 climbing to ~40% at wave 9
local SPECIALS = {
	{ id = "Crawler", from = 3, base = 0.08, per = 0.01, max = 0.14 },
	{ id = "Brute", from = 4, base = 0.04, per = 0.01, max = 0.08 },
	{ id = "Spitter", from = 5, base = 0.06, per = 0.01, max = 0.10 },
	{ id = "Exploder", from = 6, base = 0.06, per = 0.01, max = 0.09 },
}
-- At most this many of a type alive at once (a wall of brutes isn't fun)
WaveConfig.SpecialAliveCap = { Crawler = 6, Brute = 2, Spitter = 3, Exploder = 3 }

function WaveConfig.PickEnemy(wave: number, aliveOf: (string) -> number): string
	if wave >= 10 then
		return "Shambler"
	end
	local roll = math.random()
	for _, s in SPECIALS do
		if wave >= s.from then
			local chance = math.min(s.max, s.base + s.per * (wave - s.from))
			if roll < chance then
				if aliveOf(s.id) < (WaveConfig.SpecialAliveCap[s.id] or 99) then
					return s.id
				end
				return "Shambler"
			end
			roll -= chance
		end
	end
	return "Shambler"
end

-- Last N zombies of a wave (nothing left to spawn) go into hunt mode.
WaveConfig.HuntWhenRemaining = 3

-- Seconds between spawns while below the alive cap: a zombies-style trickle that
-- speeds up each wave (a bit faster than classic pacing). WaveService adds ±25%
-- jitter so arrivals don't feel mechanical.
--   wave 1: 0.9s   wave 5: 0.66s   wave 10: 0.36s   (was 1.5s -> 0.5s: too much downtime)
function WaveConfig.SpawnInterval(wave: number): number
	return math.max(0.35, 0.9 - 0.06 * (wave - 1))
end

-- Quiet beat at the start of each wave before the first zombie arrives.
WaveConfig.WaveStartDelay = 1

return WaveConfig
