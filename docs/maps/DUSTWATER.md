# Map: Dustwater (working title)

An original, compact, destroyed desert town for 1–4 players. It has the feel of
classic round-based zombie maps (tight start, an open fighting street, interiors
you buy into, a hidden upgrade room), but its own layout and landmarks. **No
geometry, buildings or assets copied from any existing game.**

Scale reference: Roblox character ≈ 5 studs tall · door 4×7 · street 32–36 wide ·
small building footprint 30×40.

## Top-down layout (north ↑, ~1 char = 8 studs)

```
                                   N
   +-----------------------------------------------------------------------------------+
   |  dunes / rock wall boundary                                                        |
   |   +-----------+                                         +-------------------------+ |
   |   | GAS       |  [canopy + pumps]                       |  MOTEL (U-shaped,       | |
   |   | STATION   |                 MAIN STREET              |  2 floors, balcony)    | |
   |   | store +   |  =====================================  |  office | rooms | rooms | |
   |   | garage    |  ===  wrecked cars  ===  bus  =========  |      courtyard + pool  | |
   |   +----D2-----+   ||                    ||       D4 gate |   (storm drain → D5)    | |
   |                   ||   +---------+      ||               +-------------------------+ |
   |   burned field    ||   | DINER   |  fallen water tower                               |
   |                   ||   | D3      |  (landmark)          alley ─────────┐            |
   |                   ||   +---------+      ||                             │            |
   |                   ++=========D1=========++ ← debris barricade          │            |
   |                          ELM LANE (start)                               │            |
   |                   house  |  cul-de-sac  |  house + garage               │            |
   |                          +-------------+                                │            |
   +-----------------------------------------------------------------------------------+
                UNDERGROUND (below Main Street): storm tunnel → lab room (Spirit Forge)
```

## Areas and progression

| # | Area | Unlock | Feel | Contents |
|---|---|---|---|---|
| 0 | **Elm Lane** (start) | — | Narrow residential cul-de-sac, 2 burned houses (enterable ground floors), broken fences | Wall-buys: Pistol, SMG · Box spawn 1 (garage) · 3 boarded-window enemy entries |
| 1 | **Main Street** | D1 debris barricade, 750 | The open fight space: wide road, wrecked cars and bus for cover, fallen water tower blocking half the street | Wall-buy: Shotgun · Perk: Swift Step · Box spawn 2 · 5 entries (alley, rooftops, storm drains) · **boss arena** |
| 2 | **Gas Station** | D2 car-wreck barricade, 1000 | Canopy and pumps outside, small store and a garage bay inside | Wall-buy: Assault Rifle · Perk: Rapid Fire (garage) · 3 entries |
| 3 | **Diner** | D3 front door, 1000 | Tight interior: booths, counter, kitchen, back door to the alley | Perk: Quick Hands · Box spawn 3 · 2 window entries + kitchen door |
| 4 | **Motel** | D4 courtyard gate, 1250 | U-shaped 2-floor motel, outdoor stairs, upper balcony, drained pool | Wall-buy: Sniper (balcony) · Perk: Iron Body (office) · Box spawn 4 (a room) · 4 entries |
| 5 | **Underground lab** | D5 storm-drain hatch in the motel courtyard, 1500 | Concrete tunnel → small hidden lab under Main Street | **Spirit Forge** (upgrade station) · 1 tunnel entry |

## Design notes

- **Loops, not dead ends.** Main Street ↔ alley ↔ diner back door, and Main
  Street ↔ motel ↔ storm tunnel, give players routes to kite (train) enemies.
- **Enemy entry points are boarded windows and gaps**, spread around every area,
  so enemies always come from several sides. Each zone's entries only activate
  once that zone is unlocked.
- **The boss arena is Main Street:** the largest open space, plenty of cover,
  three exits.
- **Bounds:** rock walls, dunes and invisible walls around the edge. Every
  walkable surface sits on solid floors, so nothing falls through the world.
- **Landmarks for orientation:** the fallen water tower (center), the gas
  station canopy (west), the motel sign (east).

## Build stages (your plan)

1. ✅ **Greybox** (2026-11-19): roads, building blocks, boundaries, door and
   station positions. Playable with the current systems. Code:
   `src/server/Maps/Dustwater/`. Verified that zombies can path between every
   area (with doors open), that the drain ramp and balcony stairs slope
   correctly, and that the game runs without errors.
2. **Architecture:** real walls with openings, interiors, the motel's second
   floor and stairs, roofs.
3. **Environment:** debris, wrecked vehicles, cracked roads, fire and smoke
   (particles), dusk or night lighting.
4. **Gameplay:** spawn and entry points, navmesh checks, doors and stations
   wired in, boarded windows (zombies tear boards off, players rebuild them
   for points).
5. **Polish:** materials and textures, small details, atmosphere, performance
   pass (part count, streaming).

## Tech plan

- New layout module `src/server/Maps/Dustwater/`, one builder file per area
  (`ElmLane.luau`, `MainStreet.luau`, …) plus `init.luau`. Each builder returns
  the same data the services already use: zones, doors, wall-buys, perks,
  forge, box locations and spawns. Splitting by area keeps files reviewable.
- `MapService` loads a map by name, so the old blockout stays available as a
  test map.
- Geometry is built at runtime in Stages 1–2 so it's tracked in git. Once art
  is involved, we can move to a `.rbxm` model synced by Rojo.
