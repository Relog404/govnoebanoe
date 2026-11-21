shader_type canvas_item;
render_mode blend_mix;

// Артефакты «нестабильного чипа»: полосы, RGB-развал, шум, сканлайны.
uniform float glitch : hint_range(0.0, 1.0) = 0.0;
uniform float scanlines : hint_range(0.0, 1.0) = 0.3;
uniform vec4 tint : source_color = vec4(0.92, 1.0, 0.97, 1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

void fragment() {
	vec2 uv = UV;
	float t = TIME;
	float g = glitch;

	// Горизонтальные сдвиги целыми полосами.
	float band = floor(uv.y * 60.0);
	float jitter = (hash(vec2(band, floor(t * 24.0))) - 0.5) * 0.05 * g;
	float active = step(0.72 - g * 0.6, hash(vec2(band * 0.73, floor(t * 8.0))));
	uv.x += jitter * active;
	uv.x += sin(uv.y * 120.0 + t * 6.0) * 0.0012 * (0.4 + g);

	// Хроматическая аберрация.
	float ab = 0.0012 + g * 0.006;
	vec4 col;
	col.r = texture(TEXTURE, uv + vec2(ab, 0.0)).r;
	col.g = texture(TEXTURE, uv).g;
	col.b = texture(TEXTURE, uv - vec2(ab, 0.0)).b;
	col.a = 1.0;

	// Шум.
	float noise = hash(uv * vec2(640.0, 360.0) + vec2(t * 60.0, 0.0));
	col.rgb += (noise - 0.5) * (0.02 + g * 0.16);

	// Дизеринг + «шахматка» при нестабильности.
	float dither = hash(floor(uv * vec2(320.0, 180.0)) + vec2(floor(t * 60.0)));
	col.rgb = floor(col.rgb * 24.0 + dither * g * 1.5) / 24.0;
	float checker = mod(floor(uv.x * 320.0) + floor(uv.y * 180.0), 2.0);
	col.rgb = mix(col.rgb, col.rgb * 0.78, checker * g * 0.35);

	// Сканлайны.
	float scan = step(0.5, fract(uv.y * 180.0));
	col.rgb *= 1.0 - scanlines * 0.35 * scan;

	// Виньетка.
	vec2 d = uv - 0.5;
	col.rgb *= 1.0 - dot(d, d) * 0.85;
	col.rgb *= tint.rgb;

	COLOR = col;
}
