export function widget(name) {
  const cfg = window.hearthIntranet || {};
  return cfg[name] || {};
}
