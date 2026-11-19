--!strict
-- Single source of truth for remote names. The server creates them; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local NAMES = {
	"Fire", -- C->S  (origin: Vector3, direction: Vector3, claimedPart: BasePart?)
	"Reload", -- C->S
	"HitConfirm", -- S->C  (isHeadshot: boolean, isKill: boolean, damage: number)
	"ShotFx", -- S->C  (shooter: Player, origin: Vector3, endPos: Vector3)
	"Notify", -- S->C  (kind: string, data: any)
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
