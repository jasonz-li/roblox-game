--!nonstrict
-- Client bootstrap: require every controller, then Init() all, then Start() all.

local Controllers = script:WaitForChild("Controllers")

local ORDER = {
	"CameraController",
	"EffectsController",
	"SoundController",
	"HudController",
	"ProgressionController",
	"MinimapController",
	"WeaponController",
}

local loaded = {}
for _, name in ORDER do
	loaded[name] = require(Controllers:WaitForChild(name))
end

for _, name in ORDER do
	local controller = loaded[name]
	if controller.Init then
		controller.Init()
	end
end

for _, name in ORDER do
	local controller = loaded[name]
	if controller.Start then
		controller.Start()
	end
end

print("[Client] Started", #ORDER, "controllers")
