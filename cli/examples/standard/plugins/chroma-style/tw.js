/**
 * tw() / twMerge(): une clases y resuelve conflictos — la ultima gana — sin tablas de grupos que mantener.
 *
 * Reutiliza la gramatica del generador: cada clase se traduce a las propiedades CSS que fija y dos clases
 * entran en conflicto cuando una de las posteriores cubre TODAS las propiedades de la anterior en la misma
 * variante (hover:, md:, dark:… y !important cuentan como variantes distintas):
 *
 *   twMerge("p-4 px-2")            -> "p-4 px-2"      (px solo cubre parte de p)
 *   twMerge("px-2 p-4")            -> "p-4"           (p cubre px)
 *   twMerge("text-sm leading-6")   -> "text-sm leading-6"  (leading-* fija --cs-leading, que text-* lee)
 *   twMerge("text-sm text-lg")     -> "text-lg"
 *   twMerge("bg-red-500 hover:bg-red-600 bg-primary") -> "hover:bg-red-600 bg-primary"
 *
 * Las clases que no son utilidades conocidas (nombres propios, group, data-slot…) se conservan siempre.
 */
import { resolveUtility, splitTop } from "./lib/generate.mjs";

/** Atajo -> propiedades que cubre (para decidir si una clase posterior "tapa" a otra anterior). */
const SIDES = { top: ["top"], right: ["right"], bottom: ["bottom"], left: ["left"] };
const box = (prefix, suffix = "") => ({
  [prefix + suffix]: ["top", "right", "bottom", "left"].map((s) => `${prefix}-${s}${suffix}`),
  [`${prefix}-inline${suffix}`]: [`${prefix}-left${suffix}`, `${prefix}-right${suffix}`],
  [`${prefix}-block${suffix}`]: [`${prefix}-top${suffix}`, `${prefix}-bottom${suffix}`],
  [`${prefix}-inline-start${suffix}`]: [`${prefix}-left${suffix}`],
  [`${prefix}-inline-end${suffix}`]: [`${prefix}-right${suffix}`],
  [`${prefix}-block-start${suffix}`]: [`${prefix}-top${suffix}`],
  [`${prefix}-block-end${suffix}`]: [`${prefix}-bottom${suffix}`],
});
const SHORTHAND = {
  ...box("padding"), ...box("margin"), ...box("scroll-padding"), ...box("scroll-margin"),
  ...box("border", "-width"), ...box("border", "-color"), ...box("border", "-style"),
  border: ["border-top-width", "border-right-width", "border-bottom-width", "border-left-width"],
  inset: ["top", "right", "bottom", "left"], "inset-inline": ["left", "right"], "inset-block": ["top", "bottom"],
  "inset-inline-start": ["left"], "inset-inline-end": ["right"],
  "border-radius": ["border-top-left-radius", "border-top-right-radius", "border-bottom-right-radius", "border-bottom-left-radius"],
  "border-start-start-radius": ["border-top-left-radius"], "border-start-end-radius": ["border-top-right-radius"],
  "border-end-end-radius": ["border-bottom-right-radius"], "border-end-start-radius": ["border-bottom-left-radius"],
  gap: ["row-gap", "column-gap"], overflow: ["overflow-x", "overflow-y"], flex: ["flex-grow", "flex-shrink", "flex-basis"],
  "place-items": ["align-items", "justify-items"], "place-content": ["align-content", "justify-content"], "place-self": ["align-self", "justify-self"],
  "text-decoration": ["text-decoration-line", "text-decoration-style", "text-decoration-color", "text-decoration-thickness"],
  "overscroll-behavior": ["overscroll-behavior-x", "overscroll-behavior-y"], "list-style": ["list-style-type", "list-style-position"],
  outline: ["outline-width", "outline-style", "outline-color"],
};

const cache = new Map();

/** { key, props } de una clase, o null si no es una utilidad conocida. */
function describe(cls) {
  if (cache.has(cls)) return cache.get(cls);
  let out = null;
  try {
    const parts = splitTop(cls);
    let util = parts.pop();
    let important = false;
    if (util.endsWith("!")) { important = true; util = util.slice(0, -1); } else if (util.startsWith("!")) { important = true; util = util.slice(1); }
    const res = resolveUtility(util, {});
    if (res) {
      const props = new Set();
      for (const [p] of res.decls) for (const l of SHORTHAND[p] ?? [p]) props.add(l);
      out = { key: (important ? "!" : "") + parts.join(":"), props };
    }
  } catch { out = null; }
  if (cache.size > 5000) cache.clear();
  cache.set(cls, out);
  return out;
}

const flat = (v, out = []) => {
  if (!v && v !== 0) return out;
  if (typeof v === "string" || typeof v === "number") out.push(String(v));
  else if (Array.isArray(v)) for (const x of v) flat(x, out);
  else if (typeof v === "object") for (const k of Object.keys(v)) if (v[k]) out.push(k);
  return out;
};

/** Une y resuelve conflictos. Acepta cadenas, arrays anidados y objetos { clase: condicion }. */
export function twMerge(...inputs) {
  const classes = flat(inputs).join(" ").split(/\s+/).filter(Boolean);
  const claimed = new Map(); // key de variante -> Set de propiedades ya fijadas por clases posteriores
  const keep = new Array(classes.length);
  for (let i = classes.length - 1; i >= 0; i--) {
    const d = describe(classes[i]);
    if (!d) { keep[i] = true; continue; }
    let set = claimed.get(d.key);
    if (!set) { set = new Set(); claimed.set(d.key, set); }
    let covered = d.props.size > 0;
    for (const p of d.props) if (!set.has(p)) { covered = false; break; }
    keep[i] = !covered;
    if (keep[i]) for (const p of d.props) set.add(p);
  }
  return classes.filter((_, i) => keep[i]).join(" ");
}

/** Alias corto: tw("a", cond && "b", { c: true }). */
export const tw = twMerge;

/** Variante que primero pasa por el `cx` del motor (si se proporciona). */
export function createTw(cxFn) {
  return cxFn ? (...parts) => twMerge(cxFn(...parts)) : twMerge;
}
