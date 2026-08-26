// Shadertoy 7fyXRh — terrain / water-color noise.
// Source pasted by Nick 2026-08-25 (shadertoy.com is Cloudflare-blocked from Tawa).
// Typical Shadertoy license: CC BY-NC-SA 3.0.
// https://www.shadertoy.com/view/7fyXRh

float rng(vec2 co) {
    uvec2 v = uvec2(ivec2(co));

    v = v * uvec2(1597334677u, 3812015827u);
    uint h = (v.x ^ v.y) * 1597334677u;

    return float(h) * (1.0 / 4294967296.0);
}

float noise(vec2 co, float scale) {
    vec2 tco = co*scale;
    vec2 vertex = floor(tco);
    vec2 t = fract(tco);

    vec2 weight = smoothstep(0.0,1.0,t);

    float sw = rng(vertex+vec2(0.0,0.0));
    float se = rng(vertex+vec2(1.0,0.0));
    float nw = rng(vertex+vec2(0.0,1.0));
    float ne = rng(vertex+vec2(1.0,1.0));

    float south = mix(sw,se,weight.x);
    float north = mix(nw,ne,weight.x);

    return mix(south,north,weight.y);
}

float terrain(vec2 co, const float scales[6], float mult) {
    float height = 0.0;
    for (int i = 0; i<scales.length(); i++) {
        height += noise(co,scales[i])/scales[i];
    }
    return mult*height;
}

void mainImage( out vec4 fragColor, in vec2 fragCoord ) {

    const float scales[6] = float[](25.0,15.0,9.0,4.0,1.7,0.7);

    vec2 prePix = fragCoord/iResolution.xy;
    float preNoise = terrain(3.0*prePix+iTime,scales,1.0);
    vec2 pix = (5.0*prePix)-vec2(preNoise,0.7*preNoise);

    vec3 col = (0.5+(pow(terrain(pix+vec2(-0.09*iTime,0.3*iTime),scales,0.5),2.0)))*vec3(0.0,0.5,0.9);

    fragColor = vec4(col,1.0);
}
