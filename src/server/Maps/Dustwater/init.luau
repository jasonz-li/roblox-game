--!nonstrict
-- Map: "Dustwater" — an ORIGINAL destroyed desert town (see docs/maps/DUSTWATER.md).
-- Stage 1 GREYBOX: layout, massing, bounds, doors and stations. Plain parts only.
--
-- Coordinates: north = -Z, east = +X, ground top = y 0, underground floor = y -20.
--
--  z=-100 +--------------------------------------------------------------------------------+
--         | GAS     |  [Block A: shops]   [DINER] [Block C: theater] |  MOTEL north wing   |
--  z=-32  | STATION |=============== MAIN STREET (road z -26..6) =======|  courtyard + pool    |
--         |   D2    |   fallen tower     bus   cars              D4 gate|  pump-house (D5 ↓)  |
--  z=40   +---------+-----------------------D1--------------------------+---------------------+
--         (filler)          ELM LANE (start) houses + garage             (filler)
--  z=145  +--------------------------------------------------------------------------------+
--        x=-180   x=-110        x=-14..14                          x=120             x=210
--  Underground (y=-20): ramp under the pump-house → landing → tunnel west → lab under the diner.

local V = Vector3.new

local SAND = Color3.fromRGB(196, 160, 112)
local STUCCO = Color3.fromRGB(176, 150, 118)

return {
	Name = "Dustwater (greybox)",
	OwnGround = true,
	WallHeight = 14,
	WallColor = STUCCO,

	Lighting = {
		ClockTime = 19.1, -- dusk going to night
		Brightness = 1.1,
		Ambient = Color3.fromRGB(58, 44, 40),
		OutdoorAmbient = Color3.fromRGB(96, 70, 54),
		FogColor = Color3.fromRGB(120, 78, 50),
		FogStart = 40,
		FogEnd = 420,
	},

	Zones = {
		[0] = { Name = "Elm Lane" },
		[1] = { Name = "Main Street" },
		[2] = { Name = "Gas Station" },
		[3] = { Name = "Diner" },
		[4] = { Name = "Motel" },
		[5] = { Name = "Storm Drain Lab" },
	},

	-- Boundary walls (axis = the direction the wall RUNS; at = its fixed coordinate)
	Walls = {
		-- Outer rock walls
		{ axis = "x", at = -100, from = -180, to = 210, height = 32, color = Color3.fromRGB(120, 92, 70), material = "Rock", name = "Cliff" },
		{ axis = "x", at = 145, from = -180, to = 210, height = 32, color = Color3.fromRGB(120, 92, 70), material = "Rock", name = "Cliff" },
		{ axis = "z", at = -180, from = -100, to = 145, height = 32, color = Color3.fromRGB(120, 92, 70), material = "Rock", name = "Cliff" },
		{ axis = "z", at = 210, from = -100, to = 145, height = 32, color = Color3.fromRGB(120, 92, 70), material = "Rock", name = "Cliff" },
		-- Southern edge of the town (Elm Lane barricade gap = D1)
		{ axis = "x", at = 40, from = -180, to = 210, gaps = { { -14, 14 } } },
		-- Elm Lane sides
		{ axis = "z", at = -60, from = 40, to = 145 },
		{ axis = "z", at = 60, from = 40, to = 145 },
		-- Gas station | Main Street (D2) and Main Street | Motel (D4)
		{ axis = "z", at = -110, from = -100, to = 40, gaps = { { -26, 6 } } },
		{ axis = "z", at = 120, from = -100, to = 40, gaps = { { -26, 6 } } },
		-- Diner back yard
		{ axis = "z", at = 14, from = -84, to = -64 },
		{ axis = "z", at = 58, from = -84, to = -64 },
		{ axis = "x", at = -84, from = 14, to = 58 },
	},

	Doors = {
		{ Id = "D1", Label = "Debris barricade", Cost = 750, ZoneA = 0, ZoneB = 1, Center = V(0, 0, 40), Axis = "x", Width = 28, Material = "Wood", Color = Color3.fromRGB(110, 80, 55) },
		{ Id = "D2", Label = "Car wreck pile", Cost = 1000, ZoneA = 1, ZoneB = 2, Center = V(-110, 0, -10), Axis = "z", Width = 32, Material = "CorrodedMetal", Color = Color3.fromRGB(90, 70, 60) },
		{ Id = "D3", Label = "Diner door", Cost = 1000, ZoneA = 1, ZoneB = 3, Center = V(33, 0, -32), Axis = "x", Width = 6, Height = 8, Color = Color3.fromRGB(150, 60, 50) },
		{ Id = "D4", Label = "Motel gate", Cost = 1250, ZoneA = 1, ZoneB = 4, Center = V(120, 0, -10), Axis = "z", Width = 32, Material = "DiamondPlate", Color = Color3.fromRGB(80, 80, 85) },
		{ Id = "D5", Label = "Storm drain", Cost = 1500, ZoneA = 4, ZoneB = 5, Center = V(130, 0, -7), Axis = "x", Width = 8, Height = 8, Material = "DiamondPlate", Color = Color3.fromRGB(70, 75, 80) },
	},

	WallBuys = {
		{ Weapon = "Pistol", Pos = V(-25.3, 5, 76), Face = V(1, 0, 0) },
		{ Weapon = "SMG", Pos = V(25.7, 5, 78), Face = V(-1, 0, 0) },
		{ Weapon = "Shotgun", Pos = V(-70, 5, -31.7), Face = V(0, 0, 1) },
		{ Weapon = "AssaultRifle", Pos = V(-162, 5, 29.3), Face = V(0, 0, -1) },
		{ Weapon = "Sniper", Pos = V(138, 17, -54.7), Face = V(0, 0, 1) },
	},

	Perks = {
		{ Perk = "SwiftStep", Pos = V(-30, 0, -30.4), Face = V(0, 0, 1) },
		{ Perk = "RapidFire", Pos = V(-127, 0, 28), Face = V(0, 0, -1) },
		{ Perk = "QuickHands", Pos = V(56, 0, -46), Face = V(-1, 0, 0) },
		{ Perk = "IronBody", Pos = V(136, 0, 38), Face = V(0, 0, -1) },
	},

	Forge = { Pos = V(40, -20, -63.5), Face = V(0, 0, 1) },

	BoxLocations = {
		{ Zone = 0, Pos = V(44.2, 0, 116), Face = V(-1, 0, 0) }, -- Elm Lane garage
		{ Zone = 1, Pos = V(95, 0, 37.7), Face = V(0, 0, -1) }, -- Main Street, south lot
		{ Zone = 3, Pos = V(15.8, 0, -42), Face = V(1, 0, 0) }, -- Diner
		{ Zone = 4, Pos = V(157.5, 0, -73.2), Face = V(0, 0, 1) }, -- Motel room
	},
	BoxStart = 1,

	PlayerSpawn = V(0, 0, 118),

	EnemySpawns = {
		{ Zone = 0, Pos = V(-52, 0, 136) }, { Zone = 0, Pos = V(52, 0, 138) },
		{ Zone = 0, Pos = V(-52, 0, 48) }, { Zone = 0, Pos = V(52, 0, 48) },
		{ Zone = 1, Pos = V(-100, 0, -28) }, { Zone = 1, Pos = V(110, 0, -28) },
		{ Zone = 1, Pos = V(-100, 0, 32) }, { Zone = 1, Pos = V(110, 0, 30) }, { Zone = 1, Pos = V(0, 0, -29) },
		{ Zone = 2, Pos = V(-172, 0, -92) }, { Zone = 2, Pos = V(-120, 0, -92) }, { Zone = 2, Pos = V(-172, 0, 35) },
		{ Zone = 3, Pos = V(20, 0, -80) }, { Zone = 3, Pos = V(52, 0, -80) },
		{ Zone = 4, Pos = V(180, 0, -45) }, { Zone = 4, Pos = V(180, 0, 15) }, { Zone = 4, Pos = V(128, 0, 15) },
		{ Zone = 5, Pos = V(95, -20, -53) }, { Zone = 5, Pos = V(25, -20, -45) },
	},

	Colors = { Sand = SAND, Stucco = STUCCO },

	BuildGeometry = function(api)
		require(script.Geometry)(api)
	end,
}
