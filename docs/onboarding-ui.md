# Authentication and first entry

Begin Adventure opens Login directly over the title's existing village backdrop. A persistent `journey_backdrop.gd` owns the atmospheric video player across title, authentication, recovery and first-time character selection; authentication adds a little darkness without restarting the player. The existing image remains the placeholder until a background VideoStream is assigned on TitleScreen. Gameplay hides and pauses this backdrop.

Login, signup, password recovery, reset and verification use `auth_shell.gd`: cream panels, compact fields, maroon primary actions, inline errors, and small envelope/check states. Login includes Create Account and Forgot Password links. Password fields have individual visibility controls, and signup/reset retain password-strength feedback. Failed recovery requests stay on the form with retry feedback. Successful requests keep the server's non-enumerating email behavior.

The UI uses a consistent bundled sans-serif for headings, fields, controls and body copy, reserving pixel lettering for the wordmark and small brand marks. The title's music control is an icon with distinct speaker/muted states and action tooltips.

Both account forms use the unchanged official Google G on a white button. The existing system-browser OAuth/PKCE flow is retained, and both completion paths use `auth_flow.gd` for the same session/profile loading. The login backend now accepts email identifiers, including normalized email case and addresses longer than usernames, alongside the existing username wire field. Verification, password checks, inactive-account checks, lockout counters and refresh behavior remain shared.

## Routes

- Returning setup: Title → Continue → authenticated profile/state load → existing World.
- New account: Title → Login/Signup/Verification → shared character editor → save preset and campus setup → existing World.
- Returning password/Google login also goes straight to World when setup is complete.

The backend exposes only the `campus` map code, so no map-choice or showcase step appears in onboarding. Existing owned worlds are retained; there is no artificial Create World option. Old map-menu resources remain as legacy files, while SceneManager's map-menu navigation aliases route through the current setup check.

## One character editor

`creator_panel.gd` provides three presentations using the six existing Girl A/B/C and Boy A/B/C presets:

| Mode | Behavior |
| --- | --- |
| First-time | Six static portrait cards, one live preview, Choose Character saves setup and enters World. Back returns to title. |
| Wardrobe | Same preset editor, Save Appearance confirms the backend write; Cancel discards the draft. Saving retains the owned world and player position. |
| Mirror | Equipped character only, with direction and playback controls. Options and Save are absent; even a programmatic save cannot mutate the account. Legacy equipped farmers are previewed faithfully. |

There are no hair, skin, clothing or accessory tabs. The preview offers Idle, Walk and Run, all eight directions, Pause/Play and frame stepping. Front idle calibrates the apparent height once per character. The 321px source ground anchor stays on a fixed preview line throughout the animation; the current frame never changes the pivot or scale. Small cards use static TextureRects and keep their captions clear.

## First entry

A non-blocking sage overlay displays “Welcome to Wanderville”, “A new beginning, a world of possibilities.” and “Move with WASD · Press E to interact”, then fades after 3.5 seconds. Actual world WASD bindings are installed while the world is active and released when leaving it. The existing server tutorial acknowledgement plus account/server-scoped local preferences prevent replay. No inventory, economy or world ownership is changed by the welcome.

Contextual prompts appear near spawn until movement is learned, near the existing farming area, and near the actual CDS shop/storage building. The existing reception interaction explicitly labels E to talk to the receptionist. Hints respect modal state and existing housing prompts; no mandatory tutorial screen blocks movement.

## Validation

- `onboarding_check.gd`: rendered auth/recovery states, password eyes and strength, shared backdrop identity, compact layouts, static portrait bounds, all six preview ground anchors, Mirror protections, Wardrobe drafts, legacy previews, actual WASD/movement during welcome, contextual locations and one-time fade behavior.
- `onboarding_integration.gd`, using `verify_integration.py --onboarding`: real signup, in-memory verification email, email login and invalid-password feedback, character setup with no redundant map step, server tutorial acknowledgement, reset email/password, returning login, Mirror/Cancel without backend writes, Wardrobe Save, and restart → Continue → World. Disposable run `client_777abd37`: 0 failures, restart 0 failures.
- Authentication unit suite: 18 passed, including email/username shared lockout and long email identifiers.
- Client load, 2,016 original frame slots, customization room and existing title/CDS checks passed.

All test accounts and databases are disposable. No real email was sent. Live Google account consent/system-browser completion and a production background video were not exercised. Existing map texture UID fallback warnings remain; the map, world and both lobby background/collision scenes are unchanged.

[Open rendered review](../test-output/onboarding/review.html).

References: [Sprout Lands controls](https://cupnooble.itch.io/sprout-lands-ui-pack), [Godot UI plugin reference](https://maaack.itch.io/sprout-lands-ui-godot-plugin), and [Google Identity branding](https://developers.google.com/identity/branding-guidelines). References informed composition; their game artwork and asset packages were not copied.
