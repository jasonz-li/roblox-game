--!nonstrict
-- Server bootstrap: require every service, then Init() all, then Start() all.
-- Order matters only for Init; Start runs after everything is initialized.

local Services = script:WaitForChild("Services")

local ORDER = {
	"MapService",
	"CurrencyService",
	"PlayerService",
	"EnemyService",
	"WeaponService",
	"PerkService",
	"MysteryBoxService",
	"PowerUpService",
	"InteractionService",
	"WaveService",
}

local loaded = {}
for _, name in ORDER do
	loaded[name] = require(Services:WaitForChild(name))
end

for _, name in ORDER do
	local service = loaded[name]
	if service.Init then
		service.Init()
	end
end

for _, name in ORDER do
	local service = loaded[name]
	if service.Start then
		service.Start()
	end
end

print("[Server] Started", #ORDER, "services")
