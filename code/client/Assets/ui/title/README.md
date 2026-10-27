# Painted title-screen cards

The landing screen uses the existing `Assets/background/bg.png` and
`Assets/background/Wanderville_Logo.png`. Neither original image was changed.
`logo.res` bundles the supplied logo losslessly; it is not generated artwork.

Generated with the built-in imagegen tool, using the user's landing-screen
reference for the painted card style:

- `cream-card.png`: cream center, wood border, copper nails and a small daisy.
- `selection-cat.png`: separate pixel cat generated with built-in imagegen.

The matching `.res` files contain portable lossless textures. Rebuild all three
resources with `tools/build_title_art.gd` as described in that file. Godot atlas
regions trim transparent margins without changing the source images.

All menu cards use the same cream-card texture and fixed dimensions. A shader
animates the face to maroon (#85353e) over 0.18 seconds; the wooden silhouette stays fixed.
One separate pixel cat moves to the selected card over 0.2 seconds. Selection
follows mouse-wheel movement and keyboard/controller focus. Pointer hover does
not change selection, so it cannot override scrolling or arrow-key navigation.
Only Watch Trailer, Settings and the sound toggle keep their functional icons.
Continue appears for a completed saved session; new players begin with Begin
Adventure selected. Watch Trailer remains selectable and opens a coming-soon
message until `trailer_video` is assigned. No community URLs are fabricated.

## Generation prompts

### Pixel cat selection indicator

Use case: stylized-concept. Asset type: transparent pixel-art sprite for a cozy game's menu selection indicator. Generate ONE small orange-and-white sleepy kitten, facing forward, lying with its chin resting and two little front paws dangling over an INVISIBLE horizontal ledge. A curled tail at the right, triangular ears, tiny closed happy eyes and a pink nose. True low-resolution pixel art with an effective 64 by 48 pixel grid, hard square pixel steps, limited warm palette of cream, ginger orange, chestnut outline and tiny pink, no soft painterly brush strokes, no gradients, no antialiasing, no 3D. Simple, cute silhouette readable at 70 pixels wide. Center the entire complete sprite in the image, generously clear transparent space around it. Output only the kitten on a genuinely transparent background, no ledge or board drawn, no text, no icons, no other objects, no glow or shadow cloud, no scenery.

### Cream card

Use case: stylized-concept. Asset type: production game UI button texture. Generate exactly ONE wide cream-colored hand-painted cozy farming-game menu card on a genuinely transparent background, horizontal aspect ratio about 5.2:1, ideally 1536x320. Match the cream Begin Adventure, Watch Trailer and Settings cards in the user's reference: softly irregular rounded rectangle, thick dark warm chocolate-brown wooden outer rim, honey/caramel beveled inner edge, pale buttercream parchment-colored wooden center with extremely subtle horizontal grain, four small copper nailheads near its corners, warm lower drop shadow. A tiny sprig of 2 green leaves and a very small white daisy may sit at the BOTTOM RIGHT corner, keep decoration restrained. Clean cute storybook-game illustration, richly painted but unobtrusive. Rectangle should occupy x=3%..97%, y=12%..88%. Center 80% of card MUST be completely EMPTY to overlay sharp clickable text and an icon in Godot. Absolutely NO text, NO lettering, NO symbols, NO plants in the label area, NO scene, NO background, NO extra objects, NO additional cards, NO watermark. Output only this single complete reusable cream menu card with alpha outside its silhouette.
