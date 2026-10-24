# Character animation foundation

The six original character designs remain the playable cast. Girl A (`CharacterA`) is the visual reference. No hair, skin, outfit or accessory customization was added.

## Shared standard

- Each action uses a 2688 x 3584 PNG: six columns, eight rows, 448 x 448 cells.
- Rows are front, front-right, right, back-right, back, back-left, left, front-left.
- Every atlas region stays inside its exported cell. There is no runtime head registration or shifted sampling window.
- Ground contact is at the bottom edge of source pixel row 320, or `y = 321` exclusive. With centered 448 px frames, that is 97 px below the sprite origin, matching the existing foot-area collision geometry.
- All six character scenes, the main world, remote avatars and authority bodies use a uniform `Vector2(1.18, 1.18)` world scale. The smaller lobby artwork uses `Vector2(0.72, 0.72)` for room characters, matching the existing receptionist. Portraits and the UI preview use their own display scales.
- Idle and Walk use 6 FPS, Run uses 10 FPS, and tools use 8 FPS. Gameplay tools play once; the review preview loops them for inspection.

The original palette, hats, hair, faces and proportions are retained. Front idle heights span 167-174 source pixels across the cast; small silhouette differences are mainly hat styles, and are not corrected by stretching individual characters.

## Artwork and playback corrections

70 displaced source frames in 13 PNG sheets were translated vertically inside their cells. This includes Boy B's side-running third pose (24 px downward in the original) and Girl C's scythe poses. Translations preserve the original pixels and tool effects, with bounds checks preventing clipping. The original idle, watering and fishing PNGs are unchanged. Tool alignment ignores rods, blades and water and tolerates up to two source pixels of sole-outline/antialias variation. The exact translations are recorded in [animation-registration.json](animation-registration.json).

Each character now has a separate `walk.png`. These are six-pose, eight-direction walks articulated from the original idle artwork, with a smaller stride, alternating foot lifts and restrained upper-body motion. They are distinct image sequences, not slowed Run frames. The new sheets do not introduce the experimental long-leg proportions. The optional `GODOT_LONG_LEG_ART=1` path remains opt-in.

The shared controller rebuilds all seven actions from the same sheets used by the preview, including every tool direction. Movement speed remains 300 units/second. Network facing numbers now correctly map front-left, back-left and back-right, and stopping retains the last facing. Turning preserves Walk/Run phase.

The shared character editor provides rotation through all eight directions, Idle/Walk/Run, Play/Pause and one-frame stepping. The underlying animation loader and art review still cover all seven actions. First-time selection, Wardrobe Save/Cancel and read-only Mirror share this component; six small cards use static portraits. Existing character IDs are retained.

## Verification

Godot 4.6.2 checks completed with an isolated test profile under `test-output/animation-foundation/profile`:

- `animation_visual_review.gd`: 2,016 frame slots, 336 character/action/direction combinations, exact locomotion ground contact and actual AnimatedSprite2D advancement. A renderer exported all six poses of each action to 42 fixed-size 1440 x 1280 captures; all eight direction rows fit independently of monitor size.
- `reference_motion_check.gd`: the real Girl A controller moves, turns and stops in all eight directions at the existing speed. Stopping retains facing and has no position drift. Sixteen moving/standing captures were exported.
- `original_characters_check.gd`: all six character/action sets, direction round trips, preview rotation, pause/step/play controls, selection, cancellation, save/respawn and receptionist behavior.
- `lobby_spawner_check.gd`: all 12 character/lobby pairs use the selected scene and room scale.
- `lobby_interactions.gd`, `customization_lobby_check.gd` and `load_check.gd`: existing interaction, customization and script/scene loading checks.
- A recovery-mode editor import completed without script or import errors. The load check reports the existing duplicate `VBox` unique-name warning in the authentication UI.

Review artifacts:

- [Interactive capture review](../test-output/animation-foundation/review.html)
- [All six characters running in all eight directions](../test-output/animation-foundation/godot/run-2.png)
- [All six characters walking in all eight directions](../test-output/animation-foundation/godot/walk-1.png)
- [The actual in-game preview controls](../test-output/animation-foundation/lobby/original-picker.png)

The offline authoring tool is `code/client/tools/build_character_art.gd`. Run it with an empty Godot project and pass absolute client/output directory arguments after `--`. It writes drafts; it does not overwrite the source directory. Original modified PNG backups are in the ignored `.verification/animation-foundation-art-backup` directory, and helper-script backups are in `.verification/animation-foundation-backup`.

Voice, social/backend behavior, inventory, farming, network room membership and saved appearance schema are outside this change. Live multiplayer/backend flows were not rerun for these animation changes.
