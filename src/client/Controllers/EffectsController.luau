--!nonstrict
-- Shared client-side visual effects: tracers and impacts. Also renders other players' shots.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)
local WeaponConfig = require(game.ReplicatedStorage.Shared.Config.WeaponConfig)

local EffectsController = {}

local fxFolder: Folder

function EffectsController.Tracer(from: Vector3, to: Vector3, color: Color3?)
	local dist = (to - from).Magnitude
	if dist < 0.5 then
		return
	end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Color = color or Color3.fromRGB(255, 220, 140)
	p.Size = Vector3.new(0.07, 0.07, dist)
	p.CFrame = CFrame.lookAt(from, to) * CFrame.new(0, 0, -dist / 2)
	p.Parent = fxFolder
	TweenService:Create(p, TweenInfo.new(0.08), { Transparency = 1 }):Play()
	Debris:AddItem(p, 0.1)
end

function EffectsController.Impact(pos: Vector3, normal: Vector3?, isEnemy: boolean)
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	p.Shape = Enum.PartType.Ball
	p.Color = isEnemy and Color3.fromRGB(255, 70, 90) or Color3.fromRGB(255, 230, 180)
	p.Size = Vector3.one * (isEnemy and 0.6 or 0.35)
	p.Position = pos + (normal or Vector3.zero) * 0.05
	p.Parent = fxFolder
	TweenService:Create(p, TweenInfo.new(0.15), { Transparency = 1, Size = p.Size * 2 }):Play()
	Debris:AddItem(p, 0.2)
end

-- Floating damage number (anime-style pop). Headshots are gold and bigger, kills are red.
function EffectsController.DamageNumber(pos: Vector3, amount: number, isHead: boolean, isKill: boolean)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.1
	anchor.Position = pos + Vector3.new((math.random() - 0.5) * 1.2, 0.5, (math.random() - 0.5) * 1.2)
	anchor.Parent = fxFolder
	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(120, 40)
	bb.AlwaysOnTop = true
	bb.LightInfluence = 0
	bb.Parent = anchor
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Size = UDim2.fromScale(1, 1)
	l.Font = Enum.Font.GothamBlack
	l.TextSize = isHead and 30 or (isKill and 26 or 20)
	l.TextColor3 = isKill and Color3.fromRGB(255, 70, 90) or (isHead and Color3.fromRGB(255, 215, 70) or Color3.new(1, 1, 1))
	l.TextStrokeTransparency = 0.2
	l.Text = (amount >= 1e6 and "∞" or tostring(amount)) .. (isHead and "!" or "")
	l.Parent = bb
	-- pop in, rise, fade
	l.TextSize *= 1.5
	TweenService:Create(l, TweenInfo.new(0.12, Enum.EasingStyle.Back), { TextSize = l.TextSize / 1.5 }):Play()
	TweenService:Create(bb, TweenInfo.new(0.7, Enum.EasingStyle.Quad), { StudsOffset = Vector3.new(0, 2.2, 0) }):Play()
	TweenService:Create(l, TweenInfo.new(0.35, Enum.EasingStyle.Linear, Enum.EasingDirection.Out, 0, false, 0.4), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 0.8)
end

-- White flash on an enemy that was hit (local only, does not replicate).
local flashing = {}
function EffectsController.FlashEnemy(model: Instance)
	if typeof(model) ~= "Instance" or not model:IsA("Model") or not model.Parent or flashing[model] then
		return
	end
	local h = Instance.new("Highlight")
	h.FillColor = Color3.new(1, 1, 1)
	h.FillTransparency = 0.3
	h.OutlineTransparency = 1
	h.DepthMode = Enum.HighlightDepthMode.Occluded
	h.Parent = model
	flashing[model] = true
	task.delay(0.07, function()
		h:Destroy()
		flashing[model] = nil
	end)
end

-- Red burst at the hit point (PLACEHOLDER for proper blood/ichor particles).
function EffectsController.HitBurst(pos: Vector3, isHead: boolean)
	for _ = 1, isHead and 6 or 3 do
		local p = Instance.new("Part")
		p.Anchored = true
		p.CanCollide = false
		p.CanQuery = false
		p.CanTouch = false
		p.CastShadow = false
		p.Material = Enum.Material.Neon
		p.Color = isHead and Color3.fromRGB(255, 60, 120) or Color3.fromRGB(200, 30, 60)
		p.Size = Vector3.one * (0.15 + math.random() * 0.2)
		p.Position = pos
		p.Parent = fxFolder
		local dir = Vector3.new(math.random() - 0.5, math.random() * 0.8, math.random() - 0.5).Unit
		TweenService:Create(p, TweenInfo.new(0.25, Enum.EasingStyle.Quad), { Position = pos + dir * (1 + math.random() * 1.5), Transparency = 1, Size = Vector3.one * 0.05 }):Play()
		Debris:AddItem(p, 0.3)
	end
end

function EffectsController.GetFolder(): Folder
	return fxFolder
end

function EffectsController.Init()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ClientFx"
	fxFolder.Parent = workspace
end

function EffectsController.Start()
	Remotes.Get("ShotFx").OnClientEvent:Connect(function(_shooter, origin, endPos, weaponId, upgraded)
		if typeof(origin) == "Vector3" and typeof(endPos) == "Vector3" then
			local stats = typeof(weaponId) == "string" and WeaponConfig.Get(weaponId, upgraded == true)
			EffectsController.Tracer(origin, endPos, stats and stats.TracerColor or Color3.fromRGB(150, 200, 255))
		end
	end)
end

return EffectsController
