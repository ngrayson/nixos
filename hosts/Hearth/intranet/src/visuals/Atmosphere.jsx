import { useEffect, useMemo, useRef, useState } from "react";
import { Float } from "@react-three/drei";
import { Canvas, useFrame } from "@react-three/fiber";
import { Bloom, EffectComposer } from "@react-three/postprocessing";
import { themeVisualColors } from "../lib/themePref.js";
import ShadertoyLayer from "./ShadertoyLayer.jsx";

// Wake-greet timing: animate live for LIVE_MS, then ease the rate 1→0 over
// DECAY_MS to a standstill. REGREET_MIN_MS bounds thermal bursts — at most one
// greet per that window even if the panel is woken repeatedly.
const LIVE_MS = 10000;
const DECAY_MS = 5000;
const GREET_TOTAL_MS = LIVE_MS + DECAY_MS;
const REGREET_MIN_MS = 20000;

// How long the frozen modes animate on a theme/shader switch before re-freezing,
// so the switch repaints in the now-current palette (PR #207). rate stays 0
// during such a burst, so it is a repaint, not motion.
const BURST_MS = 800;

// The single rate-scaled virtual clock. It runs inside the Canvas, advances a
// shared `virtual` time by `dt * rate`, and computes `rate` from the mode and
// the greet phase — so one ramp governs both the geometry Field's rotations and
// the shader toys' iTime. When rate reaches 0 the virtual clock stops; the
// Canvas is separately switched to frameloop="never" so nothing repaints.
function ClockDriver({ virtual, rate, modeRef, greetStartRef }) {
  useFrame((_, dt) => {
    const step = Math.min(dt, 0.05);
    const mode = modeRef.current;
    let r;
    if (mode === "always") {
      r = 1;
    } else if (mode === "off") {
      r = 0;
    } else {
      // wake: 1 while live, a smoothstep ease 1→0 through the decay, else 0.
      const start = greetStartRef.current;
      if (start == null) {
        r = 0;
      } else {
        const el = performance.now() - start;
        if (el <= LIVE_MS) {
          r = 1;
        } else if (el <= GREET_TOTAL_MS) {
          const p = (el - LIVE_MS) / DECAY_MS;
          r = 1 - p * p * (3 - 2 * p);
        } else {
          r = 0;
        }
      }
    }
    rate.current = r;
    virtual.current += step * r;
  });
  return null;
}

function Field({ accent, strong, rate }) {
  const a = useRef(null);
  const b = useRef(null);
  useFrame((_, dt) => {
    // Scaled by the shared rate so the rotations slow and freeze with the ramp.
    const t = Math.min(dt, 0.05) * rate.current;
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

export default function Atmosphere({ shaderId = "geometry", themeId, mode = "always", wokeAt = null }) {
  const { wrapRef, reduce, play } = useAtmosphereGate();
  // Recomputed whenever the picker changes the theme.
  const colors = useMemo(() => themeVisualColors(themeId), [themeId]);
  const toy = shaderId !== "geometry";

  // The shared rate-scaled clock, read imperatively in useFrame (no re-render on
  // each tick). modeRef mirrors the mode prop so the frame loop sees it live.
  const virtual = useRef(0);
  const rate = useRef(mode === "always" ? 1 : 0);
  const modeRef = useRef(mode);
  useEffect(() => {
    modeRef.current = mode;
  }, [mode]);

  // Greet state machine (wake mode). greetStartRef timestamps the running greet
  // for ClockDriver; `greeting` drives the Canvas frameloop back on.
  const greetStartRef = useRef(null);
  const lastGreetStartRef = useRef(0);
  const prevWokeAtRef = useRef(null);
  const [greeting, setGreeting] = useState(false);

  // A new wake fires a greet. The first non-null wokeAt only seeds the baseline
  // (no greet on load); a bump while already greeting, or within the re-greet
  // cooldown, is ignored so repeated wakes never stack or overheat.
  useEffect(() => {
    if (mode !== "wake" || wokeAt == null) return;
    const prev = prevWokeAtRef.current;
    prevWokeAtRef.current = wokeAt;
    if (prev == null || wokeAt <= prev) return;
    if (greeting) return;
    const now = performance.now();
    if (now - lastGreetStartRef.current < REGREET_MIN_MS) return;
    greetStartRef.current = now;
    lastGreetStartRef.current = now;
    setGreeting(true);
  }, [wokeAt, mode, greeting]);

  // End the greet after live + decay.
  useEffect(() => {
    if (!greeting) return undefined;
    const timer = setTimeout(() => {
      greetStartRef.current = null;
      setGreeting(false);
    }, GREET_TOTAL_MS);
    return () => clearTimeout(timer);
  }, [greeting]);

  // Leaving wake mode mid-greet stops it cleanly.
  useEffect(() => {
    if (mode !== "wake" && greeting) {
      greetStartRef.current = null;
      setGreeting(false);
    }
  }, [mode, greeting]);

  // PR #207 burst: a frameloop="never" Canvas renders once and never repaints on
  // prop changes, so switching theme or shader recomputed `colors` but drew no
  // new frame. Run a short live burst on mount and on every themeId/shaderId
  // change, then re-freeze — repainting in the now-current palette. rate stays 0
  // for a burst (mode off / wake-at-rest), so it repaints without motion.
  const [bursting, setBursting] = useState(true);
  useEffect(() => {
    setBursting(true);
    const t = setTimeout(() => setBursting(false), BURST_MS);
    return () => clearTimeout(t);
  }, [themeId, shaderId]);

  if (reduce) return null;

  // Live whenever the scene should repaint: always mode, an active greet, or a
  // theme/shader burst — and never while hidden or off-screen. Everything else
  // is frozen (frameloop="never"), the ~11% CPU / 40°C resting cost from PR #204.
  const live = play && (mode === "always" || greeting || bursting);
  const frameloop = live ? "always" : "never";
  return (
    <div ref={wrapRef} className="atmosphere" aria-hidden="true">
      <Canvas
        frameloop={frameloop}
        dpr={[1, 1.5]}
        gl={{ antialias: false, alpha: true, powerPreference: "low-power" }}
        camera={{ position: [0, 0, 3.6], fov: 48 }}
        style={{ width: "100%", height: "100%" }}
      >
        <ClockDriver virtual={virtual} rate={rate} modeRef={modeRef} greetStartRef={greetStartRef} />
        {toy ? (
          <ShadertoyLayer shaderId={shaderId} colors={colors} timeRef={virtual} />
        ) : (
          <>
            <color attach="background" args={[colors.void]} />
            <Field accent={colors.accent} strong={colors.strong} rate={rate} />
            <EffectComposer disableNormalPass>
              <Bloom luminanceThreshold={0.8} intensity={0.85} mipmapBlur />
            </EffectComposer>
          </>
        )}
      </Canvas>
    </div>
  );
}
