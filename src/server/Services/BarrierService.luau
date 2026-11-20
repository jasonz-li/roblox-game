--!nonstrict
-- Boarded windows: zombies tear boards off (EnemyService calls TearBoard), players
-- rebuild them for points (InteractionService calls Repair). Board state lives in
-- attributes on the barrier's blocker part (built by MapService, tag "Barrier").

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local SoundConfig = require(game.ReplicatedStorage.Shared.Config.SoundConfig)
local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)
local CurrencyService = require(script.Parent.CurrencyService)

local BarrierService = {}

local cfg = GameConfig.Barrier
local repairEarned = {} -- [Player] = points earned from repairs this wave
local earnedWave = -1
local gameState: Folder

local function playSound(barrier: BasePart, name: string)
	local def = SoundConfig[name]
	local s = Instance.new("Sound")
	s.SoundId = def.Ids[math.random(1, #def.Ids)]
	s.Volume = def.Volume
	s.PlaybackSpeed = 1 + (math.random() * 2 - 1) * (def.PitchVariance or 0)
	s.RollOffMode = Enum.RollOffMode.InverseTapered
	s.RollOffMaxDistance = 90
	s.Parent = barrier
	s:Play()
	task.delay(3, function()
		s:Destroy()
	end)
end

-- Prompt only shows while there's something to repair.
local function refreshPrompt(barrier: BasePart)
	local prompt = barrier:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		return
	end
	local boards, max = barrier:GetAttribute("Boards"), barrier:GetAttribute("MaxBoards")
	prompt.Enabled = boards < max
	prompt.ActionText = "Hold E to repair (you can turn and shoot)"
	prompt.ObjectText = string.format("%d / %d boards", boards, max)
end

local function boardPart(barrier: BasePart, n: number): BasePart?
	return barrier:FindFirstChild("Board" .. n)
end

-- Remove the top-most intact board. Returns remaining board count.
function BarrierService.TearBoard(barrier: BasePart): number
	local boards = barrier:GetAttribute("Boards") or 0
	if boards <= 0 then
		return 0
	end
	local board = boardPart(barrier, boards)
	barrier:SetAttribute("Boards", boards - 1)
	if board then
		-- fling it outward and fade (cosmetic), keep the part for repairs
		local home = board:GetAttribute("HomeCFrame")
		local outward = (barrier:GetAttribute("Outside") - barrier:GetAttribute("Inside")).Unit
		TweenService:Create(board, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			CFrame = home * CFrame.new(0, -1.5, 0) + outward * 3,
			Transparency = 1,
		}):Play()
	end
	playSound(barrier, "BoardBreak")
	refreshPrompt(barrier)
	return boards - 1
end

-- Player repairs one board. Server-validated by InteractionService (alive, in range).
function BarrierService.Repair(player: Player, barrier: BasePart)
	local boards, max = barrier:GetAttribute("Boards") or 0, barrier:GetAttribute("MaxBoards") or 0
	if boards >= max then
		return
	end
	local n = boards + 1
	local board = boardPart(barrier, n)
	barrier:SetAttribute("Boards", n)
	if board then
		local home = board:GetAttribute("HomeCFrame")
		local inward = (barrier:GetAttribute("Inside") - barrier:GetAttribute("Outside")).Unit
		board.CFrame = home + inward * 1.5
		board.Transparency = 0
		TweenService:Create(board, TweenInfo.new(0.18, Enum.EasingStyle.Back), { CFrame = home }):Play()
	end
	playSound(barrier, "BoardRepair")
	refreshPrompt(barrier)

	-- Points, capped per wave (stops repair-farming)
	local wave = gameState:GetAttribute("Wave") or 0
	if wave ~= earnedWave then
		earnedWave = wave
		table.clear(repairEarned)
	end
	local earned = repairEarned[player] or 0
	if earned < cfg.RepairPointsCapPerWave then
		local amount = cfg.RepairPoints + (n >= max and (cfg.SealBonus or 0) or 0) -- last board: sealed bonus
		amount = math.min(amount, cfg.RepairPointsCapPerWave - earned)
		repairEarned[player] = earned + amount
		CurrencyService.Add(player, amount, n >= max and "Window sealed" or "Repair")
		Remotes.Get("Notify"):FireClient(player, "Sound", { name = "RepairCash" }) -- cha-ching
	end
end

-- Hold-to-repair, position based: while the player HOLDS E (RepairHold remote), the
-- server rebuilds one board every RepairInterval on the nearest damaged window within
-- REPAIR_RANGE of them. Where they look doesn't matter: you can turn around and shoot
-- while repairing. (The old ProximityPrompt hold cancelled when you looked away.)
local REPAIR_RANGE = 9
local repairing = {} -- [Player] = token

local function nearestDamaged(player: Player): BasePart?
	local char = player.Character
	local hum = char and char:FindFirstChildOfClass("Humanoid")
	local root = char and char:FindFirstChild("HumanoidRootPart")
	if not hum or hum.Health <= 0 or not root then
		return nil
	end
	local best, bestD = nil, REPAIR_RANGE
	for _, b in CollectionService:GetTagged("Barrier") do
		if b.Parent and (b:GetAttribute("Boards") or 0) < (b:GetAttribute("MaxBoards") or 0) then
			local d = Vector3.new(root.Position.X - b.Position.X, (root.Position.Y - b.Position.Y) * 0.5, root.Position.Z - b.Position.Z).Magnitude
			if d <= bestD then
				best, bestD = b, d
			end
		end
	end
	return best
end

local function setHolding(player: Player, holding: boolean)
	if not holding then
		repairing[player] = nil
		return
	end
	if repairing[player] then
		return
	end
	local token = {}
	repairing[player] = token
	task.spawn(function()
		while repairing[player] == token and player.Parent do
			task.wait(cfg.RepairInterval)
			if repairing[player] ~= token then
				break
			end
			local barrier = nearestDamaged(player)
			if barrier then
				BarrierService.Repair(player, barrier)
			end
		end
	end)
end

-- Fresh boards on every window (match reset rebuilds the map anyway; this also
-- fixes up barriers that appear later via the tag signal).
local function setup(barrier: BasePart)
	barrier:GetAttributeChangedSignal("Boards"):Connect(function()
		refreshPrompt(barrier)
	end)
	-- InteractionService adds the prompt when it sees the "Interactable" tag; wait for it.
	task.defer(function()
		local prompt = barrier:WaitForChild("ProximityPrompt", 5)
		if not prompt then
			return
		end
		-- The prompt is only a label now ("Hold E"): repairs come from the RepairHold
		-- remote, so the prompt itself must not grab the E key.
		prompt.KeyboardKeyCode = Enum.KeyCode.Unknown
		prompt.GamepadKeyCode = Enum.KeyCode.Unknown
		prompt.ClickablePrompt = false
		prompt.HoldDuration = 0
		prompt.MaxActivationDistance = REPAIR_RANGE
		refreshPrompt(barrier)
	end)
end

function BarrierService.Init()
	gameState = Remotes.GameState()
end

function BarrierService.Start()
	local RemoteGuard = require(script.Parent.Parent.Util.RemoteGuard)
	RemoteGuard.Connect(Remotes.Get("RepairHold"), { rate = 8, burst = 6 }, function(player, holding)
		setHolding(player, holding == true)
	end)
	CollectionService:GetInstanceAddedSignal("Barrier"):Connect(setup)
	for _, b in CollectionService:GetTagged("Barrier") do
		setup(b)
	end
	Players.PlayerRemoving:Connect(function(p)
		repairEarned[p] = nil
		repairing[p] = nil
	end)
end

return BarrierService
