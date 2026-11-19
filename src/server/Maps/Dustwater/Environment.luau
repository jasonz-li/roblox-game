--!nonstrict
-- Dustwater Stage 3 ENVIRONMENT: destruction, debris, wrecked vehicles, fire,
-- smoke, ash and steam. Uses only Roblox built-in effects (Fire, Smoke,
-- ParticleEmitter with rbxasset:// built-in textures). No external assets.
--
-- Rules followed here:
--   * Nothing collidable is placed in doorways, on routes between areas, or in
--     front of wall-buys/perks/boxes (route tests re-run after every change).
--   * Low rubble (< 2 studs) can be walked over; taller debris is cover.
--   * Fires are cosmetic for now (no damage).

local CollectionService = game:GetService("CollectionService")

local V = Vector3.new
local C = Color3.fromRGB

local SMOKE_TEX = "rbxasset://textures/particles/smoke_main.dds"
local SPARK_TEX = "rbxasset://textures/particles/sparkles_main.dds"
local FIRE_TEX = "rbxasset://textures/particles/fire_main.dds"

local CHARRED = C(38, 32, 28)
local RUBBLE = { C(120, 110, 98), C(98, 90, 82), C(140, 120, 100), C(80, 72, 66) }

local rng = Random.new(1947) -- fixed seed: the same debris every match

local function ns(...)
	local pts = { ... }
	local kps = {}
	for i = 1, #pts, 2 do
		table.insert(kps, NumberSequenceKeypoint.new(pts[i], pts[i + 1]))
	end
	return NumberSequence.new(kps)
end

------------------------------------------------------------------
-- Effect helpers
------------------------------------------------------------------

local function anchorPart(api, name, pos, size)
	return api.part({
		Name = name,
		Size = size or V(1, 1, 1),
		Position = pos,
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
end

-- Burning fire with a flickering light. scale ~1 = car fire, 2 = building fire.
local function fire(api, pos: Vector3, scale: number, withSmoke: boolean?)
	local a = anchorPart(api, "Fire", pos, V(2, 1, 2) * scale)
	local f = Instance.new("Fire")
	f.Size = 6 * scale
	f.Heat = 9 * scale
	f.Color = C(255, 120, 40)
	f.SecondaryColor = C(255, 220, 90)
	f.Parent = a
	local l = Instance.new("PointLight")
	l.Color = C(255, 130, 60)
	l.Range = 16 + 10 * scale
	l.Brightness = 2.2
	l.Shadows = true
	l.Parent = a
	CollectionService:AddTag(l, "Flicker")
	-- embers
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK_TEX
	e.Rate = 6 * scale
	e.Lifetime = NumberRange.new(1.2, 2.4)
	e.Speed = NumberRange.new(4, 9)
	e.SpreadAngle = Vector2.new(25, 25)
	e.Acceleration = V(1.5, 2, 0)
	e.Size = ns(0, 0.25, 1, 0)
	e.Color = ColorSequence.new(C(255, 180, 80), C(255, 80, 30))
	e.LightEmission = 1
	e.Parent = a
	if withSmoke then
		local s = Instance.new("ParticleEmitter")
		s.Texture = SMOKE_TEX
		s.Rate = 4 * scale
		s.Lifetime = NumberRange.new(6, 9)
		s.Speed = NumberRange.new(5, 8)
		s.SpreadAngle = Vector2.new(12, 12)
		s.Acceleration = V(2.5, 1, 0.8) -- drift with the wind
		s.Size = ns(0, 3 * scale, 1, 12 * scale)
		s.Transparency = ns(0, 0.55, 0.7, 0.75, 1, 1)
		s.Color = ColorSequence.new(C(60, 52, 48), C(30, 28, 28))
		s.RotSpeed = NumberRange.new(-20, 20)
		s.Rotation = NumberRange.new(0, 360)
		s.Parent = a
	end
	return a
end

-- Tall smoke column with no visible fire (e.g. from behind a roof).
local function smokeColumn(api, pos: Vector3, scale: number)
	local a = anchorPart(api, "SmokeColumn", pos, V(4, 1, 4) * scale)
	local s = Instance.new("ParticleEmitter")
	s.Texture = SMOKE_TEX
	s.Rate = 5 * scale
	s.Lifetime = NumberRange.new(10, 14)
	s.Speed = NumberRange.new(6, 10)
	s.SpreadAngle = Vector2.new(10, 10)
	s.Acceleration = V(3, 0.5, 1)
	s.Size = ns(0, 5 * scale, 1, 22 * scale)
	s.Transparency = ns(0, 0.5, 0.8, 0.8, 1, 1)
	s.Color = ColorSequence.new(C(55, 48, 44), C(25, 24, 24))
	s.RotSpeed = NumberRange.new(-15, 15)
	s.Rotation = NumberRange.new(0, 360)
	s.Parent = a
	return a
end

-- Low drifting steam (tunnels, broken pipes).
local function steam(api, pos: Vector3, dir: Vector3)
	local a = anchorPart(api, "Steam", pos, V(1, 1, 1))
	local s = Instance.new("ParticleEmitter")
	s.Texture = SMOKE_TEX
	s.Rate = 6
	s.Lifetime = NumberRange.new(2.5, 4)
	s.Speed = NumberRange.new(3, 5)
	s.SpreadAngle = Vector2.new(15, 15)
	s.EmissionDirection = Enum.NormalId.Top
	s.Acceleration = dir
	s.Size = ns(0, 1, 1, 6)
	s.Transparency = ns(0, 0.7, 1, 1)
	s.Color = ColorSequence.new(C(220, 230, 225))
	s.Parent = a
end

-- Pile of tumbled blocks. Low piles (maxH < 2) can be walked over.
local function rubble(api, center: Vector3, radius: number, count: number, maxH: number)
	for _ = 1, count do
		local ang = rng:NextNumber(0, math.pi * 2)
		local r = radius * math.sqrt(rng:NextNumber())
		local s = V(rng:NextNumber(0.8, 3.2), rng:NextNumber(0.5, maxH), rng:NextNumber(0.8, 3.2))
		api.part({
			Name = "Rubble",
			Size = s,
			CFrame = CFrame.new(center + V(math.cos(ang) * r, s.Y / 2 - 0.15, math.sin(ang) * r))
				* CFrame.Angles(rng:NextNumber(-0.4, 0.4), rng:NextNumber(0, 6.28), rng:NextNumber(-0.4, 0.4)),
			Color = RUBBLE[rng:NextInteger(1, #RUBBLE)],
			Material = "Concrete",
		})
	end
end

-- Flat scorch mark on the ground (non-collidable).
local function scorch(api, pos: Vector3, radius: number)
	api.part({
		Name = "Scorch",
		Shape = Enum.PartType.Cylinder,
		Size = V(0.08, radius * 2, radius * 2),
		CFrame = CFrame.new(pos.X, 0.09, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = C(20, 18, 16),
		Material = "Slate",
		Transparency = 0.25,
		CanCollide = false,
		CanQuery = false,
	})
end

-- Scorch on a wall face: axis "x" (wall along X, face at z) or "z".
local function wallScorch(api, axis, face, sign, s0, s1, y0, y1)
	local d0, d1 = face, face + sign * 0.12
	local props = { Name = "WallScorch", Color = C(22, 20, 18), Material = "Slate", Transparency = 0.15, CanCollide = false, CanQuery = false }
	if axis == "x" then
		api.box("WallScorch", V(s0, y0, math.min(d0, d1)), V(s1, y1, math.max(d0, d1)), props.Color, "Slate", props)
	else
		api.box("WallScorch", V(math.min(d0, d1), y0, s0), V(math.max(d0, d1), y1, s1), props.Color, "Slate", props)
	end
end

-- Road crack: thin dark strip, slightly rotated (non-collidable).
local function crack(api, x, z, len, yawDeg)
	api.part({
		Name = "Crack",
		Size = V(0.35, 0.04, len),
		CFrame = CFrame.new(x, 0.08, z) * CFrame.Angles(0, math.rad(yawDeg), 0),
		Color = C(18, 18, 18),
		Material = "Asphalt",
		CanCollide = false,
		CanQuery = false,
	})
	-- a branch
	api.part({
		Name = "Crack",
		Size = V(0.25, 0.04, len * 0.45),
		CFrame = CFrame.new(x, 0.08, z) * CFrame.Angles(0, math.rad(yawDeg + 35), 0) * CFrame.new(0, 0, len * 0.2),
		Color = C(18, 18, 18),
		Material = "Asphalt",
		CanCollide = false,
		CanQuery = false,
	})
end

local function pothole(api, x, z, r)
	api.part({
		Name = "Pothole",
		Shape = Enum.PartType.Cylinder,
		Size = V(0.06, r * 2, r * 2),
		CFrame = CFrame.new(x, 0.1, z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = C(25, 24, 24),
		Material = "Ground",
		CanCollide = false,
		CanQuery = false,
	})
	rubble(api, V(x, 0, z), r + 1, 4, 0.8)
end

-- Crater: scorched disc + raised rubble ring (low, walkable) + smoke wisp.
local function crater(api, x, z, r)
	scorch(api, V(x, 0, z), r)
	for i = 1, 10 do
		local a = (i / 10) * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		rubble(api, V(x + math.cos(a) * r, 0, z + math.sin(a) * r), 1.5, 2, 1.6)
	end
end

local function burnedCar(api, x, z, yawDeg, onFire: boolean?)
	local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yawDeg), 0)
	api.part({ Name = "BurnedCarBody", Size = V(7, 2.6, 15), CFrame = cf * CFrame.new(0, 1.5, 0), Color = CHARRED, Material = "CorrodedMetal" })
	api.part({ Name = "BurnedCarCabin", Size = V(6.2, 2.2, 6.5), CFrame = cf * CFrame.new(0, 3.9, 1) * CFrame.Angles(0, 0, math.rad(4)), Color = C(30, 26, 24), Material = "CorrodedMetal" })
	api.part({ Name = "BurnedCarHood", Size = V(6.6, 0.3, 4), CFrame = cf * CFrame.new(0, 3.4, -6) * CFrame.Angles(math.rad(-25), 0, 0), Color = C(45, 38, 34), Material = "CorrodedMetal" })
	scorch(api, V(x, 0, z), 7)
	if onFire then
		fire(api, (cf * CFrame.new(0, 3.5, -1)).Position, 1, true)
	end
end

local function overturnedCar(api, x, z, yawDeg, color)
	local cf = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yawDeg), 0) * CFrame.Angles(0, 0, math.rad(180))
	api.part({ Name = "FlippedCarBody", Size = V(7, 3, 15), CFrame = CFrame.new(x, 4.6, z) * CFrame.Angles(0, math.rad(yawDeg), math.rad(180)), Color = color, Material = "CorrodedMetal" })
	api.part({ Name = "FlippedCarCabin", Size = V(6.4, 2.4, 7), CFrame = CFrame.new(x, 1.4, z) * CFrame.Angles(0, math.rad(yawDeg), 0) * CFrame.new(0, 0, 1), Color = color:Lerp(C(0, 0, 0), 0.5), Material = "CorrodedMetal" })
	for _, w in { { -3.6, -4.8 }, { 3.6, -4.8 }, { -3.6, 4.8 }, { 3.6, 4.8 } } do
		api.part({ Name = "Wheel", Shape = Enum.PartType.Cylinder, Size = V(1, 2.6, 2.6), CFrame = CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(yawDeg), 0) * CFrame.new(w[1], 6.4, w[2]), Color = C(25, 25, 25), Material = "SmoothPlastic" })
	end
	_ = cf
end

local function deadBush(api, x, z)
	for _ = 1, 3 do
		api.part({
			Name = "DeadBush",
			Shape = Enum.PartType.Ball,
			Size = V(1, 1, 1) * rng:NextNumber(1.2, 2.4),
			Position = V(x + rng:NextNumber(-1, 1), 0.6, z + rng:NextNumber(-1, 1)),
			Color = C(rng:NextInteger(70, 95), rng:NextInteger(55, 70), rng:NextInteger(35, 45)),
			Material = "Grass",
			CanCollide = false,
		})
	end
end

local function tumbleweed(api, x, z)
	api.part({
		Name = "Tumbleweed",
		Shape = Enum.PartType.Ball,
		Size = V(1, 1, 1) * rng:NextNumber(2, 3.2),
		Position = V(x, 1.2, z),
		Color = C(150, 120, 80),
		Material = "Grass",
		Transparency = 0.15,
		CanCollide = false,
	})
end

local function barrelFire(api, x, z)
	api.part({ Name = "OilDrum", Shape = Enum.PartType.Cylinder, Size = V(3.4, 2.4, 2.4), CFrame = CFrame.new(x, 1.7, z) * CFrame.Angles(0, 0, math.rad(90)), Color = C(70, 50, 40), Material = "CorrodedMetal" })
	fire(api, V(x, 3.6, z), 0.45, false)
end

-- Broken plank leaning on a wall / lying in the street.
local function plank(api, pos, yaw, pitch, len)
	api.part({ Name = "Plank", Size = V(0.6, 0.25, len), CFrame = CFrame.new(pos) * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(pitch), 0, 0), Color = C(100, 76, 54), Material = "WoodPlanks", CanCollide = false })
end

-- Ash falling over the whole town: one big emitter volume above the map.
local function ashfall(api)
	local a = api.part({
		Name = "AshCloud",
		Size = V(560, 1, 340),
		Position = V(20, 70, 56),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	local e = Instance.new("ParticleEmitter")
	e.Texture = SPARK_TEX
	e.EmissionDirection = Enum.NormalId.Bottom
	e.Shape = Enum.ParticleEmitterShape.Box
	e.ShapeStyle = Enum.ParticleEmitterShapeStyle.Volume
	e.Rate = 70
	e.Lifetime = NumberRange.new(14, 20)
	e.Speed = NumberRange.new(3, 5)
	e.Acceleration = V(1.2, -0.4, 0.6)
	e.Size = ns(0, 0.18, 1, 0.12)
	e.Transparency = ns(0, 0.3, 0.85, 0.5, 1, 1)
	e.Color = ColorSequence.new(C(190, 180, 170), C(120, 110, 105))
	e.RotSpeed = NumberRange.new(-90, 90)
	e.Parent = a
end

------------------------------------------------------------------
-- Placement
------------------------------------------------------------------

return function(api)
	ashfall(api)

	-- ===== Elm Lane =====
	burnedCar(api, -8, 118, 12, true) -- replaces nothing: sits on the lane's west half
	rubble(api, V(74, 0, 152), 5, 10, 2.6) -- collapsed corner of the east house yard
	wallScorch(api, "z", 72.5, 1, 145, 150, 3, 11) -- east house back wall burned (beside the window)
	wallScorch(api, "x", 160.5, 1, -56, -50, 3, 11) -- west house south wall (between windows)
	-- Fallen power pole across the west backyard (low, can be jumped)
	api.part({ Name = "FallenPole", Shape = Enum.PartType.Cylinder, Size = V(30, 1.4, 1.4), CFrame = CFrame.new(-82, 0.7, 108) * CFrame.Angles(0, math.rad(25), 0), Color = C(70, 55, 40), Material = "Wood" })
	api.box("PoleBase", V(-96, 0, 101), V(-94, 4, 103), C(70, 55, 40), "Wood")
	for _, p in { { -84, 182 }, { 86, 175 }, { -60, 205 }, { 50, 212 }, { -20, 102 } } do
		deadBush(api, p[1], p[2])
	end
	tumbleweed(api, 22, 160)
	tumbleweed(api, -45, 100)
	crack(api, -4, 100, 14, 10)
	crack(api, 6, 135, 10, -20)
	pothole(api, 3, 155, 1.6)
	plank(api, V(-36, 1.2, 150), 0, 70, 6) -- loose board leaning on the west house
	scorch(api, V(-20, 0, 196), 5)

	-- ===== Main Street =====
	-- Car crashed nose-first into the hardware store window (fire inside the shop)
	api.part({ Name = "CrashedCar", Size = V(7, 3, 15), CFrame = CFrame.new(-107, 2, -38) * CFrame.Angles(math.rad(-6), math.rad(8), 0), Color = C(140, 40, 40), Material = "CorrodedMetal" })
	api.part({ Name = "CrashedCarCabin", Size = V(6.4, 2.4, 7), CFrame = CFrame.new(-107.4, 4.4, -35) * CFrame.Angles(math.rad(-6), math.rad(8), 0), Color = C(80, 24, 24), Material = "CorrodedMetal" })
	fire(api, V(-108, 2, -48), 1.3, true)
	rubble(api, V(-107, 0, -31), 4, 8, 1.2)
	-- Theater roof burning
	fire(api, V(120, 23.5, -70), 2, true)
	smokeColumn(api, V(90, 24, -66), 1.6)
	wallScorch(api, "x", -40, 1, 112, 135, 14, 22)
	-- Water tower: fire where it hit the street + rubble around the impact
	fire(api, V(-52, 1.5, -6), 1.1, true)
	rubble(api, V(-72, 0, -22), 6, 14, 2.2)
	-- Craters, cracks and potholes along the street (all low / walkable)
	crater(api, 70, -14, 6)
	crater(api, -20, -22, 4.5)
	for _, c in { { -130, -10, 18, 70 }, { -80, -26, 12, 15 }, { 0, 0, 16, 95 }, { 45, -8, 10, -30 }, { 120, -18, 20, 80 }, { 150, -2, 12, 10 } } do
		crack(api, c[1], c[2], c[3], c[4])
	end
	pothole(api, -40, -8, 2)
	pothole(api, 110, 0, 1.6)
	overturnedCar(api, 130, -6, 60, C(70, 80, 110))
	rubble(api, V(-30, 0, -41), 3, 6, 1) -- glass/rubble under A2 windows (clear of the Shotgun pier)
	-- Field: the burnt shack is still burning; ash, dead brush
	fire(api, V(-121, 6, 56), 1.5, true)
	for _, p in { { -100, 25 }, { -140, 80 }, { -60, 40 }, { -85, 84 }, { -125, 15 } } do
		deadBush(api, p[1], p[2])
	end
	scorch(api, V(-90, 0, 55), 14)
	scorch(api, V(-130, 0, 75), 9)
	-- Junkyard: burning barrels, spilled oil
	barrelFire(api, 92, 50)
	barrelFire(api, 140, 28)
	barrelFire(api, 68, 82)
	scorch(api, V(118, 0, 45), 6)

	-- ===== Gas Station =====
	burnedCar(api, -215, -80, 70, true)
	wallScorch(api, "x", 14.5, -1, -200, -176, 10, 12) -- soot over the bay door
	scorch(api, V(-211, 0, -32), 8) -- under the canopy, between the pumps
	rubble(api, V(-252, 0, -90), 4, 8, 2.4)
	smokeColumn(api, V(-188, 13, 40), 1.1) -- smoke out of the garage roof
	tumbleweed(api, -170, -60)

	-- ===== Diner + Alley =====
	fire(api, V(-58, 5.6, -107.5), 0.7, true) -- dumpster fire
	wallScorch(api, "x", -84.5, -1, -66, -50, 0, 9) -- alley wall scorched behind it
	rubble(api, V(30, 0, -100), 4, 8, 1.4)
	plank(api, V(-90, 0.3, -70), 30, 0, 7)
	plank(api, V(-92, 0.3, -55), -20, 0, 6)

	-- ===== Motel =====
	-- Upper-floor room on fire (east end), soot above it
	fire(api, V(256, 12.6, -78.5), 1.2, true) -- on the balcony in front of the burning room
	wallScorch(api, "x", -79.75, 1, 248, 262, 12, 23)
	smokeColumn(api, V(290, 25, 20), 1.3) -- east wing roof
	-- Junk in the drained pool (low), deck debris
	rubble(api, V(222, 0, -2), 6, 10, 1.2)
	api.part({ Name = "PoolChair", Size = V(3, 1.6, 6), CFrame = CFrame.new(210, 0.8, 5) * CFrame.Angles(0, math.rad(35), math.rad(80)), Color = C(240, 240, 235), Material = "SmoothPlastic" })
	-- Broken balcony rail section hanging down (cosmetic, non-collidable)
	api.part({ Name = "BrokenRail", Size = V(10, 3, 0.4), CFrame = CFrame.new(236, 9, -71.6) * CFrame.Angles(0, 0, math.rad(-35)), Color = C(90, 90, 95), Material = "Metal", CanCollide = false })
	burnedCar(api, 195, 30, -15, false)
	tumbleweed(api, 265, 40)

	-- ===== Underground =====
	steam(api, V(120, -11, -74), V(0, 0.5, 2))
	steam(api, V(200, -11, -74), V(0, 0.5, 2))
	steam(api, V(-60, -15, -94), V(0, 1, 0))
	rubble(api, V(170, -20, -66), 2.5, 5, 1)
end
