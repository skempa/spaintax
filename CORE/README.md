# CORE — an adventure you earn

**Put the phone down. Your creature is waiting.**

CORE is an iOS AR creature-collection RPG where real-world screen-time
behaviour determines how much gameplay you earn. You draw a creature, AI
brings it to life with one of six elemental Cores, and it lives in your
world through AR. Use your phone less → earn more Adventure Time (~5
minutes/day) → protect and evolve your creature.

This repository contains the **MVP implementation** of the
[product spec](docs/SPEC-NOTES.md): the full daily loop from drawing to
camp to a five-minute AR adventure, with screen-time-driven Adventure
Time, fragments, evolution, and permanent persistence.

## What's implemented

| Spec area | Status |
|---|---|
| Freehand drawing canvas (PencilKit, finger-first) | ✅ |
| On-device drawing analysis → creature generation | ✅ heuristic (`HeuristicCreatureGenerator`); server-side AI art slots in behind `CreatureGenerating` |
| AI Core assignment from drawing characteristics | ✅ hue/shape/energy scoring + deliberate unpredictability |
| Six Cores with identities, abilities, stat bonuses | ✅ |
| Attention Score → Adventure Time formula | ✅ reproduces all worked examples from the spec (§6): 105 m distraction/2 h total → 2:30, light day → 5:00, exceptional → up to 7:00. All constants in `Tuning.swift` |
| Screen Time integration (FamilyControls / DeviceActivity) | ✅ threshold-ladder design + monitor extension; **entitlement required** (see below). Simulator uses a debug provider |
| Camp: status, wandering creature, condition messages, ENTER WORLD | ✅ |
| 5-minute AR adventure (RealityKit): floor anchoring, creature placement, idle/wander, enemy encounters | ✅ true 3D voxel mesh generated from the player's drawing (`VoxelExtractor` + `VoxelMeshBuilder`); enemies are procedural voxel creatures |
| Real-time gesture combat: tap attack, swipe dodge, hold ability | ✅ |
| 3–5 enemy types + boss (Shrine Warden) | ✅ 5 kinds |
| Discoveries, chests, items, Core fragments | ✅ |
| Game-time freeze (state preserved mid-fight at 0:00) | ✅ |
| Condition system (Energised→Weak), recovery loop | ✅ 3-day rolling Attention average; always recoverable |
| Evolution (Origin → Awakened → Ascended) with reveal sequence | ✅ |
| Permanent persistence (creature, world, daily records) | ✅ atomic JSON in the App Group container |
| No purchasable Adventure Time | ✅ by design — there is no code path that grants time for money |

Not yet built (post-MVP per spec §23/§27): subscriptions/paywall, social
features, additional creature slots, GPS, additional zones beyond the
Meadow's first areas.

## Project layout

```
CORE/
├── project.yml                  # XcodeGen definition (app + extension targets)
├── Config/                      # Info.plist / entitlements (generated settings)
├── Sources/
│   ├── App/                     # COREApp, AppState (orchestration), RootView
│   ├── Models/                  # Creature, ElementalCore, GameState, adventure models
│   ├── Services/
│   │   ├── Tuning.swift         # every tuning variable + Attention formula
│   │   ├── ScreenTimeService.swift
│   │   ├── CreatureGenerator.swift
│   │   ├── AdventureEngine.swift
│   │   └── GameStore.swift
│   ├── Features/                # Onboarding, Drawing, Generation, Camp, Adventure, Evolution, Settings
│   └── Shared/                  # CreatureSpriteView, badges
└── Extensions/ActivityMonitor/  # DeviceActivity monitor extension
```

## Building

Requires Xcode 15+, iOS 17 SDK. The project file is generated with
[XcodeGen](https://github.com/yonaskolb/XcodeGen):

```bash
brew install xcodegen
cd CORE
xcodegen generate
open CORE.xcodeproj
```

Set your development team in `project.yml` (or Xcode signing settings).

- **Simulator**: fully playable. Screen time comes from debug sliders in
  Settings; AR is replaced with a painted Meadow backdrop.
- **Device**: AR works immediately (camera permission). Real screen-time
  data additionally requires the **Family Controls entitlement**.

## Testing the AR

AR requires a physical iPhone — the simulator has no camera or ARKit.

1. Open the project (see Building), plug in an iPhone, select it as the
   run destination, and hit Run. A free Apple ID personal team is enough
   for on-device installs (re-sign every 7 days; a paid account removes
   that limit).
2. First launch asks for camera permission; draw a creature, reach camp,
   tap ENTER WORLD.
3. Point the phone at a well-lit floor and pan slowly — the coaching
   overlay guides the scan. Once a horizontal plane is detected the
   creature anchors to it: a 3D voxel model generated from the drawing
   (`VoxelExtractor.fromDrawing` → `VoxelMeshBuilder.entity`), which you
   can walk around and view from any angle. Enemies appear beside it as
   procedural voxel creatures.

The creature-generation pipeline (drawing → voxel grid → inflated mesh)
matches the web prototype exactly, so what players see in the browser
demo is what they get in AR.

## Screen Time: how it works and what Apple requires

Apple never exposes raw usage totals to apps. CORE therefore:

1. asks the user to pick distraction apps/categories with
   `FamilyActivityPicker` (the selection is opaque tokens — CORE never
   learns which apps they are, a genuine privacy win worth keeping in
   marketing copy);
2. registers a ladder of `DeviceActivityEvent` usage thresholds
   (5, 10, 15, … minutes) for the selection;
3. the `ActivityMonitor` extension records the highest threshold crossed
   each day into the shared App Group;
4. the app converts that stair-stepped estimate through
   `AttentionScoreCalculator` into today's Adventure Time.

**Entitlement**: `com.apple.developer.family-controls` works in
development builds after enabling the capability; **distribution
requires approval** via Apple's
[Family Controls request form](https://developer.apple.com/contact/request/family-controls-distribution).
Apply early — turnaround is typically weeks. Until granted, TestFlight
builds can fall back to `SimulatedScreenTimeProvider` (self-reported /
debug usage) so loop validation isn't blocked.

## Design decisions worth knowing

- **The formula is the product.** `Tuning.swift` holds every constant:
  grace bands (30 m distraction / 3 h total cost nothing), decay rates,
  bonus thresholds, fragment counts, condition bands. MVP testing is
  expected to change these numbers, so nothing is inlined.
- **Failure is never punishment.** Losing a fight retreats the creature
  (15 HP) instead of killing it; a bad screen day degrades condition,
  which a 3-day rolling average recovers; minimum daily time is 1:00 so
  the relationship is never fully severed.
- **The freeze is a feature.** At 0:00 the engine snapshots the exact
  state — including a mid-fight enemy — and the next session resumes
  there ("The Stonehusk is still here…").
- **The drawing is the creature.** Rather than generic 3D models, the
  AR entity and every 2D view render the player's own (stylised) drawing,
  with Core auras and stage adornments layered on. Server-side generative
  art can later replace `HeuristicCreatureGenerator` behind the
  `CreatureGenerating` protocol without touching game code.

## MVP success metrics (spec §29)

`GameState.dailyRecords` retains every day's distraction minutes, total
minutes, Attention Score, and earned/used Adventure Time — the raw data
for baseline-vs-current behaviour change, 5-minute achievement rate, and
streaks. Wire these into your analytics tool of choice; no analytics SDK
is bundled in the MVP.
