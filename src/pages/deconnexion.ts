import type { APIRoute } from "astro";
import { oublierJetons } from "../lib/jetons";
import { fermerSession } from "../lib/session";

export const POST: APIRoute = ({ cookies, redirect }) => {
  fermerSession(cookies);
  oublierJetons(cookies);
  return redirect("/");
};
