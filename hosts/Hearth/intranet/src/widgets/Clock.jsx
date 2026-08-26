import { useEffect, useState } from "react";
import { ICO, Icon } from "../lib/icons.jsx";
import { formatTime, useTimeFormat } from "../lib/timeFormat.js";

export default function Clock() {
  const [now, setNow] = useState(() => new Date());
  const { hour12 } = useTimeFormat();

  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(id);
  }, []);

  return (
    <div className="clock-face">
      <h2>
        <Icon code={ICO.clock} />
        <time dateTime={now.toISOString()}>
          {formatTime(now, { hour12, seconds: true })}
        </time>
      </h2>
      <p id="clock-date">
        {now.toLocaleDateString(undefined, {
          weekday: "long",
          year: "numeric",
          month: "long",
          day: "numeric",
        })}
      </p>
    </div>
  );
}
