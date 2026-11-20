--!nonstrict
-- In-run progression HUD: kill-streak meter, upgrade pick cards (Z / X / C),
-- owned-upgrade list. State comes from player attributes set by ProgressionService.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local ProgressionConfig = require(game.ReplicatedStorage.Shared.Config.ProgressionConfig)
local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)

local ProgressionController = {}

local player = Players.LocalPlayer
local PANEL = Color3.fromRGB(14, 12, 22)
local PINK = Color3.fromRGB(255, 80, 170)
local KEYS = { Enum.KeyCode.Z, Enum.KeyCode.X, Enum.KeyCode.C }
local KEY_NAMES = { "Z", "X", "C" }
local ROMAN = { "I", "II", "III", "IV", "V" }

local gui: ScreenGui
local ui = {}
local currentOffer = {} -- { ids }

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
	local d = { BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack, TextStrokeTransparency = 0.6 }
	for k, v in props do
		d[k] = v
	end
	return new("TextLabel", d)
end

----------------------------------------------------------------------
-- Streak meter (right of the crosshair)
----------------------------------------------------------------------

local function buildStreak()
	ui.streak = new("Frame", {
		Name = "Streak",
		AnchorPoint = Vector2.new(0, 0.5),
		Position = UDim2.new(0.5, 70, 0.5, 40),
		Size = UDim2.fromOffset(150, 46),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	ui.streakMult = label({ Text = "x1.0", TextSize = 30, TextColor3 = PINK, TextXAlignment = Enum.TextXAlignment.Left, Size = UDim2.fromOffset(150, 30), Parent = ui.streak })
	ui.streakCount = label({ Text = "STREAK 0", Font = Enum.Font.GothamBold, TextSize = 12, TextXAlignment = Enum.TextXAlignment.Left, Position = UDim2.fromOffset(2, 28), Size = UDim2.fromOffset(150, 12), Parent = ui.streak })
	local bg = new("Frame", { Position = UDim2.fromOffset(2, 42), Size = UDim2.fromOffset(110, 3), BackgroundColor3 = Color3.fromRGB(40, 30, 46), BorderSizePixel = 0, Parent = ui.streak })
	ui.streakBar = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = PINK, BorderSizePixel = 0, Parent = bg })
	ui.streakScale = new("UIScale", { Parent = ui.streak })
end

local lastCount = 0
local function refreshStreak()
	local count = player:GetAttribute("StreakCount") or 0
	local mult = player:GetAttribute("StreakMult") or 1
	ui.streak.Visible = count >= 2
	ui.streakMult.Text = string.format("x%.1f", mult)
	ui.streakCount.Text = "STREAK " .. count
	local hot = mult >= ProgressionConfig.Streak.MaxMult
	ui.streakMult.TextColor3 = hot and Color3.fromRGB(255, 220, 90) or PINK
	if count > lastCount then
		ui.streakScale.Scale = 1.35
		TweenService:Create(ui.streakScale, TweenInfo.new(0.18, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	end
	lastCount = count
end

----------------------------------------------------------------------
-- Upgrade cards
----------------------------------------------------------------------

local function buildCards()
	ui.offer = new("Frame", {
		Name = "UpgradeOffer",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(3 * 200 + 2 * 14, 150),
		BackgroundTransparency = 1,
		Visible = false,
		Parent = gui,
	})
	ui.offerTitle = label({ Text = "CHOOSE AN UPGRADE", TextSize = 18, Position = UDim2.fromOffset(0, -30), Size = UDim2.new(1, 0, 0, 24), Parent = ui.offer })
	ui.cards = {}
	for i = 1, 3 do
		local card = new("Frame", {
			Position = UDim2.fromOffset((i - 1) * 214, 0),
			Size = UDim2.fromOffset(200, 120),
			BackgroundColor3 = PANEL,
			BackgroundTransparency = 0.15,
			Parent = ui.offer,
		}, { new("UICorner", { CornerRadius = UDim.new(0, 10) }) })
		local stroke = new("UIStroke", { Thickness = 2, Color = PINK, Parent = card })
		local key = label({ Text = KEY_NAMES[i], TextSize = 16, TextColor3 = PANEL, BackgroundTransparency = 0, BackgroundColor3 = Color3.new(1, 1, 1), Position = UDim2.fromOffset(-8, -8), Size = UDim2.fromOffset(26, 26), TextStrokeTransparency = 1, Parent = card }, nil)
		new("UICorner", { CornerRadius = UDim.new(0, 6), Parent = key })
		local name = label({ Text = "", TextSize = 18, TextWrapped = true, Position = UDim2.fromOffset(12, 18), Size = UDim2.new(1, -24, 0, 24), Parent = card })
		local desc = label({ Text = "", Font = Enum.Font.GothamMedium, TextSize = 14, TextWrapped = true, TextColor3 = Color3.fromRGB(210, 205, 225), Position = UDim2.fromOffset(12, 48), Size = UDim2.new(1, -24, 0, 40), Parent = card })
		local rank = label({ Text = "", Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = Color3.fromRGB(160, 155, 180), Position = UDim2.new(0, 12, 1, -24), Size = UDim2.new(1, -24, 0, 14), Parent = card })
		ui.cards[i] = { frame = card, stroke = stroke, name = name, desc = desc, rank = rank }
	end
	ui.offerTimer = label({ Text = "", Font = Enum.Font.GothamBold, TextSize = 13, TextColor3 = Color3.fromRGB(190, 185, 205), Position = UDim2.new(0, 0, 1, -22), Size = UDim2.new(1, 0, 0, 16), Parent = ui.offer })
end

local function refreshOffer()
	local raw = player:GetAttribute("UpgradeOffer") or ""
	currentOffer = raw == "" and {} or string.split(raw, ",")
	ui.offer.Visible = #currentOffer > 0
	for i, card in ui.cards do
		local id = currentOffer[i]
		local def = id and ProgressionConfig.Upgrades[id]
		card.frame.Visible = def ~= nil
		if def then
			local have = ProgressionConfig.Count(player, id)
			card.name.Text = def.Name
			card.name.TextColor3 = def.Color
			card.stroke.Color = def.Color
			card.desc.Text = def.Desc
			card.rank.Text = "Rank " .. (ROMAN[have + 1] or tostring(have + 1)) .. " / " .. (ROMAN[def.Max] or tostring(def.Max))
		end
	end
	if ui.offer.Visible then
		ui.offer.Position = UDim2.new(0.5, 0, 1, -120)
		TweenService:Create(ui.offer, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Position = UDim2.new(0.5, 0, 1, -150) }):Play()
	end
end

----------------------------------------------------------------------
-- Owned upgrades (above the vitals panel)
----------------------------------------------------------------------

local function buildOwned()
	ui.owned = label({
		Text = "",
		Font = Enum.Font.GothamBold,
		TextSize = 13,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Bottom,
		RichText = true,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.new(0, 30, 1, -164),
		Size = UDim2.fromOffset(420, 60),
		TextWrapped = true,
		Parent = gui,
	})
end

local function hex(c: Color3)
	return string.format("#%02X%02X%02X", c.R * 255, c.G * 255, c.B * 255)
end

local function refreshOwned()
	local parts = {}
	for id, def in ProgressionConfig.Upgrades do
		local n = ProgressionConfig.Count(player, id)
		if n > 0 then
			table.insert(parts, string.format('<font color="%s">%s %s</font>', hex(def.Color), def.Name, ROMAN[n] or tostring(n)))
		end
	end
	table.sort(parts)
	ui.owned.Text = table.concat(parts, "  ·  ")
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function ProgressionController.Init()
	gui = new("ScreenGui", { Name = "Progression", ResetOnSpawn = false, IgnoreGuiInset = true, Parent = player:WaitForChild("PlayerGui") })
	buildStreak()
	buildCards()
	buildOwned()
end

function ProgressionController.Start()
	local choose = Remotes.Get("ChooseUpgrade")
	for _, a in { "StreakCount", "StreakMult" } do
		player:GetAttributeChangedSignal(a):Connect(refreshStreak)
	end
	player:GetAttributeChangedSignal("UpgradeOffer"):Connect(refreshOffer)
	player.AttributeChanged:Connect(function(name)
		if name:sub(1, 4) == "Upg_" then
			refreshOwned()
		end
	end)
	refreshStreak()
	refreshOffer()
	refreshOwned()

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed or #currentOffer == 0 then
			return
		end
		local i = table.find(KEYS, input.KeyCode)
		if i and currentOffer[i] then
			choose:FireServer(i)
			local card = ui.cards[i]
			card.frame.BackgroundColor3 = card.stroke.Color
			task.delay(0.15, function()
				card.frame.BackgroundColor3 = PANEL
			end)
		end
	end)

	RunService.RenderStepped:Connect(function()
		local now = workspace:GetServerTimeNow()
		if ui.streak.Visible then
			local ends = player:GetAttribute("StreakEnds") or 0
			local left = math.clamp((ends - now) / ProgressionConfig.StreakWindow(player), 0, 1)
			ui.streakBar.Size = UDim2.fromScale(left, 1)
		end
		if ui.offer.Visible then
			local left = math.max(0, math.ceil((player:GetAttribute("UpgradeOfferEnds") or 0) - now))
			ui.offerTitle.Text = "CHOOSE AN UPGRADE"
			ui.offerTimer.Text = "Press Z, X or C  ·  random pick in " .. left .. "s"
		end
	end)

	Remotes.Get("Notify").OnClientEvent:Connect(function(kind, data)
		if kind == "UpgradeChosen" then
			local def = ProgressionConfig.Upgrades[data.id]
			ui.offerTitle.Text = (def and def.Name or data.id) .. " " .. (ROMAN[data.stacks] or "")
		end
	end)
end

return ProgressionController
