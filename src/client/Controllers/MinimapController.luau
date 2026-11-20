--!nonstrict
-- Rotating circular minimap (top-left), CoD-style.
--   * Map: footprints of the town's walls/buildings, roads, locked doors, perk machines.
--   * You: arrow fixed at the center, map turns with your view. Teammates: cyan dots.
--   * Zombies: hidden, except during a radar sweep every few seconds (dots fade out),
--     or live while a streak UAV is active (player attribute UavUntil).
-- Everything is drawn client-side from replicated parts; no remotes.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local ProgressionConfig = require(game.ReplicatedStorage.Shared.Config.ProgressionConfig)
local PerkConfig = require(game.ReplicatedStorage.Shared.Config.PerkConfig)

local MinimapController = {}

local player = Players.LocalPlayer
local SIZE = 210 -- px diameter
local RANGE = 120 -- studs from center to edge
local SCALE = (SIZE / 2) / RANGE -- px per stud
local MAX_DOTS = 40

local gui: ScreenGui
local pivot: Frame
local world: Frame
local mapLayer: Frame -- footprints (rebuilt when the map is)
local origin = Vector2.zero -- world XZ of the world frame's top-left
local dots = {}
local mates = {}
local sweepLabel: TextLabel
local sweepRing: Frame
local lastSweep = 0

local function new(className, props, children)
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, c in children or {} do
		c.Parent = inst
	end
	inst.Parent = props.Parent
	return inst
end

-- XZ world position -> pixel inside `world`
local function toMap(x: number, z: number): UDim2
	return UDim2.fromOffset((x - origin.X) * SCALE, (z - origin.Y) * SCALE)
end

----------------------------------------------------------------------
-- Static map drawing
----------------------------------------------------------------------

local ROAD_NAMES = { MainStreet = true, ElmLane = true, LoopRoad = true, GasApron = true, MotelLot = true, Alley = true, AlleyPassage = true }

local function rect(part: BasePart, color: Color3, transparency: number, z: number)
	local cf = part.CFrame
	local _, yaw, _ = cf:ToOrientation()
	new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = toMap(cf.Position.X, cf.Position.Z),
		Size = UDim2.fromOffset(math.max(1.5, part.Size.X * SCALE), math.max(1.5, part.Size.Z * SCALE)),
		Rotation = -math.deg(yaw),
		BackgroundColor3 = color,
		BackgroundTransparency = transparency,
		BorderSizePixel = 0,
		ZIndex = z,
		Parent = mapLayer,
	})
end

local function drawMap()
	local map = workspace:FindFirstChild("Map")
	if not map then
		return false
	end
	-- only the footprint layer is rebuilt; marker and dot layers live beside it
	for _, c in mapLayer:GetChildren() do
		c:Destroy()
	end
	-- bounds from the ground
	local minX, minZ, maxX, maxZ = math.huge, math.huge, -math.huge, -math.huge
	for _, p in map:GetDescendants() do
		if p:IsA("BasePart") and p.Name == "Ground" then
			minX = math.min(minX, p.Position.X - p.Size.X / 2)
			maxX = math.max(maxX, p.Position.X + p.Size.X / 2)
			minZ = math.min(minZ, p.Position.Z - p.Size.Z / 2)
			maxZ = math.max(maxZ, p.Position.Z + p.Size.Z / 2)
		end
	end
	if minX == math.huge then
		minX, minZ, maxX, maxZ = -300, -300, 300, 300
	end
	origin = Vector2.new(minX, minZ)
	world.Size = UDim2.fromOffset((maxX - minX) * SCALE, (maxZ - minZ) * SCALE)
	new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(70, 58, 46), BorderSizePixel = 0, ZIndex = 1, Parent = mapLayer })

	for _, p in map:GetDescendants() do
		if not p:IsA("BasePart") then
			continue
		end
		local top = p.Position.Y + p.Size.Y / 2
		if ROAD_NAMES[p.Name] then
			rect(p, Color3.fromRGB(40, 38, 40), 0, 2)
		elseif p.CanCollide and p.Transparency < 0.9 and p.Size.Y >= 4 and top > 3 and p.Position.Y > -4 and p.CollisionGroup ~= "PlayerClip" then
			-- walls, buildings, cliffs, containers
			local isCliff = p.Name == "Cliff" or p.Material == Enum.Material.Rock
			rect(p, isCliff and Color3.fromRGB(120, 92, 70) or Color3.fromRGB(205, 200, 190), isCliff and 0.1 or 0.05, 3)
		end
	end
	return true
end

-- Doors / perk machines change (doors disappear when bought), so redraw these on tag changes.
local markerFolder: Frame
local function drawMarkers()
	for _, c in markerFolder:GetChildren() do
		c:Destroy()
	end
	for _, p in CollectionService:GetTagged("Interactable") do
		if not p:IsA("BasePart") then
			continue
		end
		local kind = p:GetAttribute("Kind")
		if kind == "Door" then
			local cf = p.CFrame
			local _, yaw, _ = cf:ToOrientation()
			new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = toMap(cf.Position.X, cf.Position.Z),
				Size = UDim2.fromOffset(math.max(3, p.Size.X * SCALE), math.max(3, p.Size.Z * SCALE)),
				Rotation = -math.deg(yaw),
				BackgroundColor3 = Color3.fromRGB(255, 120, 40),
				BorderSizePixel = 0,
				ZIndex = 4,
				Parent = markerFolder,
			})
		elseif kind == "Perk" or kind == "MysteryBox" or kind == "Forge" then
			local perk = kind == "Perk" and PerkConfig.Perks[p:GetAttribute("Id")]
			local color = perk and perk.Color or (kind == "MysteryBox" and Color3.fromRGB(255, 215, 90) or Color3.fromRGB(255, 200, 120))
			new("Frame", {
				AnchorPoint = Vector2.new(0.5, 0.5),
				Position = toMap(p.Position.X, p.Position.Z),
				Size = UDim2.fromOffset(7, 7),
				BackgroundColor3 = color,
				BorderSizePixel = 0,
				ZIndex = 5,
				Parent = markerFolder,
			}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }), new("UIStroke", { Thickness = 1, Color = Color3.new(0, 0, 0), Transparency = 0.3 }) })
		end
	end
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------

local function build()
	gui = new("ScreenGui", { Name = "Minimap", ResetOnSpawn = false, IgnoreGuiInset = true, Parent = player:WaitForChild("PlayerGui") })
	-- Plain clipping frame (not a CanvasGroup: those didn't clip here). Clipping still
	-- works because only the content inside is rotated, never this frame.
	local frame = new("Frame", {
		Name = "Map",
		Position = UDim2.fromOffset(24, 24),
		Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundColor3 = Color3.fromRGB(14, 12, 22),
		BackgroundTransparency = 0.15,
		ClipsDescendants = true,
		Parent = gui,
	}, { new("UICorner", { CornerRadius = UDim.new(0, 14) }) })
	-- border drawn on top so it stays crisp
	new("Frame", {
		Position = UDim2.fromOffset(24, 24),
		Size = UDim2.fromOffset(SIZE, SIZE),
		BackgroundTransparency = 1,
		ZIndex = 12,
		Parent = gui,
	}, { new("UICorner", { CornerRadius = UDim.new(0, 14) }), new("UIStroke", { Color = Color3.fromRGB(80, 220, 255), Thickness = 2, Transparency = 0.3 }) })

	pivot = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, Parent = frame })
	world = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(10, 10), Parent = pivot })
	mapLayer = new("Frame", { Name = "Footprints", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 1, Parent = world })
	markerFolder = new("Frame", { Name = "Markers", BackgroundTransparency = 1, Size = UDim2.fromScale(1, 1), ZIndex = 4, Parent = world })

	-- sweep ring (expands from the center on every radar sweep)
	sweepRing = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		ZIndex = 9,
		Parent = frame,
	}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }), new("UIStroke", { Color = Color3.fromRGB(255, 80, 90), Thickness = 2, Transparency = 1 }) })

	-- you: arrow at the center (a rotated square + nose)
	local me = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 1, ZIndex = 10, Parent = frame })
	new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(9, 9), Rotation = 45, BackgroundColor3 = Color3.new(1, 1, 1), BorderSizePixel = 0, ZIndex = 10, Parent = me })
	new("Frame", { AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.fromOffset(0, -3), Size = UDim2.fromOffset(3, 8), BackgroundColor3 = Color3.fromRGB(80, 220, 255), BorderSizePixel = 0, ZIndex = 10, Parent = me })

	-- North marker that orbits the rim
	MinimapController.north = new("TextLabel", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(16, 16),
		BackgroundTransparency = 1,
		Text = "N",
		Font = Enum.Font.GothamBlack,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(255, 80, 170),
		TextStrokeTransparency = 0.4,
		ZIndex = 11,
		Parent = gui,
	})

	sweepLabel = new("TextLabel", {
		Position = UDim2.fromOffset(24, 24 + SIZE + 4),
		Size = UDim2.fromOffset(SIZE, 16),
		BackgroundTransparency = 1,
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(255, 120, 120),
		TextStrokeTransparency = 0.5,
		Parent = gui,
	})

	for i = 1, MAX_DOTS do
		dots[i] = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(6, 6),
			BackgroundColor3 = Color3.fromRGB(255, 50, 60),
			BorderSizePixel = 0,
			Visible = false,
			ZIndex = 7,
			Parent = world,
		}, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
	end
end

----------------------------------------------------------------------
-- Per frame
----------------------------------------------------------------------

local snapshot = {} -- zombie positions captured at the last sweep

local function takeSnapshot()
	table.clear(snapshot)
	for _, m in CollectionService:GetTagged("Enemy") do
		local r = m:IsA("Model") and m.PrimaryPart
		if r and r.Position.Y > -8 then
			table.insert(snapshot, { pos = r.Position, elite = m:GetAttribute("Elite") == true })
		end
	end
end

local function update()
	local cam = workspace.CurrentCamera
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not cam or not root then
		return
	end
	local pos = root.Position
	-- heading: camera look projected on XZ; map rotates so "forward" is up
	local look = cam.CFrame.LookVector
	local heading = math.atan2(look.X, -look.Z) -- 0 = facing -Z (north)
	pivot.Rotation = -math.deg(heading)
	world.Position = UDim2.fromOffset(-(pos.X - origin.X) * SCALE, -(pos.Z - origin.Y) * SCALE)

	-- north marker on the rim
	local r = SIZE / 2 - 2
	local cx, cy = 24 + SIZE / 2, 24 + SIZE / 2
	MinimapController.north.Position = UDim2.fromOffset(cx + math.sin(-heading) * r, cy - math.cos(-heading) * r)

	-- radar
	local now = workspace:GetServerTimeNow()
	local cfg = ProgressionConfig.Uav
	local uavLive = (player:GetAttribute("UavUntil") or 0) > now
	local clock = os.clock()
	if not uavLive and clock - lastSweep >= cfg.SweepEvery then
		lastSweep = clock
		takeSnapshot()
		sweepRing.Size = UDim2.fromOffset(0, 0)
		sweepRing.UIStroke.Transparency = 0.1
		game:GetService("TweenService"):Create(sweepRing, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { Size = UDim2.fromOffset(SIZE * 1.45, SIZE * 1.45) }):Play() -- reaches the corners
		game:GetService("TweenService"):Create(sweepRing.UIStroke, TweenInfo.new(0.7), { Transparency = 1 }):Play()
	end

	local list, fade
	if uavLive then
		list = {}
		for _, m in CollectionService:GetTagged("Enemy") do
			local rp = m:IsA("Model") and m.PrimaryPart
			if rp and rp.Position.Y > -8 then
				table.insert(list, { pos = rp.Position, elite = m:GetAttribute("Elite") == true })
			end
		end
		fade = 0
		sweepLabel.Text = string.format("UAV ONLINE  %ds", math.ceil((player:GetAttribute("UavUntil") or 0) - now))
		sweepLabel.TextColor3 = Color3.fromRGB(255, 220, 90)
	else
		list = snapshot
		fade = math.clamp((clock - lastSweep) / cfg.SweepShows, 0, 1)
		sweepLabel.Text = "" -- the sweep ring says enough; only a live UAV gets a label
	end
	for i, dot in dots do
		local e = list[i]
		dot.Visible = e ~= nil and fade < 1
		if e then
			dot.Position = toMap(e.pos.X, e.pos.Z)
			dot.BackgroundTransparency = fade
			local s = e.elite and 10 or 6
			dot.Size = UDim2.fromOffset(s, s)
			dot.BackgroundColor3 = e.elite and Color3.fromRGB(255, 150, 40) or Color3.fromRGB(255, 50, 60)
		end
	end

	-- teammates (always visible)
	local others = 0
	for _, p in Players:GetPlayers() do
		if p ~= player then
			local pr = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if pr then
				others += 1
				local d = mates[others]
				if not d then
					d = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(7, 7), BackgroundColor3 = Color3.fromRGB(80, 220, 255), BorderSizePixel = 0, ZIndex = 8, Parent = world }, { new("UICorner", { CornerRadius = UDim.new(1, 0) }) })
					mates[others] = d
				end
				d.Visible = true
				d.Position = toMap(pr.Position.X, pr.Position.Z)
			end
		end
	end
	for i = others + 1, #mates do
		mates[i].Visible = false
	end
end

function MinimapController.Init()
	build()
end

function MinimapController.Start()
	task.spawn(function()
		while not drawMap() do
			task.wait(1)
		end
		drawMarkers()
		-- with streaming, parts can still be arriving: redraw once they've settled
		for _, t in { 4, 6 } do
			task.wait(t)
			drawMap()
			drawMarkers()
		end
	end)
	local pending = false
	local function redrawSoon()
		if pending then
			return
		end
		pending = true
		task.delay(0.5, function()
			pending = false
			drawMarkers()
		end)
	end
	CollectionService:GetInstanceAddedSignal("Interactable"):Connect(redrawSoon)
	CollectionService:GetInstanceRemovedSignal("Interactable"):Connect(redrawSoon)
	-- the map is rebuilt on match reset: redraw the footprints too
	workspace.ChildAdded:Connect(function(c)
		if c.Name == "Map" then
			task.delay(2, function()
				drawMap()
				drawMarkers()
			end)
		end
	end)
	RunService.RenderStepped:Connect(update)
end

return MinimapController
