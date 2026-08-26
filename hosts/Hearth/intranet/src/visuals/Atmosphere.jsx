import { useEffect, useRef, useState } from "react";
import { Float } from "@react-three/drei";
import { Canvas, useFrame } from "@react-three/fiber";
import { Bloom, EffectComposer } from "@react-three/postprocessing";
import ShadertoyLayer from "./ShadertoyLayer.jsx";

function cssVar(name, fallback) {
  if (typeof document === "undefined") return fallback;
  const value = getComputedStyle(document.documentElement).getPropertyValue(name).trim();
  return value || fallback;
}

function Field({ accent }) {
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
          <meshBasicMaterial color="#d7fffb" transparent opacity={0.7} />
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

export default function Atmosphere({ shaderId = "geometry" }) {
  const { wrapRef, reduce, play } = useAtmosphereGate();
  const [colors, setColors] = useState({
    void: "#122221",
    accent: "#2fc7be",
  });
  const toy = shaderId !== "geometry";

  useEffect(() => {
    setColors({
      void: cssVar("--void", "#122221"),
      accent: cssVar("--accent", "#2fc7be"),
    });
  }, []);

  if (reduce) return null;

  return (
    <div ref={wrapRef} className="atmosphere" aria-hidden="true">
      <Canvas
        frameloop={play ? "always" : "never"}
        dpr={[1, 1.5]}
        gl={{ antialias: false, alpha: true, powerPreference: "low-power" }}
        camera={{ position: [0, 0, 3.6], fov: 48 }}
        style={{ width: "100%", height: "100%" }}
      >
        {toy ? (
          <ShadertoyLayer shaderId={shaderId} />
        ) : (
          <>
            <color attach="background" args={[colors.void]} />
            <Field accent={colors.accent} />
            <EffectComposer disableNormalPass>
              <Bloom luminanceThreshold={0.8} intensity={0.85} mipmapBlur />
            </EffectComposer>
          </>
        )}
      </Canvas>
    </div>
  );
}
