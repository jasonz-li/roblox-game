--!nonstrict
-- Turns every part tagged "Interactable" into a ProximityPrompt and handles
-- purchases server-side. ProximityPrompt.Triggered is the only client input here,
-- so there is no custom remote to abuse; we still re-check distance, aliveness,
-- cooldown and cost on the server.

local CollectionService = game:GetService("CollectionService")

local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local WeaponConfig = require(game.ReplicatedStorage.Shared.Config.WeaponConfig)
local PerkConfig = require(game.ReplicatedStorage.Shared.Config.PerkConfig)
local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)
local PlayerService = require(script.Parent.PlayerService)
local CurrencyService = require(script.Parent.CurrencyService)
local WeaponService = require(script.Parent.WeaponService)
local PerkService = require(script.Parent.PerkService)
local MapService = require(script.Parent.MapService)
local MysteryBoxService = require(script.Parent.MysteryBoxService)
local BarrierService = require(script.Parent.BarrierService)

local InteractionService = {}

local notify: RemoteEvent
local lastUse = {} -- [Player] = os.clock()

local function message(player: Player, text: string, tone: string?)
	notify:FireClient(player, "Message", { text = text, tone = tone or "bad" })
	if tone ~= "good" then
		notify:FireClient(player, "Sound", { name = "Denied" })
	end
end

local function sound(player: Player, name: string)
	notify:FireClient(player, "Sound", { name = name })
end

local function notEnough(player: Player, cost: number)
	message(player, "Not enough points (" .. cost .. ")")
end

----------------------------------------------------------------------
-- Handlers: return nothing; they message the player themselves.
----------------------------------------------------------------------

local handlers = {}

function handlers.WallBuy(player: Player, part: BasePart)
	local id = part:GetAttribute("Id")
	local stats = WeaponConfig.Get(id)
	if WeaponService.HasWeapon(player, id) then
		local cost = stats.AmmoCost
		if CurrencyService.Get(player) < cost then
			return notEnough(player, cost)
		end
		if not WeaponService.RefillWeapon(player, id) then
			return message(player, "Ammo already full", "info")
		end
		CurrencyService.TrySpend(player, cost)
		sound(player, "Purchase")
		message(player, stats.DisplayName .. " ammo refilled", "good")
	else
		if not CurrencyService.TrySpend(player, stats.WallCost) then
			return notEnough(player, stats.WallCost)
		end
		WeaponService.GiveWeapon(player, id)
		sound(player, "Purchase")
		message(player, "Bought " .. stats.DisplayName, "good")
	end
end

function handlers.Door(player: Player, part: BasePart)
	local cost = part:GetAttribute("Cost")
	if not CurrencyService.TrySpend(player, cost) then
		return notEnough(player, cost)
	end
	MapService.OpenDoor(part, player)
end

function handlers.Perk(player: Player, part: BasePart)
	local id = part:GetAttribute("Id")
	local ok, reason = PerkService.CanGrant(player, id)
	if not ok then
		return message(player, reason)
	end
	local cost = PerkConfig.Perks[id].Cost
	if not CurrencyService.TrySpend(player, cost) then
		return notEnough(player, cost)
	end
	PerkService.Grant(player, id)
	sound(player, "PerkDrink")
	message(player, PerkConfig.Perks[id].DisplayName .. ": " .. PerkConfig.Perks[id].Description, "good")
end

function handlers.Forge(player: Player, _part: BasePart)
	local w = WeaponService.GetCurrent(player)
	if not w then
		return
	end
	if w.upgraded then
		return message(player, "Already forged")
	end
	local cost = WeaponConfig.Upgrade.Cost
	if not CurrencyService.TrySpend(player, cost) then
		return notEnough(player, cost)
	end
	WeaponService.UpgradeCurrent(player)
	sound(player, "PerkDrink")
	message(player, "Forged: " .. WeaponConfig.Get(w.id, true).DisplayName, "good")
end

function handlers.Barrier(_player: Player, _part: BasePart)
	-- Repairs are continuous while E is held (BarrierService hold loop), so the
	-- prompt's Triggered event at the end of the ring does nothing extra.
end
local _ = BarrierService

function handlers.MysteryBox(player: Player, _part: BasePart)
	local ok, reason = MysteryBoxService.OnTriggered(player)
	if not ok and reason then
		message(player, reason)
	end
end

----------------------------------------------------------------------
-- Prompt wiring
----------------------------------------------------------------------

local function promptTexts(part: BasePart)
	local kind = part:GetAttribute("Kind")
	local title, cost = part:GetAttribute("Title") or "", part:GetAttribute("Cost") or 0
	if kind == "WallBuy" then
		return "Buy " .. title, cost .. " pts  •  ammo " .. tostring(part:GetAttribute("AmmoCost"))
	elseif kind == "Door" then
		return "Open (" .. cost .. ")", title
	elseif kind == "Perk" then
		return "Drink " .. title, cost .. " pts"
	elseif kind == "Forge" then
		return "Forge held weapon", cost .. " pts"
	elseif kind == "MysteryBox" then
		return "Mystery Box", cost .. " pts"
	end
	return title, tostring(cost)
end

local function setPrompt(part: BasePart, action: string?, object: string?, enabled: boolean?)
	local prompt = part:FindFirstChildOfClass("ProximityPrompt")
	if not prompt then
		return
	end
	if action then
		prompt.ActionText = action
	end
	if object then
		prompt.ObjectText = object
	end
	if enabled ~= nil then
		prompt.Enabled = enabled
	end
end

local function onInteractable(part: Instance)
	if not part:IsA("BasePart") or part:FindFirstChildOfClass("ProximityPrompt") then
		return
	end
	local kind = part:GetAttribute("Kind")
	local prompt = Instance.new("ProximityPrompt")
	local action, object = promptTexts(part)
	prompt.ActionText = action
	prompt.ObjectText = object
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.HoldDuration = (kind == "Door" or kind == "Forge") and 0.4 or 0
	prompt.MaxActivationDistance = kind == "Door" and 11 or 8
	prompt.RequiresLineOfSight = false
	prompt.Parent = part

	prompt.Triggered:Connect(function(player: Player)
		local now = os.clock()
		if now - (lastUse[player] or 0) < GameConfig.InteractCooldown then
			return
		end
		lastUse[player] = now
		if not PlayerService.IsAlive(player) or not part.Parent then
			return
		end
		local root = player.Character.HumanoidRootPart
		-- Distance to the part's surface (parts can be wide, e.g. doors)
		local closest = part.CFrame:PointToWorldSpace(part.CFrame:PointToObjectSpace(root.Position):Max(-part.Size / 2):Min(part.Size / 2))
		if (closest - root.Position).Magnitude > prompt.MaxActivationDistance + 4 then
			return
		end
		local handler = handlers[kind]
		if handler then
			handler(player, part)
		end
	end)
end

function InteractionService.Init()
	notify = Remotes.Get("Notify")
	MysteryBoxService.SetPromptSetter(setPrompt)
end

function InteractionService.Start()
	CollectionService:GetInstanceAddedSignal("Interactable"):Connect(onInteractable)
	for _, part in CollectionService:GetTagged("Interactable") do
		onInteractable(part)
	end
	CollectionService:GetInstanceRemovedSignal("Interactable"):Connect(function(part)
		local prompt = part:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt:Destroy()
		end
	end)
end

return InteractionService
