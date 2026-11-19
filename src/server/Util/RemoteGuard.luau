--!nonstrict
-- Token-bucket rate limiting + error isolation for RemoteEvent handlers.
-- Excess calls are silently dropped. Handler errors are logged, not propagated.
--
--   RemoteGuard.Connect(remote, { rate = 10, burst = 5 }, function(player, ...) end)

local Players = game:GetService("Players")

local RemoteGuard = {}

local dropped = {} -- [remoteName] = count (for debugging/telemetry)

function RemoteGuard.Connect(remote: RemoteEvent, opts: { rate: number, burst: number }, handler)
	local buckets = {}
	Players.PlayerRemoving:Connect(function(p)
		buckets[p] = nil
	end)
	return remote.OnServerEvent:Connect(function(player, ...)
		local now = os.clock()
		local b = buckets[player]
		if not b then
			b = { tokens = opts.burst, t = now }
			buckets[player] = b
		end
		b.tokens = math.min(opts.burst, b.tokens + (now - b.t) * opts.rate)
		b.t = now
		if b.tokens < 1 then
			dropped[remote.Name] = (dropped[remote.Name] or 0) + 1
			return
		end
		b.tokens -= 1
		local ok, err = pcall(handler, player, ...)
		if not ok then
			warn(("[RemoteGuard] %s handler error from %s: %s"):format(remote.Name, player.Name, tostring(err)))
		end
	end)
end

function RemoteGuard.GetDropped()
	return dropped
end

return RemoteGuard
