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
		-- Split the wall line around door gaps
		local cuts = { w.from }
		for _, g in w.gaps or {} do
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

-- Hollow building shell: 4 walls (thickness 1), optional floor/roof, doorway openings.
-- openings: { side = "n"|"s"|"e"|"w", from, to (world coord along the wall), height }
-- (n = min Z side, s = max Z side, w = min X side, e = max X side)
function GeometryApi.shell(name: string, minX, minZ, maxX, maxZ, baseY: number, height: number, opts)
	opts = opts or {}
	local color = opts.color or Color3.fromRGB(150, 130, 105)
	local material = opts.material or "Concrete"
	local t = 1
	local function wallRun(side, a0, a1)
		-- build the wall run along one side with its openings cut out
		local cuts = {}
		for _, o in opts.openings or {} do
			if o.side == side then
				table.insert(cuts, o)
			end
		end
		table.sort(cuts, function(p, q)
			return p.from < q.from
		end)
		local cursor = a0
		local function seg(s0, s1, y0, y1)
			if s1 - s0 < 0.01 or y1 - y0 < 0.01 then
				return
			end
			if side == "n" or side == "s" then
				local z = side == "n" and minZ or maxZ
				GeometryApi.box(name .. "_Wall", Vector3.new(s0, y0, z - t / 2), Vector3.new(s1, y1, z + t / 2), color, material)
			else
				local x = side == "w" and minX or maxX
				GeometryApi.box(name .. "_Wall", Vector3.new(x - t / 2, y0, s0), Vector3.new(x + t / 2, y1, s1), color, material)
			end
		end
		for _, o in cuts do
			seg(cursor, o.from, baseY, baseY + height)
			seg(o.from, o.to, baseY + (o.height or 8), baseY + height) -- lintel above the opening
			cursor = o.to
		end
		seg(cursor, a1, baseY, baseY + height)
	end
	wallRun("n", minX, maxX)
	wallRun("s", minX, maxX)
	wallRun("w", minZ + t / 2, maxZ - t / 2)
	wallRun("e", minZ + t / 2, maxZ - t / 2)
	if opts.floor ~= false then
		GeometryApi.floor(name .. "_Floor", minX, minZ, maxX, maxZ, baseY + 0.2, opts.floorColor or Color3.fromRGB(90, 80, 70), opts.floorMaterial or "WoodPlanks", opts.floorHoles)
	end
	if opts.roof ~= false then
		GeometryApi.box(name .. "_Roof", Vector3.new(minX - 1, baseY + height, minZ - 1), Vector3.new(maxX + 1, baseY + height + 1, maxZ + 1), opts.roofColor or Color3.fromRGB(70, 60, 55), "Slate")
	end
end

-- Ramp: wedge rising from `low` edge to `high` edge. dir = "n"|"s"|"e"|"w" = direction you walk to go UP.
function GeometryApi.ramp(name: string, minX, minZ, maxX, maxZ, lowY: number, highY: number, dir: string, color: Color3?)
	local sizeX, sizeZ = maxX - minX, maxZ - minZ
	local rise = highY - lowY
	local center = Vector3.new((minX + maxX) / 2, lowY + rise / 2, (minZ + maxZ) / 2)
	-- A WedgePart rises toward its -Z (front) face. Rotate so it rises toward `dir`.
	local yaw = ({ n = 0, w = math.pi / 2, s = math.pi, e = -math.pi / 2 })[dir]
	local length = (dir == "n" or dir == "s") and sizeZ or sizeX
	local width = (dir == "n" or dir == "s") and sizeX or sizeZ
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = Vector3.new(width, rise, length)
	w.CFrame = CFrame.new(center) * CFrame.Angles(0, yaw, 0) * CFrame.Angles(0, math.pi, 0)
	w.Color = color or Color3.fromRGB(120, 115, 110)
	w.Material = Enum.Material.Concrete
	w.TopSurface = Enum.SurfaceType.Smooth
	w.Parent = mapFolder
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
	buildDoors()
	buildWallBuys()
	buildPerks()
	buildForge()
	buildMarkers()
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

-- Spawn near the action: unlocked zones, not on top of a player, not too far from one.
function MapService.GetEnemySpawnPosition(): Vector3
	local roots = {}
	for _, plr in Players:GetPlayers() do
		local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
		if root then
			table.insert(roots, root.Position)
		end
	end
	local preferred, fallback = {}, {}
	for _, s in CollectionService:GetTagged("EnemySpawn") do
		if s:IsDescendantOf(mapFolder) and unlocked[s:GetAttribute("Zone")] then
			local nearest = math.huge
			for _, r in roots do
				nearest = math.min(nearest, (r - s.Position).Magnitude)
			end
			if nearest >= 22 then
				table.insert(fallback, s)
				if nearest <= 85 then
					table.insert(preferred, s)
				end
			end
		end
	end
	local list = #preferred > 0 and preferred or fallback
	if #list == 0 then
		for _, s in CollectionService:GetTagged("EnemySpawn") do
			if s:IsDescendantOf(mapFolder) and unlocked[s:GetAttribute("Zone")] then
				table.insert(list, s)
			end
		end
	end
	local chosen = list[math.random(1, #list)]
	return chosen.Position + Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
end

return MapService
