import { useEffect, useState } from "react";
import { Heading, ICO, Meter } from "../lib/icons.jsx";

function batteryIcon(percent) {
  if (percent == null || isNaN(percent)) return ICO.batteryOff;
  const n = Number(percent);
  if (n >= 95) return "f0079";
  if (n >= 85) return "f0082";
  if (n >= 75) return "f0081";
  if (n >= 65) return "f0080";
  if (n >= 55) return "f007f";
  if (n >= 45) return "f007e";
  if (n >= 35) return "f007d";
  if (n >= 25) return "f007c";
  if (n >= 15) return "f007b";
  if (n >= 5) return "f007a";
  return ICO.batteryOff;
}

function Body({ data }) {
  if (!data) {
    return <p className="empty">unavailable</p>;
  }
  const root = data.root || {};
  const diskDetail =
    (root.usedPercent != null ? root.usedPercent + "%" : "—") +
    (root.avail ? " · " + root.avail + " free" : "");
  const cold = data.cold || {};
  return (
    <>
      <Meter
        label="Disk usage"
        percent={root.usedPercent}
        detail={diskDetail}
        icon={ICO.disk}
        off={root.usedPercent == null}
      />
      {cold.mounted ? (
        <Meter
          label="HDD status"
          percent={cold.usedPercent}
          detail={
            (cold.usedPercent != null ? cold.usedPercent + "%" : "—") +
            (cold.avail ? " · " + cold.avail + " free" : "")
          }
          icon={ICO.hdd}
          off={cold.usedPercent == null}
        />
      ) : (
        <Meter label="HDD status" percent={0} detail="unplugged" icon={ICO.hddOff} hideBar />
      )}
      {data.battery && data.battery.percent != null ? (
        <Meter
          label="Battery"
          percent={data.battery.percent}
          detail={`${data.battery.percent}%`}
          icon={batteryIcon(data.battery.percent)}
        />
      ) : (
        <Meter label="Battery" percent={0} detail="none" icon={ICO.batteryOff} hideBar />
      )}
    </>
  );
}

export default function Health() {
  const [data, setData] = useState(undefined);

  useEffect(() => {
    function poll() {
      fetch("/status.json")
        .then((res) => {
          if (!res.ok) throw new Error("status " + res.status);
          return res.json();
        })
        .then(setData)
        .catch(() => setData(null));
    }
    poll();
    const id = setInterval(poll, 60000);
    return () => clearInterval(id);
  }, []);

  if (data === undefined) {
    return <Heading title="Server Status" code={ICO.server} />;
  }
  return (
    <>
      <Heading title="Server Status" code={ICO.server} />
      <Body data={data} />
    </>
  );
}
