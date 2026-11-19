--!nonstrict
-- Dustwater Stage 1 GREYBOX geometry. Plain parts: massing, walkable floors,
-- enterable shells, ramps. Stage 2 replaces shells with real architecture.

local V = Vector3.new
local C = Color3.fromRGB

local SAND = C(196, 160, 112)
local ASPHALT = C(52, 50, 52)
local SIDEWALK = C(140, 132, 120)
local STUCCO = C(176, 150, 118)
local BRICK = C(130, 80, 62)
local CONCRETE = C(120, 118, 114)
local RUST = C(110, 70, 50)

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

local function car(api, x, z, yawDeg, color)
	local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yawDeg), 0)
	api.part({ Name = "CarBody", Size = V(7, 3, 15), CFrame = cf * CFrame.new(0, 2, 0), Color = color, Material = "CorrodedMetal" })
	api.part({ Name = "CarCabin", Size = V(6.4, 2.4, 7), CFrame = cf * CFrame.new(0, 4.6, 1), Color = color:Lerp(C(0, 0, 0), 0.4), Material = "CorrodedMetal" })
end

return function(api)
	------------------------------------------------------------------
	-- Ground (with the stairwell hole) and roads
	------------------------------------------------------------------
	api.floor("Ground", -180, -100, 210, 145, 0, SAND, "Sand", { { 126, -45, 134, -7 } })

	overlay(api, "MainStreet", -110, -26, 120, 6, ASPHALT, "Asphalt")
	overlay(api, "SidewalkN", -110, -32, 120, -26, SIDEWALK, "Concrete")
	overlay(api, "SidewalkS", -110, 6, 120, 10, SIDEWALK, "Concrete")
	overlay(api, "ElmLane", -14, 10, 14, 112, ASPHALT, "Asphalt")
	overlay(api, "CulDeSac", -26, 112, 26, 140, ASPHALT, "Asphalt")
	overlay(api, "GasApron", -175, -60, -110, -2, C(90, 88, 86), "Concrete")
	overlay(api, "MotelLot", 121, -49, 185, 20, C(110, 104, 96), "Concrete")

	------------------------------------------------------------------
	-- Zone 0: Elm Lane (start) — two houses + a garage
	------------------------------------------------------------------
	api.shell("WestHouse", -54, 70, -26, 104, 0, 12, {
		color = C(160, 140, 120),
		openings = { { side = "e", from = 84, to = 90, height = 7 } },
	})
	api.box("EastHouse", V(26, 0, 60), V(54, 12, 96), C(150, 128, 104), "Concrete")
	api.box("EastHouseRoof", V(25, 12, 59), V(55, 13, 97), C(80, 60, 52), "Slate")
	api.shell("Garage", 26, 104, 46, 128, 0, 10, {
		color = C(140, 132, 120),
		openings = { { side = "w", from = 110, to = 122, height = 8 } },
		floorMaterial = "Concrete",
	})
	-- Broken fence lines (low cover)
	api.box("FenceW", V(-40, 0, 52), V(-20, 3.5, 53), C(120, 95, 70), "WoodPlanks")
	api.box("FenceE", V(20, 0, 108), V(25, 3.5, 109), C(120, 95, 70), "WoodPlanks")
	car(api, -8, 64, 12, C(120, 40, 40))
	light(api, V(-18, 9, 100), C(255, 170, 90))
	light(api, V(18, 9, 60), C(255, 170, 90))

	------------------------------------------------------------------
	-- Zone 1: Main Street — facades north, open street, south lot
	------------------------------------------------------------------
	api.box("BlockA_Shops", V(-110, 0, -64), V(14, 18, -32), STUCCO, "Concrete")
	api.box("BlockC_Theater", V(58, 0, -64), V(120, 22, -32), BRICK, "Brick")
	api.box("TheaterMarquee", V(72, 11, -34), V(104, 15, -30), C(60, 40, 40), "Metal")
	-- Fallen water tower: tank lying across the west side of the street, legs in the field
	local tank = api.part({ Name = "WaterTowerTank", Shape = Enum.PartType.Cylinder, Size = V(22, 13, 13), CFrame = CFrame.new(-48, 6.5, -12) * CFrame.Angles(0, math.rad(25), 0), Color = C(150, 150, 140), Material = "CorrodedMetal" })
	tank.Shape = Enum.PartType.Cylinder
	for i, leg in { V(-66, 0, 20), V(-58, 0, 26), V(-74, 0, 28) } do
		api.part({ Name = "TowerLeg" .. i, Size = V(1.2, 22, 1.2), CFrame = CFrame.new(leg + V(0, 9, 0)) * CFrame.Angles(math.rad(-35), math.rad(20), 0), Color = C(110, 110, 104), Material = "Metal" })
	end
	-- Bus + wrecked cars (cover)
	api.box("Bus", V(14, 0, -23), V(48, 10, -14), C(200, 150, 40), "CorrodedMetal")
	car(api, 72, -3, 20, C(70, 80, 110))
	car(api, -82, -16, 80, C(90, 90, 90))
	car(api, 96, -19, -12, C(140, 120, 90))
	car(api, -16, 0, 35, C(60, 90, 70))
	-- South lot rubble
	api.box("Rubble1", V(70, 0, 22), V(80, 3, 30), CONCRETE, "Concrete")
	api.box("Rubble2", V(-96, 0, 14), V(-88, 2.5, 22), CONCRETE, "Concrete")
	for _, p in { V(-60, 9, -31), V(-5, 9, -31), V(85, 9, 9), V(-90, 9, 9) } do
		light(api, p, C(255, 150, 80), 26)
	end

	------------------------------------------------------------------
	-- Zone 2: Gas Station — canopy + pumps, store, garage bay
	------------------------------------------------------------------
	api.box("CanopyRoof", V(-166, 14, -41), V(-129, 15.5, -9), C(200, 60, 50), "Metal")
	for _, p in { V(-163, 0, -38), V(-132, 0, -38), V(-163, 0, -12), V(-132, 0, -12) } do
		api.box("CanopyPillar", p + V(-0.75, 0, -0.75), p + V(0.75, 14, 0.75), C(220, 220, 215), "Concrete")
	end
	api.box("Pump1", V(-156, 0, -27), V(-153, 5, -23), C(200, 200, 190), "Metal")
	api.box("Pump2", V(-142, 0, -27), V(-139, 5, -23), C(200, 200, 190), "Metal")
	api.shell("GasStore", -172, 0, -140, 30, 0, 12, {
		color = C(190, 180, 160),
		openings = { { side = "n", from = -158, to = -152, height = 7 } },
		floorMaterial = "Concrete",
	})
	api.shell("GasGarage", -140, 0, -115, 30, 0, 12, {
		color = C(170, 165, 150),
		openings = { { side = "n", from = -136, to = -120, height = 10 } },
		floorMaterial = "Concrete",
	})
	api.box("StoreShelf", V(-168, 0, 12), V(-150, 5, 14), C(90, 90, 100), "Metal")
	car(api, -150, -55, 70, C(160, 160, 160))
	light(api, V(-147, 13.6, -25), C(255, 240, 220), 34)

	------------------------------------------------------------------
	-- Zone 3: Diner — interior with counter and booths, back yard
	------------------------------------------------------------------
	api.shell("Diner", 14, -64, 58, -32, 0, 10, {
		color = C(200, 200, 205),
		openings = {
			{ side = "s", from = 30, to = 36, height = 8 }, -- front door (D3)
			{ side = "n", from = 44, to = 50, height = 8 }, -- kitchen back door
		},
		floorColor = C(210, 210, 210),
		floorMaterial = "Marble",
	})
	api.box("Counter", V(20, 0, -56), V(42, 3.5, -52), C(150, 40, 40), "SmoothPlastic")
	for _, z in { -50, -43 } do
		api.box("Booth", V(50, 0, z), V(56, 3, z + 4), C(170, 40, 50), "Fabric")
	end
	api.box("DinerSign", V(20, 10, -33), V(52, 14, -32.5), C(255, 80, 120), "Neon")
	light(api, V(36, 9.4, -48), C(255, 230, 200), 28)

	------------------------------------------------------------------
	-- Zone 4: Motel — U-shape, balcony + stairs, pool, pump-house
	------------------------------------------------------------------
	api.box("MotelNorthW", V(121, 0, -75), V(150, 24, -55), STUCCO, "Concrete")
	api.shell("MotelRoom", 150, -75, 165, -55, 0, 11, {
		color = C(186, 160, 130),
		openings = { { side = "s", from = 155, to = 159, height = 7 } },
		floorColor = C(110, 60, 60),
		floorMaterial = "Fabric",
	})
	api.box("MotelRoomUpper", V(150, 12, -75), V(165, 24, -55), STUCCO, "Concrete")
	api.box("MotelNorthE", V(165, 0, -75), V(209, 24, -55), STUCCO, "Concrete")
	api.box("MotelEastWing", V(185, 0, -55), V(209, 24, 40), STUCCO, "Concrete")
	api.shell("MotelOffice", 121, 20, 150, 40, 0, 11, {
		color = C(186, 160, 130),
		openings = { { side = "n", from = 133, to = 139, height = 7 } },
	})
	api.box("MotelSouthWing", V(150, 0, 20), V(185, 12, 40), STUCCO, "Concrete")
	-- Upper balcony along the north wing, reached by a ramp/stair on the east end
	api.box("Balcony", V(121, 11, -55), V(185, 12, -49), CONCRETE, "Concrete")
	api.box("BalconyRail", V(121, 12, -49.5), V(179, 15, -49), C(90, 90, 95), "Metal")
	api.ramp("BalconyStairs", 179, -49, 185, -25, 0, 12, "n", CONCRETE)
	api.box("StairSupport", V(185, 0, -49), V(185.5, 12, -25), CONCRETE, "Concrete")
	-- Drained pool (rim only for now)
	api.box("PoolFloor", V(140, 0, -20), V(170, 0.08, 0), C(90, 130, 150), "Concrete", { CanCollide = false })
	api.box("PoolRimN", V(140, 0, -21), V(170, 1, -20), C(220, 220, 215), "Concrete")
	api.box("PoolRimS", V(140, 0, 0), V(170, 1, 1), C(220, 220, 215), "Concrete")
	api.box("PoolRimW", V(139, 0, -21), V(140, 1, 1), C(220, 220, 215), "Concrete")
	api.box("PoolRimE", V(170, 0, -21), V(171, 1, 1), C(220, 220, 215), "Concrete")
	api.box("MotelSign", V(122, 14, 8), V(124, 26, 12), C(255, 90, 60), "Neon")
	-- Pump-house over the storm-drain stairwell (D5 seals its south doorway)
	api.shell("PumpHouse", 125, -46, 135, -7, 0, 9, {
		color = C(130, 130, 125),
		openings = { { side = "s", from = 126, to = 134, height = 8 } },
		floor = false,
	})
	light(api, V(150, 10, -50.5), C(255, 120, 80), 26)
	light(api, V(160, 9, -2), C(160, 220, 255), 24)

	------------------------------------------------------------------
	-- Zone 5: Underground — ramp down, landing, tunnel, lab (y = -20)
	------------------------------------------------------------------
	api.ramp("DrainRamp", 126, -45, 134, -7, -20, 0, "s", CONCRETE)
	api.box("TrenchW", V(125, -20, -45), V(126, 0, -7), CONCRETE, "Concrete")
	api.box("TrenchE", V(134, -20, -45), V(135, 0, -7), CONCRETE, "Concrete")
	api.shell("Landing", 120, -62, 140, -45, -20, 12, {
		color = CONCRETE,
		openings = {
			{ side = "s", from = 126, to = 134, height = 12 },
			{ side = "w", from = -58, to = -48, height = 10 },
		},
		floorMaterial = "Concrete",
		floorColor = C(80, 80, 82),
	})
	api.shell("Tunnel", 62, -58, 120, -48, -20, 10, {
		color = C(100, 100, 102),
		openings = {
			{ side = "e", from = -58, to = -48, height = 10 },
			{ side = "w", from = -58, to = -48, height = 10 },
		},
		floorMaterial = "Concrete",
		floorColor = C(70, 70, 72),
	})
	api.shell("Lab", 20, -66, 62, -40, -20, 14, {
		color = C(150, 155, 160),
		openings = { { side = "e", from = -58, to = -48, height = 10 } },
		floorMaterial = "DiamondPlate",
		floorColor = C(90, 95, 100),
	})
	api.box("LabConsole", V(24, -20, -46), V(34, -17, -42), C(60, 70, 80), "Metal")
	for _, p in { V(130, -9, -53), V(100, -10.4, -53), V(75, -10.4, -53), V(41, -6.4, -53) } do
		light(api, p, C(140, 255, 180), 22)
	end
end
