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

local EnemyConfig = {
	Enemies = Enemies,
	MaxAlive = 30,
	AiTickRate = 0.2, -- seconds between AI updates
	PathRecomputeInterval = 1.5,
	PathBudgetPerTick = 4,
}

return EnemyConfig
