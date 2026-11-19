--!nonstrict
-- Builds the current map from layout data (src/server/Maps/*), tracks unlocked
-- zones, opens doors, and hands out spawn points.
-- Geometry is BLOCKOUT/PLACEHOLDER: plain parts, no art assets yet.
--
-- Interactive stations are parts tagged "Interactable" with attributes:
--   Kind = "WallBuy" | "Door" | "Perk" | "Forge" (MysteryBox is added by MysteryBoxService)
--   Id, Cost, Title  (InteractionService turns these into ProximityPrompts)

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local WeaponConfig = require(game.ReplicatedStorage.Shared.Config.WeaponConfig)
local PerkConfig = require(game.ReplicatedStorage.Shared.Config.PerkConfig)
local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)
local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
-- Map is chosen by name (GameConfig.ActiveMap); "ShrineDistrict" is the old 4-zone test blockout.
local Layout = require(script.Parent.Parent.Maps:FindFirstChild(GameConfig.ActiveMap or "ShrineDistrict"))

local MapService = {}

local mapFolder: Folder
local unlocked = {}
local notify: RemoteEvent

----------------------------------------------------------------------
-- Builders
----------------------------------------------------------------------

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Concrete
	p.Color = Color3.fromRGB(70, 72, 82)
	for k, v in props do
		if k ~= "Parent" then
			p[k] = v
		end
	end
	p.Parent = props.Parent or mapFolder
	return p
end

local function surfaceText(target: BasePart, lines: { { text: string, size: number, color: Color3 } }, face)
	local sg = Instance.new("SurfaceGui")
	sg.Face = face or Enum.NormalId.Front
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0
	sg.Parent = target
	local list = Instance.new("UIListLayout")
	list.HorizontalAlignment = Enum.HorizontalAlignment.Center
	list.VerticalAlignment = Enum.VerticalAlignment.Center
	list.Parent = sg
	for i, line in lines do
		local l = Instance.new("TextLabel")
		l.LayoutOrder = i
		l.BackgroundTransparency = 1
		l.Size = UDim2.new(1, 0, 0, line.size + 6)
		l.Text = line.text
		l.TextSize = line.size
		l.TextColor3 = line.color
		l.Font = Enum.Font.GothamBlack
		l.Parent = sg
	end
	return sg
end

local function lantern(pos: Vector3)
	part({ Name = "LanternPost", Size = Vector3.new(0.6, 7, 0.6), Position = pos + Vector3.new(0, 3.5, 0), Color = Color3.fromRGB(40, 30, 30), Material = Enum.Material.Wood })
	local lamp = part({
		Name = "Lantern",
		Size = Vector3.new(1.4, 1.8, 1.4),
		Position = pos + Vector3.new(0, 7.6, 0),
		Color = Color3.fromRGB(255, 120, 60),
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(255, 140, 80)
	light.Range = 22
	light.Brightness = 1.4
	light.Parent = lamp
end

local function buildWalls()
	for _, w in Layout.Walls or {} do
		local h = w.height or Layout.WallHeight
		local y = w.y or 0
		local wallColor = w.color or Layout.WallColor or Color3.fromRGB(52, 48, 62)
		local material = w.material and Enum.Material[w.material] or Enum.Material.Brick
		-- Split the wall line around door gaps + boarded-window gaps (auto from Layout.Barriers)
		local gaps = table.clone(w.gaps or {})
		for _, b in Layout.Barriers or {} do
			if b.Axis == w.axis and math.abs(b.At - w.at) < 0.01 and b.Along > w.from and b.Along < w.to then
				local half = (b.Width or 6) / 2
				table.insert(gaps, { b.Along - half, b.Along + half })
			end
		end
		table.sort(gaps, function(p, q)
			return p[1] < q[1]
		end)
		local cuts = { w.from }
		for _, g in gaps do
			table.insert(cuts, g[1])
			table.insert(cuts, g[2])
		end
		table.insert(cuts, w.to)
		for i = 1, #cuts - 1, 2 do
			local a, b = cuts[i], cuts[i + 1]
			local len = b - a
			if len > 0 then
				local mid = (a + b) / 2
				local pos = w.axis == "x" and Vector3.new(mid, y + h / 2, w.at) or Vector3.new(w.at, y + h / 2, mid)
				local size = w.axis == "x" and Vector3.new(len + 2, h, 2) or Vector3.new(2, h, len + 2)
				part({ Name = w.name or "Wall", Position = pos, Size = size, Color = wallColor, Material = material })
			end
		end
	end
end

local function buildZones()
	for id, z in Layout.Zones do
		local size = z.Max - z.Min
		local center = (z.Max + z.Min) / 2
		part({
			Name = "Floor_" .. z.Name,
			Size = Vector3.new(size.X, 1, size.Z),
			Position = Vector3.new(center.X, -0.45, center.Z),
			Color = z.FloorColor,
			Material = Enum.Material.Slate,
		})
	end
end

local function buildDoors()
	for _, d in Layout.Doors do
		local h = d.Height or Layout.WallHeight
		local size = d.Axis == "x" and Vector3.new(d.Width, h, 1.5) or Vector3.new(1.5, h, d.Width)
		local door = part({
			Name = "Door_" .. d.Id,
			Size = size,
			Position = d.Center + Vector3.new(0, h / 2, 0),
			Color = d.Color or Color3.fromRGB(120, 70, 50),
			Material = d.Material and Enum.Material[d.Material] or Enum.Material.WoodPlanks,
		})
		local zoneA, zoneB = Layout.Zones[d.ZoneA].Name, Layout.Zones[d.ZoneB].Name
		door:SetAttribute("Kind", "Door")
		door:SetAttribute("Id", d.Id)
		door:SetAttribute("Cost", d.Cost)
		door:SetAttribute("ZoneA", d.ZoneA)
		door:SetAttribute("ZoneB", d.ZoneB)
		door:SetAttribute("Title", d.Label or ("Open to " .. zoneA .. " / " .. zoneB))
		local lines = {
			{ text = d.Label and string.upper(d.Label) or "SEALED", size = 26, color = Color3.fromRGB(255, 120, 140) },
			{ text = tostring(d.Cost) .. " PTS", size = 44, color = Color3.fromRGB(255, 225, 120) },
		}
		surfaceText(door, lines, d.Axis == "x" and Enum.NormalId.Front or Enum.NormalId.Right)
		surfaceText(door, lines, d.Axis == "x" and Enum.NormalId.Back or Enum.NormalId.Left)
		CollectionService:AddTag(door, "Interactable")
	end
end

local function buildWallBuys()
	for _, wb in Layout.WallBuys do
		local stats = WeaponConfig.Get(wb.Weapon)
		local plaque = part({
			Name = "WallBuy_" .. wb.Weapon,
			Size = Vector3.new(6, 3.5, 0.3),
			CFrame = CFrame.lookAt(wb.Pos, wb.Pos + wb.Face),
			Color = Color3.fromRGB(28, 24, 36),
			Material = Enum.Material.SmoothPlastic,
		})
		-- Neon outline strip as a "chalk drawing" placeholder for the weapon
		part({
			Name = "Outline",
			Size = Vector3.new(4.4, 0.25, 0.1),
			CFrame = plaque.CFrame * CFrame.new(0, -1.15, -0.2),
			Color = stats.View.Accent,
			Material = Enum.Material.Neon,
			CanCollide = false,
			CanQuery = false,
		})
		plaque:SetAttribute("Kind", "WallBuy")
		plaque:SetAttribute("Id", wb.Weapon)
		plaque:SetAttribute("Cost", stats.WallCost)
		plaque:SetAttribute("AmmoCost", stats.AmmoCost)
		plaque:SetAttribute("Title", stats.DisplayName)
		surfaceText(plaque, {
			{ text = string.upper(stats.DisplayName), size = 26, color = Color3.new(1, 1, 1) },
			{ text = stats.WallCost .. "  •  ammo " .. stats.AmmoCost, size = 22, color = Color3.fromRGB(255, 225, 120) },
		})
		CollectionService:AddTag(plaque, "Interactable")
	end
end

local function buildPerks()
	for _, pm in Layout.Perks do
		local perk = PerkConfig.Perks[pm.Perk]
		local cf = CFrame.lookAt(pm.Pos + Vector3.new(0, 3.5, 0), pm.Pos + Vector3.new(0, 3.5, 0) + pm.Face)
		local body = part({ Name = "Perk_" .. perk.Id, Size = Vector3.new(4, 7, 3), CFrame = cf, Color = perk.Color:Lerp(Color3.new(0, 0, 0), 0.45) })
		part({ Name = "Sign", Size = Vector3.new(4.2, 1.2, 3.2), CFrame = cf * CFrame.new(0, 3.2, 0), Color = perk.Color, Material = Enum.Material.Neon, CanCollide = false })
		local light = Instance.new("PointLight")
		light.Color = perk.Color
		light.Range = 14
		light.Brightness = 1.2
		light.Parent = body
		body:SetAttribute("Kind", "Perk")
		body:SetAttribute("Id", perk.Id)
		body:SetAttribute("Cost", perk.Cost)
		body:SetAttribute("Title", perk.DisplayName)
		surfaceText(body, {
			{ text = string.upper(perk.DisplayName), size = 26, color = Color3.new(1, 1, 1) },
			{ text = perk.Description, size = 16, color = Color3.fromRGB(220, 220, 230) },
			{ text = perk.Cost .. " PTS", size = 26, color = Color3.fromRGB(255, 225, 120) },
		})
		CollectionService:AddTag(body, "Interactable")
	end
end

local function buildForge()
	local f = Layout.Forge
	local cf = CFrame.lookAt(f.Pos + Vector3.new(0, 2, 0), f.Pos + Vector3.new(0, 2, 0) + f.Face)
	local altar = part({ Name = "SpiritForge", Size = Vector3.new(7, 4, 4), CFrame = cf, Color = Color3.fromRGB(40, 36, 60), Material = Enum.Material.Marble })
	local orb = part({
		Name = "ForgeOrb",
		Shape = Enum.PartType.Ball,
		Size = Vector3.one * 2.4,
		CFrame = cf * CFrame.new(0, 3.6, 0),
		Color = WeaponConfig.Upgrade.Accent,
		Material = Enum.Material.Neon,
		CanCollide = false,
	})
	local light = Instance.new("PointLight")
	light.Color = WeaponConfig.Upgrade.Accent
	light.Range = 18
	light.Brightness = 2
	light.Parent = orb
	altar:SetAttribute("Kind", "Forge")
	altar:SetAttribute("Id", "Forge")
	altar:SetAttribute("Cost", WeaponConfig.Upgrade.Cost)
	altar:SetAttribute("Title", "Spirit Forge")
	surfaceText(altar, {
		{ text = "SPIRIT FORGE", size = 28, color = WeaponConfig.Upgrade.Accent },
		{ text = "Upgrade held weapon • " .. WeaponConfig.Upgrade.Cost, size = 18, color = Color3.new(1, 1, 1) },
	})
	CollectionService:AddTag(altar, "Interactable")
end

local function buildProps()
	for _, p in Layout.Props do
		local inst = part({
			Name = "Prop",
			Size = p.Size,
			Position = p.Pos,
			Color = p.Color,
			Material = p.Material and Enum.Material[p.Material] or Enum.Material.Concrete,
		})
		if p.Shape == "Cylinder" then
			inst.Shape = Enum.PartType.Cylinder
			inst.Size = Vector3.new(p.Size.Y, p.Size.X, p.Size.Z)
			inst.CFrame = CFrame.new(p.Pos) * CFrame.Angles(0, 0, math.rad(90))
		end
	end
	for _, a in Layout.Awnings do
		part({ Name = "Awning", Size = Vector3.new(11, 0.4, 6), Position = a.Pos, Color = a.Color, Material = Enum.Material.Neon, Transparency = 0.15 })
		for _, dx in { -5, 5 } do
			part({ Name = "AwningPost", Size = Vector3.new(0.4, 7, 0.4), Position = a.Pos + Vector3.new(dx, -3.5, 2.6), Color = Color3.fromRGB(60, 40, 30), Material = Enum.Material.Wood })
		end
	end
	-- Torii gate
	local t = Layout.Torii.Pos
	local red = Color3.fromRGB(190, 40, 40)
	for _, dx in { -6, 6 } do
		part({ Name = "ToriiPillar", Size = Vector3.new(1.4, 14, 1.4), Position = t + Vector3.new(dx, 7, 0), Color = red })
	end
	part({ Name = "ToriiTop", Size = Vector3.new(17, 1.2, 1.8), Position = t + Vector3.new(0, 14.4, 0), Color = Color3.fromRGB(30, 26, 26) })
	part({ Name = "ToriiBeam", Size = Vector3.new(14, 0.8, 1.2), Position = t + Vector3.new(0, 12, 0), Color = red })
	for _, pos in Layout.Lanterns do
		lantern(pos)
	end
end

local function buildMarkers()
	for i, s in Layout.EnemySpawns do
		local m = part({
			Name = "EnemySpawn" .. i,
			Size = Vector3.new(4, 0.2, 4),
			Position = s.Pos + Vector3.new(0, 0.1, 0),
			Color = Color3.fromRGB(200, 40, 60),
			Material = Enum.Material.Neon,
			Transparency = 0.7,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
		})
		m:SetAttribute("Zone", s.Zone)
		CollectionService:AddTag(m, "EnemySpawn")
	end
end

-- Boarded windows. Each fills its wall gap with a sill, lintel, an invisible blocker
-- (always solid for everyone; zombies "vault" over it with a tween) and N boards.
-- State lives in attributes on the blocker (tag "Barrier"): Boards, MaxBoards, Zone,
-- Outside, Inside (Vector3). BarrierService owns tearing/repairing.
local function buildBarriers()
	local GameConfigB = GameConfig.Barrier
	for i, b in Layout.Barriers or {} do
		local width = b.Width or 6
		local sill, openH = b.Sill or 3, b.Height or 5.5
		local wallH = b.WallHeight or Layout.WallHeight
		local inward = b.Inward.Unit
		local center = b.Axis == "x" and Vector3.new(b.Along, 0, b.At) or Vector3.new(b.At, 0, b.Along)
		local sizeAlong = function(h)
			return b.Axis == "x" and Vector3.new(width, h, 2) or Vector3.new(2, h, width)
		end
		local wallColor = Color3.fromRGB(120, 92, 70)
		local wallMat = wallH > 20 and Enum.Material.Rock or Enum.Material.Brick
		if wallH <= 20 then
			wallColor = Layout.WallColor or wallColor
		end
		part({ Name = "BarrierSill", Size = sizeAlong(sill), Position = center + Vector3.new(0, sill / 2, 0), Color = wallColor, Material = wallMat })
		part({ Name = "BarrierLintel", Size = sizeAlong(wallH - sill - openH), Position = center + Vector3.new(0, sill + openH + (wallH - sill - openH) / 2, 0), Color = wallColor, Material = wallMat })
		-- window frame trim
		part({ Name = "BarrierFrame", Size = sizeAlong(0.4) + (b.Axis == "x" and Vector3.new(0.6, 0, 0.3) or Vector3.new(0.3, 0, 0.6)), Position = center + Vector3.new(0, sill + openH + 0.2, 0), Color = Color3.fromRGB(70, 52, 40), Material = Enum.Material.Wood })

		local blocker = part({
			Name = "Barrier" .. i,
			Size = sizeAlong(openH),
			Position = center + Vector3.new(0, sill + openH / 2, 0),
			Transparency = 1,
			CanQuery = false, -- bullets pass through to zombies outside
		})
		blocker:SetAttribute("Kind", "Barrier")
		blocker:SetAttribute("Id", "Barrier" .. i)
		blocker:SetAttribute("Cost", 0)
		blocker:SetAttribute("Title", "Boarded window")
		blocker:SetAttribute("Zone", b.Zone)
		blocker:SetAttribute("Boards", GameConfigB.Boards)
		blocker:SetAttribute("MaxBoards", GameConfigB.Boards)
		blocker:SetAttribute("Outside", center - inward * 4 + Vector3.new(0, 3, 0))
		blocker:SetAttribute("Inside", center + inward * 4.5 + Vector3.new(0, 3, 0))

		-- Boards: planks across the inner face of the opening, staggered and slightly crooked
		local rngB = Random.new(i * 7919)
		for n = 1, GameConfigB.Boards do
			local y = sill + 0.5 + (n - 0.5) * (openH - 1) / GameConfigB.Boards
			local along = b.Axis == "x" and Vector3.new(width + 0.8, 0.55, 0.25) or Vector3.new(0.25, 0.55, width + 0.8)
			local roll = math.rad(rngB:NextNumber(-12, 12))
			local cf = CFrame.new(center + Vector3.new(0, y, 0) + inward * 1.15)
				* (b.Axis == "x" and CFrame.Angles(0, 0, roll) or CFrame.Angles(roll, 0, 0))
			local board = part({
				Name = "Board" .. n,
				Size = along,
				CFrame = cf,
				Color = Color3.fromRGB(rngB:NextInteger(110, 140), rngB:NextInteger(80, 100), rngB:NextInteger(55, 70)),
				Material = Enum.Material.WoodPlanks,
				CanCollide = false,
				CanQuery = false,
			})
			board:SetAttribute("HomeCFrame", cf)
			board.Parent = blocker
		end

		-- Little ledge outside so zombies have ground to stand on (some walls sit on the map edge)
		part({ Name = "BarrierLedge", Size = Vector3.new(8, 1, 8), Position = center - inward * 5 + Vector3.new(0, -0.5, 0), Color = Color3.fromRGB(120, 100, 80), Material = Enum.Material.Ground })

		CollectionService:AddTag(blocker, "Barrier")
		CollectionService:AddTag(blocker, "Interactable")
	end
end

-- Boss arena (Milestone 5): an invisible volume + boss spawn markers
local function buildBossArena()
	local a = Layout.BossArena
	if not a then
		return
	end
	local vol = part({ Name = "BossArena", Size = a.Size, Position = a.Center + Vector3.new(0, a.Size.Y / 2, 0), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
	CollectionService:AddTag(vol, "BossArena")
	for i, p in a.BossSpawns or {} do
		local m = part({ Name = "BossSpawn" .. i, Size = Vector3.new(6, 0.2, 6), Position = p + Vector3.new(0, 0.1, 0), Transparency = 1, CanCollide = false, CanQuery = false, CanTouch = false })
		CollectionService:AddTag(m, "BossSpawn")
	end
end

local function setAtmosphere()
	-- Dusk lighting, PLACEHOLDER for a proper per-map lighting preset
	Lighting.ClockTime = 18.4
	Lighting.Brightness = 1.4
	Lighting.Ambient = Color3.fromRGB(70, 60, 90)
	Lighting.OutdoorAmbient = Color3.fromRGB(90, 70, 110)
	Lighting.FogColor = Color3.fromRGB(60, 40, 70)
	Lighting.FogStart = 60
	Lighting.FogEnd = 320
	for k, v in Layout.Lighting or {} do
		Lighting[k] = v
	end
	-- Post-processing: Atmosphere haze, color grade, bloom (per map)
	local fx = Layout.PostFX
	if fx then
		local function ensure(className, name)
			local inst = Lighting:FindFirstChild(name) or Lighting:FindFirstChildOfClass(className)
			if not inst then
				inst = Instance.new(className)
				inst.Name = name
				inst.Parent = Lighting
			end
			return inst
		end
		for prop, v in fx.Atmosphere or {} do
			ensure("Atmosphere", "Atmosphere")[prop] = v
		end
		for prop, v in fx.ColorCorrection or {} do
			ensure("ColorCorrectionEffect", "MapColorGrade")[prop] = v
		end
		for prop, v in fx.Bloom or {} do
			ensure("BloomEffect", "Bloom")[prop] = v
		end
	end
end

----------------------------------------------------------------------
-- Geometry API handed to maps that build their own geometry (Layout.BuildGeometry)
----------------------------------------------------------------------

local GeometryApi = {}

-- Plain anchored part. props: Size, Position/CFrame, Color, Material (string or Enum), etc.
function GeometryApi.part(props)
	if typeof(props.Material) == "string" then
		props.Material = Enum.Material[props.Material]
	end
	return part(props)
end

-- Axis-aligned box from two corners (min/max), handy for greyboxing.
function GeometryApi.box(name: string, min: Vector3, max: Vector3, color: Color3?, material: string?, extra)
	local props = {
		Name = name,
		Size = max - min,
		Position = (min + max) / 2,
		Color = color or Color3.fromRGB(110, 100, 90),
		Material = material and Enum.Material[material] or Enum.Material.Concrete,
	}
	for k, v in extra or {} do
		props[k] = v
	end
	return part(props)
end

-- Floor slab with optional rectangular holes (e.g. stairwells). Splits into strips around holes.
-- min/max are XZ corners (Vector2 or Vector3); y = top surface height.
function GeometryApi.floor(name: string, minX, minZ, maxX, maxZ, y: number, color: Color3?, material: string?, holes)
	local xs = { minX, maxX }
	local zs = { minZ, maxZ }
	for _, h in holes or {} do
		table.insert(xs, h[1]); table.insert(xs, h[3])
		table.insert(zs, h[2]); table.insert(zs, h[4])
	end
	table.sort(xs); table.sort(zs)
	for i = 1, #xs - 1 do
		for j = 1, #zs - 1 do
			local x0, x1, z0, z1 = xs[i], xs[i + 1], zs[j], zs[j + 1]
			if x1 - x0 > 0.01 and z1 - z0 > 0.01 then
				local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
				local inHole = false
				for _, h in holes or {} do
					if cx > h[1] and cx < h[3] and cz > h[2] and cz < h[4] then
						inHole = true
						break
					end
				end
				if not inHole then
					GeometryApi.box(name, Vector3.new(x0, y - 1, z0), Vector3.new(x1, y, z1), color, material or "Slate")
				end
			end
		end
	end
end

-- Straight wall along an axis with openings cut out (doors and windows).
--   axis "x": runs along X at z = at;  axis "z": runs along Z at x = at
--   openings: { from, to (coords along the wall), height, bottom? (sill above baseY, 0 = door), glass? }
-- Windows (bottom > 0) get a sill trim; glass = true adds a pane.
function GeometryApi.wall(name: string, axis: string, at: number, a0: number, a1: number, baseY: number, height: number, openings, opts)
	opts = opts or {}
	local color = opts.color or Color3.fromRGB(150, 130, 105)
	local material = opts.material or "Concrete"
	local t = opts.thickness or 1
	local trimColor = opts.trimColor or Color3.fromRGB(230, 225, 210)
	local cuts = {}
	for _, o in openings or {} do
		table.insert(cuts, o)
	end
	table.sort(cuts, function(p, q)
		return p.from < q.from
	end)
	local function box(s0, s1, y0, y1, depth, c, m, extra)
		if s1 - s0 < 0.01 or y1 - y0 < 0.01 then
			return
		end
		local d = depth or t
		if axis == "x" then
			return GeometryApi.box(name, Vector3.new(s0, y0, at - d / 2), Vector3.new(s1, y1, at + d / 2), c or color, m or material, extra)
		else
			return GeometryApi.box(name, Vector3.new(at - d / 2, y0, s0), Vector3.new(at + d / 2, y1, s1), c or color, m or material, extra)
		end
	end
	local cursor = a0
	for _, o in cuts do
		local bottom = o.bottom or 0
		local top = bottom + (o.height or 8)
		box(cursor, o.from, baseY, baseY + height)
		box(o.from, o.to, baseY, baseY + bottom) -- wall under a window
		box(o.from, o.to, baseY + top, baseY + height) -- lintel
		if bottom > 0 then
			box(o.from - 0.3, o.to + 0.3, baseY + bottom - 0.25, baseY + bottom, t + 0.6, trimColor, "SmoothPlastic") -- sill
		end
		if o.glass then
			box(o.from, o.to, baseY + bottom, baseY + top, 0.2, Color3.fromRGB(150, 180, 190), "Glass", { Transparency = 0.55, Name = name .. "_Glass" })
		end
		cursor = o.to
	end
	box(cursor, a1, baseY, baseY + height)
end

-- Wedge (no foot pad). dir = direction it rises toward.
function GeometryApi.wedge(name: string, minX, minZ, maxX, maxZ, lowY: number, highY: number, dir: string, color: Color3?, material: string?)
	local sizeX, sizeZ = maxX - minX, maxZ - minZ
	local rise = highY - lowY
	local center = Vector3.new((minX + maxX) / 2, lowY + rise / 2, (minZ + maxZ) / 2)
	-- A WedgePart rises toward its local +Z; rotate so it rises toward `dir`.
	local yaw = ({ n = 0, w = math.pi / 2, s = math.pi, e = -math.pi / 2 })[dir]
	local length = (dir == "n" or dir == "s") and sizeZ or sizeX
	local width = (dir == "n" or dir == "s") and sizeX or sizeZ
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = Vector3.new(width, rise, length)
	w.CFrame = CFrame.new(center) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, math.pi, 0)
	w.Color = color or Color3.fromRGB(120, 115, 110)
	w.Material = material and Enum.Material[material] or Enum.Material.Concrete
	w.TopSurface = Enum.SurfaceType.Smooth
	w.Parent = mapFolder
	return w
end

-- Gable roof over a rectangle. ridge = "x" (ridge runs east-west) or "z".
function GeometryApi.gableRoof(name: string, minX, minZ, maxX, maxZ, y: number, rise: number, ridge: string, color: Color3?)
	local o = 1.2 -- overhang
	minX, minZ, maxX, maxZ = minX - o, minZ - o, maxX + o, maxZ + o
	color = color or Color3.fromRGB(90, 60, 50)
	if ridge == "x" then
		local mid = (minZ + maxZ) / 2
		GeometryApi.wedge(name, minX, minZ, maxX, mid, y, y + rise, "s", color, "Slate")
		GeometryApi.wedge(name, minX, mid, maxX, maxZ, y, y + rise, "n", color, "Slate")
	else
		local mid = (minX + maxX) / 2
		GeometryApi.wedge(name, minX, minZ, mid, maxZ, y, y + rise, "e", color, "Slate")
		GeometryApi.wedge(name, mid, minZ, maxX, maxZ, y, y + rise, "w", color, "Slate")
	end
	-- ceiling slab so the roof is solid from below
	GeometryApi.box(name .. "_Ceiling", Vector3.new(minX + o, y - 0.4, minZ + o), Vector3.new(maxX - o, y, maxZ - o), Color3.fromRGB(200, 190, 175), "SmoothPlastic")
end

-- Hollow building: 4 walls (thickness 1) with doors/windows, floor, roof.
--   openings: { side = "n"|"s"|"e"|"w", from, to, height, bottom?, glass? }
--   (n = min Z side, s = max Z side, w = min X side, e = max X side)
--   opts: color, material, skip = {"w"} (shared walls), floor = false, floorHoles,
--         roof = false | "flat" (default) | "gable", ridge = "x"|"z", rise, parapet = height
function GeometryApi.shell(name: string, minX, minZ, maxX, maxZ, baseY: number, height: number, opts)
	opts = opts or {}
	local t = 1
	local skip = {}
	for _, s in opts.skip or {} do
		skip[s] = true
	end
	local per = { n = {}, s = {}, e = {}, w = {} }
	for _, o in opts.openings or {} do
		table.insert(per[o.side], o)
	end
	local wallOpts = { color = opts.color or Color3.fromRGB(150, 130, 105), material = opts.material or "Concrete", trimColor = opts.trimColor }
	if not skip.n then
		GeometryApi.wall(name .. "_Wall", "x", minZ, minX, maxX, baseY, height, per.n, wallOpts)
	end
	if not skip.s then
		GeometryApi.wall(name .. "_Wall", "x", maxZ, minX, maxX, baseY, height, per.s, wallOpts)
	end
	if not skip.w then
		GeometryApi.wall(name .. "_Wall", "z", minX, minZ + t / 2, maxZ - t / 2, baseY, height, per.w, wallOpts)
	end
	if not skip.e then
		GeometryApi.wall(name .. "_Wall", "z", maxX, minZ + t / 2, maxZ - t / 2, baseY, height, per.e, wallOpts)
	end
	if opts.floor ~= false then
		GeometryApi.floor(name .. "_Floor", minX, minZ, maxX, maxZ, baseY + 0.2, opts.floorColor or Color3.fromRGB(90, 80, 70), opts.floorMaterial or "WoodPlanks", opts.floorHoles)
	end
	local roofColor = opts.roofColor or Color3.fromRGB(70, 60, 55)
	if opts.roof == "gable" then
		GeometryApi.gableRoof(name .. "_Roof", minX, minZ, maxX, maxZ, baseY + height, opts.rise or 6, opts.ridge or "x", roofColor)
	elseif opts.roof ~= false then
		GeometryApi.box(name .. "_Roof", Vector3.new(minX - 0.5, baseY + height, minZ - 0.5), Vector3.new(maxX + 0.5, baseY + height + 1, maxZ + 0.5), roofColor, "Slate")
		if opts.parapet then
			local p, y0 = opts.parapet, baseY + height + 1
			local c = opts.color or Color3.fromRGB(150, 130, 105)
			GeometryApi.box(name .. "_Parapet", Vector3.new(minX - 0.5, y0, minZ - 0.5), Vector3.new(maxX + 0.5, y0 + p, minZ + 0.5), c, opts.material)
			GeometryApi.box(name .. "_Parapet", Vector3.new(minX - 0.5, y0, maxZ - 0.5), Vector3.new(maxX + 0.5, y0 + p, maxZ + 0.5), c, opts.material)
			GeometryApi.box(name .. "_Parapet", Vector3.new(minX - 0.5, y0, minZ + 0.5), Vector3.new(minX + 0.5, y0 + p, maxZ - 0.5), c, opts.material)
			GeometryApi.box(name .. "_Parapet", Vector3.new(maxX - 0.5, y0, minZ + 0.5), Vector3.new(maxX + 0.5, y0 + p, maxZ - 0.5), c, opts.material)
		end
	end
end

-- Evenly spaced windows along a wall span, skipping any that overlap `avoid` ranges.
function GeometryApi.windowRow(side: string, from: number, to: number, count: number, width: number, bottom: number, height: number, avoid)
	local list = {}
	local step = (to - from) / count
	for i = 0, count - 1 do
		local c = from + step * (i + 0.5)
		local w0, w1 = c - width / 2, c + width / 2
		local ok = true
		for _, a in avoid or {} do
			if w1 > a[1] - 1 and w0 < a[2] + 1 then
				ok = false
			end
		end
		if ok then
			table.insert(list, { side = side, from = w0, to = w1, bottom = bottom, height = height, glass = true })
		end
	end
	return list
end

-- Ramp: wedge rising from `low` edge to `high` edge. dir = "n"|"s"|"e"|"w" = direction you walk to go UP.
function GeometryApi.ramp(name: string, minX, minZ, maxX, maxZ, lowY: number, highY: number, dir: string, color: Color3?)
	local w = GeometryApi.wedge(name, minX, minZ, maxX, maxZ, lowY, highY, dir, color, "Concrete")

	-- Flat pad across the ramp's bottom edge. Without it, Roblox pathfinding treats the
	-- wedge's zero-thickness low edge as disconnected from the floor (verified in Studio).
	local padMin, padMax
	if dir == "s" then
		padMin, padMax = Vector3.new(minX, lowY - 0.6, minZ - 3), Vector3.new(maxX, lowY + 0.2, minZ + 4)
	elseif dir == "n" then
		padMin, padMax = Vector3.new(minX, lowY - 0.6, maxZ - 4), Vector3.new(maxX, lowY + 0.2, maxZ + 3)
	elseif dir == "w" then
		padMin, padMax = Vector3.new(maxX - 4, lowY - 0.6, minZ), Vector3.new(maxX + 3, lowY + 0.2, maxZ)
	else
		padMin, padMax = Vector3.new(minX - 3, lowY - 0.6, minZ), Vector3.new(minX + 4, lowY + 0.2, maxZ)
	end
	GeometryApi.box(name .. "_FootPad", padMin, padMax, color or Color3.fromRGB(120, 115, 110), "Concrete")
	return w
end

function GeometryApi.lantern(pos: Vector3, color: Color3?)
	lantern(pos)
	if color then
		local lamp = mapFolder:GetChildren()[#mapFolder:GetChildren()]
		if lamp and lamp.Name == "Lantern" then
			lamp.Color = color
			lamp.PointLight.Color = color
		end
	end
end

local function build()
	local existing = workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end
	mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"
	table.clear(unlocked)
	unlocked[0] = true
	if Layout.BuildGeometry then
		Layout.BuildGeometry(GeometryApi)
	else
		buildZones()
		buildProps()
	end
	buildWalls()
	buildBarriers()
	buildDoors()
	buildWallBuys()
	buildPerks()
	buildForge()
	buildMarkers()
	buildBossArena()
	mapFolder.Parent = workspace
	-- Maps that bring their own ground (with holes for basements) remove the Rojo baseplate at runtime.
	if Layout.OwnGround then
		local bp = workspace:FindFirstChild("Baseplate")
		if bp then
			bp:Destroy()
		end
	end
end

----------------------------------------------------------------------
-- API
----------------------------------------------------------------------

function MapService.Init()
	notify = Remotes.Get("Notify")
	build()
	setAtmosphere()
end

-- Rebuild everything (doors relock) for a fresh match.
function MapService.Reset()
	build()
end

function MapService.GetMapFolder(): Folder
	return mapFolder
end

function MapService.GetLayout()
	return Layout
end

function MapService.IsZoneUnlocked(zone: number): boolean
	return unlocked[zone] == true
end

function MapService.OpenDoor(door: BasePart, opener: Player?)
	if not door.Parent then
		return
	end
	local a, b = door:GetAttribute("ZoneA"), door:GetAttribute("ZoneB")
	unlocked[a] = true
	unlocked[b] = true
	CollectionService:RemoveTag(door, "Interactable")
	door.CanCollide = false
	door.CanQuery = false
	for _, gui in door:GetChildren() do
		if gui:IsA("SurfaceGui") then
			gui:Destroy()
		end
	end
	TweenService:Create(door, TweenInfo.new(0.8), { Transparency = 1, Position = door.Position + Vector3.new(0, -2, 0) }):Play()
	task.delay(0.9, function()
		door:Destroy()
	end)
	notify:FireAllClients("DoorOpened", {
		by = opener and opener.DisplayName or nil,
		zones = { Layout.Zones[a].Name, Layout.Zones[b].Name },
		position = door.Position,
	})
end

function MapService.GetPlayerSpawnCFrame(): CFrame
	local a = math.random() * math.pi * 2
	return CFrame.new(Layout.PlayerSpawn + Vector3.new(math.cos(a) * 5, 3, math.sin(a) * 5))
end

local function playerRoots()
	local roots = {}
	for _, plr in Players:GetPlayers() do
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		local hum = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
		if root and hum and hum.Health > 0 then
			table.insert(roots, root.Position)
		end
	end
	return roots
end

local function nearestDist(roots, pos)
	local best = math.huge
	for _, r in roots do
		best = math.min(best, (r - pos).Magnitude)
	end
	return best
end

-- Pick from candidates: prefer ones 22..maxNear studs from the nearest living player.
local function pickNear(list, getPos, roots, maxNear)
	local preferred, fallback = {}, {}
	for _, c in list do
		local d = nearestDist(roots, getPos(c))
		if d >= 22 then
			table.insert(fallback, c)
			if d <= maxNear then
				table.insert(preferred, c)
			end
		end
	end
	local pool = #preferred > 0 and preferred or (#fallback > 0 and fallback or list)
	return #pool > 0 and pool[math.random(1, #pool)] or nil
end

-- Where the next zombie comes from: a boarded window (most of the time) or a ground spawn.
-- Returns { pos: Vector3, barrier: BasePart? , emerge: boolean }
function MapService.GetEnemySpawn()
	local roots = playerRoots()
	local barriers, grounds = {}, {}
	for _, b in CollectionService:GetTagged("Barrier") do
		if b:IsDescendantOf(mapFolder) and unlocked[b:GetAttribute("Zone")] then
			table.insert(barriers, b)
		end
	end
	for _, s in CollectionService:GetTagged("EnemySpawn") do
		if s:IsDescendantOf(mapFolder) and unlocked[s:GetAttribute("Zone")] then
			table.insert(grounds, s)
		end
	end
	local useBarrier = #barriers > 0 and (#grounds == 0 or math.random() < GameConfig.Barrier.BarrierSpawnChance)
	if useBarrier then
		local b = pickNear(barriers, function(x)
			return x:GetAttribute("Inside")
		end, roots, 110)
		if b then
			local out = b:GetAttribute("Outside")
			local side = (b:GetAttribute("Inside") - out).Unit:Cross(Vector3.yAxis)
			return { pos = out - Vector3.new(0, 3, 0) + side * math.random(-15, 15) / 10, barrier = b, emerge = false }
		end
	end
	local s = pickNear(grounds, function(x)
		return x.Position
	end, roots, 85)
	if not s then
		return nil
	end
	return { pos = s.Position + Vector3.new(math.random(-3, 3), 0, math.random(-3, 3)), barrier = nil, emerge = true }
end

-- Back-compat helper
function MapService.GetEnemySpawnPosition(): Vector3
	local info = MapService.GetEnemySpawn()
	return info and info.pos or Layout.PlayerSpawn
end

return MapService
