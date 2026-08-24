export default function MeterBar({ percent, off, awaiting, variant = "meter" }) {
  const pct = off ? 0 : awaiting ? 100 : Math.max(0, Math.min(100, Number(percent) || 0));
  const kind = variant === "poll" ? "poll-fill" : "meter-fill";
  const className = [kind, off ? "is-off" : "", awaiting ? "is-awaiting" : ""].filter(Boolean).join(" ");
  return <div className={className} style={{ "--meter-pct": String(pct / 100) }} />;
}
