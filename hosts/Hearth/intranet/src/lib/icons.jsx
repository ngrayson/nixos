import MeterBar from "../components/MeterBar.jsx";

// Nerd Font Symbols (hex codepoints). See nerd-fonts glyphnames.json.
export const ICO = {
  weather: "f0595",
  sunny: "e30d",
  overcast: "e30c",
  cloudy: "e312",
  fog: "e313",
  drizzle: "e31b",
  rain: "e318",
  showers: "e319",
  snow: "e31a",
  thunder: "e31d",
  thermometer: "e350",
  wind: "e31e",
  sunrise: "e34c",
  sunset: "e34d",
  moonrise: "e3c1",
  moonset: "e3c2",
  aqi: "e35d",
  disk: "f02ca",
  hdd: "f02ca",
  hddOff: "f104c",
  battery: "f0079",
  batteryOff: "f008e",
  bus: "f00e7",
  clock: "f0954",
  home: "f02dc",
  tv: "f0502",
  calendar: "f00ed",
  gallery: "f02e9",
  server: "f048b",
  map: "f034d",
  cog: "f013",
  wifi: "f05a9",
  cpu: "f0ee0",
  memory: "f035b",
  // Distinct from `thermometer` above, which is the weather glyph — keeping them
  // apart stops Server Status from echoing the Weather card.
  temp: "f050f",
};

export function nfChar(code) {
  return String.fromCodePoint(parseInt(code, 16));
}

export function Icon({ code }) {
  return (
    <span className="nf" aria-hidden="true">
      {nfChar(code)}
    </span>
  );
}

export function Heading({ title, code }) {
  return (
    <h2>
      {code ? <Icon code={code} /> : null}
      {title}
    </h2>
  );
}

export function Empty({ text, title, code }) {
  return (
    <>
      <Heading title={title} code={code} />
      <p className="empty">{text}</p>
    </>
  );
}

export function Fact({ code, text, tone }) {
  return (
    <span className={tone ? `fact ${tone}` : "fact"}>
      <Icon code={code} />
      {text}
    </span>
  );
}

export function Meter({ label, percent, detail, icon, hideBar, off }) {
  const pct = percent == null ? 0 : Math.max(0, Math.min(100, Number(percent)));
  return (
    <div className="meter">
      <div className="meter-label">
        {icon ? <Icon code={icon} /> : null}
        {label}
      </div>
      {hideBar ? null : (
        <div className="meter-track">
          <MeterBar percent={off ? 0 : pct} off={off} />
        </div>
      )}
      <div className="meter-value">{detail}</div>
    </div>
  );
}
