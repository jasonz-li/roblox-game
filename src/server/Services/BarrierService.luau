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
	prompt.ActionText = "Repair window"
	prompt.ObjectText = string.format("%d / %d boards", boards, max)
	prompt.HoldDuration = cfg.RepairHold
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
		local amount = math.min(cfg.RepairPoints, cfg.RepairPointsCapPerWave - earned)
		repairEarned[player] = earned + amount
		CurrencyService.Add(player, amount, "Repair")
	end
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
		if prompt then
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.MaxActivationDistance = 7
			refreshPrompt(barrier)
		end
	end)
end

function BarrierService.Init()
	gameState = Remotes.GameState()
end

function BarrierService.Start()
	CollectionService:GetInstanceAddedSignal("Barrier"):Connect(setup)
	for _, b in CollectionService:GetTagged("Barrier") do
		setup(b)
	end
	Players.PlayerRemoving:Connect(function(p)
		repairEarned[p] = nil
	end)
end

return BarrierService
