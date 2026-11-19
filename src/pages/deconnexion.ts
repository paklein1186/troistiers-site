import type { APIRoute } from "astro";
import { fermerSession } from "../lib/session";

export const POST: APIRoute = ({ cookies, redirect }) => {
  fermerSession(cookies);
  return redirect("/");
};
