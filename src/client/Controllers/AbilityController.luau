--!nonstrict
-- Hero abilities on the client: Q = ability, F = ultimate, H = switch hero (between
-- waves). Shows the ability/ultimate HUD, performs the Swordsman's dash locally
-- (the client owns its character's movement), and draws every AbilityFx broadcast.
-- PLACEHOLDER VFX: neon parts and tweens until the art pass (M10).

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local HeroConfig = require(game.ReplicatedStorage.Shared.Config.HeroConfig)
local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)
local SoundController = require(script.Parent.SoundController)
local CameraController = require(script.Parent.CameraController)
local EffectsController = require(script.Parent.EffectsController)
local ImpactController = require(script.Parent.ImpactController)

local AbilityController = {}

local player = Players.LocalPlayer
local PANEL = Color3.fromRGB(14, 12, 22)
local gui: ScreenGui
local ui = {}
local useRemote: RemoteEvent
local selectRemote: RemoteEvent
local dashing = false

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

local function label(props)
	local d = { BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack, TextStrokeTransparency = 0.6 }
	for k, v in props do
		d[k] = v
	end
	return new("TextLabel", d)
end

local function hero()
	return HeroConfig.Get(player:GetAttribute("Hero"))
end

----------------------------------------------------------------------
-- HUD: two slots left of the ammo panel
----------------------------------------------------------------------

local function slot(x, key, size)
	local f = new("Frame", {
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, x, 1, -28),
		Size = UDim2.fromOffset(size, size),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.3,
		ClipsDescendants = true,
		Parent = gui,
	}, { new("UICorner", { CornerRadius = UDim.new(0, 10) }) })
	local stroke = new("UIStroke", { Thickness = 2, Transparency = 0.2, Parent = f })
	-- fill rises from the bottom as it recharges
	local fill = new("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BorderSizePixel = 0, BackgroundTransparency = 0.55, Parent = f })
	local name = label({ Text = "", Font = Enum.Font.GothamBold, TextSize = 11, TextWrapped = true, Position = UDim2.fromOffset(4, 6), Size = UDim2.new(1, -8, 0, 28), ZIndex = 2, Parent = f })
	local big = label({ Text = "", TextSize = 22, Position = UDim2.new(0, 0, 0.5, -6), Size = UDim2.new(1, 0, 0, 24), ZIndex = 2, Parent = f })
	local keyLabel = label({ Text = key, TextSize = 13, TextColor3 = PANEL, BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), TextStrokeTransparency = 1, AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.fromOffset(20, 18), ZIndex = 2, Parent = f })
	new("UICorner", { CornerRadius = UDim.new(0, 4), Parent = keyLabel })
	return { frame = f, stroke = stroke, fill = fill, name = name, big = big }
end

local function buildHud()
	ui.ability = slot(-272, "Q", 76)
	ui.ult = slot(-358, "F", 76)
	ui.heroName = label({
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -272, 1, -110),
		Size = UDim2.fromOffset(240, 16),
		Parent = gui,
	})
	ui.heroHint = label({
		Text = "",
		Font = Enum.Font.GothamMedium,
		TextSize = 12,
		TextColor3 = Color3.fromRGB(180, 180, 200),
		TextXAlignment = Enum.TextXAlignment.Right,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -272, 1, -126),
		Size = UDim2.fromOffset(240, 14),
		Parent = gui,
	})
end

local wasUltReady = false
local function updateHud()
	local h = hero()
	local now = workspace:GetServerTimeNow()
	-- ability
	local left = math.max(0, (player:GetAttribute("AbilityReadyAt") or 0) - now)
	local a = ui.ability
	a.name.Text = string.upper(h.Ability.Name)
	a.stroke.Color = h.Color
	a.fill.BackgroundColor3 = h.Color
	a.fill.Size = UDim2.fromScale(1, left > 0 and (1 - left / h.Ability.Cooldown) or 1)
	a.big.Text = left > 0 and tostring(math.ceil(left)) or ""
	a.frame.BackgroundTransparency = left > 0 and 0.45 or 0.2
	-- ultimate
	local charge = player:GetAttribute("UltCharge") or 0
	local ready = charge >= HeroConfig.Ult.Max
	local u = ui.ult
	u.name.Text = string.upper(h.Ultimate.Name)
	u.stroke.Color = ready and Color3.fromRGB(255, 220, 90) or h.Color
	u.fill.BackgroundColor3 = ready and Color3.fromRGB(255, 220, 90) or h.Color
	u.fill.Size = UDim2.fromScale(1, charge / HeroConfig.Ult.Max)
	u.big.Text = ready and "READY" or (math.floor(charge) .. "%")
	u.big.TextSize = ready and 15 or 20
	if ready and not wasUltReady then
		SoundController.Play("PowerUp", 0.6, 1.3)
	end
	wasUltReady = ready
	-- pulse the ready ultimate
	u.stroke.Thickness = ready and (2 + math.abs(math.sin(os.clock() * 5)) * 2) or 2

	ui.heroName.Text = string.upper(h.Name .. "  ·  " .. h.Title)
	ui.heroName.TextColor3 = h.Color
	local state = Remotes.GameState():GetAttribute("State")
	ui.heroHint.Text = state ~= "Wave" and "[H] switch hero" or ""
end

----------------------------------------------------------------------
-- Effects (all PLACEHOLDER)
----------------------------------------------------------------------

local function fxPart(props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in props do
		p[k] = v
	end
	p.Parent = EffectsController.GetFolder()
	return p
end

local function fadeAndDie(p, t, goal)
	goal = goal or {}
	goal.Transparency = 1
	TweenService:Create(p, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), goal):Play()
	task.delay(t + 0.05, function()
		p:Destroy()
	end)
end

local function ring(pos: Vector3, radius: number, color: Color3, time: number, height: number?)
	local disc = fxPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(height or 0.3, 2, 2),
		CFrame = CFrame.new(pos + Vector3.new(0, 0.3, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = color,
		Transparency = 0.35,
	})
	fadeAndDie(disc, time, { Size = Vector3.new(height or 0.3, radius * 2, radius * 2) })
	return disc
end

local FX = {}

function FX.GaleStep(d)
	local from, to = d.from, d.to
	local len = (to - from).Magnitude
	if len < 0.5 then
		return
	end
	local mid = (from + to) / 2
	local streak = fxPart({ Size = Vector3.new(0.5, 0.5, len), CFrame = CFrame.lookAt(mid, to), Color = Color3.fromRGB(150, 220, 255), Transparency = 0.15 })
	fadeAndDie(streak, 0.45, { Size = Vector3.new(0.05, 3, len) })
	for i = 1, 3 do
		local slash = fxPart({ Size = Vector3.new(7, 0.15, 0.6), CFrame = CFrame.lookAt(from:Lerp(to, i / 4), to) * CFrame.Angles(0, 0, math.rad(-35 + i * 25)), Color = Color3.new(1, 1, 1), Transparency = 0.1 })
		fadeAndDie(slash, 0.35)
	end
	SoundController.PlayAt("KnifeSwing", mid, 80, 0.8)
	if d.by == player and (d.kills or 0) > 0 then
		ImpactController.Play(d.kills >= 3 and "heavy" or "medium")
	end
end

function FX.FrostNova(d)
	ring(d.pos, d.radius, Color3.fromRGB(160, 220, 255), 0.5, 0.6)
	local dome = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2, Position = d.pos, Color = Color3.fromRGB(200, 240, 255), Material = Enum.Material.Glass, Transparency = 0.4 })
	fadeAndDie(dome, 0.6, { Size = Vector3.one * d.radius * 2 })
	for i = 1, 10 do
		local a = i / 10 * math.pi * 2
		local p = d.pos + Vector3.new(math.cos(a), 0, math.sin(a)) * d.radius * 0.7
		local shard = fxPart({ Size = Vector3.new(0.8, 3.5, 0.8), CFrame = CFrame.new(p + Vector3.new(0, 1.2, 0)) * CFrame.Angles(math.rad(15), a, 0), Color = Color3.fromRGB(190, 235, 255), Material = Enum.Material.Ice, Transparency = 0.1 })
		task.delay(0.8, function()
			fadeAndDie(shard, 0.6)
		end)
	end
	SoundController.PlayAt("ShotgunShot", d.pos, 90, 0.55)
end

function FX.Tempest(d)
	ring(d.pos, d.radius, Color3.fromRGB(120, 210, 255), 0.35)
	for i = 1, 3 do
		local a = i / 3 * math.pi * 2 + d.pulse
		local blade = fxPart({ Size = Vector3.new(d.radius, 0.2, 1.2), CFrame = CFrame.new(d.pos + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, a, 0) * CFrame.new(d.radius / 2, 0, 0), Color = Color3.new(1, 1, 1), Transparency = 0.15 })
		local spin = CFrame.new(d.pos + Vector3.new(0, 2.5, 0)) * CFrame.Angles(0, a + math.rad(110), 0) * CFrame.new(d.radius / 2, 0, 0)
		fadeAndDie(blade, 0.35, { CFrame = spin })
	end
	SoundController.PlayAt("KnifeSwing", d.pos, 90, 0.65 + d.pulse * 0.08)
	if d.by == player then
		ImpactController.Play(d.pulse == 1 and "heavy" or "light")
	end
end

function FX.StarfallMark(d)
	local mark = ring(d.pos, d.radius, Color3.fromRGB(200, 120, 255), d.delay, 0.2)
	mark.Size = Vector3.new(0.2, d.radius * 2, d.radius * 2)
	local star = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 5, Position = d.pos + Vector3.new(30, 140, 10), Color = Color3.fromRGB(230, 190, 255) })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(200, 140, 255)
	light.Range = 40
	light.Brightness = 3
	light.Parent = star
	TweenService:Create(star, TweenInfo.new(d.delay, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = d.pos }):Play()
	task.delay(d.delay, function()
		star:Destroy()
	end)
end

function FX.Starfall(d)
	local boom = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 4, Position = d.pos, Color = Color3.fromRGB(220, 170, 255), Transparency = 0.1 })
	fadeAndDie(boom, 0.7, { Size = Vector3.one * d.radius * 2.2 })
	ring(d.pos, d.radius * 1.3, Color3.fromRGB(255, 220, 255), 0.8)
	SoundController.PlayAt("Nuke", d.pos, 220, 1.2)
	local cam = workspace.CurrentCamera
	if d.by == player then
		ImpactController.Play("heavy")
	elseif cam and (cam.CFrame.Position - d.pos).Magnitude < 120 then
		CameraController.Shake(1.2)
	end
end

-- Yuki (reworked): Glacial Lance + Absolute Zero
function FX.GlacialLance(d)
	local from, to = d.from, d.to
	local len = (to - from).Magnitude
	if len < 1 then
		return
	end
	local mid = (from + to) / 2
	local spear = fxPart({ Size = Vector3.new(0.9, 0.9, len), CFrame = CFrame.lookAt(mid, to), Color = Color3.fromRGB(180, 230, 255), Material = Enum.Material.Ice, Transparency = 0.15 })
	fadeAndDie(spear, 0.55, { Size = Vector3.new(0.1, 0.1, len) })
	local core = fxPart({ Size = Vector3.new(0.25, 0.25, len), CFrame = CFrame.lookAt(mid, to), Color = Color3.fromRGB(240, 250, 255), Transparency = 0 })
	fadeAndDie(core, 0.3)
	for i = 1, 4 do
		local p = from:Lerp(to, i / 5)
		local ringPart = fxPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.15, 1.5, 1.5), CFrame = CFrame.lookAt(p, to) * CFrame.Angles(0, math.rad(90), 0), Color = Color3.fromRGB(200, 240, 255), Transparency = 0.3 })
		fadeAndDie(ringPart, 0.4, { Size = Vector3.new(0.15, 4, 4) })
	end
	for i = 1, 6 do
		local shard = fxPart({ Size = Vector3.new(0.4, 0.4, 1.6), CFrame = CFrame.new(to) * CFrame.Angles(math.random() * 6, math.random() * 6, 0), Color = Color3.fromRGB(190, 235, 255), Material = Enum.Material.Ice, Transparency = 0.1 })
		fadeAndDie(shard, 0.5, { CFrame = shard.CFrame * CFrame.new(0, 0, -3) })
	end
	SoundController.PlayAt("LaserShot", from, 120, 0.7)
	if d.by == player then
		CameraController.Kick(1.2, 0)
	end
end

local zeroUntil = 0
function FX.AbsoluteZeroStart(d)
	if d.by == player then
		zeroUntil = os.clock() + d.duration
		ImpactController.Play("medium")
		-- a cold tint over the caster's view while the blizzard lasts
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Name = "AbsoluteZeroTint"
		cc.TintColor = Color3.fromRGB(200, 230, 255)
		cc.Saturation = -0.3
		cc.Parent = game:GetService("Lighting")
		task.delay(d.duration, function()
			cc:Destroy()
		end)
	end
	SoundController.Play("Nuke", 0.4, 1.6)
end

function FX.AbsoluteZeroPulse(d)
	local dome = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * d.radius * 1.6, Position = d.pos, Color = Color3.fromRGB(200, 235, 255), Material = Enum.Material.Glass, Transparency = 0.75 })
	fadeAndDie(dome, 0.9, { Size = Vector3.one * d.radius * 2.1 })
	ring(d.pos, d.radius, Color3.fromRGB(180, 230, 255), 0.6, 0.3)
	for i = 1, 8 do
		local a = math.random() * math.pi * 2
		local r = math.random() * d.radius
		local flake = fxPart({ Size = Vector3.new(0.5, 0.5, 0.5), Position = d.pos + Vector3.new(math.cos(a) * r, 8, math.sin(a) * r), Color = Color3.fromRGB(240, 250, 255), Transparency = 0.1 })
		fadeAndDie(flake, 0.9, { Position = flake.Position - Vector3.new(0, 7, 0) })
	end
	SoundController.PlayAt("ShotgunShot", d.pos, 80, 0.4)
end

----------------------------------------------------------------------
-- The Titan raid (BossService)
----------------------------------------------------------------------

local raidUi = {}

local function callout(text: string, sub: string?, color: Color3?)
	local t = raidUi.callout
	t.Text = text
	t.TextColor3 = color or Color3.fromRGB(255, 150, 60)
	raidUi.calloutSub.Text = sub or ""
	for _, l in { t, raidUi.calloutSub } do
		l.TextTransparency = 0
		l.TextStrokeTransparency = 0.4
		TweenService:Create(l, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 2.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end
end

function FX.BossIntro(_d)
	local f = raidUi.fade
	f.BackgroundTransparency = 1
	TweenService:Create(f, TweenInfo.new(0.6), { BackgroundTransparency = 0 }):Play()
	CameraController.Shake(2)
	SoundController.Play("Nuke", 0.6, 0.6)
	task.delay(2.4, function()
		callout("THE HOLLOW", "The Dust Titan awaits. Work together.", Color3.fromRGB(255, 120, 40))
		TweenService:Create(f, TweenInfo.new(1.0), { BackgroundTransparency = 1 }):Play()
	end)
end

function FX.BossCallout(d)
	callout(d.text, d.sub)
	SoundController.Play("WaveStart", 0.7, 0.8)
end

function FX.BossRing(d)
	local map = workspace:FindFirstChild("Map")
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Include
	params.FilterDescendantsInstances = map and { map } or {}
	local balls = {}
	for _, dir in d.dirs do
		local b = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2.4, Position = d.origin, Color = Color3.fromRGB(255, 120, 30), Transparency = 0 })
		table.insert(balls, { part = b, pos = d.origin, vel = dir * d.speed, alive = true })
	end
	local t0 = os.clock()
	local conn
	conn = RunService.Heartbeat:Connect(function(dt)
		if os.clock() - t0 > d.life then
			conn:Disconnect()
			for _, b in balls do
				b.part:Destroy()
			end
			return
		end
		for _, b in balls do
			if b.alive then
				local nextPos = b.pos + b.vel * dt
				if workspace:Raycast(b.pos, nextPos - b.pos, params) then
					b.alive = false
					fadeAndDie(b.part, 0.15, { Size = Vector3.one * 5 })
				else
					b.pos = nextPos
					b.part.Position = nextPos
				end
			end
		end
	end)
	SoundController.PlayAt("ShotgunShot", d.origin, 160, 0.5)
end

function FX.BossMark(d)
	local target = d.target
	local r = target and target.Character and target.Character:FindFirstChild("HumanoidRootPart")
	if not r then
		return
	end
	local brand = d.mark == "Brand"
	local color = brand and Color3.fromRGB(255, 130, 40) or Color3.fromRGB(190, 90, 255)
	local disc = fxPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.25, d.radius * 2, d.radius * 2), Color = color, Transparency = 0.55 })
	local inner = fxPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.3, 0.5, 0.5), Color = color, Transparency = 0.2 })
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(200, 40)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = r
	gui.Parent = disc
	local lbl = label({ Text = brand and "STACK HERE" or "SPREAD OUT", TextSize = 20, TextColor3 = color, Size = UDim2.fromScale(1, 1), Parent = gui })
	if target == player then
		lbl.Text = brand and "YOU'RE BRANDED: STACK WITH ALLIES" or "MARKED: GET AWAY FROM ALLIES"
		SoundController.Play("Denied", 0.8, 0.7)
	end
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local a = (os.clock() - t0) / d.delay
		if a >= 1 or not r.Parent then
			conn:Disconnect()
			disc:Destroy()
			inner:Destroy()
			return
		end
		local floor = r.Position - Vector3.new(0, 2.9, 0)
		local cf = CFrame.new(floor) * CFrame.Angles(0, 0, math.rad(90))
		disc.CFrame = cf
		local s = d.radius * 2 * a
		inner.Size = Vector3.new(0.3, s, s)
		inner.CFrame = cf
	end)
end

function FX.BossBoom(d)
	local boom = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 3, Position = d.pos, Color = d.color or Color3.fromRGB(255, 120, 40), Transparency = 0.1 })
	fadeAndDie(boom, 0.5, { Size = Vector3.one * d.radius * 2 })
	ring(d.pos - Vector3.new(0, 2.5, 0), d.radius, d.color or Color3.fromRGB(255, 120, 40), 0.5, 0.3)
	SoundController.PlayAt("Nuke", d.pos, 180, 1.1)
	local cam = workspace.CurrentCamera
	if cam and (cam.CFrame.Position - d.pos).Magnitude < d.radius + 4 then
		ImpactController.Play("medium")
	end
end

local function buildRaidUi()
	raidUi.fade = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 1, BorderSizePixel = 0, ZIndex = 50, Parent = gui })
	raidUi.callout = label({ Text = "", TextSize = 52, TextTransparency = 1, TextStrokeTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.24), Size = UDim2.fromOffset(900, 60), ZIndex = 51, Parent = gui })
	raidUi.calloutSub = label({ Text = "", Font = Enum.Font.GothamBold, TextSize = 20, TextTransparency = 1, TextStrokeTransparency = 1, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(0.5, 0, 0.24, 40), Size = UDim2.fromOffset(900, 26), ZIndex = 51, Parent = gui })
	-- core-break bar (Cataclysm channel)
	raidUi.core = new("Frame", { AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 132), Size = UDim2.fromOffset(360, 30), BackgroundTransparency = 1, Visible = false, Parent = gui })
	label({ Text = "BREAK THE CORE", TextSize = 16, TextColor3 = Color3.fromRGB(255, 220, 120), Size = UDim2.new(1, 0, 0, 16), Parent = raidUi.core })
	local bg = new("Frame", { Position = UDim2.fromOffset(0, 18), Size = UDim2.new(1, 0, 0, 10), BackgroundColor3 = Color3.fromRGB(40, 24, 20), BorderSizePixel = 0, Parent = raidUi.core }, { new("UICorner", { CornerRadius = UDim.new(0, 4) }) })
	raidUi.coreFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(255, 220, 120), BorderSizePixel = 0, Parent = bg }, { new("UICorner", { CornerRadius = UDim.new(0, 4) }) })
end

local lavaRing
local function updateRaid()
	local gs = Remotes.GameState()
	local now = workspace:GetServerTimeNow()
	-- core bar
	local coreUntil = gs:GetAttribute("CoreUntil") or 0
	raidUi.core.Visible = coreUntil > now
	if raidUi.core.Visible then
		local th = math.max(1, gs:GetAttribute("CoreThreshold") or 1)
		raidUi.coreFill.Size = UDim2.fromScale(math.clamp((gs:GetAttribute("CoreDamage") or 0) / th, 0, 1), 1)
	end
	-- lava edge ring (phase 3)
	local radius = gs:GetAttribute("LavaRadius") or 0
	local center = gs:GetAttribute("HollowCenter")
	local phase = gs:GetAttribute("BossPhase") or 0
	if phase >= 3 and radius > 0 and typeof(center) == "Vector3" then
		if not lavaRing then
			lavaRing = fxPart({ Shape = Enum.PartType.Cylinder, Size = Vector3.new(0.4, 2, 2), Color = Color3.fromRGB(255, 60, 20), Transparency = 0.35 })
		end
		lavaRing.Size = Vector3.new(0.4, radius * 2, radius * 2)
		lavaRing.CFrame = CFrame.new(center + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.rad(90))
		lavaRing.Material = Enum.Material.ForceField
	elseif lavaRing then
		lavaRing:Destroy()
		lavaRing = nil
	end
end

-- Kaida (tank)
function FX.WarCry(d)
	ring(d.pos, d.radius, Color3.fromRGB(255, 170, 70), 0.7, 0.4)
	ring(d.pos, d.radius * 0.5, Color3.fromRGB(255, 220, 140), 0.5, 0.6)
	SoundController.PlayAt("ZombieAttack", d.pos, 140, 0.55)
	-- a pulsing aura around her while it lasts (other players see it too)
	local char = d.by and d.by.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	if r then
		local aura = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 7, Position = r.Position, Color = Color3.fromRGB(255, 150, 50), Transparency = 0.8 })
		local t0 = os.clock()
		local conn
		conn = RunService.RenderStepped:Connect(function()
			local t = os.clock() - t0
			if t > d.duration or not r.Parent then
				conn:Disconnect()
				aura:Destroy()
				return
			end
			aura.Position = r.Position
			aura.Size = Vector3.one * (7 + math.sin(t * 8) * 0.8)
		end)
	end
	if d.by == player then
		ImpactController.Play("medium")
	end
end

function FX.Fortress(d)
	local dome = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2, Position = d.pos, Color = Color3.fromRGB(255, 200, 90), Material = Enum.Material.ForceField, Transparency = 0.2 })
	TweenService:Create(dome, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = Vector3.one * d.radius * 2 }):Play()
	ring(d.pos, d.radius, Color3.fromRGB(255, 210, 110), 0.6, 0.4)
	SoundController.PlayAt("PowerUp", d.pos, 160, 0.8)
	task.delay(d.duration - 0.4, function()
		fadeAndDie(dome, 0.4)
	end)
	if d.by == player then
		ImpactController.Play("medium")
	end
end

-- Mio (support)
function FX.SpiritPulse(d)
	ring(d.pos, d.radius, Color3.fromRGB(140, 255, 190), 0.6, 0.3)
	local orb = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 2, Position = d.pos + Vector3.new(0, 2, 0), Color = Color3.fromRGB(180, 255, 210), Transparency = 0.3 })
	fadeAndDie(orb, 0.5, { Size = Vector3.one * 10 })
	SoundController.PlayAt("PerkDrink", d.pos, 120, 1.3)
end

function FX.GuardianStart(d)
	local char = d.by and d.by.Character
	local r = char and char:FindFirstChild("HumanoidRootPart")
	if not r then
		return
	end
	-- a glowing spirit fox orb with two ears, floating at her shoulder
	local orb = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.6, Color = Color3.fromRGB(150, 255, 200), Transparency = 0.1 })
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(140, 255, 190)
	light.Range = 14
	light.Brightness = 2
	light.Parent = orb
	local ears = {
		fxPart({ Size = Vector3.new(0.35, 0.7, 0.2), Color = Color3.fromRGB(220, 255, 235) }),
		fxPart({ Size = Vector3.new(0.35, 0.7, 0.2), Color = Color3.fromRGB(220, 255, 235) }),
	}
	local t0 = os.clock()
	local conn
	conn = RunService.RenderStepped:Connect(function()
		local t = os.clock() - t0
		if t > d.duration or not r.Parent then
			conn:Disconnect()
			fadeAndDie(orb, 0.3)
			for _, e in ears do
				e:Destroy()
			end
			return
		end
		local cf = CFrame.new(r.Position + Vector3.new(0, 5 + math.sin(t * 3) * 0.4, 0) + r.CFrame.RightVector * 2.5) * r.CFrame.Rotation
		orb.CFrame = cf
		ears[1].CFrame = cf * CFrame.new(-0.45, 0.85, 0) * CFrame.Angles(0, 0, math.rad(15))
		ears[2].CFrame = cf * CFrame.new(0.45, 0.85, 0) * CFrame.Angles(0, 0, math.rad(-15))
	end)
	SoundController.PlayAt("PowerUp", r.Position, 120, 1.5)
end

function FX.SpiritBolt(d)
	local len = (d.to - d.from).Magnitude
	local bolt = fxPart({ Size = Vector3.new(0.25, 0.25, len), CFrame = CFrame.lookAt((d.from + d.to) / 2, d.to), Color = Color3.fromRGB(150, 255, 200), Transparency = 0 })
	fadeAndDie(bolt, 0.15)
	SoundController.PlayAt("LaserShot", d.from, 70, 1.8)
end

-- Forge signature effects
function FX.Explosion(d)
	local color = d.color or Color3.fromRGB(255, 140, 40)
	local ball = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1.5, Position = d.pos, Color = color, Transparency = 0.05 })
	fadeAndDie(ball, 0.32, { Size = Vector3.one * d.radius * 1.6 })
	local core = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 1, Position = d.pos, Color = Color3.fromRGB(255, 245, 220), Transparency = 0 })
	fadeAndDie(core, 0.15, { Size = Vector3.one * d.radius * 0.8 })
	ring(d.pos - Vector3.new(0, 0.2, 0), d.radius, color, 0.35, 0.2)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = d.radius * 3
	light.Brightness = 4
	light.Parent = ball
	SoundController.PlayAt("ShotgunShot", d.pos, 120, 0.55 + math.random() * 0.1)
	local cam = workspace.CurrentCamera
	if cam and (cam.CFrame.Position - d.pos).Magnitude < d.radius * 3 then
		CameraController.Shake(0.35)
	end
end

local function bolt(a: Vector3, b: Vector3)
	-- jagged 3-segment lightning bolt
	local pts = { a }
	for i = 1, 2 do
		local p = a:Lerp(b, i / 3) + Vector3.new(math.random() - 0.5, math.random() - 0.5, math.random() - 0.5) * 2.2
		table.insert(pts, p)
	end
	table.insert(pts, b)
	for i = 1, #pts - 1 do
		local p0, p1 = pts[i], pts[i + 1]
		local seg = fxPart({ Size = Vector3.new(0.18, 0.18, (p1 - p0).Magnitude), CFrame = CFrame.lookAt((p0 + p1) / 2, p1), Color = Color3.fromRGB(255, 245, 140), Transparency = 0 })
		fadeAndDie(seg, 0.18)
	end
end

function FX.Chain(d)
	local from = d.from + Vector3.new(0, 1.5, 0)
	for _, to in d.to do
		bolt(from, to + Vector3.new(0, 1.5, 0))
	end
	SoundController.PlayAt("LaserShot", from, 90, 1.6)
end

-- Dust Titan
function FX.BossSlamWarn(d)
	-- red ring that tightens until the slam lands
	local ring = fxPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.2, d.radius * 2.6, d.radius * 2.6),
		CFrame = CFrame.new(d.pos + Vector3.new(0, 0.25, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 40, 40),
		Transparency = 0.6,
	})
	TweenService:Create(ring, TweenInfo.new(d.delay, Enum.EasingStyle.Linear), { Size = Vector3.new(0.2, d.radius * 2, d.radius * 2), Transparency = 0.25 }):Play()
	task.delay(d.delay, function()
		ring:Destroy()
	end)
	SoundController.PlayAt("ZombieAttack", d.pos, 160, 0.45)
end

function FX.BossSlam(d)
	ring(d.pos, d.radius * 1.2, Color3.fromRGB(200, 160, 110), 0.6, 1.2)
	local dust = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 6, Position = d.pos, Color = Color3.fromRGB(170, 140, 100), Material = Enum.Material.SmoothPlastic, Transparency = 0.3 })
	fadeAndDie(dust, 0.7, { Size = Vector3.new(d.radius * 2.4, 6, d.radius * 2.4) })
	SoundController.PlayAt("Nuke", d.pos, 200, 0.6)
	local cam = workspace.CurrentCamera
	if cam then
		local dist = (cam.CFrame.Position - d.pos).Magnitude
		if dist < d.radius + 6 then
			ImpactController.Play("heavy")
		elseif dist < 80 then
			CameraController.Shake(1.5)
		end
	end
end

function FX.BossDown(d)
	local boom = fxPart({ Shape = Enum.PartType.Ball, Size = Vector3.one * 6, Position = d.pos, Color = Color3.fromRGB(255, 160, 60), Transparency = 0.1 })
	fadeAndDie(boom, 1.2, { Size = Vector3.one * 60 })
	SoundController.PlayAt("Nuke", d.pos, 400, 0.8)
	ImpactController.Play("heavy")
end

----------------------------------------------------------------------
-- Casting
----------------------------------------------------------------------

local MAP_PARAMS = RaycastParams.new()
MAP_PARAMS.FilterType = Enum.RaycastFilterType.Include

-- Swordsman dash: the client moves its own character (server checks the same line).
local function dash(range: number)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local cam = workspace.CurrentCamera
	if not root or not cam or dashing then
		return
	end
	local look = cam.CFrame.LookVector
	local dir = Vector3.new(look.X, 0, look.Z)
	if dir.Magnitude < 0.1 then
		return
	end
	dir = dir.Unit
	local map = workspace:FindFirstChild("Map")
	MAP_PARAMS.FilterDescendantsInstances = map and { map } or {}
	local block = workspace:Raycast(root.Position, dir * range, MAP_PARAMS)
	local length = block and math.max(0, (block.Position - root.Position).Magnitude - 2) or range
	local start = root.CFrame
	local target = start + dir * length
	dashing = true
	CameraController.Punch(3)
	local t0 = os.clock()
	local DUR = 0.16
	local conn
	conn = RunService.Heartbeat:Connect(function()
		local a = math.clamp((os.clock() - t0) / DUR, 0, 1)
		if not root.Parent then
			conn:Disconnect()
			dashing = false
			return
		end
		root.CFrame = start:Lerp(target, a)
		root.AssemblyLinearVelocity = dir * 30
		if a >= 1 then
			conn:Disconnect()
			root.AssemblyLinearVelocity = Vector3.zero
			dashing = false
		end
	end)
end

local function use(slotName: string)
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local cam = workspace.CurrentCamera
	if not hum or hum.Health <= 0 or not cam or player:GetAttribute("Downed") then
		return -- no abilities while downed (the dash used to run client-side anyway)
	end
	local h = hero()
	local aim = cam.CFrame.LookVector
	if slotName == "Ability" then
		if workspace:GetServerTimeNow() < (player:GetAttribute("AbilityReadyAt") or 0) then
			SoundController.Play("Denied", 0.5)
			return
		end
		useRemote:FireServer("Ability", aim)
		if h.Id == "Swordsman" then
			dash(h.Ability.Range)
		end
	else
		if (player:GetAttribute("UltCharge") or 0) < HeroConfig.Ult.Max or player:GetAttribute("UltActive") then
			SoundController.Play("Denied", 0.5)
			return
		end
		useRemote:FireServer("Ultimate", aim)
	end
end

local function cycleHero()
	local order = HeroConfig.Order
	local i = table.find(order, hero().Id) or 0
	selectRemote:FireServer(order[i % #order + 1])
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

----------------------------------------------------------------------
-- Downed & revive (co-op): your own "you're down" screen, and a marker over
-- downed teammates telling you to hold E. State comes from player attributes
-- set by PlayerService (Downed, DownedUntil, ReviveProgress).
----------------------------------------------------------------------

local function buildDownedUi()
	ui.downed = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Visible = false, ZIndex = 30, Parent = gui })
	-- red vignette edges
	for _, e in { { UDim2.fromScale(0, 0), UDim2.new(1, 0, 0.18, 0) }, { UDim2.fromScale(0, 0.82), UDim2.new(1, 0, 0.18, 0) }, { UDim2.fromScale(0, 0), UDim2.new(0.12, 0, 1, 0) }, { UDim2.fromScale(0.88, 0), UDim2.new(0.12, 0, 1, 0) } } do
		new("Frame", { Position = e[1], Size = e[2], BackgroundColor3 = Color3.fromRGB(150, 0, 20), BackgroundTransparency = 0.55, BorderSizePixel = 0, ZIndex = 30, Parent = ui.downed })
	end
	ui.downedTitle = label({ Text = "YOU'RE DOWN", TextSize = 46, TextColor3 = Color3.fromRGB(255, 80, 100), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.38), Size = UDim2.fromOffset(700, 52), ZIndex = 31, Parent = ui.downed })
	ui.downedSub = label({ Text = "", Font = Enum.Font.GothamBold, TextSize = 20, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.45), Size = UDim2.fromOffset(700, 26), ZIndex = 31, Parent = ui.downed })
	local bg = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(320, 12), BackgroundColor3 = Color3.fromRGB(40, 20, 26), BorderSizePixel = 0, ZIndex = 31, Parent = ui.downed }, { new("UICorner", { CornerRadius = UDim.new(0, 4) }) })
	ui.reviveFill = new("Frame", { Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(120, 255, 170), BorderSizePixel = 0, ZIndex = 32, Parent = bg }, { new("UICorner", { CornerRadius = UDim.new(0, 4) }) })
end

local markers = {} -- [Player] = BillboardGui over a downed teammate

local function markerFor(p: Player)
	local head = p.Character and p.Character:FindFirstChild("Head")
	if not head then
		return nil
	end
	local m = markers[p]
	if m and m.Parent and m.Adornee == head then
		return m
	end
	if m then
		m:Destroy()
	end
	m = new("BillboardGui", { Name = "DownedMarker", Adornee = head, AlwaysOnTop = true, Size = UDim2.fromOffset(170, 52), StudsOffset = Vector3.new(0, 3, 0), Parent = gui })
	label({ Name = "Title", Text = "DOWNED · HOLD E", TextSize = 16, TextColor3 = Color3.fromRGB(255, 90, 110), Size = UDim2.new(1, 0, 0, 20), Parent = m })
	local bg = new("Frame", { Position = UDim2.fromOffset(15, 26), Size = UDim2.new(1, -30, 0, 8), BackgroundColor3 = Color3.fromRGB(40, 20, 26), BorderSizePixel = 0, Parent = m }, { new("UICorner", { CornerRadius = UDim.new(0, 3) }) })
	new("Frame", { Name = "Fill", Size = UDim2.fromScale(0, 1), BackgroundColor3 = Color3.fromRGB(120, 255, 170), BorderSizePixel = 0, Parent = bg }, { new("UICorner", { CornerRadius = UDim.new(0, 3) }) })
	markers[p] = m
	return m
end

local function updateDowned()
	local now = workspace:GetServerTimeNow()
	-- me
	local downed = player:GetAttribute("Downed") == true
	ui.downed.Visible = downed
	if downed then
		local left = math.max(0, math.ceil((player:GetAttribute("DownedUntil") or 0) - now))
		local prog = player:GetAttribute("ReviveProgress") or 0
		ui.downedSub.Text = prog > 0 and "Being revived..." or ("A teammate can revive you · bleeding out in " .. left .. "s")
		ui.reviveFill.Size = UDim2.fromScale(math.clamp(prog, 0, 1), 1)
	end
	-- teammates
	for _, p in Players:GetPlayers() do
		if p ~= player and p:GetAttribute("Downed") then
			local m = markerFor(p)
			if m then
				local fill = m:FindFirstChild("Fill", true)
				if fill then
					fill.Size = UDim2.fromScale(math.clamp(p:GetAttribute("ReviveProgress") or 0, 0, 1), 1)
				end
			end
		elseif markers[p] then
			markers[p]:Destroy()
			markers[p] = nil
		end
	end
end

function AbilityController.Init()
	gui = new("ScreenGui", { Name = "Abilities", ResetOnSpawn = false, IgnoreGuiInset = true, Parent = player:WaitForChild("PlayerGui") })
	buildHud()
	buildDownedUi()
	buildRaidUi()
end

function AbilityController.Start()
	useRemote = Remotes.Get("UseAbility")
	selectRemote = Remotes.Get("SelectHero")

	-- Window repair: hold E anywhere near a damaged window. The server repairs the
	-- nearest one by position, so you can turn around and shoot while holding.
	local repairRemote = Remotes.Get("RepairHold")
	local repairHeld = false
	UserInputService.InputBegan:Connect(function(input, processed)
		if input.KeyCode == Enum.KeyCode.E and not repairHeld and not UserInputService:GetFocusedTextBox() then
			repairHeld = true
			repairRemote:FireServer(true)
		end
	end)
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.E and repairHeld then
			repairHeld = false
			repairRemote:FireServer(false)
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.Q then
			use("Ability")
		elseif input.KeyCode == Enum.KeyCode.F then
			use("Ultimate")
		elseif input.KeyCode == Enum.KeyCode.H then
			cycleHero()
		end
	end)

	Remotes.Get("Notify").OnClientEvent:Connect(function(kind, data)
		if kind == "AbilityFx" and FX[data.kind] then
			FX[data.kind](data)
		elseif kind == "Impact" then
			ImpactController.Play(data.tier)
		elseif kind == "Knockback" and typeof(data.vel) == "Vector3" then
			local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart")
			if root then
				root.AssemblyLinearVelocity = data.vel
			end
		end
	end)

	RunService.RenderStepped:Connect(updateHud)
	RunService.RenderStepped:Connect(updateDowned)
	RunService.RenderStepped:Connect(updateRaid)
	Players.PlayerRemoving:Connect(function(p)
		if markers[p] then
			markers[p]:Destroy()
			markers[p] = nil
		end
	end)
end

return AbilityController
