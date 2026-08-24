import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";

export default defineConfig({
  plugins: [react()],
  base: "/",
  server: {
    host: "127.0.0.1",
    port: 5173,
    strictPort: true,
    proxy: {
      "/status.json": { target: "https://home.wizt.org", changeOrigin: true },
      "/transit.json": { target: "https://home.wizt.org", changeOrigin: true },
      "/gallery.json": { target: "https://home.wizt.org", changeOrigin: true },
      "/calendar.ics": { target: "https://home.wizt.org", changeOrigin: true },
      "/gallery": { target: "https://home.wizt.org", changeOrigin: true },
    },
  },
  build: {
    outDir: "dist",
    emptyOutDir: true,
  },
});
