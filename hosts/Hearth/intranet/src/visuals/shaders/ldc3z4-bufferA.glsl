// Shadertoy ldc3z4 — "PS2 menu" by incub. Buffer A (dots).
// Source pasted by Nick 2026-08-25.
// https://www.shadertoy.com/view/ldc3z4

float pi = 3.14159265358979323;
#define clamps(x) clamp(x,0.,1.)
vec3 rX(vec3 p, float a) { //YZ
	float c,s;vec3 q=p;
	c = cos(a); s = sin(a);
	p.y = c * q.y - s * q.z;
	p.z = s * q.y + c * q.z;
    return p;
}
vec3 rY(vec3 p, float a) { //XZ
	float c,s;vec3 q=p;
	c = cos(a); s = sin(a);
	p.x = c * q.x + s * q.z;
	p.z = -s * q.x + c * q.z;
    return p;
}
vec3 rZ(vec3 p, float a) { //XY
	float c,s;vec3 q=p;
	c = cos(a); s = sin(a);
	p.x = c * q.x - s * q.y;
	p.y = s * q.x + c * q.y;
    return p;
}
vec2 dirDist(float dir, float dist) {
    return vec2(cos(dir)*dist,sin(dir)*dist);
}
vec3 animation(vec2 uv, float time) {
    float circles = 0.;
    for (float k = 0.; k < 8.; k++) {
        float i = (k/7.)*pi;
        float DIRECTION = time*k*0.1;
        float DISTANCE = 0.2;
        vec3 POSITION = vec3(dirDist((DIRECTION),(DISTANCE)),0.);
        POSITION = rY(POSITION,time*1.1); POSITION = rZ(POSITION,time*2.15); POSITION = rX(POSITION,time*0.52);
        circles = max(circles,clamps(1.-(length(uv-POSITION.xy)*40.)));
    }
    circles = clamp(circles,0.,1.);
    return vec3(circles);
}
void mainImage( out vec4 fragColor, in vec2 fragCoord ) {
	vec2 uv = fragCoord.xy / iResolution.xy;
    vec2 suv = uv-.5; suv.x /= iResolution.y/iResolution.x;
    float time = iTime;
    vec3 drawing = animation(suv,time);
    // The exponent vector is what made this pass blue: a high exponent crushes a
    // channel, a low one keeps it. Deriving it from the accent generalises that
    // — the accent's strongest channel gets 1.0, its weakest 2.5 — and lands
    // back on roughly the original (2.5, 1.8, 1.0) for a blue accent.
    drawing = vec3(pow(drawing, mix(vec3(2.5), vec3(1.0), themeTint(uAccent, 1.0))));
	fragColor = vec4(drawing,1.);
}
