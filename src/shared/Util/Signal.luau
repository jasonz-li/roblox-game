--!nonstrict
-- Minimal signal for server/client module communication (not networked).

local Signal = {}
Signal.__index = Signal

export type Connection = { Disconnect: (self: Connection) -> () }

function Signal.new()
	return setmetatable({ _handlers = {} :: { [any]: (...any) -> () } }, Signal)
end

function Signal:Connect(fn: (...any) -> ())
	local key = {}
	self._handlers[key] = fn
	return {
		Disconnect = function()
			self._handlers[key] = nil
		end,
	}
end

function Signal:Fire(...: any)
	for _, fn in self._handlers do
		task.spawn(fn, ...)
	end
end

return Signal
