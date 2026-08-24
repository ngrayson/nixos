export function hearthLan() {
  return window.hearthLan || "";
}

export function widget(name) {
  const cfg = window.hearthIntranet || {};
  return cfg[name] || {};
}
