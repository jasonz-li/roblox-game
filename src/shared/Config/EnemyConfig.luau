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
	Shape: string?,
	Scale: number?,
	Armor: number?,
	Knockback: number?,
	BonusPoints: number?,
	Spit: any?,
	Blast: any?,
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
	-- Low and quick, small target: punishes sloppy aim. Weak alone, nasty in a pack.
	Crawler = {
		Id = "Crawler",
		DisplayName = "Crawler",
		BaseHealth = 55,
		WalkSpeed = 14,
		RunSpeed = 19,
		Damage = 14,
		AttackRange = 4,
		AttackCooldown = 0.8,
		AttackWindup = 0.25,
		BodyColor = Color3.fromRGB(110, 100, 88),
		Shape = "Crawler",
		BonusPoints = 20,
	},
	-- Slow armored wall. Body shots do 40%, headshots full: aim for the head.
	-- Its swing knocks you back.
	Brute = {
		Id = "Brute",
		DisplayName = "Brute",
		BaseHealth = 340,
		WalkSpeed = 9,
		RunSpeed = 13,
		Damage = 38,
		AttackRange = 6,
		AttackCooldown = 1.7,
		AttackWindup = 0.65,
		BodyColor = Color3.fromRGB(88, 96, 84),
		Shape = "Brute",
		Scale = 1.45,
		Armor = 0.6, -- body-shot reduction
		Knockback = 55,
		BonusPoints = 100,
	},
	-- Hangs back and lobs acid that leaves a burning pool. Kill it first.
	Spitter = {
		Id = "Spitter",
		DisplayName = "Spitter",
		BaseHealth = 80,
		WalkSpeed = 11,
		RunSpeed = 15,
		Damage = 10,
		AttackRange = 4.5,
		AttackCooldown = 1.2,
		AttackWindup = 0.4,
		BodyColor = Color3.fromRGB(110, 140, 70),
		Shape = "Spitter",
		Spit = { Min = 12, Max = 42, Every = 3.2, Windup = 0.6, Flight = 0.9, PoolRadius = 5, PoolTime = 4, PoolDps = 14 },
		BonusPoints = 60,
	},
	-- Sprints at you, fuse lit when close, then blows. Shoot it early, ideally inside the
	-- horde: when it dies it bursts and hurts the zombies around it (and you, if close).
	Exploder = {
		Id = "Exploder",
		DisplayName = "Exploder",
		BaseHealth = 70,
		WalkSpeed = 19,
		RunSpeed = 21,
		Damage = 0,
		AttackRange = 0,
		AttackCooldown = 99,
		AttackWindup = 0,
		BodyColor = Color3.fromRGB(150, 110, 70),
		Shape = "Exploder",
		Blast = { Trigger = 6, Fuse = 0.8, Radius = 10, PlayerDamage = 45, DeathPlayerMult = 0.5, ZombieDamage = 400 },
		BonusPoints = 40,
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
