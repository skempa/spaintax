# CORE — spec v0.1, condensed + implementation mapping

The authoritative product spec is v0.1 ("Project Specification — Working
Title: CORE"). This file condenses it and maps each section to code.

## The hypothesis (§30)

> A personalised creature that the player created themselves will create
> a stronger emotional incentive to reduce doomscrolling than
> conventional screen-time blocking or productivity rewards.

Everything in the MVP exists to test this. If users don't voluntarily
reduce screen time to earn 5 minutes with their creature, don't build
more RPG complexity — fix motivation first.

## Non-negotiables

- **The game is the reward** (§2.1). Never position as productivity.
  Onboarding copy (`OnboardingView`) ends on "Put the phone down. Your
  creature is waiting." — not on wellbeing claims.
- **Adventure Time cannot be bought** (§24). There is deliberately no
  code path that converts money into seconds. Keep it that way.
- **Negative effects are recoverable** (§2.4, §19–20). Condition uses a
  3-day rolling average (`AppState.updateCondition`); defeat retreats,
  never kills; minimum 1:00/day keeps the bond alive.
- **The primary creature is permanent** (§2.3, §11). No deletion UI.

## Section → code map

| Spec § | Topic | Where |
|---|---|---|
| 5–6 | Adventure Time & Attention Score | `Services/Tuning.swift` (`AttentionScoreCalculator`) |
| 7 | Draw → AI interpret → Core assign | `Features/Drawing/`, `Services/CreatureGenerator.swift` |
| 8 | Six Cores table | `Models/ElementalCore.swift` |
| 9–10 | Core collection & evolution stages | `Models/Creature.swift` (`evolutionStage`), `Features/Evolution/` |
| 12 | AR system | `Features/Adventure/ARAdventureView.swift` |
| 13 | The Meadow | `Models/AdventureModels.swift` (`MeadowZone`) |
| 14 | Camp | `Features/Camp/CampView.swift` |
| 15–17 | Five-minute adventure & combat | `Services/AdventureEngine.swift`, `Features/Adventure/AdventureHUD.swift` |
| 18 | Game-time freeze | `AdventureEngine.freeze()`, `AdventureSnapshot` |
| 19–20 | Condition & recovery | `Models/Creature.swift` (`CreatureCondition`), `AppState.updateCondition` |
| 21 | Core discovery (fragments) | `AdventureEngine.rollDiscovery`/`defeat`, `Tuning.fragmentsPerCore` |
| 25 | MVP scope | README status table |
| 29 | Metrics | `GameState.dailyRecords` |

## Attention formula (implemented, spec-matching)

```
seconds = 300
        − max(0, distraction − 30) × 2.0        # distraction over 30 m
        − max(0, total − 180) × 0.5             # total over 3 h
        + bonus (only if distraction ≤ 10 and total ≤ 90):
              (10 − distraction) × 6 + (90 − total) × 1, capped at 120
clamped to [60, 420]
```

Spec worked examples: 105 m distraction + 2 h total → **2:30**; 15 m +
1 h 45 → **5:00**; near-zero day → up to **7:00**. ✅

## Deferred by design

Subscription/paywall (§24), social (§23), additional creatures (§11),
extra zones, GPS, server-side generative art, breeding/PvP/seasons (§27).
