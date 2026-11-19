--!nonstrict
-- Shared client-side visual effects: tracers and impacts. Also renders other players' shots.

local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")

local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)

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

function EffectsController.GetFolder(): Folder
	return fxFolder
end

function EffectsController.Init()
	fxFolder = Instance.new("Folder")
	fxFolder.Name = "ClientFx"
	fxFolder.Parent = workspace
end

function EffectsController.Start()
	Remotes.Get("ShotFx").OnClientEvent:Connect(function(_shooter, origin, endPos)
		if typeof(origin) == "Vector3" and typeof(endPos) == "Vector3" then
			EffectsController.Tracer(origin, endPos, Color3.fromRGB(150, 200, 255))
		end
	end)
end

return EffectsController
