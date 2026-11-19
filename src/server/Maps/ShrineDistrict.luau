--!nonstrict
-- Map 1 layout data: "Shrine District at Dusk" (BLOCKOUT / PLACEHOLDER geometry).
-- 2x2 grid of zones, each 80x80 studs. Zone 0 is the starting courtyard.
--
--   z=120 +------------------+------------------+
--         |  1 Market Street | C|  3 Upper       |
--         |                  |  |    Terrace     |
--   z=40  +-------A----------+--------D---------+
--         |  0 Courtyard     |  B  2 Shrine     |
--         |   (start)        |       Garden     |
--   z=-40 +------------------+------------------+
--        x=-40             x=40               x=120

local V = Vector3.new

return {
	Name = "Shrine District (blockout)",
	WallHeight = 16,
	Zones = {
		[0] = { Name = "Courtyard", Min = V(-40, 0, -40), Max = V(40, 0, 40), FloorColor = Color3.fromRGB(64, 60, 72) },
		[1] = { Name = "Market Street", Min = V(-40, 0, 40), Max = V(40, 0, 120), FloorColor = Color3.fromRGB(78, 62, 54) },
		[2] = { Name = "Shrine Garden", Min = V(40, 0, -40), Max = V(120, 0, 40), FloorColor = Color3.fromRGB(52, 70, 56) },
		[3] = { Name = "Upper Terrace", Min = V(40, 0, 40), Max = V(120, 0, 120), FloorColor = Color3.fromRGB(56, 60, 80) },
	},

	-- Walls: { axis = "x" (runs along X at fixed z) | "z", at = fixed coord, from, to, gaps = {{a,b},...} }
	Walls = {
		{ axis = "x", at = -40, from = -40, to = 120 },
		{ axis = "x", at = 120, from = -40, to = 120 },
		{ axis = "z", at = -40, from = -40, to = 120 },
		{ axis = "z", at = 120, from = -40, to = 120 },
		{ axis = "x", at = 40, from = -40, to = 40, gaps = { { -6, 6 } } }, -- Door A
		{ axis = "z", at = 40, from = -40, to = 40, gaps = { { -6, 6 } } }, -- Door B
		{ axis = "z", at = 40, from = 40, to = 120, gaps = { { 74, 86 } } }, -- Door C
		{ axis = "x", at = 40, from = 40, to = 120, gaps = { { 74, 86 } } }, -- Door D
	},

	Doors = {
		{ Id = "A", Cost = 750, ZoneA = 0, ZoneB = 1, Center = V(0, 0, 40), Axis = "x", Width = 12 },
		{ Id = "B", Cost = 1000, ZoneA = 0, ZoneB = 2, Center = V(40, 0, 0), Axis = "z", Width = 12 },
		{ Id = "C", Cost = 1250, ZoneA = 1, ZoneB = 3, Center = V(40, 0, 80), Axis = "z", Width = 12 },
		{ Id = "D", Cost = 1250, ZoneA = 2, ZoneB = 3, Center = V(80, 0, 40), Axis = "x", Width = 12 },
	},

	-- Wall-buy plaques: position on the wall face + facing direction (into the room)
	WallBuys = {
		{ Weapon = "Pistol", Pos = V(-15, 5, -38.8), Face = V(0, 0, 1) },
		{ Weapon = "Shotgun", Pos = V(15, 5, -38.8), Face = V(0, 0, 1) },
		{ Weapon = "SMG", Pos = V(-38.8, 5, -10), Face = V(1, 0, 0) },
		{ Weapon = "AssaultRifle", Pos = V(-38.8, 5, 80), Face = V(1, 0, 0) },
		{ Weapon = "Sniper", Pos = V(80, 5, -38.8), Face = V(0, 0, 1) },
	},

	Perks = {
		{ Perk = "SwiftStep", Pos = V(37.4, 0, -28), Face = V(-1, 0, 0) },
		{ Perk = "QuickHands", Pos = V(37.4, 0, 55), Face = V(-1, 0, 0) },
		{ Perk = "IronBody", Pos = V(117.4, 0, -20), Face = V(-1, 0, 0) },
		{ Perk = "RapidFire", Pos = V(100, 0, 117.4), Face = V(0, 0, -1) },
	},

	Forge = { Pos = V(60, 0, 114), Face = V(0, 0, -1) },

	BoxLocations = {
		{ Zone = 0, Pos = V(-25, 0, 37.4), Face = V(0, 0, -1) },
		{ Zone = 1, Pos = V(20, 0, 117.4), Face = V(0, 0, -1) },
		{ Zone = 2, Pos = V(100, 0, 37.4), Face = V(0, 0, -1) },
		{ Zone = 3, Pos = V(117.4, 0, 65), Face = V(-1, 0, 0) },
	},
	BoxStart = 1, -- index into BoxLocations

	PlayerSpawn = V(0, 0, -12),

	EnemySpawns = {
		{ Zone = 0, Pos = V(-34, 0, -34) }, { Zone = 0, Pos = V(34, 0, -34) },
		{ Zone = 0, Pos = V(-34, 0, 20) }, { Zone = 0, Pos = V(0, 0, -34) },
		{ Zone = 1, Pos = V(-34, 0, 114) }, { Zone = 1, Pos = V(0, 0, 114) },
		{ Zone = 1, Pos = V(-34, 0, 55) }, { Zone = 1, Pos = V(30, 0, 100) },
		{ Zone = 2, Pos = V(114, 0, -34) }, { Zone = 2, Pos = V(75, 0, -34) }, { Zone = 2, Pos = V(114, 0, 15) },
		{ Zone = 3, Pos = V(114, 0, 114) }, { Zone = 3, Pos = V(50, 0, 90) }, { Zone = 3, Pos = V(90, 0, 114) },
	},

	-- Simple props: { Size, Pos (center), Color, Material?, Shape? }
	Props = {
		-- Courtyard: well, crates
		{ Size = V(7, 3, 7), Pos = V(0, 1.5, 14), Color = Color3.fromRGB(90, 86, 96), Shape = "Cylinder" },
		{ Size = V(4, 4, 4), Pos = V(-20, 2, -5), Color = Color3.fromRGB(110, 80, 50), Material = "WoodPlanks" },
		{ Size = V(4, 4, 4), Pos = V(22, 2, 6), Color = Color3.fromRGB(110, 80, 50), Material = "WoodPlanks" },
		{ Size = V(4, 3, 8), Pos = V(-24, 1.5, 22), Color = Color3.fromRGB(110, 80, 50), Material = "WoodPlanks" },
		-- Market: stall counters
		{ Size = V(10, 3, 4), Pos = V(-20, 1.5, 60), Color = Color3.fromRGB(120, 84, 56), Material = "Wood" },
		{ Size = V(10, 3, 4), Pos = V(20, 1.5, 70), Color = Color3.fromRGB(120, 84, 56), Material = "Wood" },
		{ Size = V(10, 3, 4), Pos = V(-20, 1.5, 85), Color = Color3.fromRGB(120, 84, 56), Material = "Wood" },
		{ Size = V(10, 3, 4), Pos = V(20, 1.5, 98), Color = Color3.fromRGB(120, 84, 56), Material = "Wood" },
		-- Garden: stones
		{ Size = V(6, 3, 6), Pos = V(60, 1.5, -20), Color = Color3.fromRGB(100, 104, 100), Material = "Slate" },
		{ Size = V(6, 3, 6), Pos = V(100, 1.5, 15), Color = Color3.fromRGB(100, 104, 100), Material = "Slate" },
		{ Size = V(5, 4, 5), Pos = V(62, 2, 22), Color = Color3.fromRGB(100, 104, 100), Material = "Slate" },
		-- Terrace: low dais + pillars
		{ Size = V(24, 1, 24), Pos = V(80, 0.5, 80), Color = Color3.fromRGB(80, 84, 104), Material = "Marble" },
		{ Size = V(2, 12, 2), Pos = V(69, 6, 69), Color = Color3.fromRGB(150, 40, 50) },
		{ Size = V(2, 12, 2), Pos = V(91, 6, 69), Color = Color3.fromRGB(150, 40, 50) },
		{ Size = V(2, 12, 2), Pos = V(69, 6, 91), Color = Color3.fromRGB(150, 40, 50) },
		{ Size = V(2, 12, 2), Pos = V(91, 6, 91), Color = Color3.fromRGB(150, 40, 50) },
	},

	-- Market awnings (colored, decorative)
	Awnings = {
		{ Pos = V(-20, 7, 60), Color = Color3.fromRGB(255, 80, 170) },
		{ Pos = V(20, 7, 70), Color = Color3.fromRGB(80, 220, 255) },
		{ Pos = V(-20, 7, 85), Color = Color3.fromRGB(255, 200, 60) },
		{ Pos = V(20, 7, 98), Color = Color3.fromRGB(140, 255, 140) },
	},

	Torii = { Pos = V(80, 0, 0) },

	Lanterns = {
		V(-20, 0, -20), V(20, 0, -20), V(-20, 0, 20), V(20, 0, 20),
		V(-30, 0, 70), V(30, 0, 50), V(-30, 0, 110), V(30, 0, 85),
		V(60, 0, -30), V(100, 0, -30), V(60, 0, 30), V(110, 0, 0),
		V(55, 0, 55), V(105, 0, 55), V(55, 0, 105), V(105, 0, 105),
	},
}
