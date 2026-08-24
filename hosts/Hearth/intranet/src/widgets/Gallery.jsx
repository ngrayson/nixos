import { useEffect, useState } from "react";
import { Heading, ICO } from "../lib/icons.jsx";

export default function Gallery({ onPresence }) {
  const [hrefs, setHrefs] = useState(null);
  const [index, setIndex] = useState(0);

  useEffect(() => {
    let cancelled = false;
    fetch("/gallery.json")
      .then((res) => {
        if (!res.ok) throw new Error("gallery " + res.status);
        return res.json();
      })
      .then((data) => {
        if (!cancelled) setHrefs(Array.isArray(data.hrefs) ? data.hrefs : []);
      })
      .catch(() => {
        if (!cancelled) setHrefs([]);
      });
    return () => {
      cancelled = true;
    };
  }, []);

  useEffect(() => {
    if (hrefs == null) return;
    onPresence?.(hrefs.length > 0);
  }, [hrefs, onPresence]);

  useEffect(() => {
    if (!hrefs || !hrefs.length) return undefined;
    const id = setInterval(() => setIndex((i) => i + 1), 12000);
    return () => clearInterval(id);
  }, [hrefs]);

  if (!hrefs || !hrefs.length) return null;
  return (
    <>
      <Heading title="Gallery" code={ICO.gallery} />
      <img alt="" src={hrefs[index % hrefs.length]} />
    </>
  );
}
