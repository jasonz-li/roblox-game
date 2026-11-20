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

## Milestone 2: Zombies-style economy and map ✅
- ✅ Interaction system (ProximityPrompt + server validation)
- ✅ Wall-buy weapons, ammo purchase
- ✅ Buyable doors and map sections, shared unlocks (6 doors; duplicates removed)
- ✅ Mystery box (weighted pool, moves locations)
- ✅ Perk machines: 8 perks incl. Storm Coil, Phoenix Draught, Pack Mule Tonic, Hawkeye Elixir
- ✅ Spirit Forge: 3 levels per gun, each gun has a signature upgrade (Twin Foxfire etc.)
- ✅ Power-up drops (max ammo, double points, insta-kill, nuke; Titan immune)
- ✅ Generic `RemoteGuard` rate limiter
- ✅ Map 1 "Dustwater": stages 1–4 done, shrunk from hotspot data; ⬜ stage 5 polish
- ✅ Boarded windows: hold E to repair (position based), points + seal bonus

## Milestone 3: Heroes and abilities 🚧 (built, needs rework)
- ✅ Ability framework — `AbilityService`, `AbilityController`
- ✅ Ultimate charge (kills / headshots / elites)
- ✅ 2 heroes: Ren (Gale Step / Tempest), Yuki (Frost Nova / Starfall), placeholder VFX
- ✅ Hero selection (H between waves, until the lobby exists)
- ⬜ **Rework Gale Step and Tempest** (playtest: "Tempest useless, Gale Step feels bad")

## Built outside milestone order (2026-11-19 → 11-20 playtest loop)
- 10-wave level with the Dust Titan boss finale, victory screen and rewards
- Anime impact frames, knife stab with hit-stop, ragdoll deaths with dissolve
- Kill streaks (milestones, streak UAV), CoD-style minimap with radar sweeps
- Zombies-style spawning: entry-point rotation, direction spread, window queues,
  lost-zombie relocation, hunt mode for the last zombies, nuke-proof alive cap
- Tighter point economy; sprint while reloading; sniper collateral + iron sights
- Studio-only `DevService` test hook

## Milestone 4: Co-op depth ⬜ (not started)
- ⬜ Downed state and hold-to-revive
- ⬜ Difficulty scaling by player count (verified with a 4-player local test)
- ⬜ Movement sanity checks
- ⬜ Spectate while dead
- ⬜ Any multiplayer playtest at all (everything so far was solo)

## Milestone 5: Enemy variety and bosses 🚧
- ⬜ Crawler, Brute, Spitter, Exploder
- ✅ Elite zombies + Elite Wave (wave 5)
- 🚧 First boss with an arena — Dust Titan (slam, health bar); ⬜ phases
- ⬜ AI performance pass (custom mover, 50+ enemies target)

## Milestone 6: Roguelite upgrades 🚧 (mostly done)
- ✅ Data-driven upgrade pool with rarities (Common/Rare/Legendary/Cursed), weighted rolls
- ✅ Pick-1-of-3 after every wave
- 🚧 Synergies (Volatile + Chain Reaction); ⬜ a proper tags system
- ⬜ Hero-specific upgrades

## Milestone 7: Persistent data and progression 🚧
- ✅ `DataService` with session locking, autosave, schema version
- ✅ Spirit Shards (earnable currency) from streaks, elites, waves, victory; run summary
- ⬜ Hero XP, weapon XP
- ⬜ Loadouts (starting weapon from collection)
- ⬜ Hero levels, ability upgrades, evolution
- ⬜ Enable Studio API access and verify saves actually persist

## Milestone 8: Gacha ⬜
- Banner config, rarity tables, pity/soft pity/50-50
- Atomic server transactions
- Summon UI with odds/pity display and animations
- Duplicate conversion, collection inventory

## Milestone 9: Lobby, parties, matchmaking ⬜
- Lobby place, party invites, MemoryStore queues, TeleportService to match
  servers, reward return

## Milestone 10: Content and polish ⬜ (some early pieces: impact frames, ragdolls)
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
