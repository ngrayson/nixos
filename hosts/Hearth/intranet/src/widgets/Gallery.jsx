import { useEffect, useState } from "react";
import { Heading, ICO } from "../lib/icons.jsx";

function isImage(name) {
  return /\.(jpe?g|png|gif|webp|avif)$/i.test(name);
}

export default function Gallery() {
  const [hrefs, setHrefs] = useState(null);
  const [index, setIndex] = useState(0);

  useEffect(() => {
    let cancelled = false;
    fetch("/gallery/", { headers: { Accept: "text/html" } })
      .then((res) => {
        if (!res.ok) throw new Error("gallery " + res.status);
        return res.text();
      })
      .then((html) => {
        if (cancelled) return;
        const docs = new DOMParser().parseFromString(html, "text/html");
        const next = [];
        docs.querySelectorAll("a[href]").forEach((a) => {
          const href = a.getAttribute("href");
          if (!href || href === "../" || href.slice(-1) === "/") return;
          const name = href.split("/").pop();
          if (isImage(name)) next.push("/gallery/" + name);
        });
        setHrefs(next);
      })
      .catch(() => {
        if (!cancelled) setHrefs([]);
      });
    return () => {
      cancelled = true;
    };
  }, []);

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
