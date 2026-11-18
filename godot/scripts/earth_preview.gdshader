shader_type spatial;
render_mode unshaded, shadows_disabled;

uniform sampler2D globe_map : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
// Illustrative phase until the simulation supplies a Sun vector and attitude.
uniform vec3 sun_direction = vec3(0.08, 0.99, 0.14);

void fragment() {
	vec3 to_sun = normalize(mat3(VIEW_MATRIX) * sun_direction);
	float cosine = dot(normalize(NORMAL), to_sun);
	float lit = smoothstep(-0.035, 0.2, cosine);
	float at_limb = pow(1.0 - clamp(dot(normalize(NORMAL), VIEW), 0.0, 1.0), 4.0);
	vec3 atmosphere = vec3(0.11, 0.34, 0.66) * at_limb * smoothstep(-0.08, 0.35, cosine);
	ALBEDO = texture(globe_map, UV).rgb * (0.003 + lit * (0.30 + 0.80 * max(cosine, 0.0))) + atmosphere;
}
