--!nonstrict
-- Builds the PLACEHOLDER arena at runtime and hands out spawn points.
-- Replace with a real map (ServerStorage template) in Milestone 2.

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")

local MapService = {}

local ARENA_HALF = 70
local WALL_HEIGHT = 16

local mapFolder: Folder

local function part(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.Concrete
	p.Color = Color3.fromRGB(70, 72, 82)
	for k, v in props do
		p[k] = v
	end
	p.Parent = props.Parent or mapFolder
	return p
end

local function marker(name: string, tag: string, position: Vector3, color: Color3)
	local m = part({
		Name = name,
		Size = Vector3.new(4, 0.2, 4),
		Position = position + Vector3.new(0, 0.1, 0),
		Color = color,
		Material = Enum.Material.Neon,
		Transparency = 0.6,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
	})
	CollectionService:AddTag(m, tag)
	return m
end

local function buildArena()
	-- Outer walls
	local wallColor = Color3.fromRGB(52, 48, 62)
	for _, def in {
		{ Vector3.new(0, WALL_HEIGHT / 2, -ARENA_HALF), Vector3.new(ARENA_HALF * 2 + 4, WALL_HEIGHT, 4) },
		{ Vector3.new(0, WALL_HEIGHT / 2, ARENA_HALF), Vector3.new(ARENA_HALF * 2 + 4, WALL_HEIGHT, 4) },
		{ Vector3.new(-ARENA_HALF, WALL_HEIGHT / 2, 0), Vector3.new(4, WALL_HEIGHT, ARENA_HALF * 2 + 4) },
		{ Vector3.new(ARENA_HALF, WALL_HEIGHT / 2, 0), Vector3.new(4, WALL_HEIGHT, ARENA_HALF * 2 + 4) },
	} do
		part({ Name = "Wall", Position = def[1], Size = def[2], Color = wallColor, Material = Enum.Material.Brick })
	end

	-- Floor overlay so the arena reads as a distinct space
	part({
		Name = "Floor",
		Size = Vector3.new(ARENA_HALF * 2, 1, ARENA_HALF * 2),
		Position = Vector3.new(0, -0.45, 0),
		Color = Color3.fromRGB(58, 56, 64),
		Material = Enum.Material.Slate,
	})

	-- Cover blocks (symmetric layout)
	local coverColor = Color3.fromRGB(88, 84, 98)
	local covers = {
		{ Vector3.new(22, 3, 22), Vector3.new(10, 6, 3) },
		{ Vector3.new(-22, 3, -22), Vector3.new(10, 6, 3) },
		{ Vector3.new(-22, 3, 22), Vector3.new(3, 6, 10) },
		{ Vector3.new(22, 3, -22), Vector3.new(3, 6, 10) },
		{ Vector3.new(0, 2.5, 38), Vector3.new(14, 5, 3) },
		{ Vector3.new(0, 2.5, -38), Vector3.new(14, 5, 3) },
		{ Vector3.new(38, 2.5, 0), Vector3.new(3, 5, 14) },
		{ Vector3.new(-38, 2.5, 0), Vector3.new(3, 5, 14) },
		{ Vector3.new(45, 4, 45), Vector3.new(6, 8, 6) },
		{ Vector3.new(-45, 4, -45), Vector3.new(6, 8, 6) },
		{ Vector3.new(-45, 4, 45), Vector3.new(6, 8, 6) },
		{ Vector3.new(45, 4, -45), Vector3.new(6, 8, 6) },
	}
	for i, c in covers do
		part({ Name = "Cover" .. i, Position = c[1], Size = c[2], Color = coverColor })
	end

	-- Lantern posts: purely atmospheric PLACEHOLDER (anime shrine-town vibe)
	for _, pos in { Vector3.new(12, 0, 12), Vector3.new(-12, 0, -12), Vector3.new(-12, 0, 12), Vector3.new(12, 0, -12) } do
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
		light.Brightness = 1.6
		light.Parent = lamp
	end

	-- Enemy spawn points along the walls
	for i, pos in {
		Vector3.new(0, 0, -64), Vector3.new(0, 0, 64), Vector3.new(-64, 0, 0), Vector3.new(64, 0, 0),
		Vector3.new(-60, 0, -60), Vector3.new(60, 0, 60), Vector3.new(-60, 0, 60), Vector3.new(60, 0, -60),
	} do
		marker("EnemySpawn" .. i, "EnemySpawn", pos, Color3.fromRGB(200, 40, 60))
	end

	-- Player spawn ring at the center
	for i = 1, 4 do
		local a = (i / 4) * math.pi * 2
		marker("PlayerSpawn" .. i, "PlayerSpawn", Vector3.new(math.cos(a) * 6, 0, math.sin(a) * 6), Color3.fromRGB(60, 160, 255))
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
end

function MapService.Init()
	local existing = workspace:FindFirstChild("Map")
	if existing then
		existing:Destroy()
	end
	mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"
	mapFolder.Parent = workspace
	buildArena()
	setAtmosphere()
end

function MapService.GetMapFolder(): Folder
	return mapFolder
end

local function randomFrom(tag: string)
	local list = CollectionService:GetTagged(tag)
	return list[math.random(1, #list)]
end

function MapService.GetPlayerSpawnCFrame(): CFrame
	local m = randomFrom("PlayerSpawn")
	return CFrame.new(m.Position + Vector3.new(0, 3, 0))
end

-- Prefer spawn points that are not right next to a player.
function MapService.GetEnemySpawnPosition(): Vector3
	local spawns = CollectionService:GetTagged("EnemySpawn")
	local candidates = {}
	for _, s in spawns do
		local tooClose = false
		for _, plr in Players:GetPlayers() do
			local root = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
			if root and (root.Position - s.Position).Magnitude < 25 then
				tooClose = true
				break
			end
		end
		if not tooClose then
			table.insert(candidates, s)
		end
	end
	if #candidates == 0 then
		candidates = spawns
	end
	local chosen = candidates[math.random(1, #candidates)]
	local jitter = Vector3.new(math.random(-3, 3), 0, math.random(-3, 3))
	return chosen.Position + jitter
end

return MapService
