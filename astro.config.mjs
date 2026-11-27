import { defineConfig } from "astro/config";
import node from "@astrojs/node";

// Rendu côté serveur : les accès par badge sont décidés sur le serveur,
// jamais dans le navigateur. Le mode « standalone » produit un serveur Node
// autonome, recopiable sur le Mac mini comme sur un serveur en ligne.
// Bac à sable (BAC_A_SABLE=true, posé par `npm run dev:bac-a-sable` depuis .env.bac-a-sable) : aucun fichier .env
// n'est lu, pour qu'aucun réglage du site réel ne s'y glisse.
const bacASable = process.env.BAC_A_SABLE === "true";

export default defineConfig({
  output: "server",
  vite: bacASable ? { envDir: "./supabase/bac-a-sable/aucun-env" } : {},
  adapter: node({ mode: "standalone" }),
  server: { port: 4321, host: true },
});
