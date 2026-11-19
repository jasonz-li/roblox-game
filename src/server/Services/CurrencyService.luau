--!nonstrict
-- In-match points. Every point change goes through here (server only).

local Players = game:GetService("Players")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)

local CurrencyService = {}

local notify: RemoteEvent

local function setup(player: Player)
	local leaderstats = Instance.new("Folder")
	leaderstats.Name = "leaderstats"
	local points = Instance.new("IntValue")
	points.Name = "Points"
	points.Parent = leaderstats
	local kills = Instance.new("IntValue")
	kills.Name = "Kills"
	kills.Parent = leaderstats
	leaderstats.Parent = player
	CurrencyService.ResetPlayer(player)
end

local function sync(player: Player)
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		ls.Points.Value = player:GetAttribute("Points") or 0
		ls.Kills.Value = player:GetAttribute("Kills") or 0
	end
end

function CurrencyService.Init()
	notify = Remotes.Get("Notify")
end

function CurrencyService.Start()
	Players.PlayerAdded:Connect(setup)
	for _, p in Players:GetPlayers() do
		setup(p)
	end
end

function CurrencyService.ResetPlayer(player: Player)
	player:SetAttribute("Points", GameConfig.Points.Start)
	player:SetAttribute("Kills", 0)
	sync(player)
end

function CurrencyService.ResetAll()
	for _, p in Players:GetPlayers() do
		CurrencyService.ResetPlayer(p)
	end
end

function CurrencyService.Get(player: Player): number
	return player:GetAttribute("Points") or 0
end

function CurrencyService.Add(player: Player, amount: number, reason: string?)
	if amount == 0 or not player.Parent then
		return
	end
	player:SetAttribute("Points", CurrencyService.Get(player) + math.floor(amount))
	sync(player)
	notify:FireClient(player, "Points", { amount = math.floor(amount), reason = reason })
end

-- Returns true if the player could afford it (used by purchases in M2).
function CurrencyService.TrySpend(player: Player, amount: number): boolean
	local current = CurrencyService.Get(player)
	if amount < 0 or current < amount then
		return false
	end
	player:SetAttribute("Points", current - amount)
	sync(player)
	return true
end

function CurrencyService.AddKill(player: Player)
	player:SetAttribute("Kills", (player:GetAttribute("Kills") or 0) + 1)
	sync(player)
end

return CurrencyService
