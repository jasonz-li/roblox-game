--!nonstrict
-- Perks: granted at machines, stored as player attributes (Perk_<Id> = true),
-- lost on death. Effects that live on the server are applied here; fire rate and
-- reload speed are read by WeaponService via PerkConfig helpers.

local PerkConfig = require(game.ReplicatedStorage.Shared.Config.PerkConfig)
local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local PlayerService = require(script.Parent.PlayerService)

local PerkService = {}

local function owned(player: Player): { string }
	local list = {}
	for id in PerkConfig.Perks do
		if player:GetAttribute(PerkConfig.AttributeName(id)) then
			table.insert(list, id)
		end
	end
	return list
end

local function clear(player: Player)
	for id in PerkConfig.Perks do
		player:SetAttribute(PerkConfig.AttributeName(id), nil)
	end
	player:SetAttribute("PerkOrder", "")
end

-- Returns ok, reason
function PerkService.CanGrant(player: Player, perkId: string): (boolean, string?)
	if not PerkConfig.Perks[perkId] then
		return false, "Unknown perk"
	end
	if not PlayerService.IsAlive(player) then
		return false, "You're down"
	end
	if player:GetAttribute(PerkConfig.AttributeName(perkId)) then
		return false, "You already have " .. PerkConfig.Perks[perkId].DisplayName
	end
	if #owned(player) >= PerkConfig.MaxPerks then
		return false, "Perk limit reached (" .. PerkConfig.MaxPerks .. ")"
	end
	return true
end

function PerkService.Grant(player: Player, perkId: string)
	player:SetAttribute(PerkConfig.AttributeName(perkId), true)
	local order = player:GetAttribute("PerkOrder") or ""
	player:SetAttribute("PerkOrder", order == "" and perkId or (order .. "," .. perkId))

	local hum = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	if perkId == "IronBody" then
		hum.MaxHealth = PerkConfig.IronBodyHealth
		hum.Health = PerkConfig.IronBodyHealth
	elseif perkId == "SwiftStep" then
		hum.WalkSpeed = GameConfig.Player.WalkSpeed * PerkConfig.SwiftStepSpeedMult
	end
end

function PerkService.Start()
	PlayerService.CharacterSpawned:Connect(clear)
	PlayerService.PlayerDied:Connect(clear)
end

return PerkService
