export const SHADERTOY_VERTEX = `
void main() {
  gl_Position = vec4(position.xy, 0.0, 1.0);
}
`;

export function wrapShadertoyFragment(source, channelCount = 0) {
  let channels = "";
  if (channelCount >= 1) channels += "uniform sampler2D iChannel0;\n";
  if (channelCount >= 2) channels += "uniform sampler2D iChannel1;\n";
  return `
precision highp float;
uniform vec3 iResolution;
uniform vec3 iChannelResolution[4];
uniform float iTime;
uniform vec4 iMouse;
${channels}
// Not Shadertoy uniforms — the dashboard's own. Every wrapped shader gets the
// active theme's colors here, so a palette can follow the Settings picker
// instead of the literal its original author happened to pick. sRGB 0..1, the
// same space the hand-ported literals were written in; see ShadertoyLayer's
// syncTheme for why these do not go through THREE.Color.
uniform vec3 uVoid;
uniform vec3 uAccent;
uniform vec3 uStrong;

// These effects were built around vivid literals, so dropping a theme color in
// raw leaves the darker palettes looking washed out. Rescaling to a target peak
// keeps each shader's original brightness while letting its hue follow the
// theme.
vec3 themeTint(vec3 c, float peak) {
  float m = max(max(c.r, c.g), c.b);
  return m > 0.0 ? c * (peak / m) : vec3(peak);
}
${source}
out vec4 outColor;
void main() {
  mainImage(outColor, gl_FragCoord.xy);
}
`;
}
