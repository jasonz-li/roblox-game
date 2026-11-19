# Anime FPS Zombies Roguelite (working title)

A 1–4 player co-op first-person survival shooter for Roblox. You play as
collectible anime heroes, fight endless waves, and stack roguelite upgrades.

- Design: [docs/GAME_DESIGN.md](docs/GAME_DESIGN.md)
- Architecture: [docs/TECHNICAL_ARCHITECTURE.md](docs/TECHNICAL_ARCHITECTURE.md)
- Roadmap and status: [docs/ROADMAP.md](docs/ROADMAP.md)

## Running it

1. Run `rojo serve` in this folder.
2. In Roblox Studio, open the place and click **Rojo → Connect**.
3. Press **Play**.

Controls: **LMB** fire · **RMB** aim · **R** reload · **Shift** sprint.

If Studio stops picking up file changes, click Disconnect and then Connect in
the Rojo plugin.

## Tooling

Rojo is pinned in `rokit.toml` (install with [Rokit](https://github.com/rojo-rbx/rokit)).
To build a standalone place file: `rojo build -o roblox-game.rbxl`.
