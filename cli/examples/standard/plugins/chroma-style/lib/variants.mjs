/**
 * Variantes: prefijos `nombre:` que envuelven una utilidad en un selector o un at-rule.
 *
 *   hover:  focus-visible:  disabled:  first:  even:  before:  placeholder:  marker:  selection:
 *   sm: md: lg: xl: 2xl:  max-md:  min-[600px]:  @sm:  motion-safe:  print:  dark:  ltr:
 *   group-hover:  group-hover/nombre:  peer-checked:  has-[...]:  not-hover:  in-data-[...]:  *:
 *   aria-expanded:  aria-[sort=ascending]:  data-[state=open]:  data-open:  supports-[...]:
 *   [&_svg]:  [&>svg:not([class*='size-'])]:  [@media(min-width:900px)]:
 *
 * Una variante recibe un contexto { sels: [plantillas con &], at: [at-rules] } y devuelve el contexto nuevo.
 * El orden de aplicacion es de izquierda a derecha; `rank` fija el orden de emision (la ultima gana en cascada).
 */
import { breakpoints, containerQueries } from "./theme.mjs";
import { normalizeArbitrary, cssEscape } from "./value.mjs";

/** Orden de emision (de menor a mayor prioridad). */
const RANK_ORDER = [
  "group", "peer", "first-letter", "first-line", "marker", "selection", "file", "placeholder", "backdrop", "before", "after",
  "first", "last", "only", "odd", "even", "first-of-type", "last-of-type", "only-of-type",
  "visited", "target", "open", "default", "checked", "indeterminate", "placeholder-shown", "autofill", "optional", "required", "valid", "invalid", "in-range", "out-of-range", "read-only", "read-write",
  "empty", "focus-within", "hover", "focus", "focus-visible", "active", "enabled", "disabled",
  "in", "has", "not", "aria", "data", "nth", "supports", "motion-safe", "motion-reduce", "contrast-more", "forced-colors",
  "max", "min", "sm", "md", "lg", "xl", "2xl", "container", "portrait", "landscape", "ltr", "rtl", "dark", "print", "starting", "custom-data", "child", "arbitrary",
];
const rankOf = (n) => { const i = RANK_ORDER.indexOf(n); return i < 0 ? RANK_ORDER.length - 1 : i; };

const PSEUDO = {
  visited: ":visited", target: ":target", default: ":default", checked: ":checked", indeterminate: ":indeterminate", "placeholder-shown": ":placeholder-shown", autofill: ":autofill",
  optional: ":optional", required: ":required", valid: ":valid", invalid: ":invalid", "in-range": ":in-range", "out-of-range": ":out-of-range", "read-only": ":read-only", "read-write": ":read-write",
  empty: ":empty", "focus-within": ":focus-within", focus: ":focus", "focus-visible": ":focus-visible", active: ":active", enabled: ":enabled", disabled: ":disabled",
  first: ":first-child", last: ":last-child", only: ":only-child", odd: ":nth-child(odd)", even: ":nth-child(even)", "first-of-type": ":first-of-type", "last-of-type": ":last-of-type", "only-of-type": ":only-of-type",
  open: ":is([open], :popover-open, :open)", hover: ":hover",
};
const ELEMENTS = {
  before: ["&::before"], after: ["&::after"], "first-letter": ["&::first-letter"], "first-line": ["&::first-line"], backdrop: ["&::backdrop"], placeholder: ["&::placeholder"], file: ["&::file-selector-button"],
  marker: ["& ::marker", "&::marker", "& ::-webkit-details-marker", "&::-webkit-details-marker"], selection: ["& ::selection", "&::selection"],
};
/** Variantes data-* con nombre (convencion shadcn/Radix/Base UI): data-open, data-closed… */
export const NAMED_DATA = {
  open: ['&:where([data-state="open"])', "&:where([data-open]:not([data-open=\"false\"]))"],
  closed: ['&:where([data-state="closed"])', "&:where([data-closed]:not([data-closed=\"false\"]))"],
  checked: ['&:where([data-state="checked"])', "&:where([data-checked]:not([data-checked=\"false\"]))"],
  unchecked: ['&:where([data-state="unchecked"])', "&:where([data-unchecked]:not([data-unchecked=\"false\"]))"],
  selected: ['&:where([data-selected="true"])'],
  disabled: ['&:where([data-disabled="true"])', "&:where([data-disabled]:not([data-disabled=\"false\"]))"],
  active: ['&:where([data-state="active"])', "&:where([data-active]:not([data-active=\"false\"]))"],
  horizontal: ['&:where([data-orientation="horizontal"])'],
  vertical: ['&:where([data-orientation="vertical"])'],
};

const MEDIA = { "motion-safe": "(prefers-reduced-motion: no-preference)", "motion-reduce": "(prefers-reduced-motion: reduce)", "contrast-more": "(prefers-contrast: more)", "forced-colors": "(forced-colors: active)", print: "print", portrait: "(orientation: portrait)", landscape: "(orientation: landscape)" };

/** Extensible: variantes propias { nombre: { rank?: string, sels?: string[], at?: string } } (build.mjs --config). */
export const customVariants = {};

const inner = (v) => (Array.isArray(v) ? v : [v]);
const stripAmp = (t) => (t.startsWith("&") ? t.slice(1) : t);
const quoteAttr = (s) => { const m = s.match(/^([^=~|^$*]+)([~|^$*]?=)(.*)$/); if (!m) return s; const val = m[3].replace(/^["']|["']$/g, ""); return `${m[1]}${m[2]}"${val}"`; };
const arbSel = (s) => {
  // `&_svg` -> `& svg`; espacia combinadores > + ~ de primer nivel
  let out = "", d = 0;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === "(" || c === "[") d++; else if (c === ")" || c === "]") d--;
    if (c === "_") out += " ";
    else if (d === 0 && (c === ">" || c === "+" || c === "~")) out += ` ${c} `;
    else out += c;
  }
  return out.replace(/ {2,}/g, " ").trim().replace(/^&\s+(?=[>+~]\s)/, "& ");
};

/** Resuelve una variante por nombre. Devuelve { rank, apply(ctx) } o null. */
export function resolveVariant(name, cfg = {}) {
  if (customVariants[name]) {
    const c = customVariants[name];
    return { rank: rankOf(c.rank ?? "arbitrary"), apply: (ctx) => ({ sels: c.sels ? ctx.sels.flatMap((s) => c.sels.map((t) => t.replace(/&/g, s))) : ctx.sels, at: c.at ? [...ctx.at, c.at] : ctx.at }) };
  }
  if (name in PSEUDO) {
    const hover = name === "hover";
    return { rank: rankOf(name), apply: (ctx) => ({ sels: ctx.sels.map((s) => s + PSEUDO[name]), at: hover ? [...ctx.at, "@media (hover: hover)"] : ctx.at }) };
  }
  if (name in ELEMENTS) {
    const content = name === "before" || name === "after";
    return { rank: rankOf(name), apply: (ctx) => ({ sels: ctx.sels.flatMap((s) => ELEMENTS[name].map((t) => t.replace("&", s))), at: ctx.at, content: ctx.content || content }) };
  }
  if (name === "dark") return { rank: rankOf("dark"), apply: (ctx) => ({ sels: ctx.sels.map((s) => `${s}:is(.dark *, [data-theme="dark"] *)`), at: ctx.at }) };
  if (name === "ltr" || name === "rtl") return { rank: rankOf(name), apply: (ctx) => ({ sels: ctx.sels.map((s) => `${s}:where(:dir(${name}), [dir="${name}"], [dir="${name}"] *)`), at: ctx.at }) };
  if (name in MEDIA) return { rank: rankOf(name), apply: (ctx) => ({ sels: ctx.sels, at: [...ctx.at, `@media ${MEDIA[name]}`] }) };
  const bp = { ...breakpoints, ...(cfg.breakpoints ?? {}) };
  if (name in bp) return { rank: rankOf(name), apply: (ctx) => ({ sels: ctx.sels, at: [...ctx.at, `@media (width >= ${bp[name]})`] }) };
  let m;
  if ((m = name.match(/^max-(.+)$/))) {
    const v = m[1] in bp ? bp[m[1]] : bracket(m[1]);
    if (v) return { rank: rankOf("max"), apply: (ctx) => ({ sels: ctx.sels, at: [...ctx.at, `@media (width < ${v})`] }) };
  }
  if ((m = name.match(/^min-(.+)$/)) && bracket(m[1])) return { rank: rankOf("min"), apply: (ctx) => ({ sels: ctx.sels, at: [...ctx.at, `@media (width >= ${bracket(m[1])})`] }) };
  if ((m = name.match(/^@(max-)?([^/]+)(?:\/(.+))?$/))) {
    const v = m[2] in containerQueries ? containerQueries[m[2]] : bracket(m[2]);
    if (v) return { rank: rankOf("container"), apply: (ctx) => ({ sels: ctx.sels, at: [...ctx.at, `@container ${m[3] ? m[3] + " " : ""}(width ${m[1] ? "<" : ">="} ${v})`] }) };
  }
  if (name === "*") return { rank: rankOf("child"), apply: (ctx) => ({ sels: ctx.sels.map((s) => `:is(${s} > *)`), at: ctx.at }) };
  if (name === "**") return { rank: rankOf("child"), apply: (ctx) => ({ sels: ctx.sels.map((s) => `:is(${s} *)`), at: ctx.at }) };
  if ((m = name.match(/^supports-(.+)$/))) {
    const b = bracket(m[1]); const cond = b ?? `${m[1]}: initial`;
    return { rank: rankOf("supports"), apply: (ctx) => ({ sels: ctx.sels, at: [...ctx.at, `@supports (${/[:()]/.test(cond) ? cond : cond + ": initial"})`] }) };
  }
  if ((m = name.match(/^(group|peer)-(.+)$/))) {
    const [innerName, gname] = splitSlash(m[2]);
    const iv = resolveVariant(innerName, cfg);
    if (iv) {
      const kind = m[1]; const cls = `.${kind}${gname ? "\\/" + cssEscape(gname) : ""}`;
      return { rank: rankOf(kind), apply: (ctx) => {
        const probe = iv.apply({ sels: ["&"], at: [] });
        const tpls = probe.sels.map((t) => stripAmp(t));
        const rel = kind === "group" ? " " : " ~ ";
        return { sels: ctx.sels.flatMap((s) => tpls.map((t) => `${s}:is(:where(${cls})${t}${rel}*)`)), at: [...ctx.at, ...probe.at] };
      } };
    }
  }
  if ((m = name.match(/^(has|not|in)-(.+)$/))) {
    const kind = m[1];
    let iv = null, rawSel = null;
    const b = bracket(m[2]);
    if (b != null) rawSel = "&" + (b.startsWith("&") ? b.slice(1) : b);
    else iv = resolveVariant(m[2], cfg);
    if (rawSel || iv) {
      return { rank: rankOf(kind), apply: (ctx) => {
        const probe = rawSel ? { sels: [arbSel(rawSel)], at: [] } : iv.apply({ sels: ["&"], at: [] });
        const body = probe.sels.map(stripAmp).join(", ");
        if (kind === "has") return { sels: ctx.sels.map((s) => `${s}:has(${body})`), at: [...ctx.at, ...probe.at] };
        if (kind === "not") return { sels: ctx.sels.map((s) => `${s}:not(${body})`), at: [...ctx.at, ...probe.at] };
        return { sels: ctx.sels.map((s) => `:where(${body}) ${s}`), at: ctx.at };
      } };
    }
  }
  if ((m = name.match(/^aria-(.+)$/))) {
    const b = bracket(m[1]);
    const sel = b != null ? `[aria-${quoteAttr(b)}]` : `[aria-${m[1]}="true"]`;
    return { rank: rankOf("aria"), apply: (ctx) => ({ sels: ctx.sels.map((s) => s + sel), at: ctx.at }) };
  }
  if ((m = name.match(/^data-(.+)$/))) {
    const b = bracket(m[1]);
    if (b != null) return { rank: rankOf("data"), apply: (ctx) => ({ sels: ctx.sels.map((s) => `${s}[data-${quoteAttr(b)}]`), at: ctx.at }) };
    if (m[1] in NAMED_DATA) return { rank: rankOf("custom-data"), apply: (ctx) => ({ sels: ctx.sels.flatMap((s) => NAMED_DATA[m[1]].map((t) => t.replace("&", s))), at: ctx.at }) };
    return { rank: rankOf("data"), apply: (ctx) => ({ sels: ctx.sels.map((s) => `${s}[data-${m[1]}]`), at: ctx.at }) };
  }
  if ((m = name.match(/^nth-(.+)$/))) {
    const v = bracket(m[1]) ?? m[1];
    return { rank: rankOf("nth"), apply: (ctx) => ({ sels: ctx.sels.map((s) => `${s}:nth-child(${v})`), at: ctx.at }) };
  }
  if (name.startsWith("[") && name.endsWith("]")) {
    const body = name.slice(1, -1);
    if (body.startsWith("@")) { const at = "@" + arbSel(body.slice(1).replace(/^(\w+)\(/, "$1 (")); return { rank: rankOf("arbitrary"), apply: (ctx) => ({ sels: ctx.sels, at: [...ctx.at, at] }) }; }
    const sel = arbSel(body);
    return { rank: rankOf("arbitrary"), apply: (ctx) => ({ sels: ctx.sels.map((s) => (sel.includes("&") ? sel.replace(/&/g, s) : `${s} ${sel}`)), at: ctx.at }) };
  }
  return null;
}

function bracket(s) { return s.startsWith("[") && s.endsWith("]") ? normalizeArbitrary(s.slice(1, -1)) : s.startsWith("(") && s.endsWith(")") ? `var(${s.slice(1, -1)})` : null; }
function splitSlash(s) { let d = 0, idx = -1; for (let i = 0; i < s.length; i++) { if (s[i] === "[" || s[i] === "(") d++; else if (s[i] === "]" || s[i] === ")") d--; else if (s[i] === "/" && d === 0) idx = i; } return idx < 0 ? [s, null] : [s.slice(0, idx), s.slice(idx + 1)]; }

export { rankOf, RANK_ORDER };
