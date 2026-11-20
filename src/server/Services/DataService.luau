--!nonstrict
-- Persistent player data (Milestone 7 foundation). DataStoreService with:
--   * session locking via UpdateAsync ({ job = JobId, at = os.time() })
--   * autosave every AUTOSAVE seconds, save on leave and on server shutdown
--   * retries with backoff, versioned schema (v) with defaults/migrations
-- If DataStores are unavailable (Studio without "Enable Studio Access to API
-- Services", or an outage) it runs in memory: everything works, nothing is saved.
--
-- Replicated player attributes: Shards, BestStreak, BestWave, DataSaved (bool)

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Remotes = require(game.ReplicatedStorage.Shared.Net.Remotes)

local DataService = {}

local STORE_NAME = "PlayerData_v1"
local SCHEMA = 1
local AUTOSAVE = 90
local LOCK_TIMEOUT = 600 -- a lock older than this is from a crashed server
local RETRIES = 5

local store
local online = false
local profiles = {} -- [Player] = data table
local runShards = {} -- [Player] = shards earned this run
local notify: RemoteEvent

local function defaults()
	return {
		v = SCHEMA,
		Shards = 0, -- Spirit Shards: earnable-only summon currency (gacha = Milestone 8)
		LifetimeShards = 0,
		BestStreak = 0,
		BestWave = 0,
		Kills = 0,
		Runs = 0,
	}
end

local function migrate(data)
	local d = defaults()
	for k, v in data do
		d[k] = v -- keep saved values, fill new fields with defaults
	end
	d.v = SCHEMA
	return d
end

local function keyFor(player)
	return "u_" .. player.UserId
end

local function retry(fn)
	local delay = 1
	for attempt = 1, RETRIES do
		local ok, a, b = pcall(fn)
		if ok then
			return true, a, b
		end
		if attempt == RETRIES then
			return false, a
		end
		task.wait(delay)
		delay *= 2
	end
end

local function publish(player)
	local d = profiles[player]
	if not d then
		return
	end
	player:SetAttribute("Shards", d.Shards)
	player:SetAttribute("BestStreak", d.BestStreak)
	player:SetAttribute("BestWave", d.BestWave)
	player:SetAttribute("DataSaved", online)
end

local function load(player)
	if not online then
		profiles[player] = defaults()
		publish(player)
		return
	end
	local lockedOut = false
	local ok, result = retry(function()
		return store:UpdateAsync(keyFor(player), function(old)
			if old and old.lock and old.lock.job ~= game.JobId and os.time() - (old.lock.at or 0) < LOCK_TIMEOUT then
				lockedOut = true
				return nil -- another server owns this profile: don't write
			end
			local data = old and migrate(old) or defaults()
			data.lock = { job = game.JobId, at = os.time() }
			return data
		end)
	end)
	if not player.Parent then
		return
	end
	if not ok or lockedOut or not result then
		warn("[DataService] Could not load data for", player.Name, lockedOut and "(session locked elsewhere)" or tostring(result), "- running unsaved this session")
		profiles[player] = defaults()
		profiles[player].unsaved = true
	else
		profiles[player] = result
	end
	publish(player)
end

local function save(player, release: boolean)
	local d = profiles[player]
	if not online or not d or d.unsaved then
		return
	end
	local snapshot = table.clone(d)
	snapshot.lock = nil
	retry(function()
		return store:UpdateAsync(keyFor(player), function(old)
			if old and old.lock and old.lock.job ~= game.JobId and os.time() - (old.lock.at or 0) < LOCK_TIMEOUT then
				return nil -- lost the lock: never overwrite another server's session
			end
			local data = migrate(snapshot)
			data.lock = not release and { job = game.JobId, at = os.time() } or nil
			return data
		end)
	end)
end

----------------------------------------------------------------------
-- Public API (server only)
----------------------------------------------------------------------

function DataService.Get(player: Player)
	return profiles[player]
end

-- Award Spirit Shards. `reason` is shown to the player.
function DataService.AddShards(player: Player, amount: number, reason: string?)
	local d = profiles[player]
	if not d or amount <= 0 then
		return
	end
	amount = math.floor(amount)
	d.Shards += amount
	d.LifetimeShards += amount
	runShards[player] = (runShards[player] or 0) + amount
	publish(player)
	notify:FireClient(player, "Shards", { amount = amount, reason = reason, total = d.Shards })
end

function DataService.RecordStreak(player: Player, streak: number): boolean
	local d = profiles[player]
	if d and streak > d.BestStreak then
		d.BestStreak = streak
		publish(player)
		return true
	end
	return false
end

function DataService.AddKill(player: Player)
	local d = profiles[player]
	if d then
		d.Kills += 1
	end
end

function DataService.StartRun()
	table.clear(runShards)
end

-- Called at game over: wave rewards, records, then a summary to each player.
function DataService.EndRun(finalWave: number, shardsPerWave: number)
	for _, player in Players:GetPlayers() do
		local d = profiles[player]
		if d then
			local survived = math.max(0, finalWave - 1)
			if survived > 0 then
				DataService.AddShards(player, survived * shardsPerWave, "Waves survived")
			end
			d.Runs += 1
			local newBestWave = finalWave > d.BestWave
			if newBestWave then
				d.BestWave = finalWave
			end
			publish(player)
			notify:FireClient(player, "RunSummary", {
				shards = runShards[player] or 0,
				total = d.Shards,
				bestStreak = d.BestStreak,
				runStreak = player:GetAttribute("RunBestStreak") or 0,
				newBestWave = newBestWave,
				saved = online and not d.unsaved,
			})
			task.spawn(save, player, false)
		end
	end
end

----------------------------------------------------------------------
-- Lifecycle
----------------------------------------------------------------------

function DataService.Init()
	notify = Remotes.Get("Notify")
	local ok, err = pcall(function()
		store = DataStoreService:GetDataStore(STORE_NAME)
		store:GetAsync("__probe") -- fails fast if API access is off
	end)
	online = ok
	if not ok then
		warn("[DataService] DataStores unavailable (" .. tostring(err) .. "). Progress will NOT be saved. In Studio: Game Settings > Security > Enable Studio Access to API Services.")
	end
end

function DataService.Start()
	Players.PlayerAdded:Connect(load)
	for _, p in Players:GetPlayers() do
		task.spawn(load, p)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player, true)
		profiles[player] = nil
		runShards[player] = nil
	end)
	game:BindToClose(function()
		if RunService:IsStudio() and not online then
			return
		end
		local pending = 0
		for _, player in Players:GetPlayers() do
			pending += 1
			task.spawn(function()
				save(player, true)
				pending -= 1
			end)
		end
		local t = os.clock()
		while pending > 0 and os.clock() - t < 25 do
			task.wait(0.1)
		end
	end)
	task.spawn(function()
		while true do
			task.wait(AUTOSAVE)
			for _, player in Players:GetPlayers() do
				task.spawn(save, player, false)
			end
		end
	end)
end

return DataService
