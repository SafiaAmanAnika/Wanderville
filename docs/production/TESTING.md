# Testing and evidence

Source coverage and existing tests for the full game, with runtime gaps stated separately.

<details>
<summary><strong>Explore this page</strong></summary>

[Home](../../README.md) · [Current documentation checks](#current-documentation-checks) · [Feature audit](#feature-audit) · [Test map](#test-map) · [Acceptance gaps](#acceptance-gaps)

</details>


## Current documentation checks

Date: **2026-11-01**. The actual campus Map scene was rendered in Godot 4.6.2 at overview and panoramic sizes; both PNG saves returned OK. The README shows the actual overview capture alongside a separately generated promotional banner. This was an offline scene render, not a signed-in gameplay test.

The app was imported with an isolated SQLite in-memory URL solely to generate OpenAPI and SQLAlchemy metadata. No live player database was queried or migrated. Generation found 56 mapped tables, 124 paths and 136 operations. Six shop method/path pairs are registered twice.

Documentation checks passed for local links across 14 Markdown files, 32 SVG/draw.io XML files, eight image files and schema JSON. The stored OpenAPI matches the current application schema exactly. `git diff --check` passed. Checks also covered schema coverage and operation counts. These checks do not prove the player walkthrough or networking works at runtime.

## Latest regression run

On 2026-11-01, Python 3.12 ran the selection `pytest -m "not integration and not postgres" -q` against the disposable SQLite fixture. Across the initial run and resumed coverage, **439 tests passed and 33 skipped**; 18 tests were excluded by the marker expression. The skipped selected tests include Godot-dependent checks because the configured executable was unavailable. Some real-process tests do not carry the integration marker, so they were selected and then skipped by their availability guard.

The initial run stopped at the 120-second timeout in `test_native_falls_back_to_pcm_when_the_host_cannot_encode_opus`. That test passed in isolation, then the entire voice module and all remaining selected tests completed successfully: **171 passed, 32 skipped** in 235.66 seconds. This records a transient timeout rather than claiming one uninterrupted green run. No runtime code was changed to obtain these results. PostgreSQL-specific and excluded integration tests were not run.

## Feature audit

The expanded documentation was checked against actual Godot controllers, scenes, catalogs and audio calls, rather than only backend routes. The inspected definitions include **6 house choices, 5 floor finishes, 228 furniture entries in 11 categories, 10 minigame fish, 6 pet species, 6 character presets and 12 storefront choices**. Fishing timer/progress constants, housing wood costs, scene music mappings and the temporary signed-in construction counter were read from their owning scripts.

The audit also corrected two misleading earlier descriptions: current farming is driven by mouse clicks with E for carrying tiles, and visible day/night tint uses a local 30-minute cycle while the backend defaults to 40 minutes. This is a source review, not a claim that all those workflows were newly played through.

## Test map

| Area | Existing tests or runner | What it can establish |
| --- | --- | --- |
| API/auth contracts | [contract](../../code/server/tests/contract), [auth](../../code/server/tests/auth) | Schemas, identity and response behavior |
| Farming/inventory | [farming](../../code/server/tests/farming), [inventory](../../code/server/tests/inventory) | Ownership, crop mutations and stack rules |
| Database | [database](../../code/server/tests/database) | Migration/integrity behavior under the configured engine |
| Integrated multiplayer | [verify_enet_gameplay.py](../../code/server/scripts/verify_enet_gameplay.py) | Disposable backend/host and two-client scenarios |
| Godot checks | [client tests](../../code/client/tests) | Specific scene, UI and integration assertions |
| House entry/camera | [housing_entry_check.gd](../../code/client/tests/housing_entry_check.gd), [world_camera_check.gd](../../code/client/tests/world_camera_check.gd) | Existing transition/camera assertions; does not replace a complete build/decorate/save walkthrough |
| Companions | [pet_companions_check.gd](../../code/client/tests/pet_companions_check.gd), [pet_authenticated_check.gd](../../code/client/tests/pet_authenticated_check.gd) | Existing companion behavior and signed-in integration checks |
| Wardrobe/customization | [customization_lobby_check.gd](../../code/client/tests/customization_lobby_check.gd) | Existing editor/room checks |
| Tree cutting | [tree_cutting_input_check.gd](../../code/client/tests/tree_cutting_input_check.gd) | Existing tree interaction checks |
| Entrances/onboarding | [campus_lobby_entrances_check.gd](../../code/client/tests/campus_lobby_entrances_check.gd), [onboarding_check.gd](../../code/client/tests/onboarding_check.gd) | Existing room-entry and first-session UI checks |

For backend tests, use the test fixture configuration and an isolated database. SQLite checks do not establish PostgreSQL locking correctness.

## Acceptance gaps

- The rewritten manual has not been played through in this pass.
- Fishing and housing need an in-game check of their shared F binding.
- House entry/exit, reconnect, two-client visits and inventory UI need separate runtime acceptance.
- Build each house, preview all floors, buy/rotate/resize/rearrange furniture, cancel a carried piece and reload the account-scoped save.
- Exercise fishing success, timeout, Esc, rejected catch recording, aquarium display and restoration of movement/music.
- Walk through opening a storefront, stocking/unstocking, a friend's purchase and sales history; distinguish temporary construction wood from server inventory.
- Check all four music contexts, volume/mute persistence, SFX during a paused minigame, and audible action/reward cues.
- Confirm pet selection persistence, follow/wander/sleep transitions, Wardrobe save versus Mirror preview, and server seasons versus local tint.
- Banner artwork is promotional and must not be used as gameplay evidence.
- Deployment health, external email and public provider availability were not tested.

<details>
<summary><strong>Source and verification</strong></summary>

Source reviewed: `31ca97c39c05` · 2026-11-01. Source inspection is not a new gameplay test.

</details>

[← Previous](NETWORKING.md) · [Back to top](#testing-and-evidence) · [Next →](BUILD_AND_DEPLOY.md)
