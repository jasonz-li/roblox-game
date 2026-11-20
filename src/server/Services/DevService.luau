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
		elseif cmd == "killall" then
			EnemyService.KillAll()
			return "killed all"
		elseif cmd == "wave" then
			return WaveService.DevSetWave(tonumber(a) or 1)
		end
		return "unknown command"
	end
	fn.Parent = ServerStorage
end

return DevService
