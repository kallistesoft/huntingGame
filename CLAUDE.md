# Hunting Game — project brief

This file carries the design discussion from a Claude chat (2026-10-27) so any Claude Code session on this repo starts with the full picture. A first playable proof of concept (POC) exists; see **Current state** below.

## Current state (POC v0.1.0)

**Godot 4.7, GDScript, 3D with an angled top-down camera** (fixed angle, follows the hunter; owner's choice 2026-10-27). Landscape 1280×720, stretch mode `canvas_items`, aspect `expand`, Mobile renderer. Placeholder art is simple 3D shapes built in code (`scripts/world/shapes.gd`), so there are no model files yet. The world and UI are built in code from `scenes/main.tscn`. Units are metres; map rectangles are `Rect2` on the ground plane (x = world x, y = world z). The camera never turns, so joystick up = world −Z.

What the POC covers:
- **Zones are data** (`Data.ZONES`, 2026-11-04): each entry holds the zone's rect, ground/grass colours, label, unlock rule (level + boss to defeat), entry barrier (a fence along its west edge, or a pass gate to walk through), resource and animal counts, ponds, boss id and outpost spot. `main.gd` and `ground.gd` loop over it; `Data.NEXT_ZONE` is the zone not built yet, whose gate ends the demo. Zone 1 (the meadow): camp clearing, trees, rocks, berry bushes, tall grass, a pond, rabbits and squirrels. Zone 2 (the east forest, fence until level 3): deer, the Great Boar, an **outpost** (chest linked to the camp storage + campfire to sleep on the ground). **Zone 3 (the mountains, pass at level 8 + boar, added 2026-11-04):** boulder wall with a gap at the pass, iron rocks (need a bone pickaxe or better: `needs_tier`), mountain herbs (eating heals 30), snow hares, mountain goats (horn), **wolves** (aggressive: chase inside their range and bite 12 every 1.6 s), the **Great Bear** boss (45 HP, 40-damage swipe, drops bear pelt and claws), an outpost, and the **Northern pass** to `Data.NEXT_ZONE` (level 13 + bear, ends the demo). Walking across an open border counts as entering the zone (`Game.on_enter_zone`, `visited_zones`). Every kill gives a little XP, raw meat and fur; deer also give hide and antler. Bosses live in `Data.BOSSES` (a `look` of boar or bear), beaten ones in `Game.bosses_defeated`.
- Touch controls: joystick on the left half, round ACTION button bottom right (hold to repeat). WASD/arrows + Space/E on desktop.
- Gather by hand (a tool doubles the yield), carry weight limit, hunger/thirst drain and slow the hunter when low, drink at the pond, eat from the bag.
- Energy 100 → 0 spent by actions; at 0 the hunter is slow and can't act. Sleep (60 s outside, shorter in the house) or a **placeholder rewarded ad** for +10 energy (10 per day).
- Camp: crafting place, storage, house, tanning rack (3 tiers each) and the **forge** (1 tier, level 8 + house tier 2, smelts iron bars), built on real-time timers. The house is the master building: tier T of another building needs house tier T−1 (`house_tier` per tier). Each station with recipes runs **one craft job at a time** (`Game.craft_jobs[station]`), so the rack and the crafting place work in parallel.
- **Materials chain (2026-11-04):** fibre (tall grass) → rope (crafting place); hide (deer, boar) + fibre → leather (tanning rack); bone (deer, boar); iron ore (mountains) + wood → iron bar (forge); wolf pelt + leather → thick leather (tanning rack tier 3). Tier-2 buildings cost rope/leather.
- **Equipment** (`Data.TOOLS` with `slot`, `tier`, `upgrades_from`, stats; `Game.equipped(slot)` = highest tier owned): weapon (wooden spear → bone spear; hunting bow), axe and pickaxe (stone → bone, 2× → 3× yield), head (fur hood → boar-tusk helm, +max health), body (fur tunic → leather armor: hunger/thirst 33% slower, armor blocks 50%), feet (fibre wraps → leather boots: +15% → +30% speed), bag (fibre pouch → leather bag: +10 → +20 kg). **Tier 3** (iron bars + thick leather, crafting place tier 3): iron spear / iron-tipped bow (damage 4 / 5), iron axe and pickaxe (4×), iron helm (+80), wolf-pelt armor (blocks 70%), wolf boots (+45%), hunter's pack (+35 kg). Upgrade recipes list the old piece in their cost and consume it. **Hunter** window (HUD button) shows every slot, the stats and the next upgrade. Tier = the zone whose materials make it.
- Hunting with spear/bow; animals flee, then stop to rest. Drops: meat, hide, fur, antler.
- **Quest lines per zone** (`Data.QUEST_LINES`, flattened by `Data.quests()` so `Game.quest_index` stays one number): 13 meadow quests (the chain: fibre, wraps, tanning rack, leather, fur tunic), 11 east-forest quests (house, deer, crafting place tier 2, bone pickaxe, leather boots and armor, level 5, the boar, house tier 2), 11 mountain quests (pass, iron, wolves, forge, iron bars, crafting place tier 3, thick leather, an iron tool, level 10, the bear, the northern pass). Build quests may ask for a `tier`; `Data.QUEST_GROUPS` lets one target stand for several ids. The board shows the current zone's line with done / current / upcoming quests. **Balance:** 15 levels (`LEVEL_XP`, level 8 at 1400, 13 at 3900); each zone's quests plus its boss give 120–135% of the next gate (checked by the smoke test); tier-2/3 buildings and crafts take 1–6 minutes, so the speed-up ad and off-app timers matter. Quest types: gather, harvest an animal's drop ("Harvest 2 rabbit fur"), craft, build, reach a level, defeat the boss, travel.
- **Boss: the Great Boar** (`Data.BOSSES["boar"]`) in its lair at the far east of zone 2. It paws the ground (red glow), then charges; a hit does 30 damage and knocks the hunter back. After a charge it is dizzy and takes double damage. Heals slowly if the hunter leaves. Drops tusks, hide, meat, 150 XP. HUD shows its health bar nearby.
- **Health and getting knocked out** (owner's rule, 2026-10-27): health 0–100, regenerates slowly while fed and watered, full after sleep. At 0 the hunter is knocked out and chooses: **watch a rewarded ad** → get back up where they fell with 50% health (2 s protection), or **give up** → wake in the house (or at camp) with full health and **lose everything in the bag**. Storage and tools are kept (owner confirmed). Damage comes from the boar and from **starvation**: food or water at 0 drains 1 health/s each (2/s if both), with a warning every few seconds. Giving up also restores food and water to at least 50%.
- **Passes** (`zone_gate.gd`): the Mountain pass at the end of the east forest enters zone 3 (level 8 + boar, `Game.zone_blocker`); the Northern pass at the end of the mountains is the entry of `Data.NEXT_ZONE` (level 13 + bear) and crossing it (`Game.cross_into`) shows the **End of the demo** screen ("Keep playing" returns to the game).
- Shop with **placeholder packs** (Starter, Hunter): no real payment.
- **Crafting/building UX (2026-11-04):** a **speed-up rewarded ad** halves the time left on a build or craft (`Game.speed_up`, shares the 10-ads-a-day cap); upgrade cards show cost chips, a "now → next" benefit line and the level needed; tapping a cost chip shows **where to find** the item (`Data.sources`); a recipe can be **pinned** to the HUD (`Game.pinned_recipe`) and its have/need updates as you gather; item recipes can be crafted **×1 / ×5 / Max** (`craft_job.count`); recipes unlocked but not yet looked at carry a **NEW** badge (`Game.seen_recipes`) and the action pill shows a dot. **Dev menu** (debug builds only, bottom of the Menu window): give materials, set tiers and level, finish timers, reset NEW badges, teleport.
- Save to `user://save.json` every 10 s and when the app is paused/closed. Timers use real-world time, so building, crafting and sleep finish while the app is closed; hunger/thirst only drain while it's open.

- **Visible progress (2026-11-04):** each building tier has its own model (`station.gd`: crate → shed → barn, hut → chimney and window → porch, bench → tool rack and fire pit → roofed workshop, one hide per rack tier, a forge with a glowing mouth); the hunter wears the equipped pieces (`player.gd` `_update_gear`: hood/helm, tunic/armor with shoulder pads, boots, a bag on the back, tool heads coloured stone/bone/iron); finishing a piece of equipment pops a burst and "Equipped: …" (`Game.crafted` → `main.gd`).
- Game feel: floating "+1 Wood / +2 XP" text, chips and dust bursts, items flying into the Bag button, camera shake and phone vibration on hits, buildings pop with sparks when a tier finishes, level-up banner, smooth bars, press animation on buttons. Animals are animated in code (hop, gallop, idle sniff, fall over on death).
- Look: procedural sky, glow, light fog, colour adjustment, swaying trees/grass/flowers (shader), animated pond water, grass tufts via MultiMesh.
- UI: Nunito font (SIL OFL, `assets/fonts/`), rounded cards and pills, vector icons drawn in code (`scripts/ui/icons.gd`), level badge with XP ring, round icon buttons, contextual action button showing the tool icon, full-screen windows that slide up (UI scale 1.35 via `window/stretch/scale`). Station, bag and shop lists are grouped by item category (`Data.CATEGORIES`) in a two-column grid; the crafting window shows a progress card, recipe cards with icon, effect line, cost chips (green/red with "have N") and the reason a craft is blocked. Palette and theme in `scripts/ui/style.gd`.

Not done yet: real AdMob and billing plugins, release signing / Play Store bundle (.aab), sounds, real 3D models, day/night cycle. Known issue: trees between the camera and the hunter can hide the hunter.

### Code layout

- `scripts/autoload/data.gd` (`Data`): all items, recipes, structures, animals, quests, packs and balance numbers. **Tune the game here.**
- `scripts/autoload/game_state.gd` (`Game`): player progress, survival, timers, quests, save/load. Game rules live here, not in nodes.
- `scripts/autoload/ad_service.gd` (`AdService`), `store_service.gd` (`StoreService`): placeholders; AdMob and billing plug in here only.
- `scripts/world/`: `main.gd` builds the world from `Data.ZONES` (props, animals, bosses, gates, outposts), the camera and lights; `ground.gd` (planes, grass, lairs, fences per zone); `player.gd`, `animal.gd`, `boss.gd` (any boss, by `kind`), `zone_gate.gd` (pass between zones), `outpost.gd` (chest + campfire), `resource_node.gd`, `station.gd`; `shapes.gd` holds the placeholder-shape helpers.
- `scripts/ui/`: `hud.gd` (stats, quest and pinned-recipe cards, buttons, touch controls, sleep prompt, effects), `panel_shell.gd` (full-screen window shell + building blocks: labels, cards, chips, icon tiles, progress bars, category grids), `panel.gd` (extends the shell: station, crafting, bag, shop, menu and dev views), `style.gd` (palette, font, theme), `icons.gd` + `icon_rect.gd` + `icon_button.gd` (vector icons).
- `scripts/world/fx.gd`: floating text and particle bursts; `main.gd` has the `fx_*` hooks, camera shake and vibration.
- Visual previews here use Godot's OpenGL (Compatibility) renderer because the cloud has no Vulkan; the game itself uses the Mobile renderer, so check lighting on a real phone. Filmic tone-mapping looked washed out in previews, so the tone-mapper is left at Linear.
- `tests/smoke_test.tscn`: plays the core loop and checks it.

### Running

- Play: open the folder in Godot 4.7 and press F5.
- Smoke test (headless): `godot --headless --path . res://tests/smoke_test.tscn` prints `SMOKE TEST: PASS` and exits with the number of failures. Run it after every change. (The hunting step used to flake when a tree or grass tuft stood next to the rabbit; `_act_on` now tries several sides of its target.)
- Android APK: `export_presets.cfg` has an **Android** preset (package `com.kallistesoft.huntinggame`, arm64, version 0.1.0, vibrate permission, no Gradle build). In the editor: Project → Export → Android → Export Project. Headless: `godot --headless --path . --export-debug "Android" build/HuntingGame.apk` (needs Godot 4.7.1 Android export templates, an Android SDK with build-tools, a JDK, and a debug keystore set in Editor Settings → Export → Android). `build/` is git-ignored. The current APK is a **debug** build signed with a throwaway debug key: fine for sideloading, not for Google Play.

## Engine decision

**Godot 4 (GDScript), 3D with an angled top-down camera** (first built in 2D, switched to 3D at the owner's request). Chosen because:
- Native export to Android (Google Play) and iOS; AdMob plugins exist.
- Free, no revenue share.
- Scenes and resources are plain text, so Claude can write the whole project, not only scripts. The owner opens it in the Godot editor to playtest and export.

Alternatives considered: Unity (viable, but heavier and Claude can't run the editor), Phaser + Capacitor (fine for quick web prototypes, weaker for a growing store game).

Target: mobile (touch controls), monetized with AdMob rewarded ads and in-app purchases.

**Platforms: Android and iOS. Android first for the proof of concept (POC)**, on Google Play under the owner's organization developer account. The owner also already has an AdMob account. iOS comes after the POC (needs an Apple Developer account and a Mac with Xcode to build).

To keep the later iOS port cheap:
- Choose ads/purchase plugins that support both Android and iOS.
- Keep ads and purchases behind small wrappers (`AdService`, `StoreService`) so platform-specific code stays in one place.
- Avoid Android-only features in game code.

## Game concept (as described by the owner)

You are a **hunter**. You start at **level 1, almost naked**, in a **small zone**.

- **Hunt to eat**, and hunt/gather to find **components used to build other components**.
- At the start you must **break wood** to build something to hunt with (first tool/weapon).
- **Gathering loop:** gather materials → **bring them somewhere** (a station/storage) → **select what you want to build** → **wait** (build/craft timers).
- **Weight limit:** you are limited by how much you can carry.
- **Survival needs:** you must **find water and eat**, otherwise you become **tired and your character is slow**.
- **Camp structures to build:**
  - a **house**
  - a **storage place** to empty your bags
  - a **crafting place**
- **Every structure can be improved:** storage upgrades hold more / better items; crafting upgrades unlock better crafts.
- **Progression:** quests and gathering give **XP**. Reaching a level **unlocks a new area**, and so on.
- Play style: **both active and idle** — active gathering/hunting plus timer-based building and crafting.

## Energy and monetization (owner, 2026-10-27)

The game relies on **rewarded ads and in-app purchases**, built around a tiredness gauge:

- **Energy gauge from 100 down to 0.** Actions (quests, gathering, hunting, etc.) lower it.
- **At 0 the character must sleep** and the player waits for a sleep timer.
- **A rewarded ad gives +10 energy** so the player can keep going a little longer.
- In-app purchases also exist. Confirmed: **packs that help you level up** (contents not decided yet: XP boosts, resources, tools, etc.).

Implications for the build:
- Gives the **house** its role: it's where the character sleeps. House upgrades could shorten sleep or raise the energy cap.
- Sleep has to count down in **real time, including while the app is closed**, so timers rely on saved timestamps, not in-game ticks.
- Rewarded ads must stay opt-in (Google Play / AdMob policy); show only after the player taps a button.

## Original build order (steps 1–7 are all in the POC)

1. Core loop in zone 1: movement, gather wood/stone, XP and levels.
2. Survival stats (hunger, thirst, fatigue → movement speed) and carry weight.
3. Camp: storage, crafting station, house — build with timers, upgrade tiers.
4. Hunting: first crafted weapon, animals that drop meat and components.
5. Simple quests from an NPC or a board.
6. Zone unlock at a level threshold.
7. Save system on device.

Placeholder art first; real art to be sourced later (asset packs or an artist).

## Roadmap (owner, 2026-11-04)

The game is a demo today but must extend quickly: **3 zones at launch, more zones by update.** Each zone is a biome with its own resources, animals, boss and one gear/tool tier (tier = zone). One home camp in zone 1, small outposts later. Hunter equipment slots head/body/feet/bag plus weapon/axe/pick; upgrades consume the previous piece; no durability. Level cap ~15 at launch; placeholder ads/IAP stay until the content is in.

Steps (each shipped and tested on the phone, then committed): **1.** crafting/building UX (done) → **2.** zone framework: `Data.ZONES` drives ground, spawns, bosses, gates and outposts (done) → **3.** material chain (fibre, rope, bone, leather, tanning rack) and gear tiers 1–2 (done) → **4.** zone 3 (mountains, iron, wolves, Great Bear) and tier 3 (done) → **5.** visible building tiers and gear on the hunter (done) → **6.** per-zone quest lines, 15 levels, balance (done). Deferred: craft queue, one builder + paid second slot, idle producers, notifications, real AdMob/billing.

### Adding a zone

1. Append an entry to `Data.ZONES` (rect to the east of the last one, colours, label, `unlock` = level + previous boss, `entry` = the pass that was in `NEXT_ZONE`, resource/animal counts, ponds, boss id, outpost spot). Point `NEXT_ZONE` at the zone after it (new gate position at the new east edge).
2. Add its items (with `category`), animals (`ANIMALS`, placement comes from the zone entry), boss (`BOSSES`, with `lair` inside the rect), recipes and gear tier.
3. Shapes: resource nodes in `resource_node.gd`, animal looks in `animal.gd`, boss look in `boss.gd` if it differs, gear meshes in `player.gd`.
4. Its quest line; raise `LEVEL_XP` by about 5 levels.
5. Bump `version/code` and `version/name` in `export_presets.cfg`; run the smoke test; test on the phone with the Dev menu.

## Open questions

- Number of zones and level gates.
- Whether build/craft timers also keep running while the app is closed (the sleep timer does).
- Energy cost per action, sleep duration, and a daily cap on energy ads.
- In-app purchase offers beyond level-up packs (e.g. refill energy, skip sleep, remove interstitials, bigger bags, cosmetics).
- Level-up pack contents and limits: flat XP vs. timed XP boosts vs. resources, and whether a pack can skip a zone gate.
- Whether "tired" is the energy gauge alone, or hunger/thirst also slow the character.
- Art style.
