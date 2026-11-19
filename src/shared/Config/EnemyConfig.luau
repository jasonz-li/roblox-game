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
	BodyColor: Color3,
}

local Enemies: { [string]: EnemyStats } = {
	Shambler = {
		Id = "Shambler",
		DisplayName = "Shambler",
		BaseHealth = 100,
		WalkSpeed = 8,
		RunSpeed = 17,
		Damage = 25,
		AttackRange = 4.5,
		AttackCooldown = 1.0,
		BodyColor = Color3.fromRGB(96, 110, 92),
	},
}

local EnemyConfig = {
	Enemies = Enemies,
	MaxAlive = 24,
	AiTickRate = 0.2, -- seconds between AI updates
	PathRecomputeInterval = 1.5,
	PathBudgetPerTick = 4,
}

return EnemyConfig
