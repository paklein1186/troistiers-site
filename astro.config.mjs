import { defineConfig } from "astro/config";
import node from "@astrojs/node";

// Rendu côté serveur : les accès par badge sont décidés sur le serveur,
// jamais dans le navigateur. Le mode « standalone » produit un serveur Node
// autonome, recopiable sur le Mac mini comme sur un serveur en ligne.
export default defineConfig({
  output: "server",
  adapter: node({ mode: "standalone" }),
  server: { port: 4321, host: true },
});
