--!nonstrict
-- STUDIO-ONLY test hook. Creates ServerStorage.Dev (a BindableFunction) so test
-- scripts can drive the LIVE services (scripts run from the command bar get a fresh,
-- uninitialized copy of every module). Never created in a live server.
--
--   Dev:Invoke("boss")                       spawn the Dust Titan near player 1
--   Dev:Invoke("give", "Pistol", true)       give player 1 a weapon (true = Forge upgraded)
--   Dev:Invoke("points", 5000)               add points to player 1
--   Dev:Invoke("wave", 9)                    next wave started will be this number

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local DevService = {}

function DevService.Start()
	if not RunService:IsStudio() then
		return
	end
	local EnemyService = require(script.Parent.EnemyService)
	local WeaponService = require(script.Parent.WeaponService)
	local CurrencyService = require(script.Parent.CurrencyService)
	local WaveService = require(script.Parent.WaveService)

	local old = ServerStorage:FindFirstChild("Dev")
	if old then
		old:Destroy()
	end
	local fn = Instance.new("BindableFunction")
	fn.Name = "Dev"
	fn.OnInvoke = function(cmd, a, b)
		local p = Players:GetPlayers()[1]
		if cmd == "boss" then
			local root = p and p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			local pos = root and (root.Position + root.CFrame.LookVector * 30 - Vector3.new(0, 3, 0)) or Vector3.zero
			EnemyService.SpawnBoss(10, #Players:GetPlayers(), Vector3.new(pos.X, 0, pos.Z))
			return "boss spawned"
		elseif cmd == "give" and p then
			if WeaponService.HasWeapon(p, a) and b then
				WeaponService.UpgradeCurrent(p)
				return "upgraded current"
			end
			WeaponService.GiveWeapon(p, a, b == true)
			return "given " .. tostring(a)
		elseif cmd == "points" and p then
			CurrencyService.Add(p, tonumber(a) or 0, "Dev")
			return "points"
		elseif cmd == "spawnprobe" and p then
			-- move player 1 to `a` (Vector3) and sample where the next 40 zombies would come from
			local MapService = require(script.Parent.MapService)
			local root = p.Character and p.Character:FindFirstChild("HumanoidRootPart")
			if root and typeof(a) == "Vector3" then
				root.CFrame = CFrame.new(a)
				task.wait(0.3)
			end
			local windows, ground, sumDist, maxDist = 0, 0, 0, 0
			local here = root and root.Position or Vector3.zero
			for _ = 1, 40 do
				local info = MapService.GetEnemySpawn()
				if info then
					if info.barrier then
						windows += 1
					else
						ground += 1
					end
					local flat = Vector3.new(info.pos.X - here.X, 0, info.pos.Z - here.Z).Magnitude + math.abs(info.pos.Y - here.Y) * 6
					sumDist += flat
					maxDist = math.max(maxDist, flat)
				end
			end
			return string.format("windows=%d ground=%d avgWalkDist=%.0f maxWalkDist=%.0f", windows, ground, sumDist / 40, maxDist)
		elseif cmd == "opendoors" then
			local MapService = require(script.Parent.MapService)
			local n = 0
			for _, d in game:GetService("CollectionService"):GetTagged("Interactable") do
				if d:GetAttribute("Kind") == "Door" then
					MapService.OpenDoor(d, nil, true)
					n += 1
				end
			end
			return "opened " .. n
		elseif cmd == "raid" then
			-- jump straight into the Titan encounter (testing). `a` = power multiplier.
			local BossService = require(script.Parent.BossService)
			task.spawn(BossService.Run, 10, tonumber(a) or 1, function()
				return false
			end)
			return "raid started"
		elseif cmd == "bosshp" then
			-- set the Titan's health fraction (testing phase changes), e.g. 0.6
			for _, m in game:GetService("CollectionService"):GetTagged("Enemy") do
				if m:GetAttribute("Boss") then
					local h = m:FindFirstChildOfClass("Humanoid")
					h.Health = h.MaxHealth * (tonumber(a) or 1)
				end
			end
			return "boss hp set"
		elseif cmd == "killall" then
			EnemyService.KillAll(true)
			return "killed all"
		elseif cmd == "wave" then
			return WaveService.DevSetWave(tonumber(a) or 1)
		end
		return "unknown command"
	end
	fn.Parent = ServerStorage
end

return DevService
