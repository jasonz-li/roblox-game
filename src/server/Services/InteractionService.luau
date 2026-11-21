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
local ThrowableService = require(script.Parent.ThrowableService)

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
	local u = WeaponConfig.Upgrade
	local level = w.level or (w.upgraded and 1 or 0)
	if level >= u.MaxLevel then
		return message(player, "Already fully reforged")
	end
	local cost = u.Costs[level + 1]
	if not CurrencyService.TrySpend(player, cost) then
		return notEnough(player, cost)
	end
	WeaponService.UpgradeCurrent(player)
	sound(player, "PerkDrink")
	message(player, (level == 0 and "Forged: " or "Reforged: ") .. WeaponConfig.Get(w.id, level + 1).DisplayName, "good")
end

function handlers.Barrier(_player: Player, _part: BasePart)
	-- Repairs are continuous while E is held (BarrierService hold loop), so the
	-- prompt's Triggered event at the end of the ring does nothing extra.
end
local _ = BarrierService

function handlers.Lure(player: Player, _part: BasePart)
	local ok, msg = ThrowableService.BuyLure(player)
	if ok then
		sound(player, "Purchase")
		message(player, msg, "good")
	else
		message(player, msg)
	end
end

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
		local c = WeaponConfig.Upgrade.Costs
		return "Forge held weapon", c[1] .. " / " .. c[2] .. " / " .. c[3] .. " pts (3 levels)"
	elseif kind == "MysteryBox" then
		return "Mystery Box", cost .. " pts"
	elseif kind == "Lure" then
		return "Buy Maneki Lure", cost .. " pts  •  carry 2  •  throw with T"
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
	if not part:IsA("BasePart") or part:GetAttribute("PromptsBuilt") then
		return
	end
	part:SetAttribute("PromptsBuilt", true)
	local kind = part:GetAttribute("Kind")
	local action, object = promptTexts(part)

	local function onTriggered(player: Player, prompt: ProximityPrompt)
		local now = os.clock()
		if now - (lastUse[player] or 0) < GameConfig.InteractCooldown then
			return
		end
		lastUse[player] = now
		-- A door being opened loses its tag first: stops a second purchase from another prompt
		if not part.Parent or not CollectionService:HasTag(part, "Interactable") then
			return
		end
		if not PlayerService.IsAlive(player) then
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
	end

	local function makePrompt(host: Instance)
		local prompt = Instance.new("ProximityPrompt")
		prompt.ActionText = action
		prompt.ObjectText = object
		prompt.KeyboardKeyCode = Enum.KeyCode.E
		prompt.HoldDuration = kind == "Forge" and 0.4 or 0 -- doors buy instantly now
		prompt.MaxActivationDistance = kind == "Door" and 9 or 8
		prompt.RequiresLineOfSight = false
		prompt.Parent = host
		prompt.Triggered:Connect(function(player)
			onTriggered(player, prompt)
		end)
		return prompt
	end

	if kind == "Door" then
		-- Doors: prompts at chest height (4 studs up), one every ~8 studs along the width,
		-- so you can buy from wherever you stand (only the nearest one shows). A prompt at
		-- the part's center sat 14 studs up on tall doors: narrow gates had only that one
		-- and couldn't be bought.
		local width = math.max(part.Size.X, part.Size.Z)
		local alongX = part.Size.X >= part.Size.Z
		local count = math.max(1, math.floor(width / 8))
		for i = 1, count do
			local offset = -width / 2 + (i - 0.5) * (width / count)
			local att = Instance.new("Attachment")
			att.Name = "PromptPoint"
			att.Position = Vector3.new(alongX and offset or 0, -part.Size.Y / 2 + 4, alongX and 0 or offset)
			att.Parent = part
			makePrompt(att)
		end
	else
		-- Everything else keeps its prompt on the part (other services find it there).
		makePrompt(part)
	end
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
		for _, d in part:GetDescendants() do
			if d:IsA("ProximityPrompt") then
				d:Destroy()
			end
		end
	end)
end

return InteractionService
