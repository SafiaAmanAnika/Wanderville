# UI assets

`google-g.png` is Google's official multicolored G, downloaded unchanged from
[Google Identity](https://developers.google.com/static/identity/images/g-logo.png).
The authentication cards display it proportionally inside a white button with
bundled sans-serif text. See [Google's sign-in branding guidance](https://developers.google.com/identity/branding-guidelines).

`loading_boot.png` is rendered from the supplied logo, shared maroon cat progress
bar and original world background. It covers startup before the live UI exists.
Scene changes show measured resource progress; network waits use a moving segment
because their total duration is unknown. The same bar appears inside account,
profile, inventory, social, voice, map and character-save loading states. No
background vignette or tagline is added.

The other new auth marks and borders are drawn by the game's UI code. No Sprout
Lands package or reference-game artwork is bundled by this change.

## Additional supplied UI pack

# Wanderville UI — under 20 MB edition

18 assets encoded as lossless WebP to reduce the ZIP size. Original resolution,
colors and alpha are preserved. Every decoded RGBA byte was checked against
the corresponding original PNG. Godot supports WebP textures.

Open PREVIEW.html to inspect the images and interactive button states.
manifest.json records dimensions, draw targets and file hashes.
The original PNG folder and ZIP are kept separately in Downloads, unchanged.
Original reference copies are omitted from this compact delivery to save space.
No game files changed; nothing installed or pushed.
