--!nonstrict
-- Client-side sound playback: 2D UI/weapon sounds for the local player and 3D
-- one-shots at world positions (e.g. other players' gunshots).

local Debris = game:GetService("Debris")
local SoundService = game:GetService("SoundService")

local SoundConfig = require(game.ReplicatedStorage.Shared.Config.SoundConfig)
local WeaponConfig = require(game.ReplicatedStorage.Shared.Config.WeaponConfig)
local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)

local SoundController = {}

local templates = {} -- [name] = { Sound }
local worldFolder: Folder

local function pick(name)
	local list = templates[name]
	return list and list[math.random(1, #list)]
end

-- Non-positional sound (your own gun, hitmarkers, UI).
function SoundController.Play(name: string, volumeScale: number?, pitch: number?)
	local template = pick(name)
	if not template then
		return
	end
	local def = SoundConfig[name]
	local s = template:Clone()
	s.Volume = def.Volume * (volumeScale or 1)
	s.PlaybackSpeed = (pitch or 1) * (1 + (math.random() * 2 - 1) * (def.PitchVariance or 0))
	s.Parent = SoundService
	s:Play()
	Debris:AddItem(s, s.TimeLength > 0 and s.TimeLength / s.PlaybackSpeed + 0.2 or 4)
	return s
end

-- Positional one-shot (other players' gunshots).
function SoundController.PlayAt(name: string, position: Vector3, maxDistance: number?, pitch: number?)
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
	s.PlaybackSpeed = (pitch or 1) * (1 + (math.random() * 2 - 1) * (def.PitchVariance or 0))
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

-- DEV sound audition: F6 = next gunshot recording, F7 = toggle the low "thump" layer.
-- Only changes sounds on this client; copy the winner into SoundConfig.RifleShot.Ids.
SoundController.ThumpEnabled = true
local auditionIndex = 0
local repairIndex = 0
local function auditionLabel(text: string)
	local pg = game:GetService("Players").LocalPlayer:WaitForChild("PlayerGui")
	local gui = pg:FindFirstChild("SoundAudition")
	if not gui then
		gui = Instance.new("ScreenGui")
		gui.Name = "SoundAudition"
		gui.ResetOnSpawn = false
		gui.Parent = pg
		local l = Instance.new("TextLabel")
		l.Name = "Label"
		l.AnchorPoint = Vector2.new(0.5, 0)
		l.Position = UDim2.new(0.5, 0, 0, 120)
		l.Size = UDim2.fromOffset(700, 30)
		l.BackgroundTransparency = 0.4
		l.BackgroundColor3 = Color3.new(0, 0, 0)
		l.TextColor3 = Color3.fromRGB(255, 230, 120)
		l.Font = Enum.Font.GothamBold
		l.TextSize = 18
		l.Parent = gui
	end
	local l = gui.Label
	l.Text = text
	l.Visible = true
	local stamp = os.clock()
	l:SetAttribute("Stamp", stamp)
	task.delay(4, function()
		if l:GetAttribute("Stamp") == stamp then
			l.Visible = false
		end
	end)
end

local function setGunshot(id: string)
	for _, key in { "RifleShot", "HeavyShot" } do
		for _, s in templates[key] or {} do
			s.SoundId = id
		end
	end
end

function SoundController.Start()
	local GunshotCandidates = require(game.ReplicatedStorage.Shared.Config.GunshotCandidates)
	game:GetService("UserInputService").InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.KeyCode == Enum.KeyCode.F6 then
			auditionIndex = auditionIndex % #GunshotCandidates + 1
			local c = GunshotCandidates[auditionIndex]
			setGunshot(c.Id)
			auditionLabel(string.format("Gunshot %d/%d: %s   (F6 next, F7 thump %s)", auditionIndex, #GunshotCandidates, c.Name, SoundController.ThumpEnabled and "ON" or "OFF"))
			SoundController.Play("RifleShot")
		elseif input.KeyCode == Enum.KeyCode.F7 then
			SoundController.ThumpEnabled = not SoundController.ThumpEnabled
			auditionLabel("Thump layer " .. (SoundController.ThumpEnabled and "ON" or "OFF"))
		elseif input.KeyCode == Enum.KeyCode.F8 then
			-- Preview window-repair sounds at the real rhythm (3 boards). Preview only:
			-- the server keeps using SoundConfig.BoardRepair until you pick one.
			local RepairCandidates = require(game.ReplicatedStorage.Shared.Config.RepairCandidates)
			local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
			repairIndex = repairIndex % #RepairCandidates + 1
			local c = RepairCandidates[repairIndex]
			auditionLabel(string.format("Repair sound %d/%d: %s   (F8 next)", repairIndex, #RepairCandidates, c.Name))
			task.spawn(function()
				for _ = 1, 3 do
					local s = Instance.new("Sound")
					s.SoundId = c.Id
					s.Volume = SoundConfig.BoardRepair.Volume
					s.PlaybackSpeed = 1 + (math.random() * 2 - 1) * 0.08
					s.Parent = game:GetService("SoundService")
					s:Play()
					game:GetService("Debris"):AddItem(s, 3)
					task.wait(GameConfig.Barrier.RepairInterval)
				end
			end)
		end
	end)

	Remotes.Get("ShotFx").OnClientEvent:Connect(function(_shooter, origin, _endPos, weaponId, upgraded)
		if typeof(origin) ~= "Vector3" then
			return
		end
		local stats = typeof(weaponId) == "string" and WeaponConfig.Get(weaponId, upgraded == true)
		SoundController.PlayAt(stats and stats.ShotSound or "RifleShot", origin, nil, stats and stats.ShotPitch or 1)
	end)
	Remotes.Get("Notify").OnClientEvent:Connect(function(kind, data)
		if kind == "WaveStart" then
			SoundController.Play("WaveStart")
		elseif kind == "WaveComplete" then
			SoundController.Play("WaveComplete")
		elseif kind == "Sound" and typeof(data) == "table" and SoundConfig[data.name] then
			SoundController.Play(data.name)
		elseif kind == "PowerUp" then
			SoundController.Play(data.id == "Nuke" and "Nuke" or "PowerUp")
		elseif kind == "DoorOpened" and typeof(data) == "table" and typeof(data.position) == "Vector3" then
			SoundController.PlayAt("DoorOpen", data.position, 250)
		end
	end)
end

return SoundController
