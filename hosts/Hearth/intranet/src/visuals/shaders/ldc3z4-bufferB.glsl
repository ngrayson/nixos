// Shadertoy ldc3z4 — "PS2 menu" by incub. Buffer B (trail).
// iChannel0 = Buffer A, iChannel1 = previous Buffer B.
// Source pasted by Nick 2026-08-25.
// https://www.shadertoy.com/view/ldc3z4

#define clamps(x) clamp(x,0.,1.)
float pi = 3.14159265358979323;
vec2 circle(float a){return vec2(cos(a),sin(a));}
void mainImage( out vec4 fragColor, in vec2 fragCoord ) {
	vec2 uv = fragCoord.xy / iResolution.xy;
    vec4 d = vec4(0);
    #define L 8.
    for(float i=0.;i<L;i++){
        vec2 p = circle((i/L)*pi*2.);
        p.x /= iResolution.x/iResolution.y;
		d = max(d,texture(iChannel1,uv+(p*0.00015)));
    }
	fragColor = pow(texture(iChannel0,uv),vec4(10.))+(clamps(d)*0.95);
}
