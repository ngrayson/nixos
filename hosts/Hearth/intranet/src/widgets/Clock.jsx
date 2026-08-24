import { useEffect, useState } from "react";
import { ICO, Icon } from "../lib/icons.jsx";

export default function Clock() {
  const [now, setNow] = useState(() => new Date());

  useEffect(() => {
    const id = setInterval(() => setNow(new Date()), 1000);
    return () => clearInterval(id);
  }, []);

  return (
    <div className="clock-face">
      <h2>
        <Icon code={ICO.clock} />
        <time dateTime={now.toISOString()}>
          {now.toLocaleTimeString("en-US", {
            hour: "numeric",
            minute: "2-digit",
            second: "2-digit",
            hour12: true,
          })}
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
