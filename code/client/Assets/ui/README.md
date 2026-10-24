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
