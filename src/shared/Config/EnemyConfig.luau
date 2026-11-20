--!strict
-- Enemy archetypes. Visuals are PLACEHOLDER block models built in EnemyService.

export type EnemyStats = {
	Id: string,
	DisplayName: string,
	BaseHealth: number,
	WalkSpeed: number,
	RunSpeed: number,
	Damage: number,
	AttackRange: number,
	AttackCooldown: number,
	AttackWindup: number,
	BodyColor: Color3,
}

local Enemies: { [string]: EnemyStats } = {
	Shambler = {
		Id = "Shambler",
		DisplayName = "Shambler",
		BaseHealth = 100,
		WalkSpeed = 11, -- was 8: still slower than the player's walk (16)
		RunSpeed = 20, -- was 17: faster than walking, slower than sprinting (25)
		Damage = 20, -- 5 hits from full health (was 30 = 3 hits)
		AttackRange = 4.5,
		AttackCooldown = 1.1,
		AttackWindup = 0.4, -- delay before the first swing once in reach: time to back off or knife
		BodyColor = Color3.fromRGB(96, 110, 92),
	},
}

-- Boss (wave 10 finale). Built from the zombie model, scaled up; PLACEHOLDER art.
local Boss = {
	Id = "Titan",
	DisplayName = "Dust Titan",
	Health = 9000, -- solo; x PlayerHealthMult per extra player
	PlayerHealthMult = { 1, 1.6, 2.2, 2.8 },
	Scale = 2.6,
	WalkSpeed = 13,
	Damage = 45,
	AttackRange = 8,
	AttackCooldown = 1.6,
	-- Ground slam: telegraphed ring, then damage + knockback inside it
	Slam = { Every = 7, Windup = 1.1, Radius = 16, Damage = 40, Knockback = 70, TriggerRange = 18 },
	Points = 2000, -- to every player when it dies
}

local EnemyConfig = {
	Enemies = Enemies,
	Boss = Boss,
	MaxAlive = 30,
	AiTickRate = 0.2, -- seconds between AI updates
	PathRecomputeInterval = 1.5,
	PathBudgetPerTick = 4,
}

return EnemyConfig
