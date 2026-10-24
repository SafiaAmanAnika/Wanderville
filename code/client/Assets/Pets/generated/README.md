# Generated sleeping poses

`sleep_atlas.png` was produced with the built-in imagegen tool with transparent
background enabled. The supplied cat, dog, rabbit, fox and red panda walking
sheets were the five image references. Duck identity was described in the
prompt to match the supplied duck sheet. Walking assets were not changed.

The image is RGBA, 1536×1024, with six 512×512 cells. Cell order is cat, dog,
rabbit / fox, duck, red panda. `sleep_frames.json` records the visible body bounds
at alpha ≥200 in each cell; it is used for runtime scaling and ground anchoring.
The PNG is the original generated output, with its alpha channel preserved.

## Exact generation prompt

Create ONE production sprite atlas for Wanderville matching these reference pets. References supply identity and style. Actual transparent RGBA background, no checkerboard, no scenery, no text, no Z letters, no cast shadows. Atlas canvas 1536x1024, exact 3 equal columns x 2 equal rows of 512x512 cells. ONE sleeping creature per cell, matching the flat cute chibi outlines and warm simple cel shading in reference walk sheets. TOP ROW left to right: orange tabby CAT with cream muzzle/paws and tail tip curled sleeping; floppy brown-eared tan-and-white DOG curled with muzzle resting on paws; gray cream-bellied pink-eared RABBIT tucked lying with long ears relaxed. BOTTOM ROW left to right: orange FOX with dark paws and white-tipped bushy tail curled around body; bright yellow downy DUCK with orange beak and feet tucked sleeping with beak nestled into wing; rust RED PANDA with dark legs, cream face markings and striped tail curled around itself. ALL eyes CLOSED with peaceful sleepy expressions. Duck matches the same style: round yellow head, small head tuft, orange broad beak, cream yellow wing/belly. Preserve the five references' exact species markings and palette, add no accessories. Strict uniform framing in EVERY 512 cell: center horizontally at x=256, ground contact baseline at y=440, creature about 390 pixels wide and 230 pixels tall above baseline, ears may rise slightly higher. Generous transparent gutters, NO cell dividers. Clean game sprites suitable for 128x128 downscaling. All face southeast/three-quarter toward viewer. Each pet is one continuous whole-body drawing.
