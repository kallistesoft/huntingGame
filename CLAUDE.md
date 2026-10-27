# Hunting Game — project brief

This file carries the design discussion from a Claude chat (2026-10-27) so any Claude Code session on this repo starts with the full picture. A first playable proof of concept (POC) exists; see **Current state** below.

## Current state (POC v0.1.0)

**Godot 4.7, GDScript, landscape 1280×720** (stretch mode `canvas_items`, aspect `expand`, Mobile renderer). Placeholder art is drawn in code (`_draw()`), so there are no image assets yet. The world and UI are built in code from `scenes/main.tscn`.

What the POC covers:
- Zone 1 with a camp clearing, trees, rocks, berry bushes, a pond, **rabbits and squirrels**. Zone 2 (east forest, deer) behind a fence until level 3.
- Touch controls: joystick on the left half, round ACTION button bottom right (hold to repeat). WASD/arrows + Space/E on desktop.
- Gather by hand (a tool doubles the yield), carry weight limit, hunger/thirst drain and slow the hunter when low, drink at the pond, eat from the bag.
- Energy 100 → 0 spent by actions; at 0 the hunter is slow and can't act. Sleep (60 s outside, shorter in the house) or a **placeholder rewarded ad** for +10 energy (10 per day).
- Camp: crafting place, storage, house, each 3 tiers built on real-time timers. Crafting recipes (spear, axe, pickaxe, cooked meat, bag, bow).
- Hunting with spear/bow; animals flee, then stop to rest. Drops: meat, hide, fur, antler.
- Quest board with 9 linear quests, XP and levels.
- Shop with **placeholder packs** (Starter, Hunter): no real payment.
- Save to `user://save.json` every 10 s and when the app is paused/closed. Timers use real-world time, so building, crafting and sleep finish while the app is closed; hunger/thirst only drain while it's open.

Not done yet: real AdMob and billing plugins, Android export preset and signing, sounds, real art.

### Code layout

- `scripts/autoload/data.gd` (`Data`): all items, recipes, structures, animals, quests, packs and balance numbers. **Tune the game here.**
- `scripts/autoload/game_state.gd` (`Game`): player progress, survival, timers, quests, save/load. Game rules live here, not in nodes.
- `scripts/autoload/ad_service.gd` (`AdService`), `store_service.gd` (`StoreService`): placeholders; AdMob and billing plug in here only.
- `scripts/world/`: `main.gd` builds the world; `player.gd`, `animal.gd`, `resource_node.gd`, `station.gd`, `ground.gd`.
- `scripts/ui/`: `hud.gd` (bars, buttons, touch controls, sleep prompt), `panel.gd` (station, bag, shop, menu windows).
- `tests/smoke_test.tscn`: plays the core loop and checks it.

### Running

- Play: open the folder in Godot 4.7 and press F5.
- Smoke test (headless): `godot --headless --path . res://tests/smoke_test.tscn` prints `SMOKE TEST: PASS` and exits with the number of failures. Run it after every change.

## Engine decision

**Godot 4 (GDScript), top-down 2D.** Chosen because:
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

## Open questions

- Number of zones and level gates.
- Death / failure rules when hunger or thirst run out.
- Whether build/craft timers also keep running while the app is closed (the sleep timer does).
- Energy cost per action, sleep duration, and a daily cap on energy ads.
- In-app purchase offers beyond level-up packs (e.g. refill energy, skip sleep, remove interstitials, bigger bags, cosmetics).
- Level-up pack contents and limits: flat XP vs. timed XP boosts vs. resources, and whether a pack can skip a zone gate.
- Whether "tired" is the energy gauge alone, or hunger/thirst also slow the character.
- Art style.
