--!nonstrict
-- Mystery box: pay, watch it cycle, take the weapon it lands on (only the buyer
-- can). After a random number of uses it "moves": the buyer is refunded and the
-- box relocates to another unlocked location. Model is a PLACEHOLDER chest.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local WeaponConfig = require(game.ReplicatedStorage.Shared.Config.WeaponConfig)
local SoundConfig = require(game.ReplicatedStorage.Shared.Config.SoundConfig)
local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)
local MapService = require(script.Parent.MapService)
local CurrencyService = require(script.Parent.CurrencyService)
local WeaponService = require(script.Parent.WeaponService)

local MysteryBoxService = {}

local cfg = GameConfig.MysteryBox
local folder: Folder
local box -- { base, display, label, sound, locationIndex }
local state = "Idle" -- Idle | Rolling | Offer | Moving
local uses, useLimit = 0, 0
local offer -- { player, weaponId, token }
local token = 0
local notify: RemoteEvent
local promptSetter -- injected by InteractionService

local function setPrompt(action, object, enabled)
	if promptSetter and box then
		promptSetter(box.base, action, object, enabled)
	end
end

local function rollLimit()
	useLimit = math.random(cfg.MinUsesBeforeMove, cfg.MaxUsesBeforeMove)
	uses = 0
end

local function showDisplay(text: string?, color: Color3?)
	if not box then
		return
	end
	box.display.Transparency = text and 0.1 or 1
	box.display.Color = color or Color3.fromRGB(255, 255, 255)
	box.label.Text = text or ""
	box.label.TextColor3 = color or Color3.new(1, 1, 1)
end

local function build(locationIndex: number)
	if box then
		box.model:Destroy()
	end
	local loc = MapService.GetLayout().BoxLocations[locationIndex]
	local cf = CFrame.lookAt(loc.Pos + Vector3.new(0, 1.25, 0), loc.Pos + Vector3.new(0, 1.25, 0) + loc.Face)

	local model = Instance.new("Model")
	model.Name = "MysteryBox"

	local base = Instance.new("Part")
	base.Name = "Base"
	base.Anchored = true
	base.Size = Vector3.new(5, 2.5, 2.5)
	base.CFrame = cf
	base.Color = Color3.fromRGB(70, 40, 90)
	base.Material = Enum.Material.WoodPlanks
	base.Parent = model

	local trim = Instance.new("Part")
	trim.Name = "Trim"
	trim.Anchored = true
	trim.CanCollide = false
	trim.Size = Vector3.new(5.2, 0.3, 2.7)
	trim.CFrame = cf * CFrame.new(0, 1.2, 0)
	trim.Color = Color3.fromRGB(255, 80, 200)
	trim.Material = Enum.Material.Neon
	trim.Parent = model

	local display = Instance.new("Part")
	display.Name = "Display"
	display.Anchored = true
	display.CanCollide = false
	display.CanQuery = false
	display.Size = Vector3.new(3, 0.6, 0.4)
	display.CFrame = cf * CFrame.new(0, 3, 0)
	display.Material = Enum.Material.Neon
	display.Transparency = 1
	display.Parent = model

	local bb = Instance.new("BillboardGui")
	bb.Size = UDim2.fromOffset(260, 50)
	bb.StudsOffset = Vector3.new(0, 1.4, 0)
	bb.AlwaysOnTop = true
	bb.MaxDistance = 60
	bb.Parent = display
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 24
	label.TextStrokeTransparency = 0.4
	label.Text = ""
	label.Parent = bb

	local beam = Instance.new("PointLight")
	beam.Color = Color3.fromRGB(255, 80, 200)
	beam.Range = 16
	beam.Brightness = 1.5
	beam.Parent = trim

	local sound = Instance.new("Sound")
	sound.SoundId = SoundConfig.BoxJingle.Ids[1]
	sound.Volume = SoundConfig.BoxJingle.Volume
	sound.RollOffMaxDistance = 80
	sound.Parent = base

	base:SetAttribute("Kind", "MysteryBox")
	base:SetAttribute("Id", "Box")
	base:SetAttribute("Cost", cfg.Cost)
	base:SetAttribute("Title", "Mystery Box")
	model.Parent = folder
	CollectionService:AddTag(base, "Interactable")

	box = { model = model, base = base, display = display, label = label, sound = sound, locationIndex = locationIndex }
	state = "Idle"
	offer = nil
	showDisplay(nil)
end

local function pickWeapon(player: Player): string
	local pool = {}
	local total = 0
	for _, entry in WeaponConfig.BoxPool() do
		if not WeaponService.HasWeapon(player, entry.id) then
			table.insert(pool, entry)
			total += entry.weight
		end
	end
	local r = math.random() * total
	for _, entry in pool do
		r -= entry.weight
		if r <= 0 then
			return entry.id
		end
	end
	return pool[#pool].id
end

local function relocate()
	local locations = MapService.GetLayout().BoxLocations
	local options = {}
	for i, loc in locations do
		if i ~= box.locationIndex and MapService.IsZoneUnlocked(loc.Zone) then
			table.insert(options, i)
		end
	end
	local nextIndex = #options > 0 and options[math.random(1, #options)] or box.locationIndex
	build(nextIndex)
	rollLimit()
	notify:FireAllClients("Message", { text = "The Mystery Box has moved to the " .. MapService.GetLayout().Zones[locations[nextIndex].Zone].Name, tone = "info" })
end

local function roll(player: Player)
	state = "Rolling"
	token += 1
	local myToken = token
	uses += 1
	setPrompt("Mystery Box", "Rolling…", false)
	box.sound:Play()

	local pool = WeaponConfig.BoxPool()
	local t0 = os.clock()
	while os.clock() - t0 < cfg.RollTime do
		local w = WeaponConfig.Get(pool[math.random(1, #pool)].id)
		showDisplay(w.DisplayName, w.View.Accent)
		task.wait(0.12 + (os.clock() - t0) / cfg.RollTime * 0.2)
		if myToken ~= token then
			return
		end
	end

	if uses >= useLimit then
		state = "Moving"
		showDisplay("✦ IT FLED ✦", Color3.fromRGB(255, 80, 120))
		if player.Parent then
			CurrencyService.Add(player, cfg.Cost, "Box refund")
		end
		task.wait(cfg.MoveDelay)
		if myToken == token then
			relocate()
			setPrompt("Mystery Box", cfg.Cost .. " pts", true)
		end
		return
	end

	local weaponId = pickWeapon(player)
	local w = WeaponConfig.Get(weaponId)
	showDisplay(w.DisplayName, w.View.Accent)
	state = "Offer"
	offer = { player = player, weaponId = weaponId, token = myToken }
	setPrompt("Take " .. w.DisplayName, "for " .. player.DisplayName, true)

	task.delay(cfg.TakeTime, function()
		if offer and offer.token == myToken then
			offer = nil
			state = "Idle"
			showDisplay(nil)
			setPrompt("Mystery Box", cfg.Cost .. " pts", true)
		end
	end)
end

-- Called by InteractionService. Returns ok, message.
function MysteryBoxService.OnTriggered(player: Player): (boolean, string?)
	if state == "Idle" then
		if not CurrencyService.TrySpend(player, cfg.Cost) then
			return false, "Not enough points (" .. cfg.Cost .. ")"
		end
		task.spawn(roll, player)
		return true
	elseif state == "Offer" and offer then
		if offer.player ~= player then
			return false, "That weapon is for " .. offer.player.DisplayName
		end
		local id = offer.weaponId
		offer = nil
		state = "Idle"
		showDisplay(nil)
		setPrompt("Mystery Box", cfg.Cost .. " pts", true)
		if not WeaponService.GiveWeapon(player, id) then
			WeaponService.RefillWeapon(player, id)
		end
		return true
	end
	return false, "The box is busy"
end

function MysteryBoxService.SetPromptSetter(fn)
	promptSetter = fn
end

function MysteryBoxService.Reset()
	token += 1
	build(MapService.GetLayout().BoxStart)
	rollLimit()
end

function MysteryBoxService.Init()
	notify = Remotes.Get("Notify")
	folder = Instance.new("Folder")
	folder.Name = "MysteryBox"
	folder.Parent = workspace
end

function MysteryBoxService.Start()
	MysteryBoxService.Reset()
	Players.PlayerRemoving:Connect(function(p)
		if offer and offer.player == p then
			offer = nil
			state = "Idle"
			showDisplay(nil)
			setPrompt("Mystery Box", cfg.Cost .. " pts", true)
		end
	end)
end

return MysteryBoxService
