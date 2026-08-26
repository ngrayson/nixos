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
uniform float iTime;
uniform vec4 iMouse;
${channels}
${source}
out vec4 outColor;
void main() {
  mainImage(outColor, gl_FragCoord.xy);
}
`;
}
