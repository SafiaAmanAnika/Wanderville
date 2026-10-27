shader_type canvas_item;
uniform float selection : hint_range(0.0, 1.0) = 0.0;

// A single painted silhouette for both colors, with the wood rim preserved.
void fragment() {
	float brightness = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	float face = smoothstep(0.58, 0.81, brightness);
	// Preserve white petals without leaving a rectangular patch of cream.
	float saturation = max(COLOR.r,max(COLOR.g,COLOR.b)) - min(COLOR.r,min(COLOR.g,COLOR.b));
	float flower_zone = smoothstep(0.86,0.93,UV.x) * smoothstep(0.60,0.76,UV.y);
	face *= mix(1.0,smoothstep(0.09,0.18,saturation),flower_zone);
	float grain_shade = clamp(1.0 + (brightness-0.85)*2.3,0.72,1.15);
	vec3 maroon = vec3(0.5215686, 0.2078431, 0.2431373) * grain_shade;
	COLOR.rgb = mix(COLOR.rgb, maroon, selection * face);
	COLOR.a = smoothstep(0.85, 0.99, COLOR.a);
}
