--!nonstrict
-- Dustwater Stage 1 GREYBOX v2 geometry. Plain parts: massing, walkable floors,
-- enterable shells, ramps. Stage 2 replaces shells with real architecture.

local V = Vector3.new
local C = Color3.fromRGB

local SAND = C(196, 160, 112)
local ASPHALT = C(52, 50, 52)
local SIDEWALK = C(140, 132, 120)
local STUCCO = C(176, 150, 118)
local BRICK = C(130, 80, 62)
local CONCRETE = C(120, 118, 114)
local CHARRED = C(45, 38, 34)

local function overlay(api, name, x0, z0, x1, z1, color, material)
	-- Flat visual strip on top of the ground (roads, sidewalks). Not collidable.
	api.box(name, V(x0, 0, z0), V(x1, 0.06, z1), color, material, { CanCollide = false, CanQuery = false })
end

local function light(api, pos: Vector3, color: Color3, range: number?)
	local p = api.part({
		Name = "Light",
		Size = V(1, 0.3, 1),
		Position = pos,
		Color = color,
		Material = "Neon",
		CanCollide = false,
		CanQuery = false,
	})
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range or 20
	l.Brightness = 1.6
	l.Parent = p
	return p
end

local function car(api, x, z, yawDeg, color, y)
	local cf = CFrame.new(x, y or 0, z) * CFrame.Angles(0, math.rad(yawDeg), 0)
	api.part({ Name = "CarBody", Size = V(7, 3, 15), CFrame = cf * CFrame.new(0, 2, 0), Color = color, Material = "CorrodedMetal" })
	api.part({ Name = "CarCabin", Size = V(6.4, 2.4, 7), CFrame = cf * CFrame.new(0, 4.6, 1), Color = color:Lerp(C(0, 0, 0), 0.4), Material = "CorrodedMetal" })
end

local function deadTree(api, x, z, h)
	api.part({ Name = "DeadTree", Size = V(1.4, h, 1.4), CFrame = CFrame.new(x, h / 2, z) * CFrame.Angles(math.rad(6), math.rad(x % 90), 0), Color = CHARRED, Material = "Wood" })
	api.part({ Name = "DeadBranch", Size = V(0.6, 6, 0.6), CFrame = CFrame.new(x, h * 0.75, z) * CFrame.Angles(0, 0, math.rad(50)) * CFrame.new(0, 2.5, 0), Color = CHARRED, Material = "Wood" })
end

local function fence(api, x0, z0, x1, z1)
	api.box("Fence", V(math.min(x0, x1), 0, math.min(z0, z1)), V(math.max(x0, x1) + 0.5, 3.5, math.max(z0, z1) + 0.5), C(120, 95, 70), "WoodPlanks")
end

return function(api)
	------------------------------------------------------------------
	-- Ground (holes for both underground ramps) and roads
	------------------------------------------------------------------
	api.floor("Ground", -260, -112, 300, 225, 0, SAND, "Sand", {
		{ 251, -59, 261, -9 }, -- motel storm drain
		{ -70, -98, -20, -90 }, -- alley sewer ramp
	})

	overlay(api, "MainStreet", -150, -32, 170, 4, ASPHALT, "Asphalt")
	overlay(api, "SidewalkN", -150, -40, 170, -32, SIDEWALK, "Concrete")
	overlay(api, "SidewalkS", -150, 4, 170, 12, SIDEWALK, "Concrete")
	overlay(api, "ElmLane", -14, 12, 14, 165, ASPHALT, "Asphalt")
	overlay(api, "LoopRoad", -30, 165, 30, 215, ASPHALT, "Asphalt")
	overlay(api, "GasApron", -255, -100, -152, 10, C(90, 88, 86), "Concrete")
	overlay(api, "MotelLot", 172, -72, 280, 60, C(110, 104, 96), "Concrete")
	overlay(api, "Alley", -96, -112, 36, -84, C(64, 60, 58), "Asphalt")
	overlay(api, "AlleyPassage", -96, -84, -88, -40, C(64, 60, 58), "Asphalt")

	------------------------------------------------------------------
	-- Zone 0: Elm Lane (start) — houses as islands, loop road, backyards
	------------------------------------------------------------------
	api.shell("WestHouse", -70, 120, -35, 160, 0, 12, {
		color = C(160, 140, 120),
		openings = {
			{ side = "e", from = 136, to = 142, height = 7 }, -- front door
			{ side = "w", from = 128, to = 134, height = 7 }, -- back door into the yard (loop)
		},
	})
	api.box("WestShed", V(-88, 0, 185), V(-76, 8, 200), C(120, 100, 80), "WoodPlanks")
	api.box("EastHouse", V(35, 0, 115), V(72, 12, 150), C(150, 128, 104), "Concrete")
	api.box("EastHouseRoof", V(34, 12, 114), V(73, 13, 151), C(80, 60, 52), "Slate")
	api.shell("Garage", 40, 170, 65, 200, 0, 10, {
		color = C(140, 132, 120),
		openings = { { side = "w", from = 178, to = 192, height = 8 } },
		floorMaterial = "Concrete",
	})
	api.box("Median", V(-10, 0, 180), V(10, 1.2, 200), C(90, 80, 60), "Ground")
	deadTree(api, 0, 190, 14)
	-- Broken backyard fences (low cover with gaps)
	fence(api, -96, 172, -80, 172)
	fence(api, -62, 172, -45, 172)
	fence(api, 72, 160, 96, 160)
	fence(api, 76, 205, 76, 222)
	car(api, -8, 118, 12, C(120, 40, 40))
	car(api, 78, 110, 80, C(60, 70, 90))
	for _, p in { V(-24, 9, 150), V(24, 9, 110), V(-24, 9, 205), V(24, 9, 205) } do
		light(api, p, C(255, 170, 90), 28)
	end

	------------------------------------------------------------------
	-- Zone 1: Main Street — shop blocks north, street, burned field + junkyard south
	------------------------------------------------------------------
	api.box("BlockA1_Hardware", V(-150, 0, -84), V(-96, 18, -40), STUCCO, "Concrete")
	api.box("BlockA2_Shops", V(-88, 0, -84), V(-24, 18, -40), C(168, 140, 112), "Concrete")
	api.box("BlockC_Theater", V(36, 0, -84), V(170, 22, -40), BRICK, "Brick")
	api.box("TheaterMarquee", V(70, 11, -42), V(120, 15, -38), C(60, 40, 40), "Metal")
	-- Fallen water tower: tank across the west street, legs in the field
	api.part({ Name = "WaterTowerTank", Shape = Enum.PartType.Cylinder, Size = V(24, 14, 14), CFrame = CFrame.new(-62, 7, -12) * CFrame.Angles(0, math.rad(25), 0), Color = C(150, 150, 140), Material = "CorrodedMetal" })
	for i, leg in { V(-80, 0, 32), V(-70, 0, 40), V(-90, 0, 42) } do
		api.part({ Name = "TowerLeg" .. i, Size = V(1.4, 26, 1.4), CFrame = CFrame.new(leg + V(0, 10, 0)) * CFrame.Angles(math.rad(-35), math.rad(20), 0), Color = C(110, 110, 104), Material = "Metal" })
	end
	-- Street cover
	api.box("Bus", V(20, 0, -27), V(60, 10, -17), C(200, 150, 40), "CorrodedMetal")
	car(api, 100, -6, 20, C(70, 80, 110))
	car(api, -118, -20, 80, C(90, 90, 90))
	car(api, 140, -24, -12, C(140, 120, 90))
	car(api, -28, -2, 35, C(60, 90, 70))
	-- Burned field (west lot)
	api.floor("FieldAsh", -150, 12, -40, 90, 0.08, C(70, 60, 50), "Ground")
	for _, t in { { -120, 40, 16 }, { -110, 72, 12 }, { -58, 76, 14 }, { -136, 20, 10 }, { -95, 60, 18 } } do
		deadTree(api, t[1], t[2], t[3])
	end
	api.box("BurntShack", V(-130, 0, 50), V(-112, 7, 62), CHARRED, "Wood")
	fence(api, -150, 30, -128, 30)
	-- Junkyard (east lot)
	api.box("Container", V(100, 0, 60), V(126, 9, 70), C(150, 60, 40), "CorrodedMetal")
	api.box("Container2", V(58, 0, 40), V(66, 9, 62), C(50, 90, 120), "CorrodedMetal")
	car(api, 80, 32, 0, C(120, 110, 100))
	car(api, 80, 32, 10, C(90, 60, 50), 5)
	car(api, 145, 40, 85, C(100, 100, 110))
	car(api, 150, 72, 40, C(130, 90, 60))
	api.box("ScrapPile", V(112, 0, 22), V(126, 4, 34), C(90, 80, 70), "CorrodedMetal")
	for _, p in { V(-120, 9, -39), V(-40, 9, -39), V(90, 9, -39), V(-100, 9, 11), V(40, 9, 11), V(130, 9, 11) } do
		light(api, p, C(255, 150, 80), 30)
	end

	------------------------------------------------------------------
	-- Zone 2: Gas Station — canopy + pumps, store (front + back doors), garage bay
	------------------------------------------------------------------
	api.box("CanopyRoof", V(-236, 14, -51), V(-184, 15.5, -13), C(200, 60, 50), "Metal")
	for _, p in { V(-233, 0, -48), V(-187, 0, -48), V(-233, 0, -16), V(-187, 0, -16) } do
		api.box("CanopyPillar", p + V(-0.75, 0, -0.75), p + V(0.75, 14, 0.75), C(220, 220, 215), "Concrete")
	end
	api.box("Pump1", V(-224, 0, -36), V(-220, 5, -30), C(200, 200, 190), "Metal")
	api.box("Pump2", V(-202, 0, -36), V(-198, 5, -30), C(200, 200, 190), "Metal")
	api.shell("GasStore", -250, 15, -205, 55, 0, 12, {
		color = C(190, 180, 160),
		openings = {
			{ side = "n", from = -232, to = -224, height = 7 },
			{ side = "s", from = -215, to = -209, height = 7 }, -- back door (loop)
		},
		floorMaterial = "Concrete",
	})
	api.shell("GasGarage", -205, 15, -170, 55, 0, 12, {
		color = C(170, 165, 150),
		openings = { { side = "n", from = -200, to = -176, height = 10 } },
		floorMaterial = "Concrete",
	})
	api.box("StoreShelf1", V(-246, 0, 28), V(-222, 5, 30), C(90, 90, 100), "Metal")
	api.box("StoreShelf2", V(-246, 0, 38), V(-222, 5, 40), C(90, 90, 100), "Metal")
	api.box("Lift", V(-196, 0, 30), V(-184, 1, 44), C(200, 170, 40), "Metal")
	car(api, -215, -80, 70, C(160, 160, 160))
	car(api, -175, 75, 10, C(120, 50, 40))
	light(api, V(-210, 13.6, -32), C(255, 240, 220), 40)
	light(api, V(-227, 9, 70), C(255, 150, 80), 24)

	------------------------------------------------------------------
	-- Zone 3: Diner + back alley + passage; sewer ramp down to the lab
	------------------------------------------------------------------
	api.shell("Diner", -24, -84, 36, -40, 0, 10, {
		color = C(200, 200, 205),
		openings = {
			{ side = "s", from = 0, to = 8, height = 8 }, -- front door (D3)
			{ side = "n", from = 12, to = 20, height = 8 }, -- kitchen back door → alley
		},
		floorColor = C(210, 210, 210),
		floorMaterial = "Marble",
	})
	api.box("Counter", V(-15, 0, -72), V(15, 3.5, -68), C(150, 40, 40), "SmoothPlastic")
	for _, z in { -80, -52, -46 } do
		api.box("Booth", V(28, 0, z), V(34, 3, z + 4), C(170, 40, 50), "Fabric")
	end
	api.box("DinerSign", V(-18, 10, -41), V(30, 14, -40.5), C(255, 80, 120), "Neon")
	light(api, V(6, 9.4, -62), C(255, 230, 200), 34)
	-- Alley clutter
	api.box("Dumpster1", V(-62, 0, -110), V(-54, 5, -105), C(40, 80, 50), "Metal")
	api.box("Dumpster2", V(4, 0, -110), V(12, 5, -105), C(40, 80, 50), "Metal")
	api.box("Crates", V(-86, 0, -110), V(-80, 4, -102), C(120, 90, 60), "WoodPlanks")
	-- Sewer ramp into the lab (rails around the opening)
	api.ramp("SewerRamp", -70, -98, -20, -90, -20, 0, "w", CONCRETE)
	api.box("SewerTrenchN", V(-70, -20, -99), V(-20, 0, -98), CONCRETE, "Concrete")
	api.box("SewerTrenchS", V(-70, -20, -90), V(-20, 0, -89), CONCRETE, "Concrete")
	api.box("SewerRailN", V(-64, 0, -99), V(-20, 3, -98.5), C(90, 90, 95), "Metal")
	api.box("SewerRailS", V(-64, 0, -89.5), V(-20, 3, -89), C(90, 90, 95), "Metal")
	api.box("SewerRailE", V(-20.5, 0, -99), V(-20, 3, -89), C(90, 90, 95), "Metal")
	for _, p in { V(-60, 9, -85), V(0, 9, -85), V(-92, 9, -60) } do
		light(api, p, C(180, 255, 200), 24)
	end

	------------------------------------------------------------------
	-- Zone 4: Motel — U-shape, balcony + stairs, pool, pump-house
	------------------------------------------------------------------
	api.box("MotelNorthW", V(172, 0, -110), V(210, 24, -80), STUCCO, "Concrete")
	api.shell("MotelRoom", 210, -110, 230, -80, 0, 11, {
		color = C(186, 160, 130),
		openings = { { side = "s", from = 217, to = 223, height = 7 } },
		floorColor = C(110, 60, 60),
		floorMaterial = "Fabric",
	})
	api.box("MotelRoomUpper", V(210, 12, -110), V(230, 24, -80), STUCCO, "Concrete")
	api.box("MotelNorthE", V(230, 0, -110), V(298, 24, -80), STUCCO, "Concrete")
	api.box("MotelEastWing", V(280, 0, -80), V(298, 24, 90), STUCCO, "Concrete")
	api.shell("MotelOffice", 172, 60, 210, 90, 0, 11, {
		color = C(186, 160, 130),
		openings = { { side = "n", from = 186, to = 194, height = 7 } },
	})
	api.box("MotelSouthWing", V(210, 0, 60), V(280, 12, 90), STUCCO, "Concrete")
	-- Upper balcony along the north wing; stairs at the east end
	api.box("Balcony", V(172, 11, -80), V(278, 12, -72), CONCRETE, "Concrete")
	api.box("BalconyRail", V(172, 12, -72.5), V(270, 15, -72), C(90, 90, 95), "Metal")
	api.ramp("BalconyStairs", 270, -72, 278, -40, 0, 12, "n", CONCRETE)
	api.box("StairSupport", V(278, 0, -72), V(278.5, 12, -40), CONCRETE, "Concrete")
	-- Drained pool (rim)
	api.box("PoolFloor", V(200, 0, -20), V(245, 0.08, 15), C(90, 130, 150), "Concrete", { CanCollide = false })
	api.box("PoolRimN", V(200, 0, -21), V(245, 1, -20), C(220, 220, 215), "Concrete")
	api.box("PoolRimS", V(200, 0, 15), V(245, 1, 16), C(220, 220, 215), "Concrete")
	api.box("PoolRimW", V(199, 0, -21), V(200, 1, 16), C(220, 220, 215), "Concrete")
	api.box("PoolRimE", V(245, 0, -21), V(246, 1, 16), C(220, 220, 215), "Concrete")
	api.box("MotelSign", V(173, 14, 40), V(175, 26, 46), C(255, 90, 60), "Neon")
	-- Pump-house over the storm-drain stairwell (D5 seals its south doorway)
	api.shell("PumpHouse", 250, -60, 262, -8, 0, 9, {
		color = C(130, 130, 125),
		openings = { { side = "s", from = 251, to = 261, height = 8 } },
		floor = false,
	})
	for _, p in { V(200, 10, -80.5), V(250, 10, -80.5), V(222, 9, 0), V(190, 9, 59.5) } do
		light(api, p, C(255, 120, 80), 30)
	end

	------------------------------------------------------------------
	-- Zone 5: Underground (y = -20): ramp, landing, long tunnel, lab
	------------------------------------------------------------------
	api.ramp("DrainRamp", 251, -59, 261, -9, -20, 0, "s", CONCRETE)
	api.box("TrenchW", V(250, -20, -59), V(251, 0, -9), CONCRETE, "Concrete")
	api.box("TrenchE", V(261, -20, -59), V(262, 0, -9), CONCRETE, "Concrete")
	api.shell("Landing", 240, -80, 270, -59, -20, 12, {
		color = CONCRETE,
		openings = {
			{ side = "s", from = 251, to = 261, height = 12 },
			{ side = "w", from = -76, to = -64, height = 10 },
		},
		floorMaterial = "Concrete",
		floorColor = C(80, 80, 82),
	})
	api.shell("Tunnel", 50, -76, 240, -64, -20, 10, {
		color = C(100, 100, 102),
		openings = {
			{ side = "e", from = -76, to = -64, height = 10 },
			{ side = "w", from = -76, to = -64, height = 10 },
		},
		floorMaterial = "Concrete",
		floorColor = C(70, 70, 72),
	})
	api.shell("Lab", -20, -100, 50, -56, -20, 14, {
		color = C(150, 155, 160),
		openings = {
			{ side = "e", from = -76, to = -64, height = 10 },
			{ side = "w", from = -98, to = -90, height = 10 }, -- sewer ramp from the alley (D6)
		},
		floorMaterial = "DiamondPlate",
		floorColor = C(90, 95, 100),
	})
	api.box("LabConsole", V(-10, -20, -66), V(4, -17, -62), C(60, 70, 80), "Metal")
	api.box("LabTank", V(30, -20, -64), V(40, -12, -58), C(80, 160, 140), "Glass", { Transparency = 0.4 })
	for _, p in { V(255, -9, -70), V(200, -10.4, -70), V(150, -10.4, -70), V(100, -10.4, -70), V(15, -6.4, -78), V(-40, -2, -94) } do
		light(api, p, C(140, 255, 180), 24)
	end
end
