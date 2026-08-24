import { useEffect, useState } from "react";
import { widget } from "../lib/config.js";
import { Heading, ICO } from "../lib/icons.jsx";

function parseIcsDays(text) {
  const marked = {};
  const re = /DTSTART(?:;VALUE=DATE)?:(\d{8})/g;
  let m;
  while ((m = re.exec(text))) {
    marked[`${m[1].slice(0, 4)}-${m[1].slice(4, 6)}-${m[1].slice(6, 8)}`] = true;
  }
  return marked;
}

function MonthGrid({ marked }) {
  const now = new Date();
  const year = now.getFullYear();
  const month = now.getMonth();
  const first = new Date(year, month, 1);
  const startPad = first.getDay();
  const days = new Date(year, month + 1, 0).getDate();
  const cells = [];
  for (let i = 0; i < startPad; i++) cells.push({ key: `pad-${i}`, empty: true });
  for (let i = 1; i <= days; i++) {
    const key = `${year}-${String(month + 1).padStart(2, "0")}-${String(i).padStart(2, "0")}`;
    const cls = [i === now.getDate() ? "today" : "", marked && marked[key] ? "marked" : ""]
      .filter(Boolean)
      .join(" ");
    cells.push({ key, day: i, className: cls });
  }
  const rows = [];
  for (let i = 0; i < cells.length; i += 7) rows.push(cells.slice(i, i + 7));
  return (
    <table className="cal">
      <thead>
        <tr>
          {["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"].map((d) => (
            <th key={d}>{d}</th>
          ))}
        </tr>
      </thead>
      <tbody>
        {rows.map((row, ri) => (
          <tr key={ri}>
            {row.map((cell) =>
              cell.empty ? <td key={cell.key} /> : (
                <td key={cell.key} className={cell.className || undefined}>
                  {cell.day}
                </td>
              ),
            )}
          </tr>
        ))}
      </tbody>
    </table>
  );
}

export default function Calendar() {
  const ics = widget("calendar").calendarIcsUrl;
  const [marked, setMarked] = useState({});

  useEffect(() => {
    if (!ics) return;
    let cancelled = false;
    fetch(ics)
      .then((res) => {
        if (!res.ok) throw new Error("ics " + res.status);
        return res.text();
      })
      .then((text) => {
        if (!cancelled) setMarked(parseIcsDays(text));
      })
      .catch(() => {
        if (!cancelled) setMarked({});
      });
    return () => {
      cancelled = true;
    };
  }, [ics]);

  const cap = new Date().toLocaleString(undefined, {
    month: "long",
    year: "numeric",
  });

  return (
    <>
      <Heading title="Calendar" code={ICO.calendar} />
      <p>{cap}</p>
      <MonthGrid marked={marked} />
    </>
  );
}
