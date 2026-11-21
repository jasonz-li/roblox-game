--!strict
-- Single source of truth for remote names. The server creates them; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"Fire", -- C->S  (origin: Vector3, directions: {Vector3}, claimedParts: {BasePart | false})
	"Reload", -- C->S
	"SwitchWeapon", -- C->S  (slot: number)
	"Melee", -- C->S  (lookDirection: Vector3, claimedEnemyPart: BasePart?)
	"HitConfirm", -- S->C  (isHeadshot, isKill, totalDamage, hits: {{model, pos, damage, head, kill}}, isMelee)
	"ShotFx", -- S->C  (shooter: Player, origin: Vector3, endPos: Vector3)
	"Notify", -- S->C  (kind: string, data: any)
	-- kinds: Points, WaveStart, WaveComplete, GameOver, Message, Sound, PowerUp, DoorOpened,
	--        UpgradeChosen, Shards, StreakMilestone, RunSummary
	"ChooseUpgrade", -- C->S  (index: number)  pick from the current upgrade offer
	"UseAbility", -- C->S  (slot: "Ability" | "Ultimate", aim: Vector3 look direction)
	"SelectHero", -- C->S  (heroId: string)  between waves only (dev picker until the lobby)
	"RepairHold", -- C->S  (holding: boolean)  E held/released: repair the nearest window
	"Throw", -- C->S  (kind: "Frag" | "Lure", aim: Vector3 look direction)
}

local Remotes = {}

local folder: Folder
if RunService:IsServer() then
	folder = ReplicatedStorage:FindFirstChild("Remotes") :: Folder
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in NAMES do
		if not folder:FindFirstChild(name) then
			local remote = Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Remotes.Get(name: string): RemoteEvent
	assert(table.find(NAMES, name), "Unknown remote: " .. name)
	return folder:WaitForChild(name) :: RemoteEvent
end

-- Replicated game state lives as attributes on this folder.
function Remotes.GameState(): Folder
	if RunService:IsServer() then
		local gs = ReplicatedStorage:FindFirstChild("GameState") :: Folder
		if not gs then
			gs = Instance.new("Folder")
			gs.Name = "GameState"
			gs.Parent = ReplicatedStorage
		end
		return gs
	end
	return ReplicatedStorage:WaitForChild("GameState") :: Folder
end

return Remotes
