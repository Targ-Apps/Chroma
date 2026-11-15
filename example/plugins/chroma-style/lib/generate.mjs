/**
 * Gramática de clases en JavaScript (se usa en el navegador: tw()/twMerge de tw.js resuelve cada clase con resolveUtility).
 * El generador de CSS del build es el plugin nativo chroma-style del CLI (Rust), que reproduce esta misma gramática byte a byte.
 * Del nombre de clase al CSS: parsea `variantes:utilidad`, resuelve la utilidad en el registro y ordena la salida.
 */
import { registry, byRoot } from "./rules.mjs";
import { resolveVariant, RANK_ORDER } from "./variants.mjs";
import { breakpoints } from "./theme.mjs";
import { cssEscape, normalizeArbitrary, parseArb } from "./value.mjs";

/** Parte por `:` de primer nivel (respeta [] y ()). */
export function splitTop(s, sep = ":") {
  const out = []; let d = 0, cur = "";
  for (const c of s) {
    if (c === "[" || c === "(") d++; else if (c === "]" || c === ")") d--;
    if (c === sep && d === 0) { out.push(cur); cur = ""; } else cur += c;
  }
  out.push(cur); return out;
}

function candidateSplits(name) {
  // posiciones de '-' fuera de [] y ()
  const cuts = []; let d = 0;
  for (let i = 0; i < name.length; i++) {
    const c = name[i];
    if (c === "[" || c === "(") d++; else if (c === "]" || c === ")") d--;
    else if (c === "-" && d === 0 && i > 0) cuts.push(i);
  }
  const out = [[name, ""]];
  for (let k = cuts.length - 1; k >= 0; k--) out.push([name.slice(0, cuts[k]), name.slice(cuts[k] + 1)]);
  return out;
}

/** Resuelve la parte "utilidad" -> { decls, order, childSel, extraAt } o null. */
export function resolveUtility(util, cfg) {
  // propiedad arbitraria: [prop:valor]
  let m = util.match(/^\[(-{0,2}[a-zA-Z][\w-]*):(.+)\]$/s);
  if (m) return { decls: [[m[1], normalizeArbitrary(m[2])]], order: registry.length + (m[1].startsWith("--") ? 2 : 1) };
  let neg = false, name = util;
  if (name.startsWith("-") && /^-[a-z@\[(]/.test(name)) { neg = true; name = name.slice(1); }
  const ctx = { neg, uses: new Set(), cfg };
  for (const [root, rest] of candidateSplits(name)) {
    const list = byRoot.get(root); if (!list) continue;
    for (const entry of list.slice().sort((a, b) => a.order - b.order)) {
      const decls = entry.fn(rest, ctx);
      if (decls && decls.length) {
        const res = { decls, order: entry.order, childSel: decls.childSel, container: entry.container, animation: ctx.animation };
        return res;
      }
    }
  }
  return null;
}

/** Compila un nombre de clase completo. Devuelve lista de reglas o null. */
export function compile(token, cfg = {}) {
  if (token.length > 200 || /[\s"'`<>{};]/.test(token.replace(/\[[^\]]*\]/g, "")) ) return null;
  const parts = splitTop(token);
  let util = parts.pop();
  if (!util) return null;
  let important = false;
  if (util.endsWith("!")) { important = true; util = util.slice(0, -1); } else if (util.startsWith("!")) { important = true; util = util.slice(1); }
  const res = resolveUtility(util, cfg);
  if (!res) return null;
  let ctx = { sels: ["&"], at: [], content: false };
  let key = 0n;
  for (const v of parts) {
    const name = v.replace(/^!/, "");
    const rv = resolveVariant(name, cfg);
    if (!rv) return null;
    ctx = { ...ctx, ...rv.apply(ctx) };
    key |= 1n << BigInt(rv.rank);
  }
  const cls = "." + cssEscape(token);
  const wrapSel = (s) => (res.childSel ? `:where(${s} > :not(:last-child))` : s);
  const selectors = ctx.sels.map((s) => wrapSel(s).split("&").join(cls));
  let decls = res.decls.map(([p, v]) => [p, important ? `${v} !important` : v]);
  if (ctx.content) decls = [["content", "var(--cs-content)"], ...decls];
  const base = { token, selectors, at: ctx.at, decls, key, order: res.order, animation: res.animation };
  const rules = [base];
  if (res.container) {
    rules.push(...Object.values({ ...breakpoints }).map((bp) => ({ ...base, at: [...ctx.at, `@media (width >= ${bp})`], decls: [["max-width", bp]], order: res.order + 0.1 })));
  }
  return rules;
}

const collator = new Intl.Collator("en", { numeric: true });

/** Ordena reglas: variantes (por rango) -> utilidad (orden del registro) -> nombre. */
export function sortRules(rules) {
  return rules.sort((a, b) => (a.key < b.key ? -1 : a.key > b.key ? 1 : 0) || a.order - b.order || collator.compare(a.token, b.token));
}

/** Imprime reglas agrupando at-rules consecutivas iguales. */
export function printRules(rules, { minify = false, indent = "  " } = {}) {
  const nl = minify ? "" : "\n";
  const sp = minify ? "" : " ";
  let out = ""; let cur = []; 
  const ind = (n) => (minify ? "" : indent.repeat(n));
  const closeTo = (n) => { while (cur.length > n) { cur.pop(); out += `${ind(cur.length)}}${nl}`; } };
  for (const r of rules) {
    let common = 0;
    while (common < cur.length && common < r.at.length && cur[common] === r.at[common]) common++;
    closeTo(common);
    for (let i = common; i < r.at.length; i++) { out += `${ind(cur.length)}${r.at[i]}${sp}{${nl}`; cur.push(r.at[i]); }
    const sel = r.selectors.join(minify ? "," : `,${sp}`);
    const body = r.decls.map(([p, v]) => `${ind(cur.length + 1)}${p}:${sp}${v};`).join(nl);
    out += `${ind(cur.length)}${sel}${sp}{${nl}${body}${nl}${ind(cur.length)}}${nl}`;
  }
  closeTo(0);
  return out;
}
