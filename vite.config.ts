import { defineConfig } from "vite";
import react from "@vitejs/plugin-react";
export default defineConfig({
  build: { outDir: "web-dist" }, plugins: [react()], server: { port: 1420, strictPort: true } });
