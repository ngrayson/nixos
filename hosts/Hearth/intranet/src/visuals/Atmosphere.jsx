import { useEffect, useMemo, useRef, useState } from "react";
import { Float } from "@react-three/drei";
import { Canvas, useFrame } from "@react-three/fiber";
import { Bloom, EffectComposer } from "@react-three/postprocessing";
import { themeVisualColors } from "../lib/themePref.js";
import ShadertoyLayer from "./ShadertoyLayer.jsx";

function Field({ accent, strong }) {
  const a = useRef(null);
  const b = useRef(null);
  useFrame((_, dt) => {
    const t = Math.min(dt, 0.05);
    if (a.current) {
      a.current.rotation.y += t * 0.07;
      a.current.rotation.x += t * 0.025;
    }
    if (b.current) {
      b.current.rotation.y -= t * 0.045;
      b.current.rotation.z += t * 0.02;
    }
  });
  return (
    <group>
      <mesh ref={a} position={[0.15, 0.05, -0.4]}>
        <icosahedronGeometry args={[1.55, 1]} />
        <meshBasicMaterial color={accent} wireframe transparent opacity={0.55} />
      </mesh>
      <mesh ref={b} position={[-1.7, -0.55, -1.2]}>
        <icosahedronGeometry args={[0.7, 0]} />
        <meshBasicMaterial color={accent} transparent opacity={0.22} />
      </mesh>
      <Float speed={0.35} rotationIntensity={0.15} floatIntensity={0.25}>
        <mesh position={[1.85, 0.85, -1.4]}>
          <octahedronGeometry args={[0.45, 0]} />
          <meshBasicMaterial color={strong} transparent opacity={0.7} />
        </mesh>
      </Float>
    </group>
  );
}

function useAtmosphereGate() {
  const wrapRef = useRef(null);
  const [reduce, setReduce] = useState(() =>
    typeof window !== "undefined" && window.matchMedia("(prefers-reduced-motion: reduce)").matches,
  );
  const [visible, setVisible] = useState(() => (typeof document !== "undefined" ? !document.hidden : true));
  const [onScreen, setOnScreen] = useState(true);

  useEffect(() => {
    const mq = window.matchMedia("(prefers-reduced-motion: reduce)");
    const onMq = () => setReduce(mq.matches);
    mq.addEventListener("change", onMq);
    const onVis = () => setVisible(!document.hidden);
    document.addEventListener("visibilitychange", onVis);
    return () => {
      mq.removeEventListener("change", onMq);
      document.removeEventListener("visibilitychange", onVis);
    };
  }, []);

  useEffect(() => {
    const el = wrapRef.current;
    if (!el || typeof IntersectionObserver === "undefined") return undefined;
    const io = new IntersectionObserver(([entry]) => setOnScreen(entry.isIntersecting), { threshold: 0 });
    io.observe(el);
    return () => io.disconnect();
  }, []);

  return { wrapRef, reduce, play: visible && onScreen && !reduce };
}

// How long the frozen mode animates on mount and on each theme/shader switch
// before re-freezing. Long enough to read as a greeting of motion and to settle
// the frame past its t=0 pose; short enough that the steady-state stays frozen.
const BURST_MS = 800;

export default function Atmosphere({ shaderId = "geometry", themeId, animate = true }) {
  const { wrapRef, reduce, play } = useAtmosphereGate();
  // Recomputed whenever the picker changes the theme. This used to be state set
  // by a mount-only effect, which is why the background stayed in whichever
  // palette was active when the page loaded no matter what Settings said.
  const colors = useMemo(() => themeVisualColors(themeId), [themeId]);
  const toy = shaderId !== "geometry";

  // In the frozen ("Animate background: Off") mode a frameloop="never" Canvas
  // renders exactly once and never repaints on prop changes — so switching the
  // theme or shader recomputed `colors` but drew no new frame, stranding the
  // old palette until you toggled animation (the reported bug). Instead, run a
  // short live burst on mount and on every themeId/shaderId change, then
  // re-freeze: the burst repaints in the now-current palette AND greets a
  // passer-by with a moment of motion. The timeout is reset on each change so
  // the last switch wins and rapid switches can't strand `bursting` true.
  const [bursting, setBursting] = useState(true);
  useEffect(() => {
    setBursting(true);
    const t = setTimeout(() => setBursting(false), BURST_MS);
    return () => clearTimeout(t);
  }, [themeId, shaderId]);

  if (reduce) return null;

  // On: the visibility gate governs (never redraw while the tab is hidden or the
  // canvas is off-screen). Off: frozen — "never" except during a burst, so the
  // steady state keeps the ~11% CPU / 41C frozen cost measured in PR #204 (the
  // per-vsync redraw is the whole cost of the live mode) and only the brief
  // burst spends GPU. The burst still honours `play` so a hidden/off-screen tab
  // never animates.
  const frameloop = animate ? (play ? "always" : "never") : (bursting && play ? "always" : "never");
  return (
    <div ref={wrapRef} className="atmosphere" aria-hidden="true">
      <Canvas
        frameloop={frameloop}
        dpr={[1, 1.5]}
        gl={{ antialias: false, alpha: true, powerPreference: "low-power" }}
        camera={{ position: [0, 0, 3.6], fov: 48 }}
        style={{ width: "100%", height: "100%" }}
      >
        {toy ? (
          <ShadertoyLayer shaderId={shaderId} colors={colors} />
        ) : (
          <>
            <color attach="background" args={[colors.void]} />
            <Field accent={colors.accent} strong={colors.strong} />
            <EffectComposer disableNormalPass>
              <Bloom luminanceThreshold={0.8} intensity={0.85} mipmapBlur />
            </EffectComposer>
          </>
        )}
      </Canvas>
    </div>
  );
}
