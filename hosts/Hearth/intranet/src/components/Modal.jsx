import { useEffect, useState } from "react";
import { createPortal } from "react-dom";
import MeterBar from "./MeterBar.jsx";
import { Icon } from "../lib/icons.jsx";

const IDLE_MS = 120_000;

// Portaled to body on purpose: widgets live in hug cards that are
// overflow:hidden and whose height is measured by cloning their own subtree.
export default function Modal({ title, label, icon, onClose, children }) {
  const [idleGen, setIdleGen] = useState(0);

  useEffect(() => {
    const onKey = (event) => {
      if (event.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [onClose]);

  useEffect(() => {
    const id = setTimeout(onClose, IDLE_MS);
    return () => clearTimeout(id);
  }, [onClose, idleGen]);

  return createPortal(
    <div
      className="modal-backdrop"
      onClick={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div
        className="modal-card"
        role="dialog"
        aria-modal="true"
        aria-label={label || title}
        onPointerDown={(event) => {
          if (event.target.closest(".modal-close")) return;
          setIdleGen((n) => n + 1);
        }}
      >
        <div className="modal-head">
          <h2>
            {icon ? <Icon code={icon} /> : null}
            {title}
          </h2>
          <button
            type="button"
            className="modal-close"
            onClick={onClose}
            aria-label="Close"
            autoFocus
          >
            ×
          </button>
        </div>
        {children}
      </div>
      <div className="poll-track modal-idle" aria-hidden="true">
        <MeterBar key={idleGen} variant="poll" percent={100} />
      </div>
    </div>,
    document.body,
  );
}
