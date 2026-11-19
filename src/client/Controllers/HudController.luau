--!nonstrict
-- In-match HUD built in code: crosshair, hitmarker, ammo, health, points, wave info,
-- banners, damage flash, game-over screen. Visual style is a PLACEHOLDER theme.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)
local SoundController = require(script.Parent.SoundController)

local THREAT_RANGE = 24 -- studs: show edge arrows for enemies this close
local THREAT_RING = 150 -- px from screen center
local MAX_THREATS = 6

local HudController = {}

local player = Players.LocalPlayer
local ACCENT = Color3.fromRGB(255, 80, 170) -- pink
local ACCENT2 = Color3.fromRGB(80, 220, 255) -- cyan
local WHITE = Color3.new(1, 1, 1)
local PANEL = Color3.fromRGB(14, 12, 22)

local gui: ScreenGui
local ui = {}
local crosshairSpreadPx, crosshairPulse = 8, 0
local ads = false

----------------------------------------------------------------------
-- UI helpers
----------------------------------------------------------------------

local function new(className, props, children)
	local inst = Instance.new(className)
	for k, v in props do
		if k ~= "Parent" then
			inst[k] = v
		end
	end
	for _, child in children or {} do
		child.Parent = inst
	end
	inst.Parent = props.Parent
	return inst
end

local function label(props)
	local defaults = {
		BackgroundTransparency = 1,
		TextColor3 = WHITE,
		Font = Enum.Font.GothamBlack,
		TextScaled = false,
		TextStrokeTransparency = 0.6,
	}
	for k, v in props do
		defaults[k] = v
	end
	return new("TextLabel", defaults)
end

local function corner(r)
	return new("UICorner", { CornerRadius = UDim.new(0, r) })
end

----------------------------------------------------------------------
-- Build
----------------------------------------------------------------------

local function buildCrosshair()
	local root = new("Frame", {
		Name = "Crosshair",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(0, 0),
		BackgroundTransparency = 1,
		Parent = gui,
	})
	ui.crossLines = {}
	for _, dir in { Vector2.new(1, 0), Vector2.new(-1, 0), Vector2.new(0, 1), Vector2.new(0, -1) } do
		local horizontal = dir.Y == 0
		local line = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = horizontal and UDim2.fromOffset(9, 2) or UDim2.fromOffset(2, 9),
			BackgroundColor3 = WHITE,
			BorderSizePixel = 0,
			Parent = root,
		}, { new("UIStroke", { Thickness = 1, Transparency = 0.5 }) })
		table.insert(ui.crossLines, { line, dir })
	end
	ui.crossDot = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5),
		Size = UDim2.fromOffset(3, 3),
		BackgroundColor3 = ACCENT,
		BorderSizePixel = 0,
		Parent = root,
	}, { corner(2) })

	-- Hitmarker: four diagonal ticks
	ui.hitmarker = new("Frame", { BackgroundTransparency = 1, Size = UDim2.fromOffset(0, 0), Parent = root })
	ui.hitLines = {}
	for i = 0, 3 do
		local angle = 45 + i * 90
		local rad = math.rad(angle)
		local line = new("Frame", {
			AnchorPoint = Vector2.new(0.5, 0.5),
			Position = UDim2.fromOffset(math.cos(rad) * 11, math.sin(rad) * 11),
			Size = UDim2.fromOffset(10, 2),
			Rotation = angle,
			BackgroundColor3 = WHITE,
			BackgroundTransparency = 1,
			BorderSizePixel = 0,
			Parent = ui.hitmarker,
		})
		table.insert(ui.hitLines, line)
	end
end

local function buildAmmo()
	local panel = new("Frame", {
		Name = "Ammo",
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -28, 1, -28),
		Size = UDim2.fromOffset(230, 92),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.35,
		Parent = gui,
	}, { corner(10), new("UIStroke", { Color = ACCENT2, Thickness = 1.5, Transparency = 0.4 }) })
	ui.weaponName = label({ Text = "WEAPON", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = ACCENT2, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.fromOffset(12, 6), Size = UDim2.new(1, -24, 0, 18), Parent = panel })
	ui.ammoMag = label({ Text = "30", TextSize = 46, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.fromOffset(12, 24), Size = UDim2.new(1, -110, 0, 50), Parent = panel })
	ui.ammoReserve = label({ Text = "/ 180", Font = Enum.Font.GothamBold, TextSize = 22, TextColor3 = Color3.fromRGB(190, 190, 210), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.new(1, -94, 0, 40), Size = UDim2.fromOffset(84, 28), Parent = panel })
	ui.reloadHint = label({ Text = "", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = ACCENT, TextXAlignment = Enum.TextXAlignment.Right, Position = UDim2.new(0, 12, 1, -22), Size = UDim2.new(1, -24, 0, 16), Parent = panel })
end

local function buildHealthAndPoints()
	local panel = new("Frame", {
		Name = "Vitals",
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 28, 1, -28),
		Size = UDim2.fromOffset(270, 92),
		BackgroundColor3 = PANEL,
		BackgroundTransparency = 0.35,
		Parent = gui,
	}, { corner(10), new("UIStroke", { Color = ACCENT, Thickness = 1.5, Transparency = 0.4 }) })

	label({ Text = "PTS", Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = ACCENT, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 8), Size = UDim2.fromOffset(40, 18), Parent = panel })
	ui.points = label({ Text = "0", TextSize = 32, TextColor3 = Color3.fromRGB(255, 225, 120), TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(14, 22), Size = UDim2.fromOffset(200, 36), Parent = panel })
	ui.popupAnchor = new("Frame", { BackgroundTransparency = 1, Position = UDim2.fromOffset(150, 22), Size = UDim2.fromOffset(110, 36), Parent = panel })

	local barBg = new("Frame", {
		Position = UDim2.new(0, 14, 1, -26),
		Size = UDim2.new(1, -28, 0, 14),
		BackgroundColor3 = Color3.fromRGB(40, 30, 46),
		BorderSizePixel = 0,
		Parent = panel,
	}, { corner(4) })
	ui.healthFill = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(110, 255, 160),
		BorderSizePixel = 0,
		Parent = barBg,
	}, { corner(4) })
	ui.healthText = label({ Text = "100", Font = Enum.Font.GothamBold, TextSize = 12, Size = UDim2.fromScale(1, 1), Parent = barBg })
end

local function buildWaveInfo()
	ui.wave = label({
		Text = "",
		TextSize = 38,
		TextColor3 = Color3.fromRGB(255, 70, 90),
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 16),
		Size = UDim2.fromOffset(400, 42),
		Parent = gui,
	})
	ui.waveSub = label({
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 18,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 58),
		Size = UDim2.fromOffset(400, 24),
		Parent = gui,
	})
	ui.banner = label({
		Text = "",
		TextSize = 64,
		TextColor3 = WHITE,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.3),
		Size = UDim2.fromOffset(800, 80),
		Parent = gui,
	})
	ui.bannerSub = label({
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 24,
		TextColor3 = ACCENT2,
		TextTransparency = 1,
		TextStrokeTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.new(0.5, 0, 0.3, 52),
		Size = UDim2.fromOffset(800, 30),
		Parent = gui,
	})
end

-- Edge arrows pointing at nearby enemies (works with sound off too).
local function buildThreatIndicators()
	ui.threats = {}
	for i = 1, MAX_THREATS do
		local arrow = label({
			Name = "Threat" .. i,
			Text = "▲",
			TextSize = 34,
			TextColor3 = Color3.fromRGB(255, 50, 70),
			TextStrokeTransparency = 0.3,
			AnchorPoint = Vector2.new(0.5, 0.5),
			Size = UDim2.fromOffset(40, 40),
			Visible = false,
			Parent = gui,
		})
		table.insert(ui.threats, arrow)
	end
end

local threatFlash = 0

local function updateThreats(dt)
	threatFlash = math.max(0, threatFlash - dt * 2)
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart")
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local enemies = workspace:FindFirstChild("Enemies")
	local list = {}
	if root and hum and hum.Health > 0 and enemies then
		for _, m in enemies:GetChildren() do
			local r = m.PrimaryPart
			if r and r.CanQuery then
				local d = (r.Position - root.Position).Magnitude
				if d <= THREAT_RANGE then
					table.insert(list, { r.Position, d })
				end
			end
		end
	end
	table.sort(list, function(a, b)
		return a[2] < b[2]
	end)

	local cam = workspace.CurrentCamera
	local center = cam.ViewportSize / 2
	for i, arrow in ui.threats do
		local entry = list[i]
		if not entry then
			arrow.Visible = false
			continue
		end
		local rel = cam.CFrame:PointToObjectSpace(entry[1])
		local angle = math.atan2(rel.X, -rel.Z) -- 0 = straight ahead
		-- Enemies you're already looking at only get an arrow when they're on top of you.
		if math.abs(angle) < math.rad(28) and entry[2] > 7 then
			arrow.Visible = false
			continue
		end
		local closeness = 1 - entry[2] / THREAT_RANGE
		arrow.Visible = true
		arrow.Position = UDim2.fromOffset(center.X + math.sin(angle) * THREAT_RING, center.Y - math.cos(angle) * THREAT_RING)
		arrow.Rotation = math.deg(angle)
		arrow.TextSize = 24 + 18 * closeness
		arrow.TextTransparency = math.clamp(0.75 - closeness * 0.75 - threatFlash * 0.5, 0, 0.8)
	end
end

local function buildOverlays()
	ui.damage = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(200, 0, 30),
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		ZIndex = 0,
		Parent = gui,
	})
	ui.gameOver = new("Frame", {
		Size = UDim2.fromScale(1, 1),
		BackgroundColor3 = Color3.fromRGB(10, 0, 12),
		BackgroundTransparency = 0.25,
		Visible = false,
		ZIndex = 10,
		Parent = gui,
	})
	label({ Text = "OVERWHELMED", TextSize = 84, TextColor3 = Color3.fromRGB(255, 60, 90), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(900, 100), ZIndex = 11, Parent = ui.gameOver })
	ui.gameOverWave = label({ Text = "", Font = Enum.Font.GothamBold, TextSize = 30, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(900, 40), ZIndex = 11, Parent = ui.gameOver })
	ui.gameOverTimer = label({ Text = "", Font = Enum.Font.GothamBold, TextSize = 20, TextColor3 = ACCENT2, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.6), Size = UDim2.fromOffset(900, 30), ZIndex = 11, Parent = ui.gameOver })
	ui.deadNotice = label({ Text = "YOU ARE DOWN. Respawning next wave", Font = Enum.Font.GothamBold, TextSize = 24, TextColor3 = Color3.fromRGB(255, 120, 140), AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.62), Size = UDim2.fromOffset(700, 30), Visible = false, Parent = gui })
end

----------------------------------------------------------------------
-- Public API (used by WeaponController)
----------------------------------------------------------------------

function HudController.SetAmmo(mag: number, reserve: number, reloading: boolean, weaponName: string, magSize: number)
	ui.weaponName.Text = string.upper(weaponName)
	ui.ammoMag.Text = tostring(mag)
	ui.ammoReserve.Text = "/ " .. tostring(reserve)
	local low = mag <= math.floor(magSize * 0.25)
	ui.ammoMag.TextColor3 = (mag == 0 and Color3.fromRGB(255, 70, 90)) or (low and Color3.fromRGB(255, 190, 90)) or WHITE
	if reloading then
		ui.reloadHint.Text = "RELOADING…"
	elseif mag == 0 and reserve == 0 then
		ui.reloadHint.Text = "NO AMMO"
	elseif low then
		ui.reloadHint.Text = "[R] RELOAD"
	else
		ui.reloadHint.Text = ""
	end
end

function HudController.SetCrosshairSpread(degrees: number)
	crosshairSpreadPx = 6 + degrees * 7
end

function HudController.PulseCrosshair()
	crosshairPulse = math.min(crosshairPulse + 5, 14)
end

function HudController.SetAds(value: boolean)
	ads = value
end

function HudController.ShowHitmarker(isHeadshot: boolean, isKill: boolean)
	local color = isKill and Color3.fromRGB(255, 60, 80) or (isHeadshot and Color3.fromRGB(255, 220, 90) or WHITE)
	local size = isKill and 14 or 10
	for _, line in ui.hitLines do
		line.BackgroundColor3 = color
		line.Size = UDim2.fromOffset(size, isKill and 3 or 2)
		line.BackgroundTransparency = 0
		TweenService:Create(line, TweenInfo.new(isKill and 0.35 or 0.2), { BackgroundTransparency = 1 }):Play()
	end
end

----------------------------------------------------------------------
-- Feedback
----------------------------------------------------------------------

local function showBanner(text: string, sub: string?, color: Color3?)
	ui.banner.Text = text
	ui.banner.TextColor3 = color or WHITE
	ui.bannerSub.Text = sub or ""
	for _, l in { ui.banner, ui.bannerSub } do
		l.TextTransparency = 0
		l.TextStrokeTransparency = 0.5
		TweenService:Create(l, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, false, 1.6), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	end
end

local function pointsPopup(amount: number)
	local l = label({
		Text = (amount >= 0 and "+" or "") .. tostring(amount),
		TextSize = 20,
		TextColor3 = amount >= 60 and Color3.fromRGB(255, 225, 120) or WHITE,
		TextXAlignment = Enum.TextXAlignment.Left,
		Position = UDim2.fromOffset(math.random(0, 20), 8),
		Size = UDim2.fromOffset(100, 22),
		Parent = ui.popupAnchor,
	})
	TweenService:Create(l, TweenInfo.new(0.8), { Position = l.Position - UDim2.fromOffset(0, 34), TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	task.delay(0.85, function()
		l:Destroy()
	end)
end

local function flashDamage(amount: number)
	threatFlash = 1
	SoundController.Play("PlayerHurt")
	ui.damage.BackgroundTransparency = math.clamp(0.85 - amount / 100, 0.5, 0.85)
	TweenService:Create(ui.damage, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
end

local function bindCharacter(char: Model)
	local hum = char:WaitForChild("Humanoid")
	local lastHealth = hum.Health
	local function refresh()
		local frac = math.clamp(hum.Health / math.max(hum.MaxHealth, 1), 0, 1)
		ui.healthFill.Size = UDim2.fromScale(frac, 1)
		ui.healthFill.BackgroundColor3 = Color3.fromRGB(255, 70, 90):Lerp(Color3.fromRGB(110, 255, 160), frac)
		ui.healthText.Text = tostring(math.ceil(hum.Health))
		if hum.Health < lastHealth - 0.5 then
			flashDamage(lastHealth - hum.Health)
		end
		lastHealth = hum.Health
		ui.deadNotice.Visible = hum.Health <= 0 and ui.gameOver.Visible == false
	end
	hum.HealthChanged:Connect(refresh)
	refresh()
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function HudController.Init()
	gui = new("ScreenGui", {
		Name = "Hud",
		ResetOnSpawn = false,
		IgnoreGuiInset = true,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	buildCrosshair()
	buildAmmo()
	buildHealthAndPoints()
	buildWaveInfo()
	buildThreatIndicators()
	buildOverlays()
end

function HudController.Start()
	local gameState = Remotes.GameState()

	local function refreshPoints()
		ui.points.Text = tostring(player:GetAttribute("Points") or 0)
	end
	player:GetAttributeChangedSignal("Points"):Connect(refreshPoints)
	refreshPoints()

	Remotes.Get("Notify").OnClientEvent:Connect(function(kind, data)
		if kind == "Points" then
			pointsPopup(data.amount)
		elseif kind == "WaveStart" then
			showBanner("WAVE " .. data.wave, "Survive.", Color3.fromRGB(255, 70, 90))
		elseif kind == "WaveComplete" then
			showBanner("WAVE " .. data.wave .. " CLEARED", "+" .. data.bonus .. " pts  •  ammo refilled", ACCENT2)
		end
	end)

	if player.Character then
		task.spawn(bindCharacter, player.Character)
	end
	player.CharacterAdded:Connect(bindCharacter)

	RunService.RenderStepped:Connect(function(dt)
		-- Crosshair
		crosshairPulse -= crosshairPulse * math.min(1, dt * 12)
		local gap = crosshairSpreadPx + crosshairPulse
		for _, entry in ui.crossLines do
			local line, dir = entry[1], entry[2]
			line.Position = UDim2.fromOffset(dir.X * (gap + 4), dir.Y * (gap + 4))
			line.Visible = not ads
		end

		updateThreats(dt)

		-- Wave info
		local state = gameState:GetAttribute("State")
		local wave = gameState:GetAttribute("Wave") or 0
		ui.gameOver.Visible = state == "GameOver"
		if state == "Wave" then
			ui.wave.Text = "WAVE " .. wave
			ui.waveSub.Text = tostring(gameState:GetAttribute("EnemiesRemaining") or 0) .. " ENEMIES REMAINING"
		elseif state == "Intermission" then
			local left = math.max(0, math.ceil((gameState:GetAttribute("IntermissionEndsAt") or 0) - workspace:GetServerTimeNow()))
			ui.wave.Text = wave > 0 and ("WAVE " .. wave) or "GET READY"
			ui.waveSub.Text = "NEXT WAVE IN " .. left
		elseif state == "GameOver" then
			ui.wave.Text = ""
			ui.waveSub.Text = ""
			local final = gameState:GetAttribute("FinalWave") or wave
			ui.gameOverWave.Text = "You survived " .. math.max(0, final - 1) .. " wave" .. (final - 1 == 1 and "" or "s") .. " (fell on wave " .. final .. ")"
			local left = math.max(0, math.ceil((gameState:GetAttribute("RestartAt") or 0) - workspace:GetServerTimeNow()))
			ui.gameOverTimer.Text = "Restarting in " .. left
			ui.deadNotice.Visible = false
		else
			ui.wave.Text = ""
			ui.waveSub.Text = "WAITING FOR PLAYERS"
		end
	end)
end

return HudController
