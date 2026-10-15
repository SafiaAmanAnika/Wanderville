# Whole-room floor assets

Each palette folder contains floor_layer.png, floor_spritesheet.png, rooms/*.png and floor_positions.json. Room shapes, transparency, canvas offsets and sheet coordinates are unchanged. There are no 32 × 32 floor block PNGs.

Place room crops at their placement coordinates; use sheet_rect to read a whole room from its sheet. The full layer starts at canvas origin (0,0). Shared placement-grid coordinates are in ../placement_grid_32.json.

For custom complete-floor colors, use the original ../floor.png alpha and floor_layer_tones_native.png red channel. Upscale tones by the integer scale and offset in ../floor_positions.json. Floor RGB = clamp(targetRGB + toneR - 128,0,255), preserving floor alpha.
