import { useEffect, useState } from "react";
import { Empty, Fact, Heading, ICO } from "../lib/icons.jsx";

const POLL_MS = 60000;
const SHOW = 6;

// hearth-ingest mirrors the tree verbatim, so the interesting part of a
// destination is its basename; the library is carried separately.
function fileName(path) {
  if (!path) return "";
  const parts = String(path).split("/");
  return parts[parts.length - 1] || path;
}

function since(epochSeconds) {
  if (!epochSeconds) return "";
  const secs = Math.max(0, Math.floor(Date.now() / 1000 - Number(epochSeconds)));
  if (secs < 60) return "just now";
  const mins = Math.floor(secs / 60);
  if (mins < 60) return mins + "m ago";
  const hours = Math.floor(mins / 60);
  if (hours < 24) return hours + "h ago";
  return Math.floor(hours / 24) + "d ago";
}

function Body({ data }) {
  const recent = (data.recent || []).filter((entry) => entry.result === "linked");
  const pending = data.pending || [];
  const errors = data.errors || [];

  if (!recent.length && !pending.length && !errors.length) {
    return <p className="empty">nothing filed yet</p>;
  }

  return (
    <>
      <div className="facts">
        <Fact code={ICO.hdd} text={recent.length + " filed"} />
        {pending.length ? (
          <Fact code={ICO.disk} text={pending.length + " needs attention"} tone="tone-warm" />
        ) : null}
      </div>
      {recent.length ? (
        <ul className="ingest-list">
          {recent.slice(0, SHOW).map((entry) => (
            <li key={entry.dest}>
              <span className="ingest-name">{fileName(entry.dest)}</span>
              <span className="ingest-meta">
                {entry.library}
                {entry.at ? " · " + since(entry.at) : ""}
              </span>
            </li>
          ))}
        </ul>
      ) : null}
      {errors.length ? <p className="ingest-error">{errors[errors.length - 1]}</p> : null}
    </>
  );
}

export default function Ingest() {
  const [data, setData] = useState(undefined);

  useEffect(() => {
    let cancelled = false;
    function poll() {
      fetch("/ingest.json")
        .then((res) => {
          if (!res.ok) throw new Error("ingest " + res.status);
          return res.json();
        })
        .then((payload) => {
          if (!cancelled) setData(payload);
        })
        // The file does not exist until hearth-ingest's first timer run, so a
        // 404 is the normal cold-start state rather than a fault.
        .catch(() => {
          if (!cancelled) setData(null);
        });
    }
    poll();
    const id = setInterval(poll, POLL_MS);
    return () => {
      cancelled = true;
      clearInterval(id);
    };
  }, []);

  if (data === undefined) {
    return <Heading title="Ingest" code={ICO.hdd} />;
  }
  if (data === null) {
    return <Empty title="Ingest" code={ICO.hdd} text="no ingest data yet" />;
  }
  return (
    <>
      <Heading title="Ingest" code={ICO.hdd} />
      <Body data={data} />
    </>
  );
}
