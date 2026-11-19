# Technical Architecture

## 1. Principles

1. **The server is the authority.** Clients send *intent* ("I fired along this
   ray", "I want to reload", "I want to buy door 3"). The server checks it,
   applies it, and replicates the result. Clients never set health, points,
   ammo, pity, or inventory.
2. **One entry script per side.** `Server` (Script) and `Client` (LocalScript)
   load modules in a fixed order. No scattered `Script` objects inside parts.
3. **Services and controllers.** Server modules are *Services* and client
   modules are *Controllers*. Each exposes optional `Init()` (set up state, no
   cross-calls) and `Start()` (connect events, start loops). The bootstrap calls
   every `Init` first, then every `Start`.
4. **Config is data.** Weapon, enemy, wave, and economy numbers live in
   `Shared/Config/*`, so balancing doesn't mean touching logic.
5. **Feedback is predicted, outcomes are confirmed.** The client plays shots,
   recoil, and tracers instantly; the server confirms hits (hitmarkers) and
   damage.
6. **Few loops, not many scripts.** Enemy AI runs in one server loop over all
   enemies (throttled), not one script per enemy.

## 2. Roblox service mapping

| Location | Rojo path | Contents |
|---|---|---|
| `ReplicatedStorage.Shared` | `src/shared` | Config, networking definitions, utilities (both sides) |
| `ServerScriptService.Server` | `src/server` | Bootstrap + services (server only, invisible to clients) |
| `ServerStorage` | `src/serverstorage` *(later)* | Enemy/map templates, boss assets |
| `StarterPlayer.StarterPlayerScripts.Client` | `src/client` | Bootstrap + controllers |
| `StarterGui` | built in code for now | HUD is built by `HudController` |
| `Workspace.Map` | built at runtime (M1) | Placeholder arena from `MapService` |

## 3. Networking

All remotes are declared in `Shared/Net/Remotes.luau`. The server creates them,
and clients wait for them. Using the names from that one module avoids typos.

| Remote | Direction | Payload | Server validation |
|---|---|---|---|
| `Fire` | C→S | `origin: Vector3, direction: Vector3, claimedPart: BasePart?` | types, alive, fire-rate budget, ammo, not reloading, origin near head, unit direction, claimed hit plausibility |
| `Reload` | C→S | — | alive, not reloading, mag not full, reserve > 0 |
| `HitConfirm` | S→C | `isHeadshot, isKill, damage` | — |
| `ShotFx` | S→C (others) | `shooter, origin, endPos` | — |
| `Notify` | S→C | `kind, data` (point popups, wave events) | — |

**Replicated state uses attributes, not remotes**, wherever possible:
- `ReplicatedStorage.GameState` (Folder) attributes: `State`, `Wave`,
  `EnemiesRemaining`, `IntermissionEndsAt` (server `os.time`-based clock
  via `workspace:GetServerTimeNow()`).
- `Player` attributes: `Points`, `Kills`, `WeaponId`, `Ammo`, `Reserve`,
  `Reloading`.

### Hit registration ("favor the shooter, then verify")
1. The client raycasts locally and sends the ray plus the part it hit.
2. The server re-checks:
   - The claimed part belongs to a live enemy.
   - The part's **current** position is within `HIT_TOLERANCE` studs of the
     ray. This allows for latency: enemies move a few studs between the
     client's frame and the server receiving the shot.
   - The hit is within weapon range.
   - The map doesn't block the line from origin to the claimed part.
3. If the claim fails, the server uses its own raycast result instead.

Later improvement: per-enemy position history (rewind by player ping) to
shrink the tolerance.

### Rate limiting
Each weapon tracks recent shot timestamps. The server rejects a shot if more
than `ceil(rate × 1.25) + 1` shots arrived in the last second, or if two
shots came closer than 50% of the fire interval. That allows normal network
bunching but not speed hacks.

## 4. Server services (Milestone 1)

| Service | Responsibility |
|---|---|
| `MapService` | Builds the placeholder arena, tags `EnemySpawn` and `PlayerSpawn` points (CollectionService), and gives out spawn CFrames |
| `PlayerService` | Manual character spawning (`CharacterAutoLoads = false`), alive tracking, spawning players at the start of each wave, "all dead" signal |
| `CurrencyService` | Per-player match `Points` and `Kills`, leaderstats, all point changes go through here |
| `WeaponService` | Per-player weapon state, `Fire`/`Reload` validation, damage application |
| `EnemyService` | Spawning, the AI loop (target pick, move, path around cover, attack), death and rewards, cleanup |
| `WaveService` | State machine: `Intermission → Wave → Intermission … → GameOver → reset` |

Communication between services goes through direct `require` plus small
`Signal`s (e.g. `EnemyService.EnemyDied`, `PlayerService.AllPlayersDead`).

## 5. Client controllers (Milestone 1)

| Controller | Responsibility |
|---|---|
| `CameraController` | First-person lock, FOV, ADS zoom, sprint FOV, camera recoil kick |
| `WeaponController` | Input (LMB fire, RMB ADS, R reload, Shift sprint), local raycast, placeholder viewmodel, muzzle flash, tracers, predicted ammo |
| `HudController` | Crosshair, hitmarker, ammo, health, points with popups, wave banner, intermission timer, game-over screen, damage vignette |
| `EffectsController` | Tracers and impacts (own shots plus other players' via `ShotFx`) |
| `SoundController` | 2D sounds (own gun, hitmarkers, wave stingers) and 3D one-shots (other players' shots). Enemy groans/attacks are 3D `Sound`s on each enemy, played by the server so everyone hears them from the right place |

The HUD also shows **threat arrows**: red screen-edge arrows pointing at
enemies within 24 studs that aren't already in front of you. These are
computed client-side from replicated enemy positions.

## 6. Enemy AI and performance

- Enemies are lightweight Humanoid models: an invisible collision root plus a
  few welded, non-colliding visual parts. They have no Motor6D rigs, so the
  animation cost is zero for now.
- Network ownership is pinned to the server (`SetNetworkOwner(nil)`). That
  stops exploiters from moving enemies and avoids ownership handoff jitter.
- A single AI tick runs every **0.2 s**. Each enemy re-targets the nearest
  alive player and checks whether the straight line is clear:
  - If it's clear: `Humanoid:MoveTo(target)`.
  - If it's blocked: `PathfindingService` path, recomputed at most every 1.5 s
    per enemy, with a global budget of a few path computations per tick.
- A stuck check (low speed while far from the target) makes the enemy jump or
  repath.
- **Max alive enemies** is capped (24 to start) and the rest queue.

Later: replace Humanoids with a custom `AlignPosition`/raycast mover for
hundreds of enemies, use `workspace:BulkMoveTo` for visuals, LOD visuals by
distance, and keep enemy visuals client-side only.

## 7. Data (Milestone 5+)

- `DataService` with **session locking** via `UpdateAsync`
  (`{ lockedBy = JobId, lockedAt = time }`), autosaving every 60–120 s,
  saving on `PlayerRemoving` and `BindToClose`, and retries with backoff.
- Versioned schema with migrations (`schemaVersion`).
- Gacha rolls are applied in the **same** profile write as the currency
  deduction and pity update, so a pull can never be partially applied.
- MemoryStoreService for matchmaking queues and party state across servers.

## 8. Anti-exploit checklist

- [x] No client-writable points/ammo/health/damage (M1)
- [x] Remote payload type checks and NaN/inf guards (M1)
- [x] Fire-rate budget, origin distance, range, line-of-sight checks (M1)
- [x] Server-owned enemies (M1)
- [ ] Purchase validation with proximity checks (M2)
- [ ] Ability cooldowns enforced server-side (M3)
- [ ] Gacha atomic transactions (M6)
- [ ] Rate limits on all remotes, generic `RemoteGuard` wrapper (M2)
- [ ] Movement sanity checks (speed/teleport) (M4)

## 9. Folder structure

```
roblox-game/
├─ default.project.json        Rojo tree (what goes where in the DataModel)
├─ rokit.toml                  Pinned toolchain (Rojo version)
├─ docs/
│  ├─ GAME_DESIGN.md
│  ├─ TECHNICAL_ARCHITECTURE.md
│  └─ ROADMAP.md
└─ src/
   ├─ shared/                  → ReplicatedStorage.Shared
   │  ├─ Config/
   │  │  ├─ GameConfig.luau    economy, timings, caps
   │  │  ├─ WeaponConfig.luau  weapon stat tables
   │  │  ├─ EnemyConfig.luau   enemy types + scaling
   │  │  ├─ WaveConfig.luau    wave composition formulas
   │  │  └─ SoundConfig.luau   sound asset IDs (placeholders)
   │  ├─ Net/
   │  │  └─ Remotes.luau       remote names + get/create helpers
   │  └─ Util/
   │     └─ Signal.luau        tiny event class
   ├─ server/                  → ServerScriptService.Server
   │  ├─ init.server.luau      bootstrap (Init → Start)
   │  └─ Services/
   │     ├─ MapService.luau
   │     ├─ PlayerService.luau
   │     ├─ CurrencyService.luau
   │     ├─ WeaponService.luau
   │     ├─ EnemyService.luau
   │     └─ WaveService.luau
   └─ client/                  → StarterPlayer.StarterPlayerScripts.Client
      ├─ init.client.luau      bootstrap (Init → Start)
      └─ Controllers/
         ├─ CameraController.luau
         ├─ WeaponController.luau
         ├─ HudController.luau
         ├─ EffectsController.luau
         └─ SoundController.luau
```

Planned additions per milestone: `Services/InteractionService` (buys, doors),
`Services/AbilityService`, `Services/UpgradeService`, `Services/DataService`,
`Services/GachaService`, `Services/MatchmakingService`, `src/serverstorage/`
for templates, and `Controllers/MenuController` etc.

## 10. Conventions

- Files use `.luau`. Modules return a table and are `PascalCase`.
- `--!strict` is a goal for shared config and utilities. Services use
  `--!nonstrict` until the types settle.
- Every remote handler starts with type guards and returns early on bad input.
- Placeholders are named `PLACEHOLDER_*` or commented `-- PLACEHOLDER:`.
- One feature branch per milestone. A milestone is merged only after
  playtesting.
