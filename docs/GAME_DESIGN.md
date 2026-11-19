# Game Design Document — Anime FPS Zombies Roguelite

> Working title: **TBD** (placeholder). Status: living document, Milestone 1.

## 1. Pitch

A 1–4 player co-op **first-person** survival shooter. You play as a collectible
anime-style hero, fight endless waves of enemies with guns and character
abilities, buy your way deeper into the map, and stack randomized roguelite
upgrades until the horde finally overwhelms you. Between matches you summon new
heroes and weapons, level them up, and build loadouts.

Not a tower defense game: the player is always the one aiming and shooting.

**Inspirations**
- *Round-based zombies* (Call of Duty Zombies style): endless rounds, points per
  kill, wall-buys, mystery box, perk machines, doors that cost points.
- *Anime collection games*: hero roster, banners, rarity, evolution.
- *Modern FPS*: responsive hitscan, recoil, ADS, reload timing.
- *Roguelites*: pick 1 of 3 random upgrades, rarity, synergies, reset per run.

## 2. Core loop

```
 Lobby ──► pick hero + loadout ──► Match ──► rewards ──► summon / upgrade ──┐
   ▲                                                                       │
   └───────────────────────────────────────────────────────────────────────┘

 In a match:
 Intermission ─► Wave N (kill everything) ─► wave reward ─► (every few waves:
 pick 1 of 3 upgrades) ─► Intermission ─► … ─► everyone down ─► Game Over
```

Moment to moment: shoot enemies → earn points → spend points (weapons, ammo,
perks, doors, upgrades) → survive the harder next wave.

## 3. Match rules

| Rule | Design |
|---|---|
| Players | 1–4, co-op |
| Waves | Endless; difficulty scales every wave |
| Elite waves | Every 5 waves (elite variants with modifiers) |
| Boss waves | Every 10 waves (map-specific boss) |
| Currency | **Points**, per player, reset each match |
| Earning | Hits, kills, headshot kills, wave completion, objectives |
| Down state | Downed players can be revived by teammates (Milestone 4) |
| Death | Dead players respawn at the start of the next wave |
| Loss | All players down/dead at once → Game Over |
| Rewards | Permanent currency/XP scaled by wave reached (Milestone 6) |

### Point economy (initial numbers, tune in playtests)
| Event | Points |
|---|---|
| Body hit | +10 |
| Kill | +60 |
| Headshot kill | +100 |
| Wave survived | +50 × wave number (capped) |
| Wall-buy rifle | 500–1500 |
| Door | 750–2000 |
| Mystery box | 950 |
| Perk | 1500–4000 |
| Upgrade machine | 5000 |

## 4. Difficulty scaling

- **Enemy count**: `6 + 3 × (wave − 1)`, × player multiplier
  (1 / 1.5 / 2 / 2.5 for 1–4 players). Max alive at once is capped (24 at
  first) so performance stays stable; the rest trickle in.
- **Enemy health**: linear growth early, compounding later:
  `base × (1 + 0.2 × (wave − 1))` up to wave 10, then `× 1.08` per wave.
- **Enemy speed**: starts as a walk, a growing share become runners after wave 4.
- **Enemy damage**: +5% per wave.
- **New enemy types** unlock at set waves (see §7).

## 5. Playable heroes

Heroes are collected via the gacha and played in first person. All heroes can
use any weapon; heroes differ by abilities and passives, not weapon locks.

Each hero has:
- 1 **passive**
- 2 **active abilities** (keys `Q` / `E`), cooldown-based
- 1 **ultimate** (key `F`), charged by dealing damage
- **Specialties** (stat leanings, e.g. +melee damage)
- **Level** (1–60), **ability upgrades**, **evolution** (star tiers)

### Archetypes (first five heroes, names are placeholders)

| Archetype | Passive | Active 1 | Active 2 | Ultimate |
|---|---|---|---|---|
| Swordsman | Kills restore a little HP | Dash slash (gap close + damage) | Parry stance (block, counter) | Blade storm (AoE spin) |
| Mage | Ability hits apply elemental status | Fireball (AoE) | Frost nova (slow) | Meteor (huge AoE) |
| Assassin | Crits from behind | Blink (short teleport) | Smoke (enemies lose target) | Shadow clones |
| Sniper | Headshots deal bonus damage | Mark target (team deals +dmg) | Grapple / reposition | Piercing railshot |
| Support | Nearby allies regen | Heal pulse | Speed/fire-rate buff field | Team revive + shield |

## 6. Weapons

### Two progression layers
1. **Permanent**: weapons collected from banners, with rarity
   (Common → Rare → Epic → Legendary → Mythic), levels, and attachments. You
   choose one **starting loadout weapon** to bring into a match.
2. **In-match**: wall-buys, mystery box, ammo purchases, the upgrade machine
   ("Pack-a-Punch"-style tier upgrades), and temporary modifiers from roguelite
   upgrades.

Your permanent weapon only decides what you **start** with. Stronger weapons are
found during the run.

### Weapon classes
Pistol, SMG, Assault Rifle, Shotgun, LMG, Sniper, Special (energy/anime
weapons, e.g. a spirit bow).

### Core stats
Damage, headshot multiplier, fire rate, fire mode (semi/auto/burst), magazine,
reserve, reload time, spread (hip/ADS), recoil, range/falloff, pellets.

## 7. Enemies

| Enemy | Unlocks | Role |
|---|---|---|
| Shambler | Wave 1 | Basic melee walker → runner |
| Crawler | Wave 4 | Low, fast, hard to hit |
| Brute | Wave 6 | Slow tank, heavy hit |
| Spitter | Wave 8 | Ranged projectile |
| Exploder | Wave 9 | Explodes on death/contact |
| Elite variants | Every 5th wave | Shielded/hasted/regenerating modifiers |
| Boss | Every 10th wave | Map-specific, phases + arena mechanics |

## 8. Map progression

Each map: a **starting area** and locked sections opened with points. Contains
wall-buy stations, perk machines, a mystery box (moves around), an upgrade
machine, hidden areas, secret objectives (easter-egg steps), and a boss arena.
Each map has its own atmosphere, enemy roster, and boss.

First map concept (placeholder): **"Shrine District at Dusk"**, a ruined
Japanese-style town with lantern-lit streets, a shrine, and a boss arena on the
mountain.

## 9. Roguelite upgrades

After every 3rd wave (tunable), each player picks **1 of 3** random upgrades.
Upgrades last only for the current match.

- **Categories**: Offensive, Defensive, Weapon, Ability, Utility, Hero-specific
- **Rarities**: Common / Rare / Epic / Legendary (weighted, luck can shift odds)
- **Stacking**: most upgrades stack; some are unique
- **Synergies**: tag-based (e.g. two `Lightning` upgrades unlock *Overcharge*)

Examples: explosive rounds, chain lightning on hit, lifesteal, +fire rate,
+crit damage, −ability cooldown, extra projectiles, ammo regen, "last stand"
(a cheat-death once per wave).

## 10. Permanent progression (outside matches)

- Collect heroes and weapons.
- Hero levels (XP from matches), ability unlocks/upgrades, evolution using
  duplicates and materials.
- Weapon levels and attachments.
- Daily/weekly challenges, achievements, cosmetics (skins, weapon camos,
  titles).
- Saved with DataStoreService, using session locking (see Technical
  Architecture).

## 11. Gacha

- **Banners**: Standard hero, Standard weapon, Featured (rate-up, limited time).
- **Rarities**: 3★ / 4★ / 5★ (exact odds configurable per banner).
- **Pity**: guaranteed 4★+ every 10 pulls; guaranteed 5★ at a hard pity of N.
  Soft pity raises the odds after a threshold. 50/50 rule on featured banners
  (lose it → next 5★ is guaranteed featured).
- **Duplicates** convert to evolution shards / currency.
- **Odds and pity are always visible** in the summon UI.
- **Server-side only**: the server rolls the random numbers, deducts currency,
  and updates pity counters in one step.
- **Compliance**: Roblox requires published odds for paid random items, and
  some regions restrict them via PolicyService. Paid summons check
  `PolicyService:GetPolicyInfoForPlayerAsync().ArePaidRandomItemsRestricted`.
  We should launch with **earnable-only** summon currency until this is
  reviewed.

## 12. Multiplayer

Party creation and matchmaking (lobby place → match place via TeleportService
and MemoryStoreService queues), co-op missions, revives, shared map unlocks,
individual points, individual upgrade picks, difficulty scaling, and reward
distribution. All gameplay math is server-authoritative.

## 13. Visual direction

Anime-inspired, cel-shaded look; strong silhouettes; saturated ability VFX;
punchy hit feedback (hitmarkers, damage numbers, enemy flinch); stylized dusk
and night lighting. Avoid the generic "simulator" look (flat bright plastic,
huge pop-up buttons).

**Asset policy:** anything not made yet uses a clearly named placeholder
(`PLACEHOLDER_*` in code, grey/neon blockout in game). Nothing is described as
final art until it is.

## 14. Open questions

- Final title and setting lore.
- Paid summons, or earnable-only at launch?
- Revive: hold-to-revive only, or also a revive item?
- Controller and mobile support level (mobile needs on-screen fire and aim).
