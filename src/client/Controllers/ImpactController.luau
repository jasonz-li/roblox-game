--!nonstrict
-- Anime-style impact frames. A strong hit plays a ~3-frame sequence:
--   frame 1: white flash, world drained to stark black-and-white, ink speed lines
--   frame 2: inverted (dark frame, white speed lines)
--   then a snap back to normal color with a camera shake.
-- Lighter tiers skip the inversion and use thinner lines. Throttled so it never strobes.
--
-- ImpactController.Play(tier)   tier = "light" | "medium" | "heavy"
-- ImpactController.HoldUntil    os.clock() until which animations should freeze (hit-stop)

local Lighting = game:GetService("Lighting")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local CameraController = require(script.Parent.CameraController)

local ImpactController = {}
ImpactController.HoldUntil = 0

local TIERS = {
	light = { flash = 0.55, lines = 10, invert = false, hold = 0.03, shake = 0.4, frames = 0.035 },
	medium = { flash = 0.25, lines = 16, invert = false, hold = 0.06, shake = 0.8, frames = 0.05 },
	heavy = { flash = 0.05, lines = 24, invert = true, hold = 0.09, shake = 1.4, frames = 0.055 },
}
local MIN_GAP = { light = 0.12, medium = 0.18, heavy = 0.25 }

local gui: ScreenGui
local flash: Frame
local lineHolder: Frame
local lines = {}
local cc: ColorCorrectionEffect
local lastPlay = 0
local token = 0

local function build()
	gui = Instance.new("ScreenGui")
	gui.Name = "ImpactFrames"
	gui.IgnoreGuiInset = true
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 100
	gui.Parent = Players.LocalPlayer:WaitForChild("PlayerGui")

	flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BorderSizePixel = 0
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 1
	flash.Parent = gui

	-- Speed lines: long thin wedges radiating from the screen center
	lineHolder = Instance.new("Frame")
	lineHolder.AnchorPoint = Vector2.new(0.5, 0.5)
	lineHolder.Position = UDim2.fromScale(0.5, 0.5)
	lineHolder.Size = UDim2.fromOffset(0, 0)
	lineHolder.BackgroundTransparency = 1
	lineHolder.Visible = false
	lineHolder.Parent = gui
	for i = 1, 24 do
		local l = Instance.new("Frame")
		l.AnchorPoint = Vector2.new(0, 0.5)
		l.BorderSizePixel = 0
		l.BackgroundColor3 = Color3.new(0, 0, 0)
		l.Parent = lineHolder
		lines[i] = l
	end

	-- Local-only color grade (Lighting changes made on the client stay on this client)
	cc = Instance.new("ColorCorrectionEffect")
	cc.Name = "ImpactGrade"
	cc.Enabled = false
	cc.Parent = Lighting
end

-- Randomize the speed lines (different every hit, like hand-drawn frames)
local function layoutLines(count: number, color: Color3)
	local vp = workspace.CurrentCamera and workspace.CurrentCamera.ViewportSize or Vector2.new(1280, 720)
	local reach = vp.Magnitude * 0.6
	for i, l in lines do
		l.Visible = i <= count
		if i <= count then
			local angle = (i / count) * 360 + math.random(-8, 8)
			local inner = reach * (0.32 + math.random() * 0.18)
			local rad = math.rad(angle)
			l.Position = UDim2.fromOffset(math.cos(rad) * inner, math.sin(rad) * inner)
			l.Size = UDim2.fromOffset(reach - inner, math.random(3, 9))
			l.Rotation = angle
			l.BackgroundColor3 = color
			l.BackgroundTransparency = 0
		end
	end
end

local function setFrame(kind: string, cfg)
	if kind == "white" then
		flash.BackgroundColor3 = Color3.new(1, 1, 1)
		flash.BackgroundTransparency = cfg.flash
		cc.Enabled = true
		cc.Saturation = -1
		cc.Contrast = 1.6
		cc.Brightness = 0.25
		cc.TintColor = Color3.new(1, 1, 1)
		layoutLines(cfg.lines, Color3.new(0, 0, 0))
		lineHolder.Visible = true
	elseif kind == "invert" then
		flash.BackgroundColor3 = Color3.new(0, 0, 0)
		flash.BackgroundTransparency = 0.25
		cc.Saturation = -1
		cc.Contrast = 2.2
		cc.Brightness = -0.15
		cc.TintColor = Color3.fromRGB(255, 70, 90) -- a red-tinted negative
		layoutLines(cfg.lines, Color3.new(1, 1, 1))
	else
		flash.BackgroundTransparency = 1
		lineHolder.Visible = false
		cc.Enabled = false
	end
end

function ImpactController.Play(tier: string?)
	tier = TIERS[tier or ""] and tier or "medium"
	local cfg = TIERS[tier]
	local now = os.clock()
	if now - lastPlay < MIN_GAP[tier] then
		return
	end
	lastPlay = now
	token += 1
	local my = token
	ImpactController.HoldUntil = now + cfg.hold

	setFrame("white", cfg)
	task.delay(cfg.frames, function()
		if token ~= my then
			return
		end
		if cfg.invert then
			setFrame("invert", cfg)
			task.delay(cfg.frames, function()
				if token == my then
					setFrame("off", cfg)
					CameraController.Shake(cfg.shake)
				end
			end)
		else
			setFrame("off", cfg)
			CameraController.Shake(cfg.shake)
		end
	end)
end

function ImpactController.IsHolding(): boolean
	return os.clock() < ImpactController.HoldUntil
end

function ImpactController.Init()
	build()
end

function ImpactController.Start()
	-- safety: never leave the grade on (e.g. after a hitch)
	RunService.Heartbeat:Connect(function()
		if cc.Enabled and os.clock() - lastPlay > 0.5 then
			setFrame("off", TIERS.light)
		end
	end)
end

return ImpactController
