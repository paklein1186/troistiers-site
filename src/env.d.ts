/// <reference path="../.astro/types.d.ts" />

declare namespace App {
  interface Locals {
    utilisateur: import("./lib/acces").Utilisateur | null;
  }
}
