# Map: Dustwater (working title)

An original, compact, destroyed desert town for 1–4 players. It has the feel of
classic round-based zombie maps (a tight start, an open fighting street,
interiors you buy into, a hidden upgrade room), but its own layout and
landmarks. **No geometry, buildings or assets copied from any existing game.**

Scale reference: Roblox character ≈ 5 studs tall · door 4×7 · Main Street 36
road + sidewalks · whole town ≈ 560 × 340 studs (layout v2).

## Top-down layout, v2 (north ↑)

```
 z=-112 +=================================== cliff =============================================+
        | GAS STATION   |A1|  ALLEY ─── dumpsters ─── sewer ramp ↓ (D6)   |                        |
        |  canopy pumps |  |pass| A2 shops |  DINER   |  C: theater      |  MOTEL north wing 2F   |
 z=-40  |  store garage |  D3b                 D3                         |  balcony ── stairs     |
        |           D2  |======== MAIN STREET (water tower, bus, cars) ===| D4  courtyard  pool    |
 z=12   |               |  BURNED FIELD  | lane |    JUNKYARD            |   pump-house (D5 ↓)    |
        |          D2b  |                |      |                    D4b |  office    south wing  |
 z=90   +---------------+-----------------D1-----------------------------+------------------------+
                         |  ELM LANE (start): 2 houses, shed, garage,    |
                         |  loop road around a center island             |
 z=225                   +-----------------------------------------------+
       x=-260        x=-150                 x≈0                      x=170                    x=300

 Underground (y = -20):  motel ramp → landing → long tunnel west → LAB (under the diner) → sewer ramp up into the alley
```

## Areas and progression

| # | Area | Ways in | Contents |
|---|---|---|---|
| 0 | **Elm Lane** (start) | — | Houses you can run around (the west house has front and back doors), a shed, garage, loop road · Pistol and SMG wall-buys · Box 1 (garage) · 5 enemy spawns |
| 1 | **Main Street + Burned Field + Junkyard** | D1 debris barricade, 750 | The big fighting space: street with the fallen water tower, bus, cars; a burned field with dead trees (west) and a junkyard with containers (east) · Shotgun wall-buy · Swift Step · Box 2 (junkyard) · 7 spawns · **boss arena** |
| 2 | **Gas Station** | D2 wreck pile (street) **or** D2b back gate (field), 1000 | Canopy and pumps, store with front and back doors, garage bay · Assault Rifle wall-buy · Rapid Fire · Box 5 (behind the store) · 4 spawns |
| 3 | **Diner + Alley** | D3 diner door **or** D3b alley gate, 1000 | Diner interior (counter, booths), kitchen door to the back alley, alley passage back to Main Street · Quick Hands · Box 3 · 3 spawns |
| 4 | **Motel** | D4 front gate (street) **or** D4b back gate (junkyard), 1250 | U-shaped courtyard, drained pool, office, a room, 2nd-floor balcony and stairs · Sniper wall-buy (balcony) · Iron Body · Box 4 · 4 spawns |
| 5 | **Storm Drain Lab** | D5 pump-house (motel) **or** D6 sewer grate (alley), 1500 | Ramp, landing, long tunnel, lab · **Spirit Forge** · 4 spawns |

## Loops (where you can run circles)

1. **Elm Lane:** around each house, through the west house, around the center island.
2. **Main → diner → alley → passage → Main**, once D3 and D3b are open.
3. **Main → gas station → back gate → field → Main**, once D2 and D2b are open.
4. **Main → motel → back gate → junkyard → Main**, once D4 and D4b are open.
5. **The big underground loop:** motel → drain → tunnel → lab → sewer → alley → Main → motel.

## Build stages

1. ✅ **Greybox v1** (2026-11-19). **v2** (same day) after feedback: bigger and
   more spread out, more loops, empty lots filled. Verified 13 walking routes
   between every area, including Elm Lane all the way to the lab (doors treated
   as open).
2. **Architecture:** real walls with openings, interiors, the motel's second
   floor, roofs.
3. **Environment:** debris, wrecked vehicles, cracked roads, fire and smoke,
   lighting.
4. **Gameplay:** boarded windows (zombies tear boards off, players rebuild them
   for points), spawn tuning, boss arena setup.
5. **Polish:** materials, small details, atmosphere, performance.

## Tech notes

- Code: `src/server/Maps/Dustwater/init.luau` (layout data: zones, walls,
  doors, stations, spawns, lighting) and `Geometry.luau` (greybox builders).
- `MapService` provides the geometry API: `box`, `floor` (with holes), `shell`
  (hollow building with doorways), `ramp`, `part`.
- **Gotcha:** Roblox pathfinding doesn't connect a WedgePart's thin bottom edge
  to the floor, so `ramp()` always adds a flat foot pad at the bottom.
