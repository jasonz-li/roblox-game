--!nonstrict
-- Client-side sound playback: 2D UI/weapon sounds for the local player and 3D
-- one-shots at world positions (e.g. other players' gunshots).

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local SoundConfig = require(game.ReplicatedStorage.Shared.Config.SoundConfig)
local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)

local SoundController = {}

local templates = {} -- [name] = { Sound }
local worldFolder: Folder

local function pick(name)
	local list = templates[name]
	return list and list[math.random(1, #list)]
end

-- Non-positional sound (your own gun, hitmarkers, UI).
function SoundController.Play(name: string, volumeScale: number?)
	local template = pick(name)
	if not template then
		return
	end
	local def = SoundConfig[name]
	local s = template:Clone()
	s.Volume = def.Volume * (volumeScale or 1)
	s.PlaybackSpeed = 1 + (math.random() * 2 - 1) * (def.PitchVariance or 0)
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, s.TimeLength > 0 and s.TimeLength / s.PlaybackSpeed + 0.2 or 4)
	return s
end

-- Positional one-shot (other players' gunshots).
function SoundController.PlayAt(name: string, position: Vector3, maxDistance: number?)
	local template = pick(name)
	if not template then
		return
	end
	local def = SoundConfig[name]
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.one * 0.2
	anchor.Position = position
	anchor.Parent = worldFolder
	local s = template:Clone()
	s.Volume = def.Volume
	s.PlaybackSpeed = 1 + (math.random() * 2 - 1) * (def.PitchVariance or 0)
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMinDistance = 8
	s.RollOffMaxDistance = maxDistance or 200
	s.Parent = anchor
	s:Play()
	Debris:AddItem(anchor, 3)
end

function SoundController.Init()
	local folder = Instance.new("Folder")
	folder.Name = "SoundTemplates"
	folder.Parent = SoundService
	for name, def in SoundConfig do
		templates[name] = {}
		for _, id in def.Ids do
			local s = Instance.new("Sound")
			s.Name = name
			s.SoundId = id
			s.Parent = folder
			table.insert(templates[name], s)
		end
	end
	worldFolder = Instance.new("Folder")
	worldFolder.Name = "ClientSounds"
	worldFolder.Parent = workspace
end

function SoundController.Start()
	Remotes.Get("ShotFx").OnClientEvent:Connect(function(_shooter, origin)
		if typeof(origin) == "Vector3" then
			SoundController.PlayAt("RifleShot", origin)
		end
	end)
	Remotes.Get("Notify").OnClientEvent:Connect(function(kind)
		if kind == "WaveStart" then
			SoundController.Play("WaveStart")
		elseif kind == "WaveComplete" then
			SoundController.Play("WaveComplete")
		end
	end)
end

return SoundController
