--!strict
-- Weapon stat tables. The server uses these as the source of truth; the client
-- uses the same values only for prediction and feedback.
-- Viewmodels are PLACEHOLDER block guns built from the `View` spec.

export type ViewSpec = {
	Length: number, -- receiver length
	Barrel: number,
	Color: Color3,
	Accent: Color3,
	Stock: boolean,
	MagHeight: number,
	Scope: boolean?,
	AdsHeight: number?, -- how far above the gun's center the sight line is
}

export type WeaponStats = {
	Id: string,
	DisplayName: string,
	Class: string,
	FireMode: "Auto" | "Semi" | "Burst",
	BurstCount: number?,
	Effects: { [string]: any }?, -- built-in effects (e.g. the Hanabi Launcher's explosive shells)
	Damage: number, -- per pellet
	HeadshotMultiplier: number,
	RPM: number,
	MagSize: number,
	ReserveAmmo: number,
	ReloadTime: number,
	Range: number,
	HipSpread: number, -- degrees
	AdsSpread: number,
	RecoilKick: number,
	RecoilSide: number,
	AdsFov: number,
	Pellets: number,
	Pierce: number, -- extra enemies a bullet passes through
	PierceFalloff: number?, -- damage multiplier per enemy passed through (default 0.8)
	ShotSound: string, -- SoundConfig key
	ShotPitch: number,
	TracerColor: Color3?,
	WallCost: number?, -- nil = not on walls
	AmmoCost: number?,
	BoxWeight: number, -- 0 = never from the mystery box
	View: ViewSpec,
}

local METAL = Color3.fromRGB(38, 40, 48)

local Weapons: { [string]: WeaponStats } = {
	Pistol = {
		Id = "Pistol", DisplayName = "Kitsune Sidearm", Class = "Pistol", FireMode = "Semi",
		Damage = 34, HeadshotMultiplier = 2.5, RPM = 420, MagSize = 10, ReserveAmmo = 80, ReloadTime = 1.4,
		Range = 350, HipSpread = 1.0, AdsSpread = 0.3, RecoilKick = 0.9, RecoilSide = 0.3, AdsFov = 62,
		Pellets = 1, Pierce = 0, ShotSound = "RifleShot", ShotPitch = 1.35,
		WallCost = 300, AmmoCost = 150, BoxWeight = 0,
		View = { Length = 0.9, Barrel = 0.35, Color = METAL, Accent = Color3.fromRGB(255, 160, 60), Stock = false, MagHeight = 0.45 },
	},
	SMG = {
		Id = "SMG", DisplayName = "Hornet SMG", Class = "SMG", FireMode = "Auto",
		Damage = 26, HeadshotMultiplier = 1.8, RPM = 820, MagSize = 32, ReserveAmmo = 224, ReloadTime = 1.8,
		Range = 260, HipSpread = 2.2, AdsSpread = 0.7, RecoilKick = 0.45, RecoilSide = 0.35, AdsFov = 60,
		Pellets = 1, Pierce = 0, ShotSound = "RifleShot", ShotPitch = 1.3,
		WallCost = 1000, AmmoCost = 500, BoxWeight = 20,
		View = { Length = 1.3, Barrel = 0.45, Color = Color3.fromRGB(50, 52, 64), Accent = Color3.fromRGB(255, 220, 60), Stock = true, MagHeight = 0.75 },
	},
	Shotgun = {
		Id = "Shotgun", DisplayName = "Oni Breaker", Class = "Shotgun", FireMode = "Semi",
		-- buffed (playtest: "shotgun is bad"): was 22 dmg x8, spread 5.5, range 110, mag 6
		Damage = 38, HeadshotMultiplier = 1.5, RPM = 100, MagSize = 8, ReserveAmmo = 56, ReloadTime = 2.4,
		Range = 140, HipSpread = 3.8, AdsSpread = 2.8, RecoilKick = 3.2, RecoilSide = 0.8, AdsFov = 65,
		Pellets = 9, Pierce = 0, ShotSound = "ShotgunShot", ShotPitch = 1.0,
		WallCost = 1200, AmmoCost = 600, BoxWeight = 18,
		View = { Length = 1.9, Barrel = 0.9, Color = Color3.fromRGB(70, 46, 36), Accent = Color3.fromRGB(255, 90, 60), Stock = true, MagHeight = 0.25 },
	},
	AssaultRifle = {
		Id = "AssaultRifle", DisplayName = "Raijin AR", Class = "AssaultRifle", FireMode = "Auto",
		Damage = 34, HeadshotMultiplier = 2.0, RPM = 600, MagSize = 30, ReserveAmmo = 180, ReloadTime = 2.0,
		Range = 600, HipSpread = 1.6, AdsSpread = 0.25, RecoilKick = 0.55, RecoilSide = 0.25, AdsFov = 55,
		Pellets = 1, Pierce = 0, ShotSound = "RifleShot", ShotPitch = 1.0,
		WallCost = 1500, AmmoCost = 750, BoxWeight = 18,
		View = { Length = 1.8, Barrel = 1.0, Color = METAL, Accent = Color3.fromRGB(80, 220, 255), Stock = true, MagHeight = 0.65 },
	},
	Sniper = {
		Id = "Sniper", DisplayName = "Tsukuyomi Longbow", Class = "Sniper", FireMode = "Semi",
		-- buffed (playtest: "sniper is bad"): was 240 dmg, 55 rpm, mag 5, hip spread 5
		Damage = 520, HeadshotMultiplier = 3.0, RPM = 75, MagSize = 6, ReserveAmmo = 42, ReloadTime = 2.5,
		Range = 900, HipSpread = 2.5, AdsSpread = 0, RecoilKick = 4, RecoilSide = 0.5, AdsFov = 42,
		-- collateral: a round punches through up to 5 zombies at full damage
		Pellets = 1, Pierce = 5, PierceFalloff = 1, ShotSound = "HeavyShot", ShotPitch = 0.85,
		TracerColor = Color3.fromRGB(180, 140, 255),
		WallCost = 2000, AmmoCost = 1000, BoxWeight = 12,
		-- iron sights (no scope overlay)
		View = { Length = 2.3, Barrel = 1.4, Color = Color3.fromRGB(40, 44, 40), Accent = Color3.fromRGB(180, 140, 255), Stock = true, MagHeight = 0.4 },
	},
	LMG = {
		Id = "LMG", DisplayName = "Kaiju LMG", Class = "LMG", FireMode = "Auto",
		Damage = 42, HeadshotMultiplier = 1.6, RPM = 640, MagSize = 100, ReserveAmmo = 400, ReloadTime = 4.5,
		Range = 500, HipSpread = 2.6, AdsSpread = 0.8, RecoilKick = 0.6, RecoilSide = 0.45, AdsFov = 58,
		Pellets = 1, Pierce = 0, ShotSound = "HeavyShot", ShotPitch = 1.15,
		BoxWeight = 14,
		View = { Length = 2.2, Barrel = 1.1, Color = Color3.fromRGB(60, 62, 50), Accent = Color3.fromRGB(120, 255, 120), Stock = true, MagHeight = 0.5 },
	},
	SpiritRailgun = {
		Id = "SpiritRailgun", DisplayName = "Spirit Railgun", Class = "Special", FireMode = "Auto",
		Damage = 160, HeadshotMultiplier = 1.5, RPM = 180, MagSize = 12, ReserveAmmo = 96, ReloadTime = 2.4,
		Range = 700, HipSpread = 0.8, AdsSpread = 0.15, RecoilKick = 1.2, RecoilSide = 0.2, AdsFov = 55,
		Pellets = 1, Pierce = 5, ShotSound = "LaserShot", ShotPitch = 0.9,
		TracerColor = Color3.fromRGB(255, 80, 200),
		BoxWeight = 5,
		View = { Length = 1.7, Barrel = 0.8, Color = Color3.fromRGB(240, 240, 255), Accent = Color3.fromRGB(255, 80, 200), Stock = false, MagHeight = 0.3 },
	},
	-- New for variety (Mystery Box)
	Magnum = {
		Id = "Magnum", DisplayName = "Kappa Magnum", Class = "Pistol", FireMode = "Semi",
		Damage = 210, HeadshotMultiplier = 2.6, RPM = 190, MagSize = 6, ReserveAmmo = 54, ReloadTime = 2.0,
		Range = 500, HipSpread = 1.4, AdsSpread = 0.2, RecoilKick = 3.0, RecoilSide = 0.6, AdsFov = 58,
		Pellets = 1, Pierce = 1, PierceFalloff = 0.9, ShotSound = "HeavyShot", ShotPitch = 1.25,
		BoxWeight = 16,
		View = { Length = 1.1, Barrel = 0.6, Color = Color3.fromRGB(70, 74, 86), Accent = Color3.fromRGB(120, 230, 160), Stock = false, MagHeight = 0.2 },
	},
	Launcher = {
		Id = "Launcher", DisplayName = "Hanabi Launcher", Class = "Special", FireMode = "Semi",
		Damage = 60, HeadshotMultiplier = 1, RPM = 70, MagSize = 4, ReserveAmmo = 24, ReloadTime = 2.8,
		Range = 300, HipSpread = 0.6, AdsSpread = 0.3, RecoilKick = 3.5, RecoilSide = 0.4, AdsFov = 62,
		Pellets = 1, Pierce = 0, ShotSound = "ShotgunShot", ShotPitch = 0.7,
		TracerColor = Color3.fromRGB(255, 120, 200),
		BoxWeight = 10,
		-- explosive shells: burst where they land
		Effects = { Explosive = { Radius = 11, Damage = 280, Color = Color3.fromRGB(255, 110, 190) } },
		View = { Length = 1.6, Barrel = 0.9, Color = Color3.fromRGB(60, 40, 60), Accent = Color3.fromRGB(255, 110, 190), Stock = true, MagHeight = 0.35 },
	},
	BurstRifle = {
		Id = "BurstRifle", DisplayName = "Tengu Burst Rifle", Class = "AssaultRifle", FireMode = "Burst", BurstCount = 3,
		Damage = 58, HeadshotMultiplier = 2.4, RPM = 780, MagSize = 24, ReserveAmmo = 192, ReloadTime = 2.0,
		Range = 650, HipSpread = 1.3, AdsSpread = 0.15, RecoilKick = 0.7, RecoilSide = 0.2, AdsFov = 52,
		Pellets = 1, Pierce = 0, ShotSound = "RifleShot", ShotPitch = 0.95,
		BoxWeight = 16,
		View = { Length = 1.9, Barrel = 0.9, Color = Color3.fromRGB(46, 50, 58), Accent = Color3.fromRGB(255, 200, 80), Stock = true, MagHeight = 0.55 },
	},
}

local WeaponConfig: any = {
	Weapons = Weapons,
	Default = "Pistol",
	MaxSlots = 3, -- absolute max (2 normally, 3 with the Pack Mule Tonic perk)
	SwitchTime = 0.35,
	-- "Spirit Forge" upgrade multipliers
	Upgrade = {
		Cost = 5000, -- first forge (kept for older callers)
		Costs = { 5000, 7500, 10000 }, -- forge, reforge II, reforge III
		MaxLevel = 3,
		Damage = 2.0,
		Mag = 1.5,
		Reserve = 1.5,
		Prefix = "✦ ",
		Accent = Color3.fromRGB(255, 200, 60),
	},
}

-- Spirit Forge signature upgrades: each weapon becomes something new, not just
-- "more damage". Fields here override the doubled stats; `Effects` are handled by
-- WeaponService on hit:
--   Explosive = { Radius, Damage, HeadshotOnly?, Color }  blast at the bullet's end point
--   Chain     = { Count, Range, Mult }                    lightning arcs to nearby zombies
--   Burn      = { Dps, Duration }                         sets zombies on fire
--   Shock     = { Slow, Time }                            slows what it hits
local Signature: { [string]: { [string]: any } } = {
	Pistol = {
		Name = "Twin Foxfire",
		Dual = true, -- two pistols, alternating shots
		Damage = 70, RPM = 560, MagSize = 24, ReserveAmmo = 168, ReloadTime = 1.7,
		ShotSound = "ShotgunShot", ShotPitch = 1.6,
		Tracer = Color3.fromRGB(255, 140, 40),
		Effects = { Explosive = { Radius = 9, Damage = 140, Color = Color3.fromRGB(255, 130, 40) } },
	},
	SMG = {
		Name = "Hornet Queen",
		RPM = 900, Tracer = Color3.fromRGB(255, 240, 90),
		Effects = { Chain = { Count = 2, Range = 16, Mult = 0.6 } },
	},
	Shotgun = {
		Name = "Oni's Breath",
		Pellets = 10, Tracer = Color3.fromRGB(255, 90, 40),
		Effects = { Burn = { Dps = 140, Duration = 3 } }, -- (was 60: too weak)
	},
	AssaultRifle = {
		Name = "Raijin Thunderhead",
		Tracer = Color3.fromRGB(120, 220, 255),
		Effects = { Shock = { Slow = 0.45, Time = 1.5 }, Explosive = { Radius = 4, Damage = 45, Color = Color3.fromRGB(120, 220, 255) } },
	},
	Sniper = {
		Name = "Moonlance",
		Pierce = 99, Tracer = Color3.fromRGB(200, 170, 255),
		Effects = { Explosive = { Radius = 12, Damage = 900, HeadshotOnly = true, Color = Color3.fromRGB(200, 160, 255) } }, -- (was 600)
	},
	Magnum = {
		Name = "Thunder Magnum",
		Pierce = 3, Tracer = Color3.fromRGB(140, 255, 190),
		Effects = { Chain = { Count = 3, Range = 18, Mult = 0.7 } },
	},
	Launcher = {
		Name = "Grand Finale",
		MagSize = 6, Tracer = Color3.fromRGB(255, 160, 230),
		Effects = { Explosive = { Radius = 15, Damage = 420, Color = Color3.fromRGB(255, 150, 230) }, Burn = { Dps = 80, Duration = 3 } },
	},
	BurstRifle = {
		Name = "Tengu Gale",
		Pierce = 2, Tracer = Color3.fromRGB(255, 220, 120),
		Effects = { Shock = { Slow = 0.5, Time = 1.2 } },
	},
	LMG = {
		Name = "Kaiju Inferno",
		MagSize = 150, Tracer = Color3.fromRGB(255, 120, 40),
		Effects = { Burn = { Dps = 40, Duration = 4 } },
	},
	SpiritRailgun = {
		Name = "Void Rail",
		Pierce = 99, Tracer = Color3.fromRGB(160, 60, 255),
		Effects = { Explosive = { Radius = 7, Damage = 220, Color = Color3.fromRGB(170, 70, 255) } },
	},
}
WeaponConfig.Signature = Signature

local cache: { [string]: WeaponStats } = {}

-- Forge level from either the old boolean or a number (0 = not forged, max 3).
function WeaponConfig.Level(upgraded: any): number
	if upgraded == true then
		return 1
	end
	return math.clamp(tonumber(upgraded) or 0, 0, WeaponConfig.Upgrade.MaxLevel)
end

local ROMAN = { "", " II", " III" }
local LEVEL_TINT = { nil, Color3.fromRGB(255, 80, 200), Color3.fromRGB(230, 250, 255) } -- reforge glow

-- Scale a signature effect for reforge levels 2 and 3 (bigger, stronger, more arcs).
local function scaleEffects(effects, level: number)
	if not effects or level <= 1 then
		return effects
	end
	local k = level - 1
	local out = {}
	for name, e in effects do
		local c = table.clone(e)
		if name == "Explosive" then
			c.Radius = e.Radius * (1.2 ^ k)
			c.Damage = e.Damage * (1.6 ^ k)
		elseif name == "Chain" then
			c.Count = e.Count + 2 * k
			c.Range = e.Range * (1.15 ^ k)
			c.Mult = math.min(1, e.Mult + 0.15 * k)
		elseif name == "Burn" then
			c.Dps = e.Dps * (1.7 ^ k)
		elseif name == "Shock" then
			c.Slow = math.max(0.15, e.Slow - 0.12 * k)
			c.Time = e.Time + 0.5 * k
		end
		out[name] = c
	end
	return out
end

-- Effective stats for a weapon at a Forge level (true/1..3). Cached, treat as read-only.
function WeaponConfig.Get(id: string, upgraded: any): WeaponStats?
	local base = Weapons[id]
	if not base then
		return nil
	end
	local level = WeaponConfig.Level(upgraded)
	if level == 0 then
		return base
	end
	local key = id .. "+" .. level
	if cache[key] then
		return cache[key]
	end
	local up = table.clone(base) :: any
	local u = WeaponConfig.Upgrade
	local sig = Signature[id] or {}
	up.DisplayName = string.rep("✦", level) .. " " .. (sig.Name or base.DisplayName) .. ROMAN[level]
	up.Damage = base.Damage * u.Damage
	up.MagSize = math.floor(base.MagSize * u.Mag)
	up.ReserveAmmo = math.floor(base.ReserveAmmo * u.Reserve)
	for _, k in { "Damage", "RPM", "MagSize", "ReserveAmmo", "ReloadTime", "Pellets", "Pierce", "ShotSound", "ShotPitch" } do
		if sig[k] ~= nil then
			up[k] = sig[k]
		end
	end
	-- reforges: +60% damage and +25% ammo per level above 1
	local extra = level - 1
	up.Damage *= 1.6 ^ extra
	up.MagSize = math.floor(up.MagSize * (1.25 ^ extra))
	up.ReserveAmmo = math.floor(up.ReserveAmmo * (1.25 ^ extra))
	local color = sig.Tracer or u.Accent
	if LEVEL_TINT[level] then
		color = color:Lerp(LEVEL_TINT[level], 0.6)
	end
	local view = table.clone(base.View) :: any
	view.Accent = color
	view.Dual = sig.Dual
	up.View = view
	up.TracerColor = color
	up.Effects = scaleEffects(sig.Effects, level)
	up.Level = level
	cache[key] = up
	return up
end

function WeaponConfig.BoxPool(): { { id: string, weight: number } }
	local pool = {}
	for id, w in Weapons do
		if w.BoxWeight > 0 then
			table.insert(pool, { id = id, weight = w.BoxWeight })
		end
	end
	table.sort(pool, function(a, b)
		return a.id < b.id
	end)
	return pool
end

return WeaponConfig
