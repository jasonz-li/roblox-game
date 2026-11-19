--!nonstrict
-- Server-authoritative weapons: 2-slot inventory, switching, ammo, reload,
-- fire-rate limits, hit validation (incl. shotgun pellets and piercing), damage,
-- Spirit Forge upgrades. See docs/TECHNICAL_ARCHITECTURE.md §3.
--
-- Replicated player attributes:
--   WeaponId, WeaponUpgraded, Ammo, Reserve, Reloading      (current weapon)
--   CurrentSlot, Slot1, Slot2, Slot1Up, Slot2Up              (inventory, "" = empty)

local Players = game:GetService("Players")

local WeaponConfig = require(game.ReplicatedStorage.Shared.Config.WeaponConfig)
local PerkConfig = require(game.ReplicatedStorage.Shared.Config.PerkConfig)
local GameConfig = require(game.ReplicatedStorage.Shared.Config.GameConfig)
local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)
local RemoteGuard = require(script.Parent.Parent.Util.RemoteGuard)
local PlayerService = require(script.Parent.PlayerService)
local EnemyService = require(script.Parent.EnemyService)
local CurrencyService = require(script.Parent.CurrencyService)
local MapService = require(script.Parent.MapService)

local WeaponService = {}

local MAX_ORIGIN_OFFSET = 10 -- studs between claimed origin and server-side head
local HIT_TOLERANCE = 6 -- studs a claimed hit may be off the ray (latency allowance)
local PIERCE_FALLOFF = 0.8

local inventories = {} -- [Player] = { slots = {weapon...}, current = 1, switchUntil = 0, generation = n }
local hitConfirm: RemoteEvent
local shotFx: RemoteEvent
local gameState: Folder

----------------------------------------------------------------------
-- Inventory helpers
----------------------------------------------------------------------

local function newWeapon(id: string, upgraded: boolean?)
	local stats = WeaponConfig.Get(id, upgraded)
	return {
		id = id,
		upgraded = upgraded == true,
		stats = stats,
		mag = stats.MagSize,
		reserve = stats.ReserveAmmo,
		reloading = false,
		reloadToken = 0,
		lastShot = 0,
		recentShots = {},
	}
end

local function current(player)
	local inv = inventories[player]
	return inv and inv.slots[inv.current], inv
end

local function sync(player)
	local inv = inventories[player]
	if not inv then
		return
	end
	local w = inv.slots[inv.current]
	player:SetAttribute("WeaponId", w.id)
	player:SetAttribute("WeaponUpgraded", w.upgraded)
	player:SetAttribute("Ammo", w.mag)
	player:SetAttribute("Reserve", w.reserve)
	player:SetAttribute("Reloading", w.reloading)
	player:SetAttribute("CurrentSlot", inv.current)
	for i = 1, WeaponConfig.MaxSlots do
		local s = inv.slots[i]
		player:SetAttribute("Slot" .. i, s and s.id or "")
		player:SetAttribute("Slot" .. i .. "Up", s and s.upgraded or false)
	end
end

local function cancelReload(w)
	w.reloading = false
	w.reloadToken += 1
end

local function resetInventory(player)
	local prev = inventories[player]
	inventories[player] = {
		slots = { newWeapon(WeaponConfig.Default) },
		current = 1,
		switchUntil = 0,
		generation = (prev and prev.generation or 0) + 1,
	}
	sync(player)
end

----------------------------------------------------------------------
-- Validation helpers
----------------------------------------------------------------------

local function isFiniteVector(v)
	return typeof(v) == "Vector3"
		and v.X == v.X and v.Y == v.Y and v.Z == v.Z
		and math.abs(v.X) < 1e6 and math.abs(v.Y) < 1e6 and math.abs(v.Z) < 1e6
end

-- Fire-rate budget: tolerate network bunching, reject speed hacks.
local function passesRateLimit(player, w, now): boolean
	local rpm = w.stats.RPM * PerkConfig.RpmMultiplier(player)
	local interval = 60 / rpm
	if now - w.lastShot < interval * 0.5 then
		return false
	end
	local shots = w.recentShots
	local i = 1
	while i <= #shots do
		if now - shots[i] > 1 then
			table.remove(shots, i)
		else
			i += 1
		end
	end
	if #shots >= math.ceil((rpm / 60) * 1.25) + 1 then
		return false
	end
	table.insert(shots, now)
	w.lastShot = now
	return true
end

local function characterList()
	local list = {}
	for _, p in Players:GetPlayers() do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

local function claimIsValid(origin, direction, range, claimedPart)
	if typeof(claimedPart) ~= "Instance" or not claimedPart:IsA("BasePart") then
		return nil
	end
	local enemy = EnemyService.GetEnemyFromPart(claimedPart)
	if not enemy then
		return nil
	end
	local toPart = claimedPart.Position - origin
	local along = toPart:Dot(direction)
	if along <= 0 or along > range then
		return nil
	end
	if (toPart - direction * along).Magnitude > HIT_TOLERANCE then
		return nil
	end
	local mapParams = RaycastParams.new()
	mapParams.FilterType = Enum.RaycastFilterType.Include
	mapParams.FilterDescendantsInstances = { MapService.GetMapFolder() }
	if workspace:Raycast(origin, direction * along, mapParams) then
		return nil
	end
	return enemy, origin + direction * along
end

-- Returns list of { enemy, part, index } (index = how many enemies it already passed through) and the end position.
local function traceBullet(origin, direction, range, pierce, claimedPart)
	local hits = {}
	local exclude = characterList()
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local endPos = origin + direction * range
	for i = 0, pierce do
		params.FilterDescendantsInstances = exclude
		local result = workspace:Raycast(origin, direction * range, params)
		if not result then
			break
		end
		endPos = result.Position
		local enemy = EnemyService.GetEnemyFromPart(result.Instance)
		if not enemy then
			break
		end
		table.insert(hits, { enemy = enemy, part = result.Instance, index = i, pos = result.Position })
		table.insert(exclude, enemy.model)
	end
	if #hits == 0 and claimedPart then
		local enemy, pos = claimIsValid(origin, direction, range, claimedPart)
		if enemy then
			table.insert(hits, { enemy = enemy, part = claimedPart, index = 0, pos = pos })
			endPos = pos
		end
	end
	return hits, endPos
end

----------------------------------------------------------------------
-- Remote handlers
----------------------------------------------------------------------

local function onFire(player: Player, origin, directions, claims)
	if not isFiniteVector(origin) or typeof(directions) ~= "table" then
		return
	end
	local w, inv = current(player)
	if not w or w.reloading or w.mag <= 0 or os.clock() < inv.switchUntil then
		return
	end
	local stats = w.stats
	local n = #directions
	if n < 1 or n > stats.Pellets then
		return
	end
	local dirs = {}
	local mean = Vector3.zero
	for i = 1, n do
		local d = directions[i]
		if not isFiniteVector(d) or d.Magnitude < 0.9 or d.Magnitude > 1.1 then
			return
		end
		dirs[i] = d.Unit
		mean += dirs[i]
	end
	if n > 1 then
		mean = mean.Unit
		local maxAngle = math.rad(stats.HipSpread * 1.8 + 3)
		for _, d in dirs do
			if math.acos(math.clamp(d:Dot(mean), -1, 1)) > maxAngle then
				return
			end
		end
	end
	if typeof(claims) ~= "table" then
		claims = {}
	end

	if not PlayerService.IsAlive(player) then
		return
	end
	local head = player.Character:FindFirstChild("Head")
	if not head or (head.Position - origin).Magnitude > MAX_ORIGIN_OFFSET then
		return
	end
	if not passesRateLimit(player, w, os.clock()) then
		return
	end

	w.mag -= 1
	player:SetAttribute("Ammo", w.mag)

	local instaKill = workspace:GetServerTimeNow() < (gameState:GetAttribute("InstaKillUntil") or 0)
	local hitEnemies, anyHead, anyKill, total = {}, false, false, 0
	local report = {} -- per-hit info for the shooter's damage numbers / flashes
	local firstEnd

	for i, dir in dirs do
		local claimed = claims[i]
		if claimed == false then
			claimed = nil
		end
		local hits, endPos = traceBullet(origin, dir, stats.Range, stats.Pierce, claimed)
		firstEnd = firstEnd or endPos
		for _, h in hits do
			local isHead = h.part.Name == "Head"
			local damage = stats.Damage * (isHead and stats.HeadshotMultiplier or 1) * (PIERCE_FALLOFF ^ h.index)
			if instaKill then
				damage = h.enemy.humanoid.Health
			end
			local model = h.enemy.model
			local killed = EnemyService.Damage(h.enemy, damage, player, isHead, dir)
			total += damage
			if #report < 12 then
				table.insert(report, { model, h.pos, math.floor(damage + 0.5), isHead, killed })
			end
			if not hitEnemies[h.enemy] then
				hitEnemies[h.enemy] = true
				CurrencyService.Add(player, GameConfig.Points.Hit, nil, true)
			end
			anyHead = anyHead or isHead
			if killed then
				anyKill = true
				CurrencyService.AddKill(player)
				CurrencyService.Add(player, isHead and GameConfig.Points.HeadshotKill or GameConfig.Points.Kill, isHead and "Headshot" or "Kill", true)
			end
		end
	end

	for _, other in Players:GetPlayers() do
		if other ~= player then
			shotFx:FireClient(other, player, origin, firstEnd, w.id, w.upgraded)
		end
	end
	if next(hitEnemies) then
		hitConfirm:FireClient(player, anyHead, anyKill, total, report, false)
	end
end

-- Knife: server picks the target from the player's real position (claim only breaks ties).
local lastMelee = {}
local function onMelee(player: Player, lookDir, claimedPart)
	local cfg = GameConfig.Melee
	if not isFiniteVector(lookDir) or lookDir.Magnitude < 0.5 then
		return
	end
	lookDir = lookDir.Unit
	local now = os.clock()
	if now - (lastMelee[player] or 0) < cfg.Cooldown * 0.8 then
		return
	end
	if not PlayerService.IsAlive(player) then
		return
	end
	lastMelee[player] = now
	local w = current(player)
	if w and w.reloading then
		cancelReload(w)
		sync(player)
	end

	local head = player.Character:FindFirstChild("Head")
	if not head then
		return
	end
	local claimedEnemy = typeof(claimedPart) == "Instance" and EnemyService.GetEnemyFromPart(claimedPart)
	local best, bestScore = nil, math.huge
	for _, model in EnemyService.GetFolder():GetChildren() do
		local enemy = model.PrimaryPart and EnemyService.GetEnemyFromPart(model.PrimaryPart)
		if enemy then
			local to = enemy.root.Position - head.Position
			local dist = to.Magnitude
			-- +2 studs latency tolerance; must be roughly in front
			if dist <= cfg.Range + 2 and (dist < 2.5 or to.Unit:Dot(lookDir) > 0.3) then
				local score = dist - (enemy == claimedEnemy and 3 or 0)
				if score < bestScore then
					best, bestScore = enemy, score
				end
			end
		end
	end
	if not best then
		return
	end
	local instaKill = workspace:GetServerTimeNow() < (gameState:GetAttribute("InstaKillUntil") or 0)
	local damage = instaKill and best.humanoid.Health or cfg.Damage
	local model, pos = best.model, best.root.Position + Vector3.new(0, 1, 0)
	local killed = EnemyService.Damage(best, damage, player, false, lookDir)
	CurrencyService.Add(player, GameConfig.Points.Hit, nil, true)
	if killed then
		CurrencyService.AddKill(player)
		CurrencyService.Add(player, cfg.KillPoints, "Knife", true)
	end
	hitConfirm:FireClient(player, false, killed, damage, { { model, pos, math.floor(damage), false, killed } }, true)
end

function WeaponService.CancelReload(player: Player)
	local w = current(player)
	if w and w.reloading then
		cancelReload(w)
		sync(player)
	end
end

local function onReload(player: Player)
	local w, inv = current(player)
	if not w or w.reloading or not PlayerService.IsAlive(player) or os.clock() < inv.switchUntil then
		return
	end
	if w.mag >= w.stats.MagSize or w.reserve <= 0 then
		return
	end
	w.reloading = true
	w.reloadToken += 1
	local token, generation = w.reloadToken, inv.generation
	player:SetAttribute("Reloading", true)

	task.delay(w.stats.ReloadTime * PerkConfig.ReloadMultiplier(player), function()
		local inv2 = inventories[player]
		if not inv2 or inv2.generation ~= generation or w.reloadToken ~= token or not w.reloading then
			return
		end
		if PlayerService.IsAlive(player) then
			local take = math.min(w.stats.MagSize - w.mag, w.reserve)
			w.mag += take
			w.reserve -= take
		end
		w.reloading = false
		sync(player)
	end)
end

local function onSwitch(player: Player, slot)
	if typeof(slot) ~= "number" or slot ~= math.floor(slot) then
		return
	end
	local inv = inventories[player]
	if not inv or not inv.slots[slot] or inv.current == slot or not PlayerService.IsAlive(player) then
		return
	end
	cancelReload(inv.slots[inv.current])
	inv.current = slot
	inv.switchUntil = os.clock() + WeaponConfig.SwitchTime * 0.8 -- small server-side tolerance
	sync(player)
end

----------------------------------------------------------------------
-- Public API (purchases, power-ups)
----------------------------------------------------------------------

function WeaponService.HasWeapon(player: Player, id: string): boolean
	local inv = inventories[player]
	if not inv then
		return false
	end
	for _, w in inv.slots do
		if w.id == id then
			return true
		end
	end
	return false
end

function WeaponService.GetCurrent(player: Player)
	local w = current(player)
	return w
end

-- Adds to an empty slot, otherwise replaces the weapon in hand.
function WeaponService.GiveWeapon(player: Player, id: string, upgraded: boolean?): boolean
	local inv = inventories[player]
	if not inv or not WeaponConfig.Get(id) or WeaponService.HasWeapon(player, id) then
		return false
	end
	cancelReload(inv.slots[inv.current])
	local slot = #inv.slots < WeaponConfig.MaxSlots and #inv.slots + 1 or inv.current
	inv.slots[slot] = newWeapon(id, upgraded)
	inv.current = slot
	inv.switchUntil = os.clock() + WeaponConfig.SwitchTime * 0.8
	sync(player)
	return true
end

-- Wall-buy ammo. Returns false if that weapon is already full.
function WeaponService.RefillWeapon(player: Player, id: string): boolean
	local inv = inventories[player]
	if not inv then
		return false
	end
	for _, w in inv.slots do
		if w.id == id then
			if w.reserve >= w.stats.ReserveAmmo and w.mag >= w.stats.MagSize then
				return false
			end
			cancelReload(w)
			w.mag = w.stats.MagSize
			w.reserve = w.stats.ReserveAmmo
			sync(player)
			return true
		end
	end
	return false
end

-- Spirit Forge. Returns ok, reason.
function WeaponService.UpgradeCurrent(player: Player): (boolean, string?)
	local w, inv = current(player)
	if not w then
		return false, "No weapon"
	end
	if w.upgraded then
		return false, "Already forged"
	end
	inv.slots[inv.current] = newWeapon(w.id, true)
	sync(player)
	return true
end

-- Max Ammo power-up: full reserve for every weapon of every player.
function WeaponService.RefillAll()
	for player, inv in inventories do
		for _, w in inv.slots do
			w.reserve = w.stats.ReserveAmmo
		end
		sync(player)
	end
end

function WeaponService.Init()
	hitConfirm = Remotes.Get("HitConfirm")
	shotFx = Remotes.Get("ShotFx")
	gameState = Remotes.GameState()
end

function WeaponService.Start()
	RemoteGuard.Connect(Remotes.Get("Fire"), { rate = 25, burst = 10 }, onFire)
	RemoteGuard.Connect(Remotes.Get("Reload"), { rate = 4, burst = 3 }, onReload)
	RemoteGuard.Connect(Remotes.Get("SwitchWeapon"), { rate = 8, burst = 4 }, onSwitch)
	RemoteGuard.Connect(Remotes.Get("Melee"), { rate = 3, burst = 2 }, onMelee)

	-- Fresh loadout (starting pistol) every time a character spawns.
	PlayerService.CharacterSpawned:Connect(resetInventory)
	Players.PlayerRemoving:Connect(function(player)
		inventories[player] = nil
		lastMelee[player] = nil
	end)
end

return WeaponService
