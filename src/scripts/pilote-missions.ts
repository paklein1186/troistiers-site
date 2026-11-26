// @ts-nocheck — rendu repris de l'artefact « Pilote 3/3 » (même balisage, même design), en lecture seule.
// Les données viennent de la base Trois-Tiers (copie synchronisée de l'artefact), injectées par la page.

const DATA = JSON.parse(document.getElementById("p33-donnees")!.textContent || "{}");
const $ = (s: string) => document.querySelector(s) as HTMLElement;
const D = 864e5;
const reDate = /^\d{4}-\d{2}-\d{2}$/;
const esc = (s) => String(s ?? "").replace(/[&<>"']/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;", "'": "&#39;" })[c]);
const todayStr = () => { const n = new Date(); return n.getFullYear() + "-" + String(n.getMonth() + 1).padStart(2, "0") + "-" + String(n.getDate()).padStart(2, "0"); };
const toMs = (s) => { if (!s || !reDate.test(s)) return null; const [y, m, d] = s.split("-").map(Number); return Date.UTC(y, m - 1, d); };
const todayMs = () => toMs(todayStr());
const fmtD = (s) => { const ms = toMs(s); if (ms === null) return ""; const d = new Date(ms); const o: any = { day: "numeric", month: "short", timeZone: "UTC" }; if (d.getUTCFullYear() !== new Date().getFullYear()) o.year = "numeric"; return d.toLocaleDateString("fr-BE", o); };
const fmtDT = (iso) => { if (!iso) return ""; try { return new Date(iso).toLocaleString("fr-BE", { day: "numeric", month: "short", hour: "2-digit", minute: "2-digit" }); } catch { return ""; } };
function isoWeek(ms) { const d = new Date(ms); const day = (d.getUTCDay() + 6) % 7; d.setUTCDate(d.getUTCDate() - day + 3); const ft = new Date(Date.UTC(d.getUTCFullYear(), 0, 4)); return 1 + Math.round(((d.getTime() - ft.getTime()) / D - 3 + ((ft.getUTCDay() + 6) % 7)) / 7); }

const ST = { todo: "À faire", doing: "En cours", block: "Bloqué", done: "Fait" };
const ST_RANK = { block: 0, doing: 1, todo: 2, done: 3 };
const MSTAT = { active: "Active", veille: "En veille", cloturee: "Clôturée" };
const S_LBL = { t: "Tâches", m: "Missions", j: "Journal et décisions" };
const S_LIM = { t: 12, m: 6, j: 8 };
const VIEWS = ["tableau", "missions", "planning", "attente", "journal"];
const LABELS = { tableau: "Tableau", missions: "Missions", planning: "Planning", attente: "Salle d’attente", journal: "Agents & journal" };

const S = {
  tasks: new Map(DATA.taches.map((t) => [t.id, t])),
  missions: DATA.missions,
  absences: DATA.absences,
  journal: DATA.journal,
  proposals: DATA.propositions,
  config: { members: DATA.membres, chantiers: DATA.chantiers },
};
const vueInitiale = (location.hash.match(/^#(tableau|missions|planning|attente|journal)$/) || [])[1];
const U = {
  view: vueInitiale || DATA.vue || "tableau", fResp: "all", fCh: "all", fFam: "all", group: "chantier", hideDone: false,
  openSubs: new Set(), mfilter: "active", mtype: "all", jFilter: "all", q: "", sOpen: false, sType: "all", sMore: {}, fiche: null, mfocus: "",
};

/* Familles d'activité : fonction socle, coordination, groupes de travail (classement propre au site). */
const FAM = DATA.familles || [];
const FAMG = { socle: "Fonction socle", coordination: "Coordination", groupe: "Groupes de travail" };
const famDe = (code) => FAM.find((f) => f.code === code);
const famLib = (code) => { const f = famDe(code); return f ? FAMG[f.famille] + " · " + f.libelle : "Non classé"; };
const famOk = (code) => U.fFam === "all" || code === U.fFam || (famDe(code) || {}).famille === U.fFam;
function selectFamille(id, valeur, attrs, avecTous) {
  const groupes = Object.entries(FAMG).map(([g, l]) => `<optgroup label="${esc(l)}">${avecTous ? `<option value="${g}" ${valeur === g ? "selected" : ""}>${esc(l)} : tout</option>` : ""}${FAM.filter((f) => f.famille === g).map((f) => `<option value="${esc(f.code)}" ${valeur === f.code ? "selected" : ""}>${esc(f.libelle)}</option>`).join("")}</optgroup>`).join("");
  return `<select class="fsel" id="${esc(id)}" ${attrs}>${avecTous ? `<option value="all">Toutes</option>` : ""}${groupes}</select>`;
}
async function classer(type, ref, famille) {
  try {
    const r = await fetch(DATA.url_classer, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ type, ref, famille }) });
    const j = await r.json();
    if (!r.ok) { alert(j.erreur || "Classement refusé."); return; }
    for (const x of j.taches) { const t = S.tasks.get(x.id); if (t) { t.famille = x.famille; t.famille_choisie = x.choisie; } }
    for (const x of j.missions) { const m = missionById(x.id); if (m) { m.famille = x.famille; m.famille_choisie = x.choisie; } }
    renderAll();
  } catch { alert("Le classement n’a pas pu être enregistré. Réessayez."); }
}
const members = () => S.config.members;
const chantiers = () => S.config.chantiers;
const mName = (k) => (members().find((m) => m.k === k) || {}).n || (k ? k : "—");
const chName = (k) => (chantiers().find((c) => c.k === k) || {}).n || (k || "Sans chantier");
const missionById = (id) => S.missions.find((m) => m.id === id);
const missionName = (id) => { const m = missionById(id); return m ? m.name : id || "—"; };
const curTask = (id) => S.tasks.get(id);
const AGENTS_N = { agent: "l’agent PV", "agent-missions": "l’agent Missions", "agent-coherence": "l’agent Cohérence", "agent-element": "l’agent Element", "agent-dispos": "l’agent Disponibilités", "agent-whatsapp": "l’agent WhatsApp", "agent-newsletter": "l’agent Newsletter", "agent-hebdo": "l’agent Hebdo", "agent-relances": "l’agent Relances" };
const AUTHOR = (a) => AGENTS_N[a] || (members().some((m) => m.k === a) ? mName(a) : a ? a : "une analyse depuis la page");
const whoName = (w) => (String(w || "").startsWith("agent") ? AUTHOR(w).replace(/^l’/, "") : mName(w));
function sortTasks(a, b) { const r = (ST_RANK[a.status] ?? 2) - (ST_RANK[b.status] ?? 2); if (r) return r; const ea = toMs(a.end) ?? 9e15, eb = toMs(b.end) ?? 9e15; if (ea !== eb) return ea - eb; return a.id.localeCompare(b.id, "fr", { numeric: true }); }
function mdLite(src) {
  const lines = String(src || "").split("\n"); let html = "", inList = false;
  const inl = (x) => esc(x).replace(/\*\*(.+?)\*\*/g, "<b>$1</b>");
  for (const raw of lines) {
    const l = raw.trim();
    if (/^[-*•]\s+/.test(l)) { if (!inList) { html += "<ul>"; inList = true; } html += "<li>" + inl(l.replace(/^[-*•]\s+/, "")) + "</li>"; continue; }
    if (inList) { html += "</ul>"; inList = false; }
    if (l) html += "<p>" + inl(l.replace(/^#+\s*/, "")) + "</p>";
  }
  if (inList) html += "</ul>";
  return html;
}
const lienSur = (u) => (u && /^https?:\/\//i.test(u) ? u : null);
const lienSource = (src, defaut = "source") => (src && lienSur(src.url) ? `<a href="${esc(src.url)}" target="_blank" rel="noopener">${esc(src.label || defaut)}</a>` : src && src.label ? `<span>${esc(src.label)}</span>` : "");

function datesLine(t) {
  const late = t.status !== "done" && toMs(t.end) !== null && toMs(t.end) < todayMs();
  if (t.milestone) return `<span class="${late ? "late" : ""}">◆ ${esc(fmtD(t.end || t.start) || "date à fixer")}</span>`;
  if (!t.start && !t.end) return "<span>dates à fixer</span>";
  return `<span class="${late ? "late" : ""}">${esc(fmtD(t.start) || "…")} → ${esc(fmtD(t.end) || "…")}</span>`;
}
function respChips(t) {
  const out = [];
  if (t.pilot) out.push(`<span class="rchip pilot" style="--c:var(--${esc(t.pilot)},var(--col));--cs:var(--${esc(t.pilot)}-soft,var(--col-soft))" title="Pilote">${esc(mName(t.pilot))}</span>`);
  else out.push('<span class="rchip ghost">Sans pilote</span>');
  for (const k of t.contributors || []) if (k !== t.pilot) out.push(`<span class="rchip" style="--c:var(--${esc(k)},var(--col))" title="Contributeur·rice">${esc(mName(k))}</span>`);
  return out.join("");
}
const statutPill = (t) => `<span class="stsel ro" data-s="${esc(t.status || "todo")}">${esc(ST[t.status] || "")}</span>`;

/* ---------- En-tête, onglets, filtres, compteurs ---------- */
function renderStatus() {
  const pend = S.proposals.filter((p) => p.status === "pending").length;
  $("#statusline").innerHTML = `Copie synchronisée de l’artefact, en lecture · ${S.tasks.size} tâche${S.tasks.size > 1 ? "s" : ""} · ${pend} proposition${pend > 1 ? "s" : ""} en attente${DATA.racine.synchro_le ? " · synchronisée le " + esc(fmtDT(DATA.racine.synchro_le)) : ""}`;
}
function renderTabs() {
  const pend = S.proposals.filter((p) => p.status === "pending").length;
  $("#tabs").innerHTML = VIEWS.map((v) => `<button class="tab ${U.view === v ? "on" : ""}" role="tab" aria-selected="${U.view === v}" data-act="view" data-v="${v}">${LABELS[v]}${v === "attente" && pend ? `<span class="badge">${pend}</span>` : ""}</button>`).join("");
}
function renderFilters() {
  const el = $("#filters");
  if (U.view !== "tableau" && U.view !== "planning") { el.innerHTML = ""; el.hidden = true; return; }
  el.hidden = false;
  el.innerHTML = `
    <div class="fgroup"><span class="flabel">Personne</span>
      <button class="fchip ${U.fResp === "all" ? "on" : ""}" data-act="fresp" data-k="all">Toutes</button>
      ${members().map((m) => `<button class="fchip ${U.fResp === m.k ? "on" : ""}" data-c style="--c:var(--${esc(m.k)},var(--col))" data-act="fresp" data-k="${esc(m.k)}">${esc(m.n)}</button>`).join("")}
    </div>
    <div class="fgroup"><span class="flabel">Chantier</span>
      <select class="fsel" id="f-ch" data-chg="fch"><option value="all">Tous</option>${chantiers().map((c) => `<option value="${esc(c.k)}" ${U.fCh === c.k ? "selected" : ""}>${esc(c.k)} · ${esc(c.n)}</option>`).join("")}</select>
    </div>
    ${FAM.length ? `<div class="fgroup"><span class="flabel">Famille</span>${selectFamille("f-fam", U.fFam, 'data-chg="ffam"', true)}</div>` : ""}
    <div class="fgroup"><span class="flabel">Grouper par</span>
      <button class="fchip ${U.group === "pilot" ? "on" : ""}" data-act="group" data-k="pilot">Personne</button>
      <button class="fchip ${U.group === "chantier" ? "on" : ""}" data-act="group" data-k="chantier">Chantier</button>
      ${FAM.length ? `<button class="fchip ${U.group === "famille" ? "on" : ""}" data-act="group" data-k="famille">Famille</button>` : ""}
    </div>
    <label class="ck"><input type="checkbox" id="f-hide" data-chg="hide" ${U.hideDone ? "checked" : ""}> Masquer les tâches faites</label>`;
}
function renderSummary() {
  const el = $("#summary");
  if (U.view !== "tableau" && U.view !== "planning") { el.innerHTML = ""; return; }
  const list = [...S.tasks.values()].filter((t) => (U.fResp === "all" || t.pilot === U.fResp || (t.contributors || []).includes(U.fResp)) && famOk(t.famille));
  const c = { todo: 0, doing: 0, block: 0, done: 0 }; let late = 0; const tm = todayMs();
  for (const t of list) { c[t.status] = (c[t.status] || 0) + 1; if (t.status !== "done" && toMs(t.end) !== null && toMs(t.end) < tm) late++; }
  const pend = S.proposals.filter((p) => p.status === "pending").length;
  el.innerHTML = `
    <div class="kpi doing"><div class="n">${c.doing}</div><div class="l">En cours</div></div>
    <div class="kpi todo"><div class="n">${c.todo}</div><div class="l">À faire</div></div>
    <div class="kpi block"><div class="n">${c.block}</div><div class="l">Bloquées</div></div>
    <div class="kpi done"><div class="n">${c.done}</div><div class="l">Faites</div></div>
    <div class="kpi block"><div class="n">${late}</div><div class="l">Échéance dépassée</div></div>
    ${pend ? `<button class="kpi" data-act="view" data-v="attente"><div class="n">${pend}</div><div class="l">À valider</div></button>` : ""}`;
}
function filtered() {
  return [...S.tasks.values()].filter((t) =>
    (U.fResp === "all" || t.pilot === U.fResp || (t.contributors || []).includes(U.fResp)) &&
    (U.fCh === "all" || t.chantier === U.fCh) && famOk(t.famille) && (!U.hideDone || t.status !== "done"));
}
function grouped(list) {
  let g;
  if (U.group === "famille") {
    g = FAM.map((f) => ({ key: f.code, label: FAMG[f.famille] + " · " + f.libelle, c: "col", items: [] }));
    const none = { key: "", label: "Non classé", c: "none", items: [] };
    for (const t of list) (g.find((x) => x.key === t.famille) || none).items.push(t);
    g.push(none);
  } else if (U.group === "pilot") {
    g = members().map((m) => ({ key: m.k, label: m.n, c: m.k, items: [] }));
    const none = { key: "", label: "Sans pilote", c: "none", items: [] };
    for (const t of list) (g.find((x) => x.key === t.pilot) || none).items.push(t);
    g.push(none);
  } else {
    g = chantiers().map((c) => ({ key: c.k, label: c.k + " · " + c.n, c: "col", items: [] }));
    const none = { key: "", label: "Sans chantier", c: "none", items: [] };
    for (const t of list) (g.find((x) => x.key === t.chantier) || none).items.push(t);
    g.push(none);
  }
  g = g.filter((x) => x.items.length);
  g.forEach((x) => x.items.sort(sortTasks));
  return g;
}

/* ---------- Tableau ---------- */
function taskRow(t) {
  const subs = t.subtasks || []; const nd = subs.filter((s) => s.d).length; const open = U.openSubs.has(t.id);
  return `<div class="trow ${t.status === "done" ? "done" : ""}" data-id="${esc(t.id)}">
    <div class="tcell">
      <div class="tt"><span class="tid">${esc(t.id)}</span>${esc(t.title || "Sans titre")}</div>
      <div class="tmeta">
        ${U.group === "pilot" ? `<span title="${esc(chName(t.chantier))}">${esc(t.chantier || "—")}</span>` : ""}
        ${t.mission ? `<button class="mchip" data-act="gomission" data-mid="${esc(t.mission)}" title="Voir la mission">${esc(missionName(t.mission))}</button>` : ""}
        ${datesLine(t)}
        ${t.estimate_h ? `<span>${esc(t.estimate_h)} h</span>` : ""}
        ${t.milestone ? '<span class="mstag">jalon</span>' : ""}
        ${(t.deps || []).length ? `<span title="Dépend de">↤ ${esc(t.deps.join(", "))}</span>` : ""}
        ${t.source && lienSur(t.source.url) ? `<a class="linkbtn" href="${esc(t.source.url)}" target="_blank" rel="noopener">source</a>` : ""}
        <button class="editlink" data-act="fiche" data-k="t" title="Ouvrir la fiche complète">Fiche</button>
      </div>
    </div>
    <div class="tcell resp-c"><div class="resp">${respChips(t)}</div></div>
    <div class="tcell st">${statutPill(t)}</div>
    <div class="tcell sub">
      <button class="subbtn" data-act="subs" aria-expanded="${open}"><span class="caret ${open ? "open" : ""}">▶</span><span class="subprog"><i style="width:${subs.length ? Math.round((nd / subs.length) * 100) : 0}%"></i></span><span class="subcount">${subs.length ? nd + "/" + subs.length : "sous-tâches"}</span></button>
      ${open ? `<div class="sublist">${subs.map((s, i) => `<div class="subitem ${s.d ? "done" : ""}"><input type="checkbox" id="sub-${esc(t.id)}-${i}" ${s.d ? "checked" : ""} disabled><span>${esc(s.t)}</span></div>`).join("") || '<span class="msg">Aucune sous-tâche.</span>'}</div>` : ""}
    </div>
  </div>`;
}
function renderTableau() {
  const gs = grouped(filtered());
  let html = '<div class="board"><div class="colhead"><span>Tâche</span><span>Qui</span><span>Statut</span><span>Sous-tâches</span></div>';
  if (!gs.length) html += '<p class="empty">Aucune tâche pour ces filtres.</p>';
  for (const g of gs) {
    html += `<div class="lane-h" style="--c:var(--${esc(g.c)},var(--col));--cs:var(--${esc(g.c)}-soft,var(--col-soft))"><span class="ld"></span><span class="lt">${esc(g.label)}</span><span class="lc">${g.items.length} tâche${g.items.length > 1 ? "s" : ""}</span></div>`;
    html += g.items.map(taskRow).join("");
  }
  $("#view-tableau").innerHTML = html + "</div>";
}

/* ---------- Missions ---------- */
function missionCard(m) {
  const tasks = [...S.tasks.values()].filter((t) => t.mission === m.id).sort(sortTasks);
  const pend = S.proposals.filter((p) => p.status === "pending" && p.mission === m.id);
  const fresh = m.last_activity && toMs(m.last_activity) >= todayMs() - 2 * D;
  const srcs = (m.sources || []).slice(-5).reverse();
  const kindL = (k) => (k === "mail" ? "mail" : k === "pv" ? "PV" : k === "element" ? "Element" : k === "whatsapp" ? "WhatsApp" : "Drive");
  return `<div class="mcard ${U.mfocus === m.id ? "hl" : ""}" data-mid="${esc(m.id)}" id="mission-${esc(m.id)}">
    <div class="mhead"><span class="mname">${esc(m.name)}</span><span class="mtype ${m.type === "marche-public" ? "mp" : ""}">${m.type === "marche-public" ? "Marché public" : "Autre mission"}</span>${fresh ? '<span class="mnew">du nouveau</span>' : ""}</div>
    ${FAM.length ? `<div class="mmeta"><span class="famtag">${esc(famLib(m.famille))}</span>${DATA.peut_classer ? `<label>Classer ${selectFamille("mfam-" + m.id, m.famille_choisie ? m.famille : "", `data-chg="classer" data-type="mission" data-ref="${esc(m.id)}"`, false).replace('<optgroup', `<option value="">Automatique</option><optgroup`)}</label>` : ""}</div>` : ""}
    <div class="mmeta">${m.lieu ? `<span>${esc(m.lieu)}</span>` : ""}<span>Statut : ${esc(MSTAT[m.statut || "active"] || m.statut)}</span>${m.referent ? `<span>Référent·e : ${esc(mName(m.referent))}</span>` : ""}${m.last_activity ? `<span>activité : ${esc(fmtD(m.last_activity))}</span>` : ""}</div>
    ${m.context_md ? `<div class="mlab">Contexte</div><div class="md">${mdLite(m.context_md)}</div>` : ""}
    ${m.requests_md ? `<div class="mlab">Demandes et attentes</div><div class="md">${mdLite(m.requests_md)}</div>` : ""}
    ${(m.next_actions || []).length ? `<div class="mlab">Prochaines actions</div><div class="md"><ul>${m.next_actions.map((a) => `<li>${esc(a)}</li>`).join("")}</ul></div>` : ""}
    <div class="mlab">Tâches du Gantt · ${tasks.length}${pend.length ? ` · <button class="lk" data-act="view" data-v="attente">${pend.length} en attente de validation</button>` : ""}</div>
    ${tasks.length ? `<div class="mlist">${tasks.map((t) => `<div class="mtask"><span class="stdot ${esc(t.status)}" title="${esc(ST[t.status] || "")}"></span><span class="tid">${esc(t.id)}</span><button data-act="fiche" data-k="t" data-id="${esc(t.id)}">${esc(t.title)}</button><span class="msg">${esc(fmtD(t.end) || "")}</span></div>`).join("")}</div>` : '<span class="msg">Aucune tâche reliée pour l’instant.</span>'}
    ${srcs.length ? `<div class="mlab">Dernières sources</div>${srcs.map((x) => `<div class="msrc">${esc(fmtD(x.date) || "")} · ${kindL(x.kind)} · ${lienSur(x.url) ? `<a href="${esc(x.url)}" target="_blank" rel="noopener">${esc(x.label || "source")}</a>` : esc(x.label || "")}</div>`).join("")}` : ""}
  </div>`;
}
function renderMissions() {
  const list = S.missions.filter((m) => (U.mfilter === "all" || (m.statut || "active") === U.mfilter) && (U.mtype === "all" || (m.type || "autre") === U.mtype) && famOk(m.famille))
    .sort((a, b) => (b.last_activity || "").localeCompare(a.last_activity || "") || a.name.localeCompare(b.name, "fr"));
  const cnt = (k) => S.missions.filter((m) => (m.statut || "active") === k).length;
  $("#view-missions").innerHTML = `
    <div class="mtools">
      <div class="fgroup"><span class="flabel">Statut</span>${[["active", "Actives · " + cnt("active")], ["veille", "En veille · " + cnt("veille")], ["cloturee", "Clôturées · " + cnt("cloturee")], ["all", "Toutes"]].map(([k, l]) => `<button class="fchip ${U.mfilter === k ? "on" : ""}" data-act="mfilter" data-k="${k}">${l}</button>`).join("")}</div>
      <div class="fgroup"><span class="flabel">Type</span>${[["all", "Tous"], ["marche-public", "Marché public"], ["autre", "Autres"]].map(([k, l]) => `<button class="fchip ${U.mtype === k ? "on" : ""}" data-act="mtype" data-k="${k}">${l}</button>`).join("")}</div>
      ${FAM.length ? `<div class="fgroup"><span class="flabel">Famille</span>${selectFamille("m-fam", U.fFam, 'data-chg="ffam"', true)}</div>` : ""}
    </div>
    <p class="msg" style="margin-top:8px">L’agent Missions tient les fiches à jour dans l’artefact ; elles arrivent ici à chaque synchronisation.</p>
    ${list.length ? `<div class="mgrid">${list.map(missionCard).join("")}</div>` : `<div class="board" style="margin-top:14px"><p class="empty"><b>Aucune mission dans ce filtre.</b></p></div>`}`;
  if (U.mfocus) { const c = document.getElementById("mission-" + U.mfocus); if (c) setTimeout(() => c.scrollIntoView({ block: "center" }), 30); U.mfocus = ""; }
}

/* ---------- Planning ---------- */
const HOL = DATA.conges;
function renderPlanning() {
  const list = filtered(); const tm = todayMs();
  let s = tm - 28 * D, e = tm + 182 * D;
  for (const t of list) { const a = toMs(t.start), b = toMs(t.end); if (a !== null) s = Math.min(s, a); if (b !== null) e = Math.max(e, b + 14 * D); else if (a !== null) e = Math.max(e, a + 21 * D); }
  s = Math.max(s, tm - 150 * D); e = Math.min(e, tm + 680 * D);
  s -= ((new Date(s).getUTCDay() + 6) % 7) * D;
  e += (6 - ((new Date(e).getUTCDay() + 6) % 7)) * D;
  const days = Math.round((e - s) / D) + 1; const PX = 4; const W = days * PX; const L = 240;
  const x = (ms) => Math.round(((ms - s) / D) * PX);
  let bg = "";
  for (const h of HOL.filter((h) => h.z === "be")) { const a = Math.max(toMs(h.s), s), b = Math.min(toMs(h.e), e); if (b >= a) bg += `<div class="vac" style="left:${x(a)}px;width:${x(b + D) - x(a)}px"></div>`; }
  for (const hb of HOL.filter((h) => h.z === "be")) for (const hf of HOL.filter((h) => h.z === "fr")) {
    const a = Math.max(toMs(hb.s), toMs(hf.s), s), b = Math.min(toMs(hb.e), toMs(hf.e), e);
    if (b >= a) bg += `<div class="vac both" style="left:${x(a)}px;width:${x(b + D) - x(a)}px"></div>`;
  }
  for (let d = s; d <= e; d += 7 * D) bg += `<div class="gl ${new Date(d).getUTCDate() <= 7 ? "m" : ""}" style="left:${x(d)}px"></div>`;
  if (tm >= s && tm <= e) bg += `<div class="today" style="left:${x(tm)}px"><b>Auj.</b></div>`;
  let months = ""; const d0 = new Date(s); let mc = Date.UTC(d0.getUTCFullYear(), d0.getUTCMonth(), 1);
  while (mc <= e) { const nx = Date.UTC(new Date(mc).getUTCFullYear(), new Date(mc).getUTCMonth() + 1, 1); const a = Math.max(mc, s), b = Math.min(nx - D, e); months += `<div class="mband" style="left:${x(a)}px;width:${x(b + D) - x(a)}px">${esc(new Date(mc).toLocaleDateString("fr-BE", { month: "long", year: "numeric", timeZone: "UTC" }))}</div>`; mc = nx; }
  let weeks = ""; for (let d = s; d <= e; d += 7 * D) weeks += `<div class="wk" style="left:${x(d)}px;width:${7 * PX}px">${isoWeek(d)}</div>`;
  const holRow = (z) => HOL.filter((h) => h.z === z).map((h) => { const a = Math.max(toMs(h.s), s), b = Math.min(toMs(h.e), e); return b >= a ? `<div class="hol ${z}" style="left:${x(a)}px;width:${x(b + D) - x(a)}px" title="${esc(h.n)} : ${esc(fmtD(h.s))} → ${esc(fmtD(h.e))}">${esc(h.n)}</div>` : ""; }).join("");
  const row = (left, inner, cls, h) => `<div class="prow ${cls || ""}" style="height:${h || 32}px"><div class="pleft" style="width:${L}px">${left}</div><div class="ptrack" style="width:${W}px">${inner}</div></div>`;
  let rows = row("<b>Mois</b>", months, "phead", 22) + row("<span>Semaine</span>", weeks, "phead", 18)
    + row("<span>Congés scolaires BE</span>", holRow("be"), "", 26) + row("<span>Vacances FR (Yonne)</span>", holRow("fr"), "", 26);
  const absBy = {};
  for (const a of S.absences) { if (!a.who) continue; (absBy[a.who] = absBy[a.who] || []).push(a); }
  for (const m of members()) {
    const arr = (absBy[m.k] || []).filter((a) => toMs(a.end) !== null && toMs(a.end) >= s && toMs(a.start) <= e);
    if (!arr.length) continue;
    rows += row(`<span>${m.k === "col" ? "Jours fériés" : "Absences · " + esc(m.n)}</span>`, arr.map((a) => { const A = Math.max(toMs(a.start), s), B = Math.min(toMs(a.end), e); return `<div class="abs" style="--c:var(--${esc(m.k)},var(--col));--cs:var(--${esc(m.k)}-soft,var(--col-soft));left:${x(A)}px;width:${x(B + D) - x(A)}px" title="${esc(a.label || "Absence")} : ${esc(fmtD(a.start))} → ${esc(fmtD(a.end))}">${esc(a.label || "")}</div>`; }).join(""), "", 24);
  }
  for (const g of grouped(list)) {
    rows += `<div class="plane" style="--c:var(--${esc(g.c)},var(--col));--cs:var(--${esc(g.c)}-soft,var(--col-soft));width:${L + W}px"><span class="ld"></span><span class="lt">${esc(g.label)}</span></div>`;
    for (const t of g.items) {
      const a = toMs(t.start), b = toMs(t.end); let inner = "";
      const col = t.pilot || "none";
      const label = `${esc(t.id)} · ${esc(t.title || "")}`;
      if (t.milestone) { const m = b ?? a; if (m !== null && m >= s && m <= e) inner = `<button class="ms" style="--c:var(--${esc(col)},var(--col));left:${x(m) + PX / 2}px" data-act="fiche" data-k="t" data-id="${esc(t.id)}" title="${label} — ${esc(fmtD(t.end || t.start))}" aria-label="${label}"></button>`; }
      else if (a !== null || b !== null) {
        const A = Math.max(a ?? b, s), B = Math.min(b ?? a + 13 * D, e);
        if (B >= A) inner = `<button class="bar s-${esc(t.status || "todo")} ${b === null ? "open" : ""}" style="--c:var(--${esc(col)},var(--col));left:${x(A)}px;width:${Math.max(6, x(B + D) - x(A))}px" data-act="fiche" data-k="t" data-id="${esc(t.id)}" title="${label} — ${esc(ST[t.status] || "")} — ${esc(fmtD(t.start) || "…")} → ${esc(fmtD(t.end) || "…")}">${esc(t.id)}</button>`;
      }
      rows += row(`<span class="tid">${esc(t.id)}</span>${esc(t.title || "")}`, inner, "task", 32);
    }
  }
  const legend = `<div class="legend">
    <span class="lg"><span class="sw" style="background:var(--col);opacity:.5"></span>À faire</span>
    <span class="lg"><span class="sw" style="background:var(--col);box-shadow:0 0 0 2px var(--st-doing) inset"></span>En cours</span>
    <span class="lg"><span class="sw" style="background:repeating-linear-gradient(45deg,var(--col),var(--col) 3px,var(--panel) 3px,var(--panel) 5px)"></span>Bloqué</span>
    <span class="lg">✓ Fait</span><span class="lg">◆ Jalon</span>
    <span class="lg"><span class="sw" style="background:var(--vac);border:1px solid var(--line)"></span>Congés scolaires BE (fond)</span>
    <span class="lg"><span class="sw" style="background:var(--vac2);border:1px solid var(--line)"></span>Congés BE et Yonne en même temps</span>
    <span class="lg">Clic sur une barre : ouvre la fiche</span></div>`;
  const tmS = todayStr();
  const absList = S.absences.filter((a) => (a.end || a.start || "") >= tmS).sort((a, b) => (a.start || "").localeCompare(b.start || ""))
    .map((a) => `<div class="absitem"><b>${esc(a.who === "col" ? "Toute l’équipe" : mName(a.who))}</b><span>${a.start === a.end ? esc(fmtD(a.start)) : esc(fmtD(a.start)) + " → " + esc(fmtD(a.end))}</span><span>${esc(a.label || "")}</span></div>`).join("");
  $("#view-planning").innerHTML = `<div class="board"><div class="pscroll"><div class="pchart" style="width:${L + W}px"><div class="pbg" style="left:${L}px;width:${W}px">${bg}</div><div class="prows">${rows}</div></div></div></div>
    ${legend}
    <div class="section"><h2>Absences et indisponibilités</h2><p class="hint">Reprises de l’artefact (grille des prestations et absences saisies) à chaque synchronisation.</p>
      <div class="abslist">${absList || '<span class="msg">Aucune absence à venir.</span>'}</div></div>`;
}

/* ---------- Salle d'attente ---------- */
const KIND_L = { create: "Nouvelle tâche", update: "Mise à jour", decision: "Décision", merge: "Fusion" };
const propTitle = (p) => (p.task_id ? p.task_id + " · " + ((curTask(p.task_id) || {}).title || "tâche") : p.reason || KIND_L[p.kind] || "Proposition");
function propCard(p) {
  return `<div class="pcard">
    <div class="phead2"><span class="kind ${esc(p.kind)}">${esc(KIND_L[p.kind] || p.kind)}</span><span class="ptitle">${esc(propTitle(p))}</span>${p.confidence ? `<span class="conf ${esc(p.confidence)}">confiance ${esc(p.confidence)}</span>` : ""}</div>
    ${p.mission ? `<div class="msg">Mission : <button class="mchip" data-act="gomission" data-mid="${esc(p.mission)}">${esc(missionName(p.mission))}</button></div>` : ""}
    ${p.reason ? `<div class="reason">${esc(p.reason)}</div>` : ""}
    <div class="pmeta"><span>Proposé par ${esc(AUTHOR(p.author))}</span><span>${esc(fmtDT(p.created_at))}</span>${lienSource(p.source)}</div>
    <div class="msg">À valider, ajuster ou rejeter dans l’artefact.</div>
  </div>`;
}
function renderAttente() {
  const pend = S.proposals.filter((p) => p.status === "pending");
  const done = S.proposals.filter((p) => p.status !== "pending").slice(0, 40);
  const autoWeek = S.journal.filter((j) => j.type === "auto" && j.ts && toMs(j.ts.slice(0, 10)) >= todayMs() - 7 * D).length;
  $("#view-attente").innerHTML = `
    <div class="section" style="padding:0;overflow:hidden">
      <div style="padding:14px 16px 0"><h2>En attente de validation · ${pend.length}</h2><p class="hint">Les agents tiennent le Gantt à jour eux-mêmes et consignent chaque changement dans le journal. Ici n’arrivent que les cas réservés : suppression, fusion, changement de titre ou de chantier, réouverture d’une tâche faite, conflit. Pendant la transition, on les valide dans l’artefact.</p>${autoWeek ? `<p class="autoline"><span>${autoWeek} changement${autoWeek > 1 ? "s" : ""} appliqué${autoWeek > 1 ? "s" : ""} par les agents ces 7 derniers jours.</span><button data-act="goauto">Les voir</button></p>` : ""}</div>
      ${pend.length ? pend.map(propCard).join("") : '<p class="empty">Aucune proposition en attente.</p>'}
    </div>
    ${done.length ? `<details class="histo"><summary>Propositions traitées récemment (${done.length})</summary>${done.map((p) => `<div class="hrow"><span class="${p.status === "accepted" ? "st-ok" : "st-no"}">${p.status === "accepted" ? "Validée" : "Rejetée"}</span><span>${esc(KIND_L[p.kind] || p.kind)} · ${esc(propTitle(p))}</span><span>par ${esc(AUTHOR(p.author))}, ${esc(fmtDT(p.created_at))}</span>${p.reason && p.task_id ? `<span>${esc(p.reason)}</span>` : ""}</div>`).join("")}</details>` : ""}`;
}

/* ---------- Agents & journal ---------- */
function autoBlock() {
  const a = DATA.auto;
  if (!a) return "";
  if (!a.fichier) return `<p class="msg">Synchronisation automatique : pas encore réglée (fichier d’export à indiquer dans le réglage PILOTE_33_EXPORT du site).</p>`;
  return `<div class="hbodj"><span>Synchronisation automatique toutes les 2 heures, depuis le fichier d’export du Drive.${a.le ? ` Dernière : ${esc(fmtDT(a.le))}${a.bilan ? ` (${a.bilan.taches} tâches, ${a.bilan.missions} missions)` : ""}.` : " Pas encore passée."}${a.essai_le && a.essai_le !== a.le && !a.erreur ? ` Fichier relu le ${esc(fmtDT(a.essai_le))}, inchangé.` : ""}</span>
    ${a.erreur ? `<span class="pill warn">${esc(a.erreur)}</span>` : ""}
    <form method="post" enctype="multipart/form-data" style="display:inline"><input type="hidden" name="depuis_fichier" value="1"><button class="btn small" type="submit">Synchroniser maintenant</button></form></div>`;
}
function syncBlock() {
  const r = DATA.import || {};
  return `<div class="section"><h2>Synchronisation avec l’artefact</h2>
    <p class="hint">Pendant la transition, on travaille dans l’artefact et ses agents ; le site en garde une copie, en lecture, réservée à l’équipe.${DATA.racine.synchro_le ? ` Dernière synchronisation : ${esc(fmtDT(DATA.racine.synchro_le))}.` : ""}${lienSur(DATA.racine.artefact) ? ` <a href="${esc(DATA.racine.artefact)}" target="_blank" rel="noopener">Ouvrir l’artefact</a>.` : ""}</p>
    ${r.bilan ? `<p class="pill ok">Synchronisation faite : ${r.bilan.missions} missions, ${r.bilan.taches} tâches, ${r.bilan.absences} indisponibilités, ${r.bilan.historique} entrées de journal et propositions${r.bilan.retirees ? `, ${r.bilan.retirees} tâche(s) retirée(s)` : ""}.</p>` : ""}
    ${r.message ? `<p class="pill warn" role="alert">${esc(r.message)}</p>` : ""}
    ${autoBlock()}
    ${DATA.peut_importer ? `<form method="post" enctype="multipart/form-data" class="formrow" style="margin-top:8px">
        <div class="field wide"><label for="export">Export de l’artefact (onglet « Agents &amp; journal », « Exporter tout (JSON) »)</label><input id="export" name="export" type="file" accept="application/json,.json" required></div>
        <button class="btn primary" type="submit">Synchroniser</button>
      </form>` : '<p class="msg">La synchronisation est faite par la coordination.</p>'}
  </div>`;
}
function renderJournal() {
  const types = [["all", "Tout"], ["auto", "Par les agents"], ["modif", "Modifications"], ["creation", "Créations"], ["validation", "Validations"], ["rejet", "Rejets"], ["decision", "Décisions"]];
  const list = S.journal.filter((j) => U.jFilter === "all" || j.type === U.jFilter);
  const typeL = { hebdo: "hebdo", auto: "agent", agent: "lancement", modif: "modif", creation: "création", validation: "validation", rejet: "rejet", decision: "décision", suppression: "suppression", absence: "absence", fusion: "fusion", mission: "mission" };
  $("#view-journal").innerHTML = `${syncBlock()}
    <div class="filters" style="margin-top:16px"><div class="fgroup">${types.map(([k, l]) => `<button class="fchip ${U.jFilter === k ? "on" : ""}" data-act="jf" data-k="${k}">${l}</button>`).join("")}</div></div>
    <div class="board">${list.length ? list.map((j) => `<div class="jrow"><span class="jdate">${esc(fmtDT(j.ts))}</span><span class="jwho">${esc(whoName(j.who))}</span><span class="jtype ${esc(j.type)}">${esc(typeL[j.type] || j.type)}</span><span class="jsum">${j.task_id && curTask(j.task_id) ? `<button class="tid lk" data-act="fiche" data-k="t" data-id="${esc(j.task_id)}">${esc(j.task_id)}</button>` : j.task_id ? `<span class="tid">${esc(j.task_id)}</span>` : ""}${esc(j.summary)}${j.source && lienSur(j.source.url) ? ` · <a href="${esc(j.source.url)}" target="_blank" rel="noopener">${esc(j.source.label || "source")}</a>` : ""}</span></div>`).join("") : '<p class="empty">Le journal est vide pour ce filtre.</p>'}</div>`;
}

/* ---------- Recherche ---------- */
const fold = (s) => String(s ?? "").normalize("NFD").replace(/[̀-ͯ]/g, "").toLowerCase();
const flat = (s) => String(s ?? "").normalize("NFC").replace(/\s+/g, " ").trim();
const mdLines = (md) => String(md || "").split("\n").map((x) => x.replace(/^[-*•#\s]+/, "").trim()).filter(Boolean);
function hlHtml(text, terms, max?) {
  const s = flat(text); const f = fold(s); const marks = [];
  for (const t of terms) { if (!t) continue; let i = f.indexOf(t); while (i >= 0) { marks.push([i, i + t.length]); i = f.indexOf(t, i + t.length); } }
  marks.sort((a, b) => a[0] - b[0]); const mg = [];
  for (const m of marks) { const l = mg[mg.length - 1]; if (l && m[0] <= l[1]) l[1] = Math.max(l[1], m[1]); else mg.push(m.slice()); }
  let a = 0, b = s.length;
  if (max && s.length > max) { const first = mg.length ? mg[0][0] : 0; a = Math.max(0, first - Math.round(max * 0.3)); b = Math.min(s.length, a + max); a = Math.max(0, b - max); }
  let out = a > 0 ? "…" : "", p = a;
  for (const [xx, y] of mg) { if (y <= a || xx >= b) continue; const X = Math.max(xx, a), Y = Math.min(y, b); out += esc(s.slice(p, X)) + "<mark>" + esc(s.slice(X, Y)) + "</mark>"; p = Y; }
  return out + esc(s.slice(p, b)) + (b < s.length ? "…" : "");
}
function searchAll(q) {
  const terms = [...new Set(fold(flat(q)).split(" ").filter(Boolean))];
  const R = { terms, t: [], m: [], j: [] };
  if (!terms.length) return R;
  const test = (fields) => {
    const ff = fields.filter((x) => x[0]).map(([x, w, l]) => ({ x, f: fold(flat(x)), w, l }));
    let score = 0;
    for (const t of terms) { let best = 0; for (const e of ff) if (e.w > best && e.f.includes(t)) best = e.w; if (!best) return null; score += best; }
    let snip = null, bestN = 0;
    for (const e of ff) { if (!e.l) continue; const n = terms.filter((t) => e.f.includes(t)).length; if (n > bestN) { bestN = n; snip = { label: e.l, text: e.x }; } }
    return { score, snip };
  };
  const lead = terms.join(" ");
  for (const t of S.tasks.values()) {
    const r = test([[t.id, 12, null], [t.title, 8, null], ...(t.subtasks || []).map((s) => [s && s.t, 3, s && s.d ? "Sous-tâche faite" : "Sous-tâche"]), ...String(t.notes || "").split("\n").map((x) => x.trim()).filter(Boolean).map((x) => [x, 2, "Note"]), [t.mission ? missionName(t.mission) : "", 4, "Mission"], [(t.chantier || "") + " " + chName(t.chantier), 1, null], [[t.pilot, ...(t.contributors || [])].filter(Boolean).map(mName).join(" "), 1, null], [t.source && t.source.label, 1, "Source"]]);
    if (!r) continue;
    let sc = r.score + (fold(t.id) === lead ? 30 : 0) + (fold(t.title).startsWith(terms[0]) ? 3 : 0);
    if (t.status === "done") sc *= 0.6;
    R.t.push({ sc, t, snip: r.snip });
  }
  for (const m of S.missions) {
    const r = test([[m.name, 10, null], [m.lieu, 5, "Lieu"], [(m.aliases || []).join(" · "), 5, "Aussi appelée"], ...mdLines(m.context_md).map((x) => [x, 2, "Contexte"]), ...mdLines(m.requests_md).map((x) => [x, 2, "Demande"]), ...(m.next_actions || []).map((x) => [x, 2, "Prochaine action"]), [m.referent ? mName(m.referent) : "", 1, null], [m.type === "marche-public" ? "Marché public SPW" : "Autre mission", 1, null]]);
    if (!r) continue;
    R.m.push({ sc: r.score * ((m.statut || "active") === "cloturee" ? 0.6 : 1) + (fold(m.name).startsWith(terms[0]) ? 3 : 0), m, snip: r.snip });
  }
  for (const j of S.journal) {
    const r = test([[j.summary, 3, null], [j.task_id, 4, null], [j.source && j.source.label, 1, "Source"], [whoName(j.who), 1, null]]);
    if (!r) continue;
    R.j.push({ sc: r.score * (j.type === "decision" ? 1.3 : 1), j, snip: r.snip });
  }
  R.t.sort((a, b) => b.sc - a.sc || sortTasks(a.t, b.t));
  R.m.sort((a, b) => b.sc - a.sc);
  R.j.sort((a, b) => b.sc - a.sc || String(b.j.ts || "").localeCompare(String(a.j.ts || "")));
  return R;
}
function renderSearch() {
  const el = $("#search-results");
  const q = U.q.trim();
  if (q.length < 2 || !U.sOpen) { if (!el.hidden) { el.hidden = true; el.innerHTML = ""; } return; }
  const R = searchAll(q); const T = R.terms;
  const tot = R.t.length + R.m.length + R.j.length;
  const snip = (r) => (r.snip ? `<span class="ssnip"><b>${esc(r.snip.label)} :</b> ${hlHtml(r.snip.text, T, 170)}</span>` : "");
  const row = {
    t: (r) => { const t = r.t; return `<button class="sres" data-act="fiche" data-k="t" data-id="${esc(t.id)}"><span class="stdot ${esc(t.status || "todo")}" title="${esc(ST[t.status] || "")}"></span><span class="sbody"><span class="stitle"><span class="tid">${hlHtml(t.id, T)}</span>${hlHtml(t.title || "Sans titre", T)}</span><span class="smeta">${esc(ST[t.status] || "")} · ${esc(t.pilot ? mName(t.pilot) : "sans pilote")} · ${esc(t.chantier || "—")}${t.end ? " · échéance " + esc(fmtD(t.end)) : ""}${t.mission ? " · " + esc(missionName(t.mission)) : ""}</span>${snip(r)}</span></button>`; },
    m: (r) => { const m = r.m; return `<button class="sres" data-act="gomission" data-mid="${esc(m.id)}"><span class="mtype ${m.type === "marche-public" ? "mp" : ""}">${m.type === "marche-public" ? "MP" : "Mission"}</span><span class="sbody"><span class="stitle">${hlHtml(m.name, T)}</span><span class="smeta">${esc(MSTAT[m.statut || "active"] || "")}${m.lieu ? " · " + esc(m.lieu) : ""}${m.referent ? " · " + esc(mName(m.referent)) : ""}${m.last_activity ? " · activité " + esc(fmtD(m.last_activity)) : ""}</span>${snip(r)}</span></button>`; },
    j: (r) => { const j = r.j; const t = j.task_id ? curTask(j.task_id) : null; const inner = `<span class="jtype ${esc(j.type)}">${esc(j.type === "auto" ? "agent" : j.type || "")}</span><span class="sbody"><span class="stitle">${j.task_id ? `<span class="tid">${hlHtml(j.task_id, T)}</span>` : ""}${hlHtml(j.summary, T, 220)}</span><span class="smeta">${esc(fmtDT(j.ts))} · ${esc(whoName(j.who))}${j.source && j.source.label ? " · " + esc(j.source.label) : ""}</span></span>`; return t ? `<button class="sres" data-act="fiche" data-k="t" data-id="${esc(t.id)}">${inner}</button>` : `<div class="sres static">${inner}</div>`; },
  };
  const kinds = ["t", "m", "j"];
  if (U.sType !== "all" && !R[U.sType].length) U.sType = "all";
  let html = `<div class="section srch"><div class="shead"><h2>${tot} résultat${tot > 1 ? "s" : ""} pour « ${esc(q)} »</h2><div class="fgroup">${[["all", "Tout · " + tot], ...kinds.filter((k) => R[k].length).map((k) => [k, S_LBL[k] + " · " + R[k].length])].map(([k, l]) => `<button class="fchip ${U.sType === k ? "on" : ""}" data-act="stype" data-k="${k}">${esc(l)}</button>`).join("")}</div><span class="spacer"></span><button class="btn small" data-act="sclear">Fermer</button></div>`;
  if (!tot) html += '<p class="msg">Aucun résultat. Essaie un autre mot, un ID (ex. SPW-04), un lieu ou un prénom.</p>';
  for (const k of kinds.filter((k) => U.sType === "all" || U.sType === k)) {
    const arr = R[k]; if (!arr.length) continue;
    const lim = U.sMore[k] || U.sType === k ? arr.length : S_LIM[k];
    html += `<h3 class="hbh">${esc(S_LBL[k])} · ${arr.length}</h3><div class="slist">${arr.slice(0, lim).map(row[k]).join("")}</div>${arr.length > lim ? `<button class="linkbtn smore" data-act="smore" data-k="${k}">Afficher les ${arr.length - lim} autres</button>` : ""}`;
  }
  el.innerHTML = html + '<p class="msg shint">Entrée ouvre le premier résultat · Échap efface · « / » revient à la recherche depuis n’importe où.</p></div>';
  el.hidden = false;
}

/* ---------- Fiche d'une tâche ---------- */
function ficheTask(t) {
  const m = t.mission ? missionById(t.mission) : null;
  const subs = t.subtasks || []; const nd = subs.filter((s) => s && s.d).length;
  const hist = S.journal.filter((j) => j.task_id === t.id).slice(0, 12);
  const rdeps = [...S.tasks.values()].filter((x) => (x.deps || []).includes(t.id));
  const depBtn = (id) => (curTask(id) ? `<button class="mchip" data-act="fiche" data-k="t" data-id="${esc(id)}" title="${esc(curTask(id).title)}">${esc(id)}</button>` : `<span class="tid">${esc(id)}</span>`);
  const body = `
    <div class="fgrid">
      <div class="fkv"><span class="fl">Statut</span>${statutPill(t)}</div>
      <div class="fkv"><span class="fl">${t.milestone ? "Jalon" : "Dates"}</span><span class="tmeta">${datesLine(t)}</span></div>
      <div class="fkv"><span class="fl">Qui</span><div class="resp">${respChips(t)}</div></div>
      ${t.estimate_h ? `<div class="fkv"><span class="fl">Durée estimée</span><span>${esc(t.estimate_h)} h</span></div>` : ""}
      ${FAM.length ? `<div class="fkv"><span class="fl">Famille</span>${DATA.peut_classer ? selectFamille("tfam-" + t.id, t.famille_choisie ? t.famille : "", `data-chg="classer" data-type="tache" data-ref="${esc(t.id)}"`, false).replace('<optgroup', `<option value="">Automatique · ${esc(t.famille_choisie ? "" : famLib(t.famille))}</option><optgroup`) : `<span>${esc(famLib(t.famille))}</span>`}</div>` : ""}
    </div>
    ${m ? `<div class="cxlab">Mission</div><div class="flinked"><div class="cxrow"><button class="mchip" data-act="gomission" data-mid="${esc(m.id)}">${esc(m.name)}</button>${m.lieu ? `<span>${esc(m.lieu)}</span>` : ""}${m.referent ? `<span>référent·e ${esc(mName(m.referent))}</span>` : ""}</div>${(m.next_actions || []).length ? `<ul class="cxsubs">${m.next_actions.slice(0, 4).map((a) => `<li>${esc(a)}</li>`).join("")}</ul>` : ""}</div>` : ""}
    <div class="cxlab">Sous-tâches · ${nd}/${subs.length}</div>
    <div class="sublist">${subs.map((s, i) => `<div class="subitem ${s.d ? "done" : ""}"><input type="checkbox" id="fsub-${esc(t.id)}-${i}" ${s.d ? "checked" : ""} disabled aria-label="${esc(s.t)}"><span>${esc(s.t)}</span></div>`).join("") || '<span class="msg">Aucune sous-tâche.</span>'}</div>
    ${t.notes ? `<div class="cxlab">Notes</div><div class="md fnotes">${mdLite(t.notes)}</div>` : ""}
    ${(t.deps || []).length || rdeps.length ? `<div class="cxlab">Liens entre tâches</div><div class="cxrow">${(t.deps || []).length ? `<span>Dépend de</span>${t.deps.map(depBtn).join("")}` : ""}${rdeps.length ? `<span>Bloque</span>${rdeps.map((x) => depBtn(x.id)).join("")}` : ""}</div>` : ""}
    ${t.source && (t.source.url || t.source.label) ? `<div class="cxlab">Source</div><div class="cxrow">${lienSource(t.source, "Ouvrir la source")}</div>` : ""}
    ${hist.length ? `<div class="cxlab">Historique · ${hist.length} dernière${hist.length > 1 ? "s" : ""} entrée${hist.length > 1 ? "s" : ""}</div><div class="fhist">${hist.map((j) => `<div class="fhrow"><span class="jdate">${esc(fmtDT(j.ts))}</span><span class="jwho">${esc(whoName(j.who))}</span><span class="jsum">${esc(j.summary)}${j.source && lienSur(j.source.url) ? ` · <a href="${esc(j.source.url)}" target="_blank" rel="noopener">${esc(j.source.label || "source")}</a>` : ""}</span></div>`).join("")}</div>` : ""}`;
  const head = `<div class="fhead"><div class="fhl"><p class="eyebrow">${esc(t.chantier || "—")} · ${esc(chName(t.chantier))}</p><h2 id="fiche-t"><span class="tid">${esc(t.id)}</span>${esc(t.title || "Sans titre")}</h2></div><button class="fclose" data-act="ficheclose" aria-label="Fermer la fiche">×</button></div>`;
  const foot = `<span class="msg">Copie en lecture : on modifie cette tâche dans l’artefact.</span>`;
  return { head, body, foot };
}
function renderFiche() {
  const el = $("#fiche"); const f = U.fiche;
  $(".p33").classList.toggle("fopen", !!f);
  if (!f) { el.innerHTML = ""; return; }
  const t = curTask(f.id);
  const c = t ? ficheTask(t) : { head: `<div class="fhead"><div class="fhl"><h2 id="fiche-t">${esc(f.id)}</h2></div><button class="fclose" data-act="ficheclose" aria-label="Fermer la fiche">×</button></div>`, body: `<p class="msg">La tâche ${esc(f.id)} n’existe plus : supprimée, fusionnée ou retirée.</p>`, foot: "" };
  el.innerHTML = `<div class="fbg" data-act="ficheclose"></div><div class="fiche" role="dialog" aria-modal="true" aria-labelledby="fiche-t">${c.head}<div class="fbody">${c.body}</div>${c.foot ? `<div class="ffoot">${c.foot}</div>` : ""}</div>`;
  const b = el.querySelector(".fclose") as HTMLElement; if (b) try { b.focus({ preventScroll: true }); } catch {}
}

/* ---------- Rendu et événements ---------- */
function renderAll() {
  renderStatus(); renderTabs(); renderFilters(); renderSummary();
  for (const v of VIEWS) $("#view-" + v).hidden = v !== U.view;
  if (U.view === "tableau") renderTableau();
  else if (U.view === "missions") renderMissions();
  else if (U.view === "planning") renderPlanning();
  else if (U.view === "attente") renderAttente();
  else renderJournal();
  renderSearch(); renderFiche();
}
function allerA(v) { U.view = v; history.replaceState(null, "", "#" + v); renderAll(); window.scrollTo({ top: $(".toolbar").offsetTop - 12 }); }

document.addEventListener("click", (ev) => {
  const el = (ev.target as HTMLElement).closest("[data-act]") as HTMLElement;
  if (!el || !el.closest(".p33")) return;
  const a = el.dataset.act;
  const row = el.closest(".trow") as HTMLElement;
  if (a === "view") allerA(el.dataset.v);
  else if (a === "fresp") { U.fResp = el.dataset.k; renderAll(); }
  else if (a === "group") { U.group = el.dataset.k; renderAll(); }
  else if (a === "subs" && row) { const id = row.dataset.id; U.openSubs.has(id) ? U.openSubs.delete(id) : U.openSubs.add(id); renderTableau(); }
  else if (a === "fiche") { U.fiche = { k: "t", id: el.dataset.id || (row && row.dataset.id) }; U.sOpen = false; renderSearch(); renderFiche(); }
  else if (a === "ficheclose") { U.fiche = null; renderFiche(); }
  else if (a === "gomission") { U.mfocus = el.dataset.mid; U.mfilter = "all"; U.fiche = null; U.sOpen = false; allerA("missions"); }
  else if (a === "mfilter") { U.mfilter = el.dataset.k; renderMissions(); }
  else if (a === "mtype") { U.mtype = el.dataset.k; renderMissions(); }
  else if (a === "jf") { U.jFilter = el.dataset.k; renderJournal(); }
  else if (a === "goauto") { U.jFilter = "auto"; allerA("journal"); }
  else if (a === "stype") { U.sType = el.dataset.k; renderSearch(); }
  else if (a === "smore") { U.sMore[el.dataset.k] = true; renderSearch(); }
  else if (a === "sclear") { U.q = ""; ($("#q") as HTMLInputElement).value = ""; U.sOpen = false; renderSearch(); }
});
document.addEventListener("change", (ev) => {
  const el = ev.target as HTMLInputElement;
  if (el.dataset.chg === "fch") { U.fCh = el.value; renderAll(); }
  else if (el.dataset.chg === "ffam") { U.fFam = el.value; renderAll(); }
  else if (el.dataset.chg === "classer") classer(el.dataset.type, el.dataset.ref, el.value || null);
  else if (el.dataset.chg === "hide") { U.hideDone = el.checked; renderAll(); }
});
const q = $("#q") as HTMLInputElement;
q.addEventListener("input", () => { U.q = q.value; U.sOpen = true; U.sType = "all"; U.sMore = {}; renderSearch(); });
q.addEventListener("keydown", (ev) => {
  if (ev.key === "Escape") { q.value = ""; U.q = ""; U.sOpen = false; renderSearch(); }
  if (ev.key === "Enter") { const first = $("#search-results .sres:not(.static)"); if (first) first.click(); }
});
document.addEventListener("keydown", (ev) => {
  if (ev.key === "Escape" && U.fiche) { U.fiche = null; renderFiche(); }
  if (ev.key === "/" && !/INPUT|TEXTAREA|SELECT/.test((document.activeElement || {}).tagName || "")) { ev.preventDefault(); q.focus(); }
});
// Liens directs : #tache-<ID>, #mission-<id>, ou un onglet.
const h = location.hash;
if (h.startsWith("#tache-")) U.fiche = { k: "t", id: decodeURIComponent(h.slice(7)) };
else if (h.startsWith("#mission-")) { U.view = "missions"; U.mfilter = "all"; U.mfocus = decodeURIComponent(h.slice(9)); }
renderAll();
export {};
