--!nonstrict
-- Dustwater geometry — Stage 2 ARCHITECTURE.
-- Real buildings: walls with doors and glass windows, interiors and partitions,
-- gable/flat roofs, storefronts, motel facades on two floors, underground details.
-- Footprints and coordinates match the v2 layout (init.luau) so doors, stations
-- and spawns stay valid. Destruction/debris/fire come in Stage 3.

local V = Vector3.new
local C = Color3.fromRGB

local SAND = C(196, 160, 112)
local ASPHALT = C(52, 50, 52)
local SIDEWALK = C(140, 132, 120)
local STUCCO = C(176, 150, 118)
local STUCCO2 = C(168, 140, 112)
local BRICK = C(130, 80, 62)
local CONCRETE = C(120, 118, 114)
local CHARRED = C(45, 38, 34)
local DARK = C(28, 24, 24)
local WOOD = C(110, 78, 52)
local TRIM = C(225, 218, 200)
local METAL = C(90, 90, 95)

------------------------------------------------------------------
-- Small helpers
------------------------------------------------------------------

local function overlay(api, name, x0, z0, x1, z1, color, material)
	-- Flat visual strip on top of the ground (roads, sidewalks). Not collidable.
	api.box(name, V(x0, 0, z0), V(x1, 0.06, z1), color, material, { CanCollide = false, CanQuery = false })
end

local function pointLight(part, color, range, brightness)
	local l = Instance.new("PointLight")
	l.Color = color
	l.Range = range or 20
	l.Brightness = brightness or 1.6
	l.Parent = part
end

local function light(api, pos: Vector3, color: Color3, range: number?)
	local p = api.part({ Name = "Light", Size = V(1.2, 0.3, 1.2), Position = pos, Color = color, Material = "Neon", CanCollide = false, CanQuery = false })
	pointLight(p, color, range)
	return p
end

-- Street lamp: pole + arm + glowing head. dirX/dirZ = which way the arm reaches.
local function streetLamp(api, x, z, dirX, dirZ, color)
	api.box("LampPole", V(x - 0.35, 0, z - 0.35), V(x + 0.35, 13, z + 0.35), C(60, 60, 64), "Metal")
	local hx, hz = x + dirX * 3, z + dirZ * 3
	api.box("LampArm", V(math.min(x, hx) - 0.2, 12.6, math.min(z, hz) - 0.2), V(math.max(x, hx) + 0.2, 13, math.max(z, hz) + 0.2), C(60, 60, 64), "Metal")
	local head = api.part({ Name = "LampHead", Size = V(1.6, 0.5, 1.6), Position = V(hx, 12.4, hz), Color = color or C(255, 170, 90), Material = "Neon", CanCollide = false })
	pointLight(head, color or C(255, 170, 90), 30, 1.8)
end

local function car(api, x, z, yawDeg, color, y)
	local cf = CFrame.new(x, y or 0, z) * CFrame.Angles(0, math.rad(yawDeg), 0)
	api.part({ Name = "CarBody", Size = V(7, 3, 15), CFrame = cf * CFrame.new(0, 2, 0), Color = color, Material = "CorrodedMetal" })
	api.part({ Name = "CarCabin", Size = V(6.4, 2.4, 7), CFrame = cf * CFrame.new(0, 4.6, 1), Color = color:Lerp(C(0, 0, 0), 0.4), Material = "CorrodedMetal" })
	api.part({ Name = "CarGlass", Size = V(6.6, 1.6, 0.2), CFrame = cf * CFrame.new(0, 4.6, -2.6), Color = C(40, 50, 55), Material = "Glass", Transparency = 0.3 })
	for _, w in { { -3.6, -4.8 }, { 3.6, -4.8 }, { -3.6, 4.8 }, { 3.6, 4.8 } } do
		api.part({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = V(1, 2.6, 2.6), CFrame = cf * CFrame.new(w[1], 1.3, w[2]), Color = C(25, 25, 25), Material = "SmoothPlastic" })
	end
end

local function deadTree(api, x, z, h)
	api.part({ Name = "DeadTree", Size = V(1.4, h, 1.4), CFrame = CFrame.new(x, h / 2, z) * CFrame.Angles(math.rad(6), math.rad(x % 90), 0), Color = CHARRED, Material = "Wood" })
	api.part({ Name = "DeadBranch", Size = V(0.6, 6, 0.6), CFrame = CFrame.new(x, h * 0.75, z) * CFrame.Angles(0, 0, math.rad(50)) * CFrame.new(0, 2.5, 0), Color = CHARRED, Material = "Wood" })
	api.part({ Name = "DeadBranch", Size = V(0.5, 4.5, 0.5), CFrame = CFrame.new(x, h * 0.6, z) * CFrame.Angles(math.rad(40), 0, math.rad(-35)) * CFrame.new(0, 2, 0), Color = CHARRED, Material = "Wood" })
end

local function fence(api, x0, z0, x1, z1)
	api.box("Fence", V(math.min(x0, x1), 0, math.min(z0, z1)), V(math.max(x0, x1) + 0.4, 3.5, math.max(z0, z1) + 0.4), C(120, 95, 70), "WoodPlanks")
end

-- Decorative panel mounted on a wall face (fake doors/windows on non-enterable facades).
-- axis "x": wall runs along X, face at z = face, sign = +1/-1 (which side the panel sticks out)
local function panel(api, axis, face, sign, s0, s1, y0, y1, color, material, extra)
	-- Decorative facings never collide: a trim strip once blocked the diner doorway
	-- at knee height and trapped zombies.
	extra = extra and table.clone(extra) or {}
	if extra.CanCollide == nil then
		extra.CanCollide = false
	end
	local d0, d1 = face, face + sign * 0.25
	if axis == "x" then
		return api.box("Panel", V(s0, y0, math.min(d0, d1)), V(s1, y1, math.max(d0, d1)), color, material, extra)
	else
		return api.box("Panel", V(math.min(d0, d1), y0, s0), V(math.max(d0, d1), y1, s1), color, material, extra)
	end
end

-- Row of motel-style units (door + window) on a facade between a0..a1, skipping `avoid` ranges.
local function motelUnits(api, axis, face, sign, a0, a1, y0, spacing, avoid)
	local s = a0 + 2
	while s + 9 <= a1 do
		local blocked = false
		for _, a in avoid or {} do
			if s + 9 > a[1] and s < a[2] then
				blocked = true
			end
		end
		if not blocked then
			panel(api, axis, face, sign, s, s + 3.6, y0, y0 + 7.2, C(120, 60, 50), "WoodPlanks") -- door
			panel(api, axis, face, sign, s + 0.8, s + 2.8, y0 + 5.2, y0 + 6.2, C(240, 220, 160), "Neon") -- room number plate glow
			panel(api, axis, face, sign, s + 5, s + 9, y0 + 3, y0 + 6.5, C(40, 50, 60), "Glass", { Transparency = 0.15 }) -- window
			panel(api, axis, face, sign, s + 4.7, s + 9.3, y0 + 2.7, y0 + 3, TRIM, "SmoothPlastic") -- sill
		end
		s += spacing
	end
end

-- Storefront building (non-enterable): walls, big glass windows on the front, visible
-- interior props, upper-floor windows, flat roof with parapet + rooftop units.
local function storefront(api, name, minX, minZ, maxX, frontZ, height, color, windows, upperAvoid)
	api.shell(name, minX, minZ, maxX, frontZ, 0, height, {
		color = color,
		openings = windows, -- glass storefront windows on side "s"
		roof = "flat",
		parapet = 2.5,
		roofColor = C(70, 64, 60),
		floorMaterial = "Concrete",
	})
	-- second floor slab inside + upper windows (fake: dark glass panels)
	api.box(name .. "_UpperFloor", V(minX + 0.5, 9.6, minZ + 0.5), V(maxX - 0.5, 10.2, frontZ - 0.5), C(60, 55, 50), "Concrete")
	local x = minX + 5
	while x + 6 <= maxX - 3 do
		local skip = false
		for _, a in upperAvoid or {} do
			if x + 6 > a[1] and x < a[2] then
				skip = true
			end
		end
		if not skip then
			panel(api, "x", frontZ + 0.5, 1, x, x + 5, 12, 15.5, C(35, 40, 48), "Glass", { Transparency = 0.1 })
			panel(api, "x", frontZ + 0.5, 1, x - 0.3, x + 5.3, 11.7, 12, TRIM, "SmoothPlastic")
			if height >= 26 then -- third storey
				local lit = (x * 7) % 5 == 0 -- the odd window still has a light on
				panel(api, "x", frontZ + 0.5, 1, x, x + 5, 20, 23.5, lit and C(255, 190, 110) or C(35, 40, 48), lit and "Neon" or "Glass", { Transparency = lit and 0.35 or 0.1 })
				panel(api, "x", frontZ + 0.5, 1, x - 0.3, x + 5.3, 19.7, 20, TRIM, "SmoothPlastic")
			end
		end
		x += 10
	end
	-- awning band over the storefront
	api.box(name .. "_Awning", V(minX, 9, frontZ + 0.5), V(maxX, 9.6, frontZ + 3.5), C(120, 50, 45), "Fabric")
	-- rooftop AC units
	api.box(name .. "_AC", V(minX + 6, height + 1, minZ + 8), V(minX + 12, height + 4, minZ + 13), C(150, 150, 150), "Metal")
end

return function(api)
	------------------------------------------------------------------
	-- Ground (holes for both underground ramps) and roads
	------------------------------------------------------------------
	api.floor("Ground", -260, -112, 300, 225, 0, SAND, "Sand", {
		{ 251, -59, 261, -9 }, -- motel storm drain
		{ -86, -99, -20, -89 }, -- alley sewer ramp (10 wide, gentle slope)
	})

	overlay(api, "MainStreet", -150, -32, 170, 4, ASPHALT, "Asphalt")
	overlay(api, "LaneLine", -150, -14.3, 170, -13.7, C(200, 170, 60), "SmoothPlastic")
	overlay(api, "SidewalkN", -150, -40, 170, -32, SIDEWALK, "Concrete")
	overlay(api, "SidewalkS", -150, 4, 170, 12, SIDEWALK, "Concrete")
	overlay(api, "ElmLane", -14, 12, 14, 165, ASPHALT, "Asphalt")
	overlay(api, "LoopRoad", -30, 165, 30, 215, ASPHALT, "Asphalt")
	overlay(api, "GasApron", -255, -100, -152, 10, C(90, 88, 86), "Concrete")
	overlay(api, "MotelLot", 172, -72, 280, 60, C(110, 104, 96), "Concrete")
	overlay(api, "Alley", -96, -112, 36, -84, C(64, 60, 58), "Asphalt")
	overlay(api, "AlleyPassage", -96, -84, -88, -40, C(64, 60, 58), "Asphalt")
	-- Driveways
	overlay(api, "DrivewayE", 14, 178, 40, 192, C(110, 106, 100), "Concrete")
	overlay(api, "WalkW", -35, 136, -14, 142, C(130, 124, 116), "Concrete")
	overlay(api, "WalkE", 14, 140, 35, 146, C(130, 124, 116), "Concrete")

	------------------------------------------------------------------
	-- Zone 0: Elm Lane — two enterable houses, garage, shed, loop road
	------------------------------------------------------------------
	-- West house: front door (east) → living room → partition doorway → kitchen → back door (west)
	api.shell("WestHouse", -70, 120, -35, 160, 0, 11, {
		color = C(186, 170, 150),
		trimColor = TRIM,
		openings = {
			{ side = "e", from = 136, to = 142, height = 7.5 }, -- front door
			{ side = "e", from = 146, to = 152, bottom = 3, height = 4, glass = true },
			{ side = "e", from = 153.5, to = 158, bottom = 3, height = 4, glass = true },
			{ side = "w", from = 128, to = 134, height = 7.5 }, -- back door
			{ side = "w", from = 144, to = 150, bottom = 3, height = 4, glass = true },
			{ side = "n", from = -64, to = -57, bottom = 3, height = 4, glass = true },
			{ side = "n", from = -49, to = -42, bottom = 3, height = 4, glass = true },
			{ side = "s", from = -64, to = -57, bottom = 3, height = 4, glass = true },
			{ side = "s", from = -49, to = -42, bottom = 3, height = 4, glass = true },
		},
		roof = "gable", ridge = "z", rise = 7, roofColor = C(96, 62, 50),
		floorColor = C(120, 86, 60),
	})
	api.wall("WestHouse_Partition", "z", -52, 120.5, 159.5, 0, 11, { { from = 130, to = 138, height = 7.5 } }, { color = C(210, 200, 185) })
	api.box("Couch", V(-50, 0, 150), V(-45, 2.5, 158), C(90, 70, 110), "Fabric")
	api.box("CoffeeTable", V(-44, 0, 149), V(-40, 1.6, 154), WOOD, "Wood")
	api.box("KitchenCounter", V(-69.5, 0, 140), V(-66, 3.5, 159.5), C(200, 195, 185), "SmoothPlastic")
	api.box("Fridge", V(-69.5, 0, 121), V(-66.5, 7, 124), C(220, 220, 220), "SmoothPlastic")
	api.box("DiningTable", V(-62, 0, 143), V(-57, 2.8, 148), WOOD, "Wood")
	api.box("WestHousePorch", V(-35, 0, 133), V(-31, 0.6, 145), C(140, 110, 80), "WoodPlanks")

	-- East house: front door (west) → hall → partition → back door (east)
	api.shell("EastHouse", 35, 115, 72, 150, 0, 11, {
		color = C(170, 150, 126),
		trimColor = TRIM,
		openings = {
			{ side = "w", from = 140, to = 146, height = 7.5 }, -- front door
			{ side = "w", from = 118, to = 124, bottom = 3, height = 4, glass = true },
			{ side = "e", from = 125, to = 131, height = 7.5 }, -- back door
			{ side = "e", from = 136, to = 144, bottom = 3, height = 4, glass = true },
			{ side = "n", from = 42, to = 50, bottom = 3, height = 4, glass = true },
			{ side = "n", from = 58, to = 66, bottom = 3, height = 4, glass = true },
			{ side = "s", from = 42, to = 50, bottom = 3, height = 4, glass = true },
			{ side = "s", from = 58, to = 66, bottom = 3, height = 4, glass = true },
		},
		roof = "gable", ridge = "z", rise = 7, roofColor = C(80, 60, 52),
		floorColor = C(110, 80, 58),
	})
	api.wall("EastHouse_Partition", "z", 54, 115.5, 149.5, 0, 11, { { from = 128, to = 136, height = 7.5 } }, { color = C(205, 195, 180) })
	api.box("Bed", V(60, 0, 140), V(70, 2.2, 149), C(150, 150, 170), "Fabric")
	api.box("Dresser", V(66, 0, 116), V(71, 4, 119), WOOD, "Wood")
	api.box("Bookshelf", V(36, 0, 128), V(38, 8, 136), WOOD, "Wood")
	api.box("EastHousePorch", V(31, 0, 137), V(35, 0.6, 149), C(140, 110, 80), "WoodPlanks")

	-- Garage (Mystery Box spot 1 inside, against the east wall)
	api.shell("Garage", 40, 170, 65, 200, 0, 10, {
		color = C(160, 150, 136),
		openings = {
			{ side = "w", from = 178, to = 192, height = 8 }, -- roll-up door opening
			{ side = "n", from = 48, to = 56, bottom = 4.5, height = 3, glass = true },
			{ side = "s", from = 48, to = 56, bottom = 4.5, height = 3, glass = true },
		},
		roof = "gable", ridge = "z", rise = 5, roofColor = C(90, 70, 60),
		floorMaterial = "Concrete", floorColor = C(110, 108, 104),
	})
	api.box("GarageDoorRolled", V(39.0, 8, 178), V(39.45, 9.6, 192), C(200, 200, 205), "Metal")
	api.box("Workbench", V(44, 0, 171), V(58, 3.2, 174), WOOD, "Wood")
	api.box("ToolBoard", V(44, 4, 170.6), V(58, 8, 171), C(120, 110, 90), "WoodPlanks")
	api.box("Shelving", V(41, 0, 196), V(50, 7, 199), METAL, "Metal")

	-- Shed (enterable, tiny)
	api.shell("Shed", -88, 185, -76, 200, 0, 7, {
		color = C(120, 100, 80), material = "WoodPlanks",
		openings = { { side = "e", from = 189, to = 195, height = 6 } },
		roof = "gable", ridge = "z", rise = 3, roofColor = C(70, 60, 55),
	})

	api.box("Median", V(-10, 0, 180), V(10, 1.2, 200), C(90, 80, 60), "Ground")
	deadTree(api, 0, 190, 14)
	fence(api, -96, 172, -80, 172)
	fence(api, -62, 172, -45, 172)
	fence(api, 72, 160, 96, 160)
	fence(api, 76, 205, 76, 222)
	api.box("Mailbox", V(-17, 0, 138), V(-16, 3.6, 139), C(70, 70, 120), "Metal")
	api.box("Mailbox", V(16, 0, 142), V(17, 3.6, 143), C(120, 50, 50), "Metal")
	api.box("Hydrant", V(15, 0, 120), V(16.2, 2.4, 121.2), C(200, 60, 40), "Metal")
	-- (burned-out car at -8,118 is placed by Environment.luau)
	car(api, 78, 110, 80, C(60, 70, 90))
	car(api, 27, 185, 90, C(150, 140, 120))
	streetLamp(api, -17, 150, 1, 0)
	streetLamp(api, 17, 110, -1, 0)
	streetLamp(api, -33, 205, 1, 0)
	streetLamp(api, 33, 205, -1, 0)

	------------------------------------------------------------------
	-- Zone 1: Main Street — storefront blocks, theater, street, field + junkyard
	------------------------------------------------------------------
	-- Hardware store (A1): front face at z = -40 (wall centered at -40.5)
	storefront(api, "A1_Hardware", -150, -84, -96, -40.5, 28, STUCCO, {
		{ side = "s", from = -146, to = -128, bottom = 1.5, height = 6.5, glass = true },
		{ side = "s", from = -114, to = -100, bottom = 1.5, height = 6.5, glass = true },
	})
	api.box("A1_Shelves", V(-146, 0, -60), V(-128, 6, -57), METAL, "Metal")
	api.box("A1_Shelves", V(-114, 0, -60), V(-100, 6, -57), METAL, "Metal")
	api.box("A1_Sign", V(-146, 10.2, -40.2), V(-100, 11.6, -39.8), C(200, 180, 120), "SmoothPlastic")

	-- Shops (A2): two shops split by a partition; shotgun wall-buy sits on the pier at x -60
	storefront(api, "A2_Shops", -88, -84, -24, -40.5, 32, STUCCO2, {
		{ side = "s", from = -84, to = -66, bottom = 1.5, height = 6.5, glass = true },
		{ side = "s", from = -52, to = -30, bottom = 1.5, height = 6.5, glass = true },
	}, { { -64, -56 } })
	api.wall("A2_Partition", "z", -56, -83.5, -41, 0, 9.6, {}, { color = C(200, 190, 175) })
	api.box("A2_Racks", V(-82, 0, -62), V(-68, 5, -60), C(140, 60, 80), "Fabric")
	api.box("A2_Counter", V(-50, 0, -54), V(-36, 3.5, -51), WOOD, "Wood")

	-- Theater (C): tall brick front, recessed glass doors, box office, marquee, blade sign
	api.shell("C_Theater", 36, -84, 170, -40.5, 0, 34, {
		color = BRICK, material = "Brick",
		openings = {
			{ side = "s", from = 88, to = 104, bottom = 0.2, height = 8, glass = true }, -- lobby doors (glass, closed)
			{ side = "s", from = 108, to = 113, bottom = 3, height = 3.5, glass = true }, -- box office window
		},
		roof = "flat", parapet = 3, roofColor = C(60, 50, 48),
	})
	api.box("TheaterLobby", V(70, 0, -60), V(130, 0.4, -41), C(120, 30, 40), "Fabric")
	api.box("TheaterMarquee", V(70, 11, -42), V(120, 15, -37), C(50, 36, 36), "Metal")
	api.box("MarqueeLights", V(70, 10.6, -37.2), V(120, 11, -36.8), C(255, 220, 140), "Neon")
	api.box("MarqueeLights", V(70, 15, -37.2), V(120, 15.4, -36.8), C(255, 220, 140), "Neon")
	local blade = api.box("BladeSign", V(150, 9, -40), V(151.5, 26, -36), C(255, 80, 150), "Neon")
	pointLight(blade, C(255, 80, 150), 24, 1.2)
	for _, x in { 50, 60, 140, 160 } do
		panel(api, "x", -40, 1, x, x + 6, 2, 10, C(30, 30, 40), "SmoothPlastic") -- poster frames
		panel(api, "x", -39.75, 1, x + 0.5, x + 5.5, 2.5, 9.5, C(90 + x % 120, 40, 60 + x % 90), "SmoothPlastic")
	end

	-- Fallen water tower
	api.part({ Name = "WaterTowerTank", Shape = Enum.PartType.Cylinder, Size = V(24, 14, 14), CFrame = CFrame.new(-62, 7, -12) * CFrame.Angles(0, math.rad(25), 0), Color = C(150, 150, 140), Material = "CorrodedMetal" })
	api.part({ Name = "WaterTowerBand", Shape = Enum.PartType.Cylinder, Size = V(1.2, 14.4, 14.4), CFrame = CFrame.new(-62, 7, -12) * CFrame.Angles(0, math.rad(25), 0) * CFrame.new(5, 0, 0), Color = C(120, 60, 50), Material = "Metal" })
	for i, leg in { V(-80, 0, 32), V(-70, 0, 40), V(-90, 0, 42) } do
		api.part({ Name = "TowerLeg" .. i, Size = V(1.4, 26, 1.4), CFrame = CFrame.new(leg + V(0, 10, 0)) * CFrame.Angles(math.rad(-35), math.rad(20), 0), Color = C(110, 110, 104), Material = "Metal" })
	end
	-- Bus (windows + wheels) and cars
	api.box("Bus", V(20, 0.8, -27), V(60, 10, -17), C(200, 150, 40), "CorrodedMetal")
	api.box("BusWindows", V(22, 5.5, -27.15), V(58, 8.5, -16.85), C(40, 45, 50), "Glass", { Transparency = 0.2 })
	for _, x in { 25, 55 } do
		for _, z in { -27.3, -16.7 } do
			api.part({ Name = "BusWheel", Shape = Enum.PartType.Cylinder, Size = V(1, 3.2, 3.2), CFrame = CFrame.new(x, 1.6, z) * CFrame.Angles(0, math.rad(90), 0), Color = C(25, 25, 25), Material = "SmoothPlastic" })
		end
	end
	car(api, 100, -6, 20, C(70, 80, 110))
	car(api, -118, -20, 80, C(90, 90, 90))
	car(api, 140, -24, -12, C(140, 120, 90))
	car(api, -28, -2, 35, C(60, 90, 70))
	for _, p in { { -130, -36, 0, 1 }, { -68, -36, 0, 1 }, { 20, -36, 0, 1 }, { 130, -36, 0, 1 }, { -100, 8, 0, -1 }, { 40, 8, 0, -1 }, { 140, 8, 0, -1 } } do
		streetLamp(api, p[1], p[2], p[3], p[4])
	end

	-- Burned field (west lot)
	api.floor("FieldAsh", -150, 12, -40, 90, 0.08, C(70, 60, 50), "Ground")
	for _, t in { { -120, 40, 16 }, { -110, 72, 12 }, { -58, 76, 14 }, { -136, 20, 10 }, { -95, 60, 18 } } do
		deadTree(api, t[1], t[2], t[3])
	end
	api.shell("BurntShack", -130, 50, -112, 62, 0, 7, {
		color = CHARRED, material = "Wood",
		openings = { { side = "n", from = -124, to = -119, height = 6 }, { side = "e", from = 53, to = 58, bottom = 2.5, height = 3 } },
		roof = "gable", ridge = "x", rise = 3, roofColor = C(40, 34, 30),
	})
	fence(api, -150, 30, -128, 30)

	-- Junkyard (east lot)
	api.box("Container", V(100, 0, 60), V(126, 9, 70), C(150, 60, 40), "CorrodedMetal")
	api.box("Container2", V(58, 0, 40), V(66, 9, 62), C(50, 90, 120), "CorrodedMetal")
	api.box("Container3", V(100, 9, 61), V(122, 18, 69), C(80, 110, 70), "CorrodedMetal")
	-- Keep players off the container stack and the bus roof (unreachable camping spots)
	api.clip("ContainerClip", V(99, 9, 59), V(127, 34, 71))
	api.clip("Container2Clip", V(57, 9, 39), V(67, 24, 63))
	api.clip("BusClip", V(19, 10, -28), V(61, 24, -16))
	car(api, 80, 32, 0, C(120, 110, 100))
	car(api, 80, 32, 10, C(90, 60, 50), 5)
	car(api, 145, 40, 85, C(100, 100, 110))
	car(api, 150, 72, 40, C(130, 90, 60))
	api.box("ScrapPile", V(112, 0, 22), V(126, 4, 34), C(90, 80, 70), "CorrodedMetal")
	api.box("TireStack", V(70, 0, 76), V(74, 4, 80), C(25, 25, 25), "SmoothPlastic")
	api.box("JunkyardFence", V(40, 0, 88.6), V(168, 6, 89), C(110, 110, 110), "DiamondPlate", { Transparency = 0.3 })

	------------------------------------------------------------------
	-- Zone 2: Gas Station — canopy + pumps, store (front + back), garage bay
	------------------------------------------------------------------
	api.box("CanopyRoof", V(-236, 14, -51), V(-184, 15.5, -13), C(220, 220, 215), "Metal")
	api.box("CanopyFascia", V(-236.4, 15.5, -51.4), V(-183.6, 17.5, -12.6), C(200, 60, 50), "SmoothPlastic")
	api.box("CanopyUnderLight", V(-226, 13.8, -40), V(-194, 14, -24), C(255, 245, 230), "Neon")
	for _, p in { V(-233, 0, -48), V(-187, 0, -48), V(-233, 0, -16), V(-187, 0, -16) } do
		api.box("CanopyPillar", p + V(-0.75, 0, -0.75), p + V(0.75, 14, 0.75), C(220, 220, 215), "Concrete")
	end
	for _, x in { -222, -200 } do
		api.box("PumpIsland", V(x - 4, 0, -38), V(x + 4, 0.6, -28), C(200, 200, 195), "Concrete")
		api.box("Pump", V(x - 2, 0.6, -36), V(x + 2, 5.6, -30), C(220, 210, 200), "Metal")
		api.box("PumpScreen", V(x - 1, 3.5, -36.2), V(x + 1, 4.8, -36), C(80, 200, 255), "Neon")
	end
	api.shell("GasStore", -250, 15, -205, 55, 0, 12, {
		color = C(200, 192, 176),
		openings = {
			{ side = "n", from = -232, to = -224, height = 7.5 }, -- front door
			{ side = "n", from = -248, to = -234, bottom = 1.5, height = 6, glass = true },
			{ side = "n", from = -222, to = -208, bottom = 1.5, height = 6, glass = true },
			{ side = "s", from = -215, to = -209, height = 7.5 }, -- back door
			{ side = "w", from = 26, to = 34, bottom = 4, height = 3, glass = true },
		},
		roof = "flat", parapet = 2, roofColor = C(70, 66, 62),
		floorMaterial = "Marble", floorColor = C(200, 200, 195),
	})
	api.box("StoreShelf1", V(-246, 0, 28), V(-222, 5, 30), METAL, "Metal")
	api.box("StoreShelf2", V(-246, 0, 38), V(-222, 5, 40), METAL, "Metal")
	api.box("Cashier", V(-220, 0, 19), V(-210, 3.6, 22), C(150, 40, 40), "SmoothPlastic")
	api.box("Coolers", V(-249.5, 0, 44), V(-246.5, 8, 54), C(200, 220, 230), "Glass", { Transparency = 0.2 })
	api.box("StoreSign", V(-246, 12.4, 14.4), V(-209, 15, 14.8), C(255, 200, 60), "Neon")
	api.shell("GasGarage", -205, 15, -170, 55, 0, 12, {
		color = C(186, 180, 166),
		skip = { "w" }, -- shares the store's east wall
		openings = {
			{ side = "n", from = -200, to = -176, height = 10 }, -- bay door
			{ side = "e", from = 26, to = 36, bottom = 5, height = 3, glass = true },
		},
		roof = "flat", parapet = 2, roofColor = C(70, 66, 62),
		floorMaterial = "Concrete", floorColor = C(100, 98, 94),
	})
	api.box("Lift", V(-196, 0, 30), V(-184, 1, 44), C(200, 170, 40), "Metal")
	api.box("LiftPost", V(-197, 0, 30), V(-196, 8, 31), C(200, 170, 40), "Metal")
	api.box("ToolChest", V(-174, 0, 40), V(-171, 4, 48), C(180, 30, 30), "Metal")
	api.box("RollupDoor", V(-200, 10, 14.0), V(-176, 11.5, 14.45), C(200, 200, 205), "Metal")
	api.box("PriceSignPole", V(-245, 0, -8), V(-244, 22, -7), METAL, "Metal")
	api.box("PriceSign", V(-249, 18, -8.2), V(-240, 24, -6.8), C(255, 80, 60), "SmoothPlastic")
	-- (burned-out car at -215,-80 is placed by Environment.luau)
	car(api, -175, 75, 10, C(120, 50, 40))
	pointLight(api.part({ Name = "CanopyLamp", Size = V(2, 0.2, 2), Position = V(-210, 13.8, -32), Color = C(255, 245, 230), Material = "Neon", CanCollide = false }), C(255, 240, 220), 44, 2)
	streetLamp(api, -230, 70, 1, 0)

	------------------------------------------------------------------
	-- Zone 3: Diner + back alley; sewer ramp down to the lab
	------------------------------------------------------------------
	api.shell("Diner", -24, -84, 36, -40, 0, 10, {
		color = C(215, 215, 220),
		trimColor = C(200, 40, 50),
		openings = {
			{ side = "s", from = 0, to = 8, height = 8 }, -- front door (D3)
			{ side = "s", from = -21, to = -12, bottom = 3, height = 4.5, glass = true },
			{ side = "s", from = -10, to = -2, bottom = 3, height = 4.5, glass = true },
			{ side = "s", from = 11, to = 20, bottom = 3, height = 4.5, glass = true },
			{ side = "s", from = 22, to = 33, bottom = 3, height = 4.5, glass = true },
			{ side = "n", from = 12, to = 20, height = 8 }, -- kitchen back door → alley
			{ side = "n", from = -10, to = -2, bottom = 4.5, height = 3, glass = true },
		},
		roof = "flat", parapet = 1.5, roofColor = C(80, 76, 72),
		floorColor = C(230, 230, 230), floorMaterial = "Marble",
	})
	-- Chrome band + red stripe along the facade
	-- trim stripes stop at the front door (x 0..8)
	for _, seg in { { -24, 0 }, { 8, 36 } } do
		panel(api, "x", -39.5, 1, seg[1], seg[2], 2.4, 3, C(200, 40, 50), "SmoothPlastic")
		panel(api, "x", -39.5, 1, seg[1], seg[2], 8, 8.5, C(230, 230, 235), "Metal")
	end
	-- Kitchen partition with a pass-through window and a doorway
	api.wall("Diner_Kitchen", "x", -76, -23.5, 35.5, 0, 10, {
		{ from = -12, to = 8, bottom = 3.6, height = 2.8 }, -- pass-through
		{ from = 22, to = 28, height = 8 }, -- kitchen doorway
	}, { color = C(200, 200, 205) })
	api.box("Counter", V(-15, 0, -72), V(15, 3.5, -68), C(150, 40, 40), "SmoothPlastic")
	api.box("CounterTop", V(-15.3, 3.5, -72.3), V(15.3, 3.8, -67.7), C(230, 230, 235), "Marble")
	for x = -12, 12, 4 do
		-- stools are decor: non-collidable so zombies don't snag on them
		api.part({ Name = "Stool", Shape = Enum.PartType.Cylinder, Size = V(2.6, 1.6, 1.6), CFrame = CFrame.new(x, 1.3, -65.5) * CFrame.Angles(0, 0, math.rad(90)), Color = C(200, 40, 50), Material = "SmoothPlastic", CanCollide = false })
	end
	-- booths along the east wall, clear of the kitchen doorway (x 22..28 at z -76)
	-- and the Quick Hands machine (x 32.5..35.5, z -62..-58)
	for _, z in { -53, -47 } do
		api.box("Booth", V(30, 0, z), V(34, 3.2, z + 4), C(170, 40, 50), "Fabric")
		api.box("BoothTable", V(26, 0, z + 0.5), V(29.5, 2.7, z + 3.5), C(220, 220, 225), "SmoothPlastic")
	end
	api.box("Stove", V(-20, 0, -83.5), V(-12, 3.6, -80), C(160, 160, 165), "Metal")
	api.box("Fridge", V(-6, 0, -83.5), V(-1, 7, -80), C(210, 210, 215), "Metal")
	api.box("PrepTable", V(-23.5, 0, -79), V(-21, 3.4, -77), C(170, 170, 175), "Metal")
	local sign = api.box("DinerSign", V(-18, 11.5, -41), V(30, 15, -40.4), C(255, 80, 120), "Neon")
	pointLight(sign, C(255, 90, 130), 26, 1.2)
	light(api, V(6, 9.4, -62), C(255, 230, 200), 34)
	light(api, V(0, 9.4, -80), C(255, 240, 220), 18)
	-- Alley clutter
	api.box("Dumpster1", V(-62, 0, -110), V(-54, 5, -105), C(40, 80, 50), "Metal")
	api.box("Dumpster2", V(4, 0, -110), V(12, 5, -105), C(40, 80, 50), "Metal")
	api.box("Crates", V(-86, 0, -110), V(-80, 4, -102), C(120, 90, 60), "WoodPlanks")
	api.box("AlleyPipes", V(-96, 12, -84.8), V(36, 12.8, -84), METAL, "Metal")
	-- Sewer ramp into the lab (rails around the opening)
	-- Sewer ramp into the lab: 10 wide, 66 long (gentle), lit, rails on the alley edges
	api.ramp("SewerRamp", -86, -99, -20, -89, -20, 0, "w", CONCRETE)
	api.box("SewerTrenchN", V(-86, -20, -100), V(-20, 0, -99), CONCRETE, "Concrete")
	api.box("SewerTrenchS", V(-86, -20, -89), V(-20, 0, -88), CONCRETE, "Concrete")
	api.box("SewerTrenchW", V(-87, -20, -100), V(-86, 0, -88), CONCRETE, "Concrete")
	api.box("SewerRailN", V(-80, 0, -99.6), V(-20, 3, -99.1), METAL, "Metal")
	api.box("SewerRailS", V(-80, 0, -88.9), V(-20, 3, -88.4), METAL, "Metal")
	api.box("SewerRailE", V(-20, 0, -99.6), V(-19.5, 3, -88.4), METAL, "Metal")
	for _, x in { -62, -38 } do
		local rampY = -20 * (x + 86) / 66 -- ramp surface height here
		light(api, V(x, rampY + 7, -98.6), C(140, 255, 180), 24)
	end
	for _, p in { V(-60, 9, -85), V(0, 9, -85), V(-92, 9, -60) } do
		light(api, p, C(180, 255, 200), 24)
	end

	------------------------------------------------------------------
	-- Zone 4: Motel — two-floor facades, enterable room + office, balcony, pool
	------------------------------------------------------------------
	local MOTEL = C(196, 172, 140)
	local MOTEL_CORE = C(36, 30, 30)
	-- North wing: dark core set back, facade wall (face at z = -80) with doors/windows on two floors
	api.box("MotelNorthCoreW", V(172, 0, -110), V(210, 23, -83), MOTEL_CORE, "Concrete")
	api.box("MotelNorthCoreE", V(230, 0, -110), V(298, 23, -83), MOTEL_CORE, "Concrete")
	api.box("MotelFacadeW", V(172, 0, -81), V(210, 23, -80), MOTEL, "Concrete")
	api.box("MotelFacadeE", V(230, 0, -81), V(280, 23, -80), MOTEL, "Concrete")
	api.box("MotelFacadeEnd", V(280, 0, -83), V(298, 23, -80), MOTEL, "Concrete")
	api.box("MotelNorthRoof", V(171.5, 23, -110.5), V(298.5, 24, -79.5), C(70, 62, 58), "Slate")
	api.box("MotelNorthParapet", V(171.5, 24, -80.5), V(280, 26, -79.5), MOTEL, "Concrete")
	motelUnits(api, "x", -80, 1, 172, 210, 0, 12, {})
	motelUnits(api, "x", -80, 1, 230, 280, 0, 12, {})
	motelUnits(api, "x", -80, 1, 172, 210, 12, 12, { { 186, 194 } }) -- keep the Sniper wall-buy clear
	motelUnits(api, "x", -80, 1, 230, 270, 12, 12, {})
	-- The one enterable room (Mystery Box spot 4): real door + window, bed, dresser
	api.shell("MotelRoom", 210, -110, 230, -80, 0, 11, {
		color = MOTEL,
		openings = {
			{ side = "s", from = 217, to = 223, height = 7 },
			{ side = "s", from = 224.5, to = 228.5, bottom = 3, height = 3.5, glass = true },
		},
		floorColor = C(110, 60, 60), floorMaterial = "Fabric",
	})
	api.box("MotelRoomUpper", V(210, 12, -110), V(230, 23, -81), MOTEL_CORE, "Concrete")
	api.box("MotelRoomUpperFacade", V(210, 12, -81), V(230, 23, -80), MOTEL, "Concrete")
	motelUnits(api, "x", -80, 1, 210, 230, 12, 12, {})
	api.box("MotelBed", V(211, 0, -96), V(219, 2.2, -86), C(180, 170, 200), "Fabric")
	api.box("MotelHeadboard", V(210.5, 0, -96), V(211, 4.5, -86), WOOD, "Wood")
	api.box("MotelDresser", V(226, 0, -96), V(229.5, 3.5, -88), WOOD, "Wood")
	api.box("MotelTV", V(226.5, 3.5, -94), V(229, 5.5, -90), C(20, 20, 22), "SmoothPlastic")

	-- Balcony along the north wing: deck, rail, posts; stairs at the east end
	api.box("Balcony", V(172, 11, -80), V(278, 12, -72), CONCRETE, "Concrete")
	api.box("BalconyRail", V(172, 12, -72.5), V(270, 15, -72), METAL, "Metal")
	for x = 176, 268, 12 do
		api.box("BalconyPost", V(x - 0.4, 0, -73), V(x + 0.4, 11, -72.2), METAL, "Metal")
	end
	api.ramp("BalconyStairs", 270, -72, 278, -40, 0, 12, "n", CONCRETE)
	api.box("StairRail", V(277.6, 0, -72), V(278.2, 15, -40), METAL, "Metal", { Transparency = 0.4 })

	-- East wing: core + west-facing facade (face at x = 280) with two floors of units
	api.box("MotelEastCore", V(283, 0, -80), V(298, 23, 90), MOTEL_CORE, "Concrete")
	api.box("MotelEastFacade", V(280, 0, -80), V(281, 23, 90), MOTEL, "Concrete")
	api.box("MotelEastFill", V(281, 0, -80), V(283, 23, 90), MOTEL_CORE, "Concrete")
	api.box("MotelEastRoof", V(279.5, 23, -80), V(298.5, 24, 90.5), C(70, 62, 58), "Slate")
	motelUnits(api, "z", 280, -1, -38, 58, 0, 12, {})
	motelUnits(api, "z", 280, -1, -38, 58, 12, 12, {})

	-- Office (enterable): windows, front desk; Iron Body perk on the back wall
	api.shell("MotelOffice", 172, 60, 210, 90, 0, 11, {
		color = MOTEL,
		openings = {
			{ side = "n", from = 186, to = 194, height = 7.5 },
			{ side = "n", from = 175, to = 183, bottom = 3, height = 4, glass = true },
			{ side = "n", from = 198, to = 207, bottom = 3, height = 4, glass = true },
		},
		roof = "flat", parapet = 1.5, roofColor = C(70, 62, 58),
		floorColor = C(140, 110, 80),
	})
	api.box("FrontDesk", V(178, 0, 72), V(204, 3.8, 75), WOOD, "Wood")
	api.box("KeyRack", V(195, 4, 89.4), V(200, 7, 89.6), C(80, 60, 40), "Wood")
	api.box("OfficeChairs", V(174, 0, 62), V(180, 2.5, 66), C(70, 90, 110), "Fabric")
	light(api, V(191, 10.4, 76), C(255, 230, 190), 26)

	-- South wing: core + north-facing facade (face at z = 60), one floor
	api.box("MotelSouthCore", V(210, 0, 63), V(280, 12, 90), MOTEL_CORE, "Concrete")
	api.box("MotelSouthFacade", V(210, 0, 60), V(280, 12, 61), MOTEL, "Concrete")
	api.box("MotelSouthFill", V(210, 0, 61), V(280, 12, 63), MOTEL_CORE, "Concrete")
	api.box("MotelSouthRoof", V(209.5, 12, 59.5), V(280.5, 13, 90.5), C(70, 62, 58), "Slate")
	motelUnits(api, "x", 60, -1, 210, 280, 0, 12, {})

	-- Pool: rim, deck chairs, diving board
	api.box("PoolFloor", V(200, 0, -20), V(245, 0.08, 15), C(90, 130, 150), "Concrete", { CanCollide = false })
	api.box("PoolRimN", V(200, 0, -21), V(245, 1, -20), C(220, 220, 215), "Concrete")
	api.box("PoolRimS", V(200, 0, 15), V(245, 1, 16), C(220, 220, 215), "Concrete")
	api.box("PoolRimW", V(199, 0, -21), V(200, 1, 16), C(220, 220, 215), "Concrete")
	api.box("PoolRimE", V(245, 0, -21), V(246, 1, 16), C(220, 220, 215), "Concrete")
	api.box("DivingBoard", V(220, 1, 15.5), V(224, 1.4, 21), C(230, 230, 230), "SmoothPlastic")
	for _, x in { 205, 215, 230, 240 } do
		api.box("DeckChair", V(x, 0, 22), V(x + 3, 1.6, 28), C(240, 240, 235), "SmoothPlastic")
	end
	-- Motel sign on a pole
	api.box("MotelSignPole", V(173.5, 0, 42.5), V(174.5, 14, 43.5), METAL, "Metal")
	local msign = api.box("MotelSign", V(172, 14, 40), V(176, 26, 46), C(255, 90, 60), "Neon")
	pointLight(msign, C(255, 100, 70), 30, 1.4)

	-- Pump-house over the storm-drain stairwell (D5 seals its south doorway)
	api.shell("PumpHouse", 250, -60, 262, -8, 0, 9, {
		color = C(140, 140, 135), material = "Concrete",
		openings = { { side = "s", from = 251, to = 261, height = 8 } },
		floor = false,
		roof = "flat", parapet = 1, roofColor = C(80, 80, 80),
	})
	api.box("PumpHouseVent", V(253, 10, -40), V(259, 12, -34), METAL, "Metal")
	api.box("HazardStripe", V(250.6, 8, -7.8), V(261.4, 8.6, -7.4), C(240, 200, 30), "SmoothPlastic")
	for _, p in { V(200, 10.6, -73), V(250, 10.6, -73), V(222, 9, 0), V(191, 10, 58) } do
		light(api, p, C(255, 140, 90), 30)
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
		floorMaterial = "Concrete", floorColor = C(80, 80, 82),
	})
	api.box("ControlPanel", V(266, -20, -79.5), V(269.5, -15, -75), C(70, 80, 90), "Metal")
	api.box("ControlScreen", V(266, -17, -75.2), V(269, -15.5, -75), C(80, 255, 160), "Neon")
	-- The old 190-stud straight tunnel is now two short tunnels with a big pump
	-- chamber in the middle (cover, machinery, flickering lights).
	for _, seg in { { "TunnelW", 50, 120 }, { "TunnelE", 180, 240 } } do
		api.shell(seg[1], seg[2], -76, seg[3], -64, -20, 10, {
			color = C(100, 100, 102),
			openings = {
				{ side = "e", from = -76, to = -64, height = 10 },
				{ side = "w", from = -76, to = -64, height = 10 },
			},
			floorMaterial = "Concrete", floorColor = C(70, 70, 72),
		})
		local len, mid = seg[3] - seg[2], (seg[2] + seg[3]) / 2
		api.part({ Name = "TunnelPipe", Shape = Enum.PartType.Cylinder, Size = V(len, 1.4, 1.4), Position = V(mid, -11.4, -74.6), Color = C(110, 80, 60), Material = "CorrodedMetal" })
		api.part({ Name = "TunnelPipe", Shape = Enum.PartType.Cylinder, Size = V(len, 0.9, 0.9), Position = V(mid, -11.6, -72.6), Color = C(70, 90, 80), Material = "Metal" })
	end
	api.box("WaterChannel", V(50, -19.8, -71), V(240, -19.7, -69), C(50, 80, 70), "Glass", { Transparency = 0.3, CanCollide = false })

	-- Pump chamber (x 120..180): tall room, pumps, pillars for cover, catwalk, flicker lights
	api.shell("PumpChamber", 120, -96, 180, -44, -20, 16, {
		color = C(92, 96, 98),
		openings = {
			{ side = "e", from = -76, to = -64, height = 10 },
			{ side = "w", from = -76, to = -64, height = 10 },
		},
		floorMaterial = "DiamondPlate", floorColor = C(66, 68, 70),
	})
	for _, x in { 134, 166 } do
		api.part({ Name = "PumpTank", Shape = Enum.PartType.Cylinder, Size = V(12, 9, 9), CFrame = CFrame.new(x, -14, -88) * CFrame.Angles(0, 0, math.rad(90)), Color = C(120, 70, 50), Material = "CorrodedMetal" })
		api.box("PumpBase", V(x - 5, -20, -93), V(x + 5, -19, -83), C(60, 60, 64), "Metal")
		api.box("PumpPipe", V(x - 0.7, -8, -88.7), V(x + 0.7, -4.2, -87.3), C(110, 80, 60), "CorrodedMetal")
	end
	api.box("PumpManifold", V(128, -6, -89), V(172, -4.6, -87.6), C(110, 80, 60), "CorrodedMetal")
	api.box("ControlBank", V(144, -20, -54), V(156, -15, -50), C(60, 70, 80), "Metal")
	api.box("ControlBankScreens", V(144.5, -17.5, -54.2), V(155.5, -15.8, -54), C(80, 255, 160), "Neon")
	-- pillars flank the walkway: cover to fight around, not a straight corridor
	for _, p in { V(136, 0, -60), V(164, 0, -60), V(136, 0, -80), V(164, 0, -80) } do
		api.box("ChamberPillar", V(p.X - 1.5, -20, p.Z - 1.5), V(p.X + 1.5, -4, p.Z + 1.5), C(110, 110, 112), "Concrete")
	end
	api.box("ChamberCrates", V(148, -20, -82), V(152, -16, -78), C(120, 90, 60), "WoodPlanks")
	api.box("ChamberCrates", V(126, -20, -52), V(132, -17, -47), C(120, 90, 60), "WoodPlanks")
	api.box("ChamberCrates", V(170, -20, -60), V(174, -16.5, -56), C(120, 90, 60), "WoodPlanks")
	-- catwalk on the north wall (decor, out of reach)
	api.box("Catwalk", V(121, -11, -95.5), V(179, -10.6, -91), C(80, 82, 86), "DiamondPlate")
	api.box("CatwalkRail", V(121, -10.6, -91.2), V(179, -9, -91), C(200, 170, 40), "Metal")
	api.box("HazardStripe", V(120.6, -20, -76.5), V(121, -19.6, -63.5), C(240, 200, 30), "SmoothPlastic", { CanCollide = false })
	api.box("HazardStripe", V(179, -20, -76.5), V(179.4, -19.6, -63.5), C(240, 200, 30), "SmoothPlastic", { CanCollide = false })
	for _, p in { V(130, -5.5, -70), V(170, -5.5, -70), V(150, -5.5, -88), V(150, -5.5, -50) } do
		local l = light(api, p, C(255, 200, 140), 30)
		game:GetService("CollectionService"):AddTag(l, "Flicker")
	end
	api.shell("Lab", -20, -100, 50, -56, -20, 14, {
		color = C(160, 165, 170),
		openings = {
			{ side = "e", from = -76, to = -64, height = 10 },
			{ side = "w", from = -99, to = -89, height = 12 }, -- sewer ramp from the alley (D6)
		},
		floorMaterial = "DiamondPlate", floorColor = C(90, 95, 100),
	})
	api.box("LabDesk", V(-10, -20, -66), V(4, -17, -62), C(60, 70, 80), "Metal")
	api.box("LabMonitors", V(-9, -17, -64), V(3, -14.5, -63.6), C(60, 200, 255), "Neon")
	api.box("LabTank", V(30, -20, -64), V(40, -12, -58), C(80, 160, 140), "Glass", { Transparency = 0.4 })
	api.box("LabTankLiquid", V(31, -20, -63), V(39, -14, -59), C(90, 255, 180), "Neon", { Transparency = 0.5 })
	api.box("ServerRack", V(44, -20, -99.5), V(49.5, -11, -94), C(30, 30, 34), "Metal")
	api.box("ServerRack", V(44, -20, -92), V(49.5, -11, -86.5), C(30, 30, 34), "Metal")
	api.box("RackLights", V(43.8, -18, -99), V(44, -12, -87), C(80, 255, 120), "Neon")
	api.box("Gurney", V(-16, -20, -86), V(-8, -17.4, -82), C(200, 200, 205), "Metal")
	for _, p in { V(255, -9, -70), V(205, -10.4, -70), V(90, -10.4, -70), V(15, -6.4, -78), V(-10, -6.4, -62), V(-40, -2, -94) } do
		light(api, p, C(140, 255, 180), 24)
	end

	------------------------------------------------------------------
	-- Skyline: jagged cliff tops, landmarks past the cliffs, distant mesas.
	-- All outside the playable area and non-collidable (pure silhouette).
	------------------------------------------------------------------
	local deco = { CanCollide = false, CanQuery = false, CanTouch = false }
	local function rnd(seed) -- deterministic 0..1
		local x = math.sin(seed * 12.9898) * 43758.5453
		return x - math.floor(x)
	end
	-- Rock spires along each cliff line, pushed outward so they never overhang the town
	local CLIFF_TOP = 56
	local cliffs = {
		{ axis = "x", at = -112, from = -260, to = 300, out = -1 },
		{ axis = "z", at = -260, from = -112, to = 90, out = -1 },
		{ axis = "z", at = 300, from = -112, to = 90, out = 1 },
		{ axis = "z", at = -75, from = 90, to = 225, out = -1 },
		{ axis = "z", at = 75, from = 90, to = 225, out = 1 },
		{ axis = "x", at = 225, from = -75, to = 75, out = 1 },
	}
	local seed = 0
	for _, c in cliffs do
		local s = c.from
		while s < c.to do
			seed += 1
			local w = 10 + rnd(seed) * 14
			local h = 6 + rnd(seed + 0.5) * 28
			local depth = 8 + rnd(seed + 0.7) * 10
			local mid = math.min(s + w / 2, c.to - 2)
			local off = c.at + c.out * (depth / 2 + 1)
			local pos = c.axis == "x" and V(mid, CLIFF_TOP + h / 2 - 2, off) or V(off, CLIFF_TOP + h / 2 - 2, mid)
			local size = c.axis == "x" and V(w, h, depth) or V(depth, h, w)
			local tilt = (rnd(seed + 0.3) - 0.5) * 0.25
			api.part({ Name = "CliffSpire", Size = size, CFrame = CFrame.new(pos) * CFrame.Angles(tilt, (rnd(seed + 0.9) - 0.5) * 0.5, -tilt), Color = C(112 + rnd(seed) * 20, 84 + rnd(seed) * 14, 64), Material = "Rock", CanCollide = false, CanQuery = false, CastShadow = false })
			s += w * 0.8
		end
	end

	-- Landmark 1: standing water tower behind Elm Lane (south)
	local wt = V(40, 0, 262)
	for _, o in { V(-7, 0, -7), V(7, 0, -7), V(-7, 0, 7), V(7, 0, 7) } do
		api.part({ Name = "TowerLeg", Size = V(1.6, 62, 1.6), Position = wt + o + V(0, 31, 0), Color = C(120, 118, 110), Material = "Metal", CanCollide = false, CanQuery = false })
	end
	api.part({ Name = "WaterTower", Shape = Enum.PartType.Cylinder, Size = V(18, 22, 22), CFrame = CFrame.new(wt + V(0, 71, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = C(170, 168, 155), Material = "CorrodedMetal", CanCollide = false, CanQuery = false })
	api.part({ Name = "WaterTowerCap", Shape = Enum.PartType.Ball, Size = V(23, 23, 23), Position = wt + V(0, 79, 0), Color = C(140, 70, 55), Material = "CorrodedMetal", CanCollide = false, CanQuery = false })
	api.box("WaterTowerName", wt + V(-11.2, 68, -6), wt + V(-11, 74, 6), C(60, 40, 35), "SmoothPlastic", deco)

	-- Landmark 2: radio mast behind the motel (north-east) with a blinking beacon
	local rm = V(250, 0, -175)
	api.box("RadioMast", rm + V(-1.2, 0, -1.2), rm + V(1.2, 120, 1.2), C(170, 60, 50), "Metal", deco)
	for y = 20, 110, 30 do
		api.box("RadioMastBand", rm + V(-1.4, y, -1.4), rm + V(1.4, y + 6, 1.4), C(230, 225, 215), "Metal", deco)
	end
	local beacon = api.part({ Name = "MastBeacon", Size = V(2.4, 2.4, 2.4), Position = rm + V(0, 121.5, 0), Color = C(255, 40, 30), Material = "Neon", CanCollide = false, CanQuery = false })
	pointLight(beacon, C(255, 40, 30), 40, 2)
	game:GetService("CollectionService"):AddTag(beacon, "Flicker")

	-- Landmark 3: grain silos past the west cliff (behind the gas station)
	for i, x in { -320, -300, -280 } do
		local h = 70 + i * 6
		api.part({ Name = "Silo", Shape = Enum.PartType.Cylinder, Size = V(h, 16, 16), CFrame = CFrame.new(x, h / 2, -30 + i * 4) * CFrame.Angles(0, 0, math.rad(90)), Color = C(185, 180, 170), Material = "CorrodedMetal", CanCollide = false, CanQuery = false, CastShadow = false })
		api.part({ Name = "SiloCap", Shape = Enum.PartType.Ball, Size = V(16.5, 16.5, 16.5), Position = V(x, h, -30 + i * 4), Color = C(150, 145, 140), Material = "CorrodedMetal", CanCollide = false, CanQuery = false, CastShadow = false })
	end
	api.box("SiloGantry", V(-322, 64, -25), V(-278, 67, -20), C(110, 105, 100), "Metal", deco)

	-- Desert floor all around the town (a frame, so the ramp holes stay open)
	local DESERT = C(186, 146, 100)
	api.box("DesertN", V(-900, -1, -900), V(900, 0, -112), DESERT, "Sand", deco)
	api.box("DesertS", V(-900, -1, 225), V(900, 0, 900), DESERT, "Sand", deco)
	api.box("DesertW", V(-900, -1, -112), V(-260, 0, 225), DESERT, "Sand", deco)
	api.box("DesertE", V(300, -1, -112), V(900, 0, 225), DESERT, "Sand", deco)

	-- Distant mesas on every side (fade into the fog)
	local mesas = {
		{ V(-150, 0, -330), V(220, 110, 90) },
		{ V(120, 0, -380), V(260, 150, 100) },
		{ V(420, 0, -120), V(100, 120, 240) },
		{ V(460, 0, 140), V(120, 90, 200) },
		{ V(-440, 0, 60), V(110, 130, 260) },
		{ V(-380, 0, -260), V(160, 95, 120) },
		{ V(-200, 0, 380), V(240, 100, 110) },
		{ V(220, 0, 420), V(200, 140, 120) },
	}
	for i, m in mesas do
		local pos, size = m[1], m[2]
		local col = C(120, 80, 60):Lerp(C(150, 95, 70), rnd(i))
		api.part({ Name = "Mesa", Size = size, Position = pos + V(0, size.Y / 2, 0), Color = col, Material = "Rock", CanCollide = false, CanQuery = false, CastShadow = false })
		-- stepped cap + talus skirt so the silhouette isn't a box
		api.part({ Name = "MesaCap", Size = V(size.X * 0.7, size.Y * 0.18, size.Z * 0.75), Position = pos + V(size.X * 0.08, size.Y * 1.09, 0), Color = col:Lerp(C(90, 60, 45), 0.3), Material = "Rock", CanCollide = false, CanQuery = false, CastShadow = false })
		api.part({ Name = "MesaSkirt", Size = V(size.X * 1.3, size.Y * 0.3, size.Z * 1.25), Position = pos + V(0, size.Y * 0.15, 0), Color = col:Lerp(C(196, 160, 112), 0.35), Material = "Sand", CanCollide = false, CanQuery = false, CastShadow = false })
	end
end
