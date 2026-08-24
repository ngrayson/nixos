import { useEffect, useState } from "react";
import MeterBar from "../components/MeterBar.jsx";
import { Heading, ICO } from "../lib/icons.jsx";

function arrivalMs(row) {
  const pred = Number(row.predictedArrivalTime || 0);
  if (pred > 0) return pred;
  return Number(row.scheduledArrivalTime || 0);
}

function minutesAway(row, nowMs) {
  const t = arrivalMs(row);
  if (!t) return null;
  return Math.round((t - nowMs) / 60000);
}

function minsLabel(row, nowMs) {
  const mins = minutesAway(row, nowMs);
  if (mins == null) return "—";
  if (mins <= 0) return "due";
  return mins + " min" + (row.predicted ? "" : " sched");
}

export default function Buses() {
  const [payload, setPayload] = useState(undefined);
  const [awaiting, setAwaiting] = useState(false);
  const [pollMs, setPollMs] = useState(60000);
  const [nextAt, setNextAt] = useState(0);
  const [now, setNow] = useState(() => Date.now());

  useEffect(() => {
    const id = setInterval(() => setNow(Date.now()), 250);
    return () => clearInterval(id);
  }, []);

  useEffect(() => {
    let cancelled = false;
    let awaitingTick = false;
    let poll = 60000;
    let due = 0;

    function tick() {
      if (awaitingTick || cancelled) return;
      awaitingTick = true;
      setAwaiting(true);
      fetch("/transit.json")
        .then((res) => {
          if (!res.ok) throw new Error("transit " + res.status);
          return res.json();
        })
        .then((data) => {
          if (cancelled) return;
          setPayload(data);
          poll = Math.max(60, Number((data && data.pollSeconds) || 60)) * 1000;
          setPollMs(poll);
          due = ((data && data.generatedAt) || 0) * 1000 + poll;
          if (due <= Date.now()) due = Date.now() + 5000;
          setNextAt(due);
        })
        .catch(() => {
          if (cancelled) return;
          setPayload(null);
          due = Date.now() + poll;
          setNextAt(due);
        })
        .finally(() => {
          awaitingTick = false;
          if (!cancelled) setAwaiting(false);
        });
    }

    tick();
    const id = setInterval(() => {
      if (!awaitingTick && due && Date.now() >= due) tick();
    }, 1000);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  const left = Math.max(0, nextAt - now);
  const pct = nextAt ? Math.max(0, Math.min(100, (left / pollMs) * 100)) : 0;

  let list;
  if (payload === undefined) {
    list = null;
  } else if (!payload) {
    list = <p className="empty">schedule unavailable</p>;
  } else {
    const stops = payload.stops || [];
    if (!stops.length) {
      list = <p className="empty">add busStops in intranet/config/transit/config.nix</p>;
    } else {
      list = (
        <>
          {payload.limited ? <p className="empty">rate limited — waiting to try again</p> : null}
          {stops.map((r) => {
            if (r.status === 429 || r.code === 429) return null;
            if (!r.ok) {
              return (
                <div className="bus-stop" key={r.id || r.name}>
                  <h3>{r.name || r.id}</h3>
                  <p className="empty">
                    {r.code === 404 || r.status === 404 ? "stop not found" : "arrivals unavailable"}
                  </p>
                </div>
              );
            }
            const nowMs = r.currentTime || Date.now();
            const rows = r.arrivals || [];
            if (!rows.length) {
              return (
                <div className="bus-stop" key={r.id || r.name}>
                  <h3>{r.name || r.id}</h3>
                  <p className="empty">no arrivals in the next hour</p>
                </div>
              );
            }
            return (
              <div className="bus-stop" key={r.id || r.name}>
                <h3>{r.name || r.id}</h3>
                <ul className="arrivals">
                  {rows.map((row, i) => (
                    <li key={`${row.routeShortName}-${row.tripHeadsign}-${i}`}>
                      <span>
                        <span className="route">{row.routeShortName || "?"}</span>
                        {" " + (row.tripHeadsign || "")}
                      </span>
                      <span className="mins">{minsLabel(row, nowMs)}</span>
                    </li>
                  ))}
                </ul>
              </div>
            );
          })}
        </>
      );
    }
  }

  return (
    <div id="buses">
      <div className={awaiting ? "poll is-awaiting" : "poll"}>
        <Heading title="Bus Schedule" code={ICO.bus} />
        <div className="poll-track">
          <MeterBar variant="poll" percent={pct} awaiting={awaiting} />
        </div>
        <div className="poll-value">
          {awaiting ? "awaiting response" : `refresh in ${Math.ceil(left / 1000)}s`}
        </div>
      </div>
      <div className="bus-list">{list}</div>
    </div>
  );
}
