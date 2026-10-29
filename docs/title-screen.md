# Landing screen and loading UI

Startup opens `Scenes/menus/TitleScreen.tscn` directly. There is no seed-opening
screen, delay, or replay action. Email verification and reset deep links retain
priority. Old opening preferences are ignored.

The title uses `Assets/background/bg.webp` and the supplied
`Assets/background/Wanderville_Logo.png`. The original map, houses and social
rooms remain in use. The title adds a warm vignette, a fine gold frame,
subtle drifting fireflies. The background asset is
`Assets/background/bg.webp`; replace that file to update the shared artwork.
Title, authentication and loading use the same background construction, with
identical aspect-preserving scaling and crop at every window size.

Menu cards share one painted cream texture. Mouse wheel, arrow keys and
controller focus move selection; the selected card fades to maroon (#85353e)
and a separate pixel cat moves to it. Other cards stay beige. Pointer hover
does not override selection. Only Trailer, Settings and Sound keep icons.

Continue Journey appears for accounts with valid character and world setup.
It validates the session and loads saved gameplay data before entering the
world. Offline failures retain the account and allow retry. Begin Adventure
opens authentication, or resumes incomplete setup for an authenticated player.

Settings shares the gameplay overlay. Leave World saves the scoped local house,
exits a farm visit if needed and returns to title while retaining the account.
Music mute preserves the volume setting. Credits contains the project/engine
acknowledgement. Desktop exports include Exit.

`Assets/ui/loading_boot.png` covers engine startup. Scene changes use the live
version: original background, supplied logo, maroon bar and pixel cat. Threaded
scene loading reports measured progress; network waits use a moving segment
without an invented percentage. Inline account, profile, inventory, social,
voice and character-save waits use the same progress component.

Assign Background Video on TitleScreen when the atmospheric loop is ready.
The persistent silent player is shared across title/auth routes. Trailer Video
is separate; until configured, Watch Trailer opens a coming-soon message.

`tests/landing_check.gd` checks immediate startup, navigation, fixed card geometry,
Continue, login, Settings, sound, compact layouts, original map and CDS access.
`tests/continuation_check.gd` checks immediate startup, loading bars, inline states,
Leave World and scoped local housing. These tests use isolated APPDATA profiles.
Font and artwork rebuild helpers remain in `code/client/tools/`; their source
assets and licenses are retained for maintenance.
