--!nonstrict
-- The Hollow: the wave-10 raid arena, a lava-lit cavern far below Dustwater.
-- Round fighting floor (radius 64), jagged rock wall, lava moat at the edge,
-- 4 pillars for cover against fireball rings, totem spots for phase 2.
-- PLACEHOLDER art (parts); positions come from Layout.Hollow in init.luau.

local V = Vector3.new
local C = Color3.fromRGB

local CENTER = V(0, -150, 470)
local R = 64

return function(api)
	local y = CENTER.Y
	-- floor (slightly larger than the walkable radius; lava covers the outer band)
	api.floor("HollowFloor", CENTER.X - R - 14, CENTER.Z - R - 14, CENTER.X + R + 14, CENTER.Z + R + 14, y, C(60, 44, 38), "Basalt")
	-- cracked inner circle (decor)
	api.part({ Name = "HollowSeal", Shape = Enum.PartType.Cylinder, Size = V(0.2, 34, 34), CFrame = CFrame.new(CENTER + V(0, 0.05, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = C(90, 40, 30), Material = "Slate", CanCollide = false, CanQuery = false })
	api.part({ Name = "HollowSealGlow", Shape = Enum.PartType.Cylinder, Size = V(0.12, 36, 36), CFrame = CFrame.new(CENTER + V(0, 0.04, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = C(255, 110, 30), Material = "Neon", CanCollide = false, CanQuery = false, Transparency = 0.5 })

	-- lava moat ring (visual) + invisible edge wall so nobody wanders into it
	local SEG = 32
	for i = 0, SEG - 1 do
		local a = (i + 0.5) / SEG * math.pi * 2
		local dir = V(math.cos(a), 0, math.sin(a))
		local yaw = CFrame.lookAt(V(), dir).Rotation
		local segLen = 2 * math.pi * (R + 6) / SEG + 1
		api.part({ Name = "HollowLava", Size = V(segLen, 0.3, 12), CFrame = CFrame.new(CENTER + dir * (R + 6) + V(0, 0.15, 0)) * yaw * CFrame.Angles(0, math.rad(90), 0), Color = C(255, 90, 20), Material = "Neon", CanCollide = false, CanQuery = false })
		-- edge wall: knee-high rim players can't cross (and an invisible blocker above)
		api.part({ Name = "HollowRim", Size = V(2 * math.pi * R / SEG + 1, 2.5, 1.5), CFrame = CFrame.new(CENTER + dir * (R + 0.8) + V(0, 1.25, 0)) * yaw * CFrame.Angles(0, math.rad(90), 0), Color = C(70, 50, 44), Material = "Basalt" })
		api.part({ Name = "HollowRimClip", Size = V(2 * math.pi * R / SEG + 1, 30, 1.5), CFrame = CFrame.new(CENTER + dir * (R + 0.8) + V(0, 17.5, 0)) * yaw * CFrame.Angles(0, math.rad(90), 0), Transparency = 1, CanQuery = false })
		-- jagged cavern wall beyond the lava
		local h = 34 + (i * 37 % 11)
		api.part({ Name = "HollowWall", Size = V(2 * math.pi * (R + 16) / SEG + 3, h, 6), CFrame = CFrame.new(CENTER + dir * (R + 16) + V(0, h / 2, 0)) * yaw * CFrame.Angles(math.rad(-6 + (i % 3) * 4), math.rad(90), 0), Color = C(64 + (i % 4) * 6, 46, 40), Material = "Rock" })
	end
	-- ceiling
	api.box("HollowCeiling", CENTER + V(-R - 24, 46, -R - 24), CENTER + V(R + 24, 48, R + 24), C(40, 30, 28), "Rock")
	-- stalactites
	for i = 1, 14 do
		local a = i * 2.39
		local d = 12 + (i * 17 % 44)
		local len = 6 + (i % 5) * 3
		api.part({ Name = "Stalactite", Size = V(2.5, len, 2.5), CFrame = CFrame.new(CENTER + V(math.cos(a) * d, 46 - len / 2, math.sin(a) * d)) * CFrame.Angles(0, a, math.rad(4)), Color = C(70, 52, 46), Material = "Rock", CanCollide = false, CanQuery = false })
	end

	-- pillars (cover from fireball rings)
	for _, p in { V(-30, 0, -25), V(30, 0, -25), V(-30, 0, 25), V(30, 0, 25) } do
		local pos = CENTER + p
		api.box("HollowPillar", pos + V(-2.5, 0, -2.5), pos + V(2.5, 46, 2.5), C(80, 60, 52), "Rock")
		api.box("HollowPillarGlow", pos + V(-2.6, 2, -2.6), pos + V(2.6, 2.4, 2.6), C(255, 120, 40), "Neon", { CanCollide = false })
	end

	-- lighting: lava glow from below + a few braziers
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		local p = api.part({ Name = "HollowGlow", Size = V(1, 1, 1), Position = CENTER + V(math.cos(a) * (R + 4), 4, math.sin(a) * (R + 4)), Transparency = 1, CanCollide = false, CanQuery = false })
		local l = Instance.new("PointLight")
		l.Color = C(255, 110, 40)
		l.Range = 40
		l.Brightness = 2.2
		l.Parent = p
	end
	local top = api.part({ Name = "HollowTopLight", Size = V(1, 1, 1), Position = CENTER + V(0, 40, 0), Transparency = 1, CanCollide = false, CanQuery = false })
	local tl = Instance.new("PointLight")
	tl.Color = C(255, 170, 120)
	tl.Range = 60
	tl.Brightness = 1.2
	tl.Parent = top
end
