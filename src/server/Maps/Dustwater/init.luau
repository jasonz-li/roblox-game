--!nonstrict
-- Map: "Dustwater" — an ORIGINAL destroyed desert town (see docs/maps/DUSTWATER.md).
-- Stage 1 GREYBOX v2: bigger, more loops, empty lots turned into play space.
--
-- Coordinates: north = -Z, east = +X, ground top = y 0, underground floor = y -20.
--
--  z=-112 +=====================================cliff==========================================+
--         | GAS STATION  |A1|  ALLEY (zone 3)  ...sewer ramp↓...      |                         |
--         |  canopy      |  |pass|  A2 shops |  DINER  |   C: theater |  MOTEL north wing (2F)  |
--  z=-40  |  store garage|  D3b                  D3                   |  balcony    stairs      |
--         |          D2  |========== MAIN STREET (road z -32..4) =====| D4  courtyard  pool    |
--  z=12   |              |  BURNED FIELD   | stem |   JUNKYARD        |       pump-house(D5↓)   |
--         |         D2b  |  (zone 1)       |      |   (zone 1)    D4b |  office   south wing    |
--  z=90   +--------------+--------------------D1----------------------+-------------------------+
--                          |   ELM LANE (start): houses as islands, loop road  |
--  z=225                   +---------------------------------------------------+
--        x=-260         x=-150          x=-14..14                    x=170                    x=300
--
--  Underground (y=-20): motel ramp → landing → long tunnel west → lab (under diner) → sewer ramp up into the alley.

local V = Vector3.new

local ROCK = Color3.fromRGB(120, 92, 70)

return {
	Name = "Dustwater (greybox v2)",
	OwnGround = true,
	WallHeight = 28,
	WallColor = Color3.fromRGB(176, 150, 118),

	Lighting = {
		ClockTime = 19.1, -- dusk going to night
		Brightness = 1.1,
		Ambient = Color3.fromRGB(58, 44, 40),
		OutdoorAmbient = Color3.fromRGB(96, 70, 54),
		FogColor = Color3.fromRGB(120, 78, 50),
		FogStart = 60,
		FogEnd = 520,
	},

	Zones = {
		[0] = { Name = "Elm Lane" },
		[1] = { Name = "Main Street" },
		[2] = { Name = "Gas Station" },
		[3] = { Name = "Diner & Alley" },
		[4] = { Name = "Motel" },
		[5] = { Name = "Storm Drain Lab" },
	},

	-- Boundary walls (axis = the direction the wall RUNS; at = its fixed coordinate)
	Walls = {
		-- Cliffs around the town
		{ axis = "x", at = -112, from = -260, to = 300, height = 56, color = ROCK, material = "Rock", name = "Cliff" },
		{ axis = "z", at = -260, from = -112, to = 90, height = 56, color = ROCK, material = "Rock", name = "Cliff" },
		{ axis = "z", at = 300, from = -112, to = 90, height = 56, color = ROCK, material = "Rock", name = "Cliff" },
		{ axis = "z", at = -100, from = 90, to = 225, height = 56, color = ROCK, material = "Rock", name = "Cliff" },
		{ axis = "z", at = 100, from = 90, to = 225, height = 56, color = ROCK, material = "Rock", name = "Cliff" },
		{ axis = "x", at = 225, from = -100, to = 100, height = 56, color = ROCK, material = "Rock", name = "Cliff" },
		-- Town's south edge; Elm Lane barricade gap = D1
		{ axis = "x", at = 90, from = -260, to = 300, gaps = { { -14, 14 } } },
		-- Gas Station | Main Street (D2 road, D2b back gate into the field)
		{ axis = "z", at = -150, from = -112, to = 90, gaps = { { -32, 4 }, { 60, 72 } } },
		-- Main Street | Motel (D4 gate, D4b back gate from the junkyard)
		{ axis = "z", at = 170, from = -112, to = 90, gaps = { { -32, 4 }, { 55, 67 } } },
		-- Alley ends
		{ axis = "z", at = -96, from = -112, to = -84 },
		{ axis = "z", at = 36, from = -112, to = -84 },
	},

	Doors = {
		{ Id = "D1", Label = "Debris barricade", Cost = 750, ZoneA = 0, ZoneB = 1, Center = V(0, 0, 90), Axis = "x", Width = 28, Material = "Wood", Color = Color3.fromRGB(110, 80, 55) },
		{ Id = "D2", Label = "Car wreck pile", Cost = 1000, ZoneA = 1, ZoneB = 2, Center = V(-150, 0, -14), Axis = "z", Width = 36, Material = "CorrodedMetal", Color = Color3.fromRGB(90, 70, 60) },
		{ Id = "D2b", Label = "Gas station back gate", Cost = 1000, ZoneA = 1, ZoneB = 2, Center = V(-150, 0, 66), Axis = "z", Width = 12, Material = "DiamondPlate", Color = Color3.fromRGB(90, 85, 80) },
		{ Id = "D3", Label = "Diner door", Cost = 1000, ZoneA = 1, ZoneB = 3, Center = V(4, 0, -40), Axis = "x", Width = 8, Height = 8, Color = Color3.fromRGB(150, 60, 50) },
		{ Id = "D3b", Label = "Alley gate", Cost = 1000, ZoneA = 1, ZoneB = 3, Center = V(-92, 0, -40), Axis = "x", Width = 8, Material = "DiamondPlate", Color = Color3.fromRGB(80, 80, 85) },
		{ Id = "D4", Label = "Motel gate", Cost = 1250, ZoneA = 1, ZoneB = 4, Center = V(170, 0, -14), Axis = "z", Width = 36, Material = "DiamondPlate", Color = Color3.fromRGB(80, 80, 85) },
		{ Id = "D4b", Label = "Motel back gate", Cost = 1250, ZoneA = 1, ZoneB = 4, Center = V(170, 0, 61), Axis = "z", Width = 12, Material = "DiamondPlate", Color = Color3.fromRGB(80, 80, 85) },
		{ Id = "D5", Label = "Storm drain", Cost = 1500, ZoneA = 4, ZoneB = 5, Center = V(256, 0, -8), Axis = "x", Width = 10, Height = 8, Material = "DiamondPlate", Color = Color3.fromRGB(70, 75, 80) },
		{ Id = "D6", Label = "Sewer grate", Cost = 1500, ZoneA = 3, ZoneB = 5, Center = V(-20, -20, -94), Axis = "z", Width = 10, Height = 12, Material = "DiamondPlate", Color = Color3.fromRGB(70, 75, 80) },
	},

	WallBuys = {
		{ Weapon = "Pistol", Pos = V(-34.3, 5, 128), Face = V(1, 0, 0) },
		{ Weapon = "SMG", Pos = V(34.3, 5, 130), Face = V(-1, 0, 0) },
		{ Weapon = "Shotgun", Pos = V(-60, 5, -39.7), Face = V(0, 0, 1) },
		{ Weapon = "AssaultRifle", Pos = V(-238, 5, 54.3), Face = V(0, 0, -1) },
		{ Weapon = "Sniper", Pos = V(190, 17, -79.7), Face = V(0, 0, 1) },
	},

	Perks = {
		{ Perk = "SwiftStep", Pos = V(-120, 0, -38.5), Face = V(0, 0, 1) },
		{ Perk = "RapidFire", Pos = V(-188, 0, 53), Face = V(0, 0, -1) },
		{ Perk = "QuickHands", Pos = V(34, 0, -60), Face = V(-1, 0, 0) },
		{ Perk = "IronBody", Pos = V(191, 0, 88), Face = V(0, 0, -1) },
	},

	Forge = { Pos = V(15, -20, -97.5), Face = V(0, 0, 1) },

	BoxLocations = {
		{ Zone = 0, Pos = V(63.2, 0, 185), Face = V(-1, 0, 0) }, -- Elm Lane garage
		{ Zone = 1, Pos = V(130, 0, 87.7), Face = V(0, 0, -1) }, -- Junkyard
		{ Zone = 3, Pos = V(-22.2, 0, -62), Face = V(1, 0, 0) }, -- Diner
		{ Zone = 4, Pos = V(220, 0, -108.2), Face = V(0, 0, 1) }, -- Motel room
		{ Zone = 2, Pos = V(-212, 0, 87.7), Face = V(0, 0, -1) }, -- Behind the gas station
	},
	BoxStart = 1,

	PlayerSpawn = V(0, 0, 160),

	-- Ground spawns: zombies claw up out of the dirt here (fewer now that windows exist).
	EnemySpawns = {
		{ Zone = 0, Pos = V(0, 0, 218) }, { Zone = 0, Pos = V(-92, 0, 98) },
		{ Zone = 1, Pos = V(-145, 0, -36) }, { Zone = 1, Pos = V(165, 0, -36) }, { Zone = 1, Pos = V(-40, 0, -38) }, { Zone = 1, Pos = V(80, 0, 20) },
		{ Zone = 2, Pos = V(-160, 0, -105) }, { Zone = 2, Pos = V(-160, 0, 85) },
		{ Zone = 3, Pos = V(-90, 0, -105) },
		{ Zone = 4, Pos = V(265, 0, 0) }, { Zone = 4, Pos = V(180, 0, -70) }, { Zone = 4, Pos = V(180, 0, 50) }, { Zone = 4, Pos = V(275, 0, 40) },
		{ Zone = 5, Pos = V(150, -20, -70) }, { Zone = 5, Pos = V(45, -20, -60) }, { Zone = 5, Pos = V(0, -20, -60) }, { Zone = 5, Pos = V(-10, -20, -80) },
	},

	-- Boarded windows cut into boundary walls. Zombies appear on the outside, tear the
	-- boards off, then climb in. Axis/At must match a wall line in `Walls` (the gap is cut
	-- automatically). Along = position along that wall; Inward = direction into play space.
	Barriers = {
		{ Zone = 0, Axis = "z", At = -100, Along = 150, Inward = V(1, 0, 0), WallHeight = 56 },
		{ Zone = 0, Axis = "z", At = 100, Along = 130, Inward = V(-1, 0, 0), WallHeight = 56 },
		{ Zone = 0, Axis = "x", At = 225, Along = -40, Inward = V(0, 0, -1), WallHeight = 56 },
		{ Zone = 0, Axis = "x", At = 225, Along = 50, Inward = V(0, 0, -1), WallHeight = 56 },
		{ Zone = 1, Axis = "x", At = 90, Along = -125, Inward = V(0, 0, -1), WallHeight = 28 },
		{ Zone = 1, Axis = "x", At = 90, Along = 145, Inward = V(0, 0, -1), WallHeight = 28 },
		{ Zone = 2, Axis = "z", At = -260, Along = -60, Inward = V(1, 0, 0), WallHeight = 56 },
		{ Zone = 2, Axis = "z", At = -260, Along = 40, Inward = V(1, 0, 0), WallHeight = 56 },
		{ Zone = 2, Axis = "x", At = -112, Along = -200, Inward = V(0, 0, 1), WallHeight = 56 },
		{ Zone = 3, Axis = "x", At = -112, Along = -40, Inward = V(0, 0, 1), WallHeight = 56 },
		{ Zone = 3, Axis = "x", At = -112, Along = 20, Inward = V(0, 0, 1), WallHeight = 56 },
	},

	-- Boss arena (Milestone 5): the widest stretch of Main Street, 3 exits.
	BossArena = { Center = V(10, 0, -14), Size = V(150, 30, 52), BossSpawns = { V(-50, 0, -14), V(90, 0, -14) } },

	-- Stage 3 post-processing (MapService applies these to Lighting)
	PostFX = {
		Atmosphere = { Density = 0.38, Offset = 0.1, Haze = 2.2, Glare = 0.4, Color = Color3.fromRGB(190, 140, 100), Decay = Color3.fromRGB(110, 70, 50) },
		ColorCorrection = { Brightness = 0.03, Contrast = 0.12, Saturation = -0.15, TintColor = Color3.fromRGB(255, 232, 214) },
		Bloom = { Intensity = 0.6, Size = 28, Threshold = 1.6 },
	},

	BuildGeometry = function(api)
		require(script.Geometry)(api) -- Stage 2 architecture
		require(script.Environment)(api) -- Stage 3 destruction, fire, smoke, debris
	end,
}
