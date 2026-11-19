# Development Roadmap

Each milestone ends with a **playtest checklist**. We only move on once every
item has been verified in Studio. Status: ✅ verified · 🚧 in progress · ⬜ not started.

## Milestone 1: Playable FPS survival prototype ✅ (pending your sign-off)
Goal: the core loop is fun to play for 5 minutes, using placeholder art.

**Verified in Studio (2026-11-19, solo playtest):** waves start/advance, enemies
spawn, chase, path around cover and attack; shooting/hits/kills award points;
reload refills from reserve; wave-clear bonus + ammo refill; death → game over
→ auto-restart; groans/attack sounds play; nearby-enemy arrows show; no
console errors from game code.
**Not yet verified:** multi-player behaviour (mid-wave death respawning next
wave while a teammate survives, player-count scaling). Test with Studio's
Test → Clients (2+) before M4.

Added during M1 after playtest feedback ("hard to tell if zombies are close"):
3D zombie groans + attack sounds, gun/reload/hitmarker/wave sounds, and red
screen-edge arrows pointing to enemies within 24 studs.

- First-person camera, sprint, ADS
- One hitscan rifle: shooting, recoil, spread, magazine, reload
- Server-validated hits, headshots, damage
- Basic melee enemy with chase AI and pathing around cover
- Enemy spawning from spawn points, max-alive cap
- Wave counter, intermission, scaling count/health/speed
- Points for hits/kills/headshots, leaderstats
- Player health and damage, death → respawn next wave
- Game over when everyone is dead, then auto-restart
- HUD: crosshair, hitmarker, ammo, health, points, wave, timers
- Placeholder arena

**Playtest checklist:** walk, sprint, ADS · fire empties the mag · reload refills
from reserve · hits award points · headshots deal more damage · enemies chase
and hit you · waves advance and get harder · dying mid-wave → respawn next
wave · all dead → game over → restart · no console errors.

## Milestone 2: Zombies-style economy and map
- Interaction system (ProximityPrompt + server validation)
- Wall-buy weapons (3–4 weapon classes), ammo purchase
- Buyable doors and map sections, shared unlocks
- Mystery box (weighted pool, moves locations)
- Perk machines (health, reload speed, fire rate, revive-speed placeholder)
- Upgrade machine (weapon tier up)
- Power-up drops (max ammo, double points, nuke)
- Generic `RemoteGuard` rate limiter
- First real blockout of map 1

## Milestone 3: Heroes and abilities
- Ability framework (server cooldowns, client prediction of VFX)
- Ultimate charge
- 2 heroes fully playable (Swordsman, Mage), placeholder VFX
- Hero selection (dev menu until the lobby exists)

## Milestone 4: Co-op depth
- Downed state and hold-to-revive
- Difficulty scaling by player count (verified with 4-player local test)
- Movement sanity checks
- Spectate while dead

## Milestone 5: Enemy variety and bosses
- Crawler, Brute, Spitter, Exploder
- Elite wave modifiers
- First boss with phases and an arena
- AI performance pass (custom mover, 50+ enemies target)

## Milestone 6: Roguelite upgrades
- Upgrade pool (data-driven), rarities, weighted rolls
- Pick-1-of-3 UI after designated waves
- Tags and synergies
- Hero-specific upgrades

## Milestone 7: Persistent data and progression
- DataService with session locking, autosave, migrations
- Match rewards → hero XP, weapon XP, soft currency
- Loadouts (starting weapon from collection)
- Hero levels, ability upgrades, evolution

## Milestone 8: Gacha
- Banner config, rarity tables, pity/soft pity/50-50
- Atomic server transactions
- Summon UI with odds/pity display and animations
- Duplicate conversion, collection inventory

## Milestone 9: Lobby, parties, matchmaking
- Lobby place, party invites, MemoryStore queues, TeleportService to match
  servers, reward return

## Milestone 10: Content and polish
- Art pass (anime visuals, viewmodels, animations), audio, UI theme
- Map 2, more heroes and weapons, challenges, achievements, cosmetics
- Performance and mobile/controller support

## Tracking known placeholders
| Placeholder | Where | Replace in |
|---|---|---|
| Block-part rifle viewmodel | `WeaponController` | M10 (art) |
| Block-part zombie model | `EnemyService` | M5/M10 |
| Grey arena with cover | `MapService` | M2 blockout |
| Third-party Creator Store sounds + Roblox built-in sounds | `Shared/Config/SoundConfig` | M10 (original audio) |
| Dusk lighting set in code | `MapService.setAtmosphere` | M2 (per-map preset) |
| No character animations on enemies | `EnemyService` | M5 |
