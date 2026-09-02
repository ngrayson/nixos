// Shadertoy ldc3z4 — "PS2 menu" by incub. Image (composite + vignette).
// iChannel0 = Buffer A, iChannel1 = Buffer B.
// Source pasted by Nick 2026-08-25.
// https://www.shadertoy.com/view/ldc3z4

#define clamps(x) clamp(x,0.,1.)
void mainImage( out vec4 fragColor, in vec2 fragCoord ) {
	vec2 uv = fragCoord.xy / iResolution.xy;
    vec2 suv = uv-.5; suv.x /= iResolution.y/iResolution.x;
	fragColor = texture(iChannel0,uv)+(texture(iChannel1,uv)*1.)+vec4(clamps(1.-(((length(suv)-0.2)+0.2)*2.))*themeTint(uAccent, 0.3),0.);
}
