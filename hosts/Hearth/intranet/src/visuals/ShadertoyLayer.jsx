import { useFrame, useThree } from "@react-three/fiber";
import { useEffect, useMemo, useRef } from "react";
import {
  GLSL3,
  LinearFilter,
  RGBAFormat,
  ShaderMaterial,
  Vector3,
  Vector4,
  WebGLRenderTarget,
} from "three";
import { FullScreenQuad } from "three/addons/postprocessing/Pass.js";
import src7fy from "./shaders/7fyXRh.glsl?raw";
import srcLdcA from "./shaders/ldc3z4-bufferA.glsl?raw";
import srcLdcB from "./shaders/ldc3z4-bufferB.glsl?raw";
import srcLdcImage from "./shaders/ldc3z4-image.glsl?raw";
import srcLtx from "./shaders/ltXczj.glsl?raw";
import srcPixelGalaxy from "./shaders/pixel-galaxy.glsl?raw";
import srcPreciousEgg from "./shaders/precious-egg.glsl?raw";
import srcStarfieldGleam from "./shaders/starfield-gleam.glsl?raw";
import { SHADERTOY_VERTEX, wrapShadertoyFragment } from "./shaders/wrap.js";

function makeMaterial(source, channelCount = 0) {
  const uniforms = {
    iResolution: { value: new Vector3(1, 1, 1) },
    iTime: { value: 0 },
    iMouse: { value: new Vector4(0, 0, 0, 0) },
  };
  if (channelCount >= 1) uniforms.iChannel0 = { value: null };
  if (channelCount >= 2) uniforms.iChannel1 = { value: null };
  return new ShaderMaterial({
    glslVersion: GLSL3,
    vertexShader: SHADERTOY_VERTEX,
    fragmentShader: wrapShadertoyFragment(source, channelCount),
    depthTest: false,
    depthWrite: false,
    uniforms,
  });
}

function syncCommon(material, gl, time) {
  const canvas = gl.domElement;
  material.uniforms.iResolution.value.set(canvas.width, canvas.height, 1);
  material.uniforms.iTime.value = time;
}

function SinglePass({ source }) {
  const material = useMemo(() => makeMaterial(source, 0), [source]);
  useEffect(() => () => material.dispose(), [material]);
  useFrame(({ clock, gl }) => {
    syncCommon(material, gl, clock.elapsedTime);
  });
  return (
    <mesh frustumCulled={false} renderOrder={-1}>
      <planeGeometry args={[2, 2]} />
      <primitive object={material} attach="material" />
    </mesh>
  );
}

function makeTarget(width, height) {
  const target = new WebGLRenderTarget(Math.max(1, width), Math.max(1, height), {
    minFilter: LinearFilter,
    magFilter: LinearFilter,
    format: RGBAFormat,
  });
  return target;
}

function Ldc3z4Pass() {
  const { gl } = useThree();
  const mats = useMemo(
    () => ({
      a: makeMaterial(srcLdcA, 0),
      b: makeMaterial(srcLdcB, 2),
      image: makeMaterial(srcLdcImage, 2),
    }),
    [],
  );
  const quads = useMemo(
    () => ({
      a: new FullScreenQuad(mats.a),
      b: new FullScreenQuad(mats.b),
    }),
    [mats],
  );
  const targets = useRef(null);
  const ping = useRef(0);

  useEffect(() => {
    const canvas = gl.domElement;
    const w = canvas.width;
    const h = canvas.height;
    targets.current = {
      a: makeTarget(w, h),
      b: [makeTarget(w, h), makeTarget(w, h)],
    };
    return () => {
      targets.current?.a.dispose();
      targets.current?.b[0].dispose();
      targets.current?.b[1].dispose();
      quads.a.dispose();
      quads.b.dispose();
      mats.a.dispose();
      mats.b.dispose();
      mats.image.dispose();
    };
  }, [gl, mats, quads]);

  useFrame(({ clock, gl: renderer }) => {
    const pack = targets.current;
    if (!pack) return;
    const time = clock.elapsedTime;
    const w = renderer.domElement.width;
    const h = renderer.domElement.height;
    if (pack.a.width !== w || pack.a.height !== h) {
      pack.a.setSize(w, h);
      pack.b[0].setSize(w, h);
      pack.b[1].setSize(w, h);
    }

    syncCommon(mats.a, renderer, time);
    syncCommon(mats.b, renderer, time);
    syncCommon(mats.image, renderer, time);

    const read = pack.b[ping.current];
    const write = pack.b[1 - ping.current];

    renderer.setRenderTarget(pack.a);
    quads.a.render(renderer);

    mats.b.uniforms.iChannel0.value = pack.a.texture;
    mats.b.uniforms.iChannel1.value = read.texture;
    renderer.setRenderTarget(write);
    quads.b.render(renderer);

    renderer.setRenderTarget(null);
    mats.image.uniforms.iChannel0.value = pack.a.texture;
    mats.image.uniforms.iChannel1.value = write.texture;
    ping.current = 1 - ping.current;
  });

  return (
    <mesh frustumCulled={false} renderOrder={-1}>
      <planeGeometry args={[2, 2]} />
      <primitive object={mats.image} attach="material" />
    </mesh>
  );
}

export default function ShadertoyLayer({ shaderId }) {
  if (shaderId === "7fyXRh") return <SinglePass source={src7fy} />;
  if (shaderId === "ltXczj") return <SinglePass source={srcLtx} />;
  if (shaderId === "ldc3z4") return <Ldc3z4Pass />;
  if (shaderId === "pixel-galaxy") return <SinglePass source={srcPixelGalaxy} />;
  if (shaderId === "precious-egg") return <SinglePass source={srcPreciousEgg} />;
  if (shaderId === "starfield-gleam") return <SinglePass source={srcStarfieldGleam} />;
  return null;
}
