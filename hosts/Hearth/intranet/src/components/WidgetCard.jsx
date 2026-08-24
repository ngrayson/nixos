export default function WidgetCard({ children, fill, hug, cardRef }) {
  const kind = fill ? "widget-card-fill" : hug ? "widget-card-hug" : "";
  return (
    <div ref={cardRef} className={kind ? `widget-card ${kind}` : "widget-card"}>
      {children}
    </div>
  );
}
