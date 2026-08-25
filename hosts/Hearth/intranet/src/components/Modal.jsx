import { useEffect } from "react";
import { createPortal } from "react-dom";
import { Icon } from "../lib/icons.jsx";

// Portaled to body on purpose: widgets live in hug cards that are
// overflow:hidden and whose height is measured by cloning their own subtree.
export default function Modal({ title, label, icon, onClose, children }) {
  useEffect(() => {
    const onKey = (event) => {
      if (event.key === "Escape") onClose();
    };
    document.addEventListener("keydown", onKey);
    return () => document.removeEventListener("keydown", onKey);
  }, [onClose]);

  return createPortal(
    <div
      className="modal-backdrop"
      onClick={(event) => {
        if (event.target === event.currentTarget) onClose();
      }}
    >
      <div className="modal-card" role="dialog" aria-modal="true" aria-label={label || title}>
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
    </div>,
    document.body,
  );
}
