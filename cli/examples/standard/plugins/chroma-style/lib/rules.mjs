/**
 * Registro de utilidades de @chroma/style.
 *
 * Cada entrada declara las "raices" que reconoce (el nombre antes del valor: `mt`, `grid-cols`, `bg`…) y una
 * funcion `fn(rest, ctx)` que devuelve las declaraciones CSS `[[prop, valor], …]` o `null` si no entiende el valor.
 * El ORDEN del registro es el orden en que se emiten las utilidades (los atajos antes que las propiedades
 * largas: p antes de px antes de pt), asi la ultima clase del mismo grupo gana igual que en un CSS escrito a mano.
 *
 * Gramatica (resumen): <raiz>-<valor>[/<modificador>] con valor = token de escala | numero | fraccion |
 * [valor arbitrario] | (--variable). Prefijo `-` = negativo. Sufijo/prefijo `!` = !important.
 * Para anadir utilidades propias: `registerUtility(roots, fn)` (ver build.mjs --config).
 */
import {
  spacingVar, containers, textSizes, fontWeights, tracking, leadings, radii, shadows, insetShadows,
  blurs, eases, aspects, animations, enterExitAnimation, breakpoints,
} from "./theme.mjs";
import { parseArb, guessType, isNumber, spacing, color, splitModifier, normalizeArbitrary } from "./value.mjs";

/** @type {{roots:string[], fn:Function, order:number}[]} */
export const registry = [];
/** raiz -> entradas */
export const byRoot = new Map();

export function registerUtility(roots, fn, { first = false } = {}) {
  const entry = { roots: [].concat(roots), fn, order: first ? -registry.length - 1 : registry.length };
  registry.push(entry);
  for (const r of entry.roots) { if (!byRoot.has(r)) byRoot.set(r, []); byRoot.get(r).push(entry); }
  return entry;
}
const add = registerUtility;

/** Utilidades estaticas: nombre -> declaraciones. */
function statics(map) {
  for (const [name, decls] of Object.entries(map)) add(name, (rest) => (rest === "" ? decls : null));
}
const D = (s) => s.split(";").map((x) => x.trim()).filter(Boolean).map((x) => { const i = x.indexOf(":"); return [x.slice(0, i).trim(), x.slice(i + 1).trim()]; });
const S = (obj) => statics(Object.fromEntries(Object.entries(obj).map(([k, v]) => [k, typeof v === "string" ? D(v) : v])));

const P = (...props) => (v) => props.map((p) => [p, v]);
const SIDE = { "": ["%"], x: ["inline"], y: ["block"], s: ["inline-start"], e: ["inline-end"], t: ["top"], r: ["right"], b: ["bottom"], l: ["left"] };

/** Familia de escala de espaciado: roots -> propiedades. */
function spacingFamily(root, propsOf, extras = {}) {
  add(root, (rest, ctx) => {
    const v = spacing(rest, ctx.neg, extras);
    return v == null ? null : propsOf(v).map(([p, val]) => [p, val]);
  });
}

// ---------------------------------------------------------------------------------------------------
// 1. Contenedores, interaccion basica, visibilidad, posicion
// ---------------------------------------------------------------------------------------------------
S({
  "@container": "container-type: inline-size", "@container-size": "container-type: size", "@container-normal": "container-type: normal",
  "pointer-events-auto": "pointer-events: auto", "pointer-events-none": "pointer-events: none",
  collapse: "visibility: collapse", invisible: "visibility: hidden", visible: "visibility: visible",
  "sr-only": "position: absolute; width: 1px; height: 1px; padding: 0; margin: -1px; overflow: hidden; clip-path: inset(50%); white-space: nowrap; border-width: 0",
  "not-sr-only": "position: static; width: auto; height: auto; padding: 0; margin: 0; overflow: visible; clip-path: none; white-space: normal",
  absolute: "position: absolute", fixed: "position: fixed", relative: "position: relative", static: "position: static", sticky: "position: sticky",
});
add("@container", (rest) => { const a = parseArb(rest); return a ? [["container-type", "inline-size"], ["container-name", a.value]] : rest ? [["container-type", "inline-size"], ["container-name", rest]] : null; });

// inset
const insetExtras = { auto: "auto", full: "100%", px: "1px" };
spacingFamily("inset", (v) => [["inset", v]], insetExtras);
spacingFamily("inset-x", (v) => [["inset-inline", v]], insetExtras);
spacingFamily("inset-y", (v) => [["inset-block", v]], insetExtras);
for (const [r, p] of [["start", "inset-inline-start"], ["end", "inset-inline-end"], ["top", "top"], ["right", "right"], ["bottom", "bottom"], ["left", "left"]]) spacingFamily(r, (v) => [[p, v]], insetExtras);
S({ isolate: "isolation: isolate", "isolation-auto": "isolation: auto" });
add("z", (rest, ctx) => { if (rest === "auto") return [["z-index", "auto"]]; if (isNumber(rest)) return [["z-index", ctx.neg ? `calc(${rest} * -1)` : rest]]; const a = parseArb(rest); return a ? [["z-index", a.value]] : null; });
add("order", (rest, ctx) => {
  if (rest === "none") return [["order", "0"]]; if (rest === "first") return [["order", "-9999"]]; if (rest === "last") return [["order", "9999"]];
  if (isNumber(rest)) return [["order", ctx.neg ? `calc(${rest} * -1)` : rest]]; const a = parseArb(rest); return a ? [["order", a.value]] : null;
});

// grid placement
function gridSpan(prop, root) {
  add(root, (rest) => {
    let m;
    if ((m = rest.match(/^span-(\d+)$/))) return [[prop, `span ${m[1]} / span ${m[1]}`]];
    if (rest === "span-full") return [[prop, "1 / -1"]];
    if ((m = rest.match(/^span-(.+)$/)) && parseArb(m[1])) return [[prop, `span ${parseArb(m[1]).value} / span ${parseArb(m[1]).value}`]];
    return null;
  });
}
gridSpan("grid-column", "col"); gridSpan("grid-row", "row");
for (const [root, prop] of [["col-start", "grid-column-start"], ["col-end", "grid-column-end"], ["row-start", "grid-row-start"], ["row-end", "grid-row-end"]]) {
  add(root, (rest, ctx) => rest === "auto" ? [[prop, "auto"]] : isNumber(rest) ? [[prop, ctx.neg ? `calc(${rest} * -1)` : rest]] : parseArb(rest) ? [[prop, parseArb(rest).value]] : null);
}
add("col", (rest) => rest === "auto" ? [["grid-column", "auto"]] : parseArb(rest) ? [["grid-column", parseArb(rest).value]] : null);
add("row", (rest) => rest === "auto" ? [["grid-row", "auto"]] : parseArb(rest) ? [["grid-row", parseArb(rest).value]] : null);
S({ "float-start": "float: inline-start", "float-end": "float: inline-end", "float-right": "float: right", "float-left": "float: left", "float-none": "float: none",
  "clear-start": "clear: inline-start", "clear-end": "clear: inline-end", "clear-right": "clear: right", "clear-left": "clear: left", "clear-both": "clear: both", "clear-none": "clear: none" });

// container: ancho completo + max-width por breakpoint (las reglas por breakpoint las emite generate.mjs)
add("container", (rest) => (rest === "" ? [["width", "100%"]] : null)).container = true;

// margin
const marginExtras = { auto: "auto", px: "1px" };
spacingFamily("m", (v) => [["margin", v]], marginExtras);
spacingFamily("mx", (v) => [["margin-inline", v]], marginExtras);
spacingFamily("my", (v) => [["margin-block", v]], marginExtras);
spacingFamily("ms", (v) => [["margin-inline-start", v]], marginExtras);
spacingFamily("me", (v) => [["margin-inline-end", v]], marginExtras);
spacingFamily("mt", (v) => [["margin-top", v]], marginExtras);
spacingFamily("mr", (v) => [["margin-right", v]], marginExtras);
spacingFamily("mb", (v) => [["margin-bottom", v]], marginExtras);
spacingFamily("ml", (v) => [["margin-left", v]], marginExtras);

S({ "box-border": "box-sizing: border-box", "box-content": "box-sizing: content-box" });
add("line-clamp", (rest) => {
  if (rest === "none") return [["overflow", "visible"], ["display", "block"], ["-webkit-box-orient", "horizontal"], ["-webkit-line-clamp", "unset"]];
  const v = isNumber(rest) ? rest : parseArb(rest)?.value; return v ? [["overflow", "hidden"], ["display", "-webkit-box"], ["-webkit-box-orient", "vertical"], ["-webkit-line-clamp", v]] : null;
});
S({ block: "display: block", contents: "display: contents", flex: "display: flex", "flow-root": "display: flow-root", grid: "display: grid", hidden: "display: none",
  inline: "display: inline", "inline-block": "display: inline-block", "inline-flex": "display: inline-flex", "inline-grid": "display: inline-grid", "inline-table": "display: inline-table",
  "list-item": "display: list-item", table: "display: table", "table-caption": "display: table-caption", "table-cell": "display: table-cell", "table-column": "display: table-column",
  "table-column-group": "display: table-column-group", "table-footer-group": "display: table-footer-group", "table-header-group": "display: table-header-group",
  "table-row": "display: table-row", "table-row-group": "display: table-row-group", "field-sizing-content": "field-sizing: content", "field-sizing-fixed": "field-sizing: fixed" });
add("aspect", (rest) => { if (rest in aspects) return [["aspect-ratio", aspects[rest]]]; const a = parseArb(rest); if (a) return [["aspect-ratio", a.value]]; const m = rest.match(/^(\d+)\/(\d+)$/); return m ? [["aspect-ratio", `${m[1]} / ${m[2]}`]] : null; });

// tamaños
const sizeWord = (axis) => ({ auto: "auto", full: "100%", px: "1px", screen: axis === "h" ? "100vh" : "100vw", min: "min-content", max: "max-content", fit: "fit-content",
  svw: "100svw", lvw: "100lvw", dvw: "100dvw", svh: "100svh", lvh: "100lvh", dvh: "100dvh", lh: "1lh" });
function sizeFamily(root, props, axis, { containerNames = false, none = false } = {}) {
  add(root, (rest, ctx) => {
    const ex = sizeWord(axis);
    if (none && rest === "none") return props.map((p) => [p, "none"]);
    if (rest === "lh" && root.startsWith("m")) return props.map((p) => [p, "1lh"]);
    if (containerNames && rest in containers) return props.map((p) => [p, `var(--container-${rest})`]);
    if (containerNames && rest === "screen") return props.map((p) => [p, "100vw"]);
    const v = spacing(rest, ctx.neg, ex);
    if (v == null) return null;
    return props.map((p) => [p, v]);
  });
}
sizeFamily("size", ["width", "height"], "w");
sizeFamily("h", ["height"], "h");
sizeFamily("max-h", ["max-height"], "h", { none: true });
sizeFamily("min-h", ["min-height"], "h");
sizeFamily("w", ["width"], "w");
sizeFamily("max-w", ["max-width"], "w", { containerNames: true, none: true });
sizeFamily("min-w", ["min-width"], "w");
sizeFamily("block", ["block-size"], "h"); sizeFamily("inline", ["inline-size"], "w");

// flex item
add("flex", (rest) => {
  const map = { "1": "1", auto: "auto", initial: "0 auto", none: "none" };
  if (rest in map) return [["flex", map[rest]]];
  if (isNumber(rest)) return [["flex", rest]];
  const a = parseArb(rest); return a ? [["flex", a.value]] : null;
});
add("flex-shrink", (rest) => rest === "" ? [["flex-shrink", "1"]] : isNumber(rest) ? [["flex-shrink", rest]] : null);
add("shrink", (rest) => rest === "" ? [["flex-shrink", "1"]] : isNumber(rest) ? [["flex-shrink", rest]] : parseArb(rest) ? [["flex-shrink", parseArb(rest).value]] : null);
add("flex-grow", (rest) => rest === "" ? [["flex-grow", "1"]] : isNumber(rest) ? [["flex-grow", rest]] : null);
add("grow", (rest) => rest === "" ? [["flex-grow", "1"]] : isNumber(rest) ? [["flex-grow", rest]] : parseArb(rest) ? [["flex-grow", parseArb(rest).value]] : null);
add("basis", (rest, ctx) => { if (rest in containers) return [["flex-basis", `var(--container-${rest})`]]; const v = spacing(rest, ctx.neg, { auto: "auto", full: "100%", px: "1px" }); return v == null ? null : [["flex-basis", v]]; });
S({ "table-auto": "table-layout: auto", "table-fixed": "table-layout: fixed", "caption-top": "caption-side: top", "caption-bottom": "caption-side: bottom",
  "border-collapse": "border-collapse: collapse", "border-separate": "border-collapse: separate" });
add("origin", (rest) => {
  const m = { center: "center", top: "top", "top-right": "100% 0", right: "100%", "bottom-right": "100% 100%", bottom: "bottom", "bottom-left": "0 100%", left: "0", "top-left": "0 0" };
  if (rest in m) return [["transform-origin", m[rest]]]; const a = parseArb(rest); return a ? [["transform-origin", a.value]] : null;
});

// transformaciones (propiedades individuales translate/scale/rotate + vars --cs-*)
function translateAxis(axis) {
  return (rest, ctx) => {
    const v = spacing(rest, ctx.neg, { full: "100%", px: "1px" });
    if (v == null) return null; ctx.uses.add("transform");
    const decls = axis === "xy" ? [["--cs-translate-x", v], ["--cs-translate-y", v]] : [[`--cs-translate-${axis}`, v]];
    return [...decls, ["translate", axis === "z" ? "var(--cs-translate-x) var(--cs-translate-y) var(--cs-translate-z)" : "var(--cs-translate-x) var(--cs-translate-y)"]];
  };
}
add("translate", (rest, ctx) => rest === "none" ? [["translate", "none"]] : translateAxis("xy")(rest, ctx));
add("translate-x", translateAxis("x")); add("translate-y", translateAxis("y")); add("translate-z", translateAxis("z"));
function scaleValue(rest, neg) {
  if (isNumber(rest)) return `${neg ? "-" : ""}${rest}%`;
  const a = parseArb(rest); return a ? a.value : null;
}
add("scale", (rest, ctx) => {
  if (rest === "none") return [["scale", "none"]];
  const a = parseArb(rest); if (a) return [["scale", a.value]];
  const v = scaleValue(rest, ctx.neg); if (v == null) return null; ctx.uses.add("transform");
  return [["--cs-scale-x", v], ["--cs-scale-y", v], ["--cs-scale-z", v], ["scale", "var(--cs-scale-x) var(--cs-scale-y)"]];
});
for (const ax of ["x", "y"]) add(`scale-${ax}`, (rest, ctx) => { const v = scaleValue(rest, ctx.neg); if (v == null) return null; ctx.uses.add("transform"); return [[`--cs-scale-${ax}`, v], ["scale", "var(--cs-scale-x) var(--cs-scale-y)"]]; });
add("rotate", (rest, ctx) => { if (rest === "none") return [["rotate", "none"]]; if (isNumber(rest)) return [["rotate", `${ctx.neg ? "-" : ""}${rest}deg`]]; const a = parseArb(rest); return a ? [["rotate", ctx.neg ? `calc(${a.value} * -1)` : a.value]] : null; });
for (const ax of ["x", "y"]) add(`skew-${ax}`, (rest, ctx) => { const v = isNumber(rest) ? `${ctx.neg ? "-" : ""}${rest}deg` : parseArb(rest)?.value; if (!v) return null; ctx.uses.add("transform"); return [[`--cs-skew-${ax}`, `skew${ax.toUpperCase()}(${v})`], ["transform", "var(--cs-rotate-x, ) var(--cs-rotate-y, ) var(--cs-rotate-z, ) var(--cs-skew-x, ) var(--cs-skew-y, )"]]; });
const TF = "var(--cs-rotate-x, ) var(--cs-rotate-y, ) var(--cs-rotate-z, ) var(--cs-skew-x, ) var(--cs-skew-y, )";
S({ transform: [["transform", TF]], "transform-cpu": [["transform", TF]], "transform-gpu": [["transform", `translateZ(0) ${TF}`]], "transform-none": "transform: none",
  "transform-3d": "transform-style: preserve-3d", "transform-flat": "transform-style: flat", "backface-hidden": "backface-visibility: hidden", "backface-visible": "backface-visibility: visible" });

// animaciones
add("animate", (rest, ctx) => {
  if (rest in animations) { ctx.animation = animations[rest].split(" ")[0]; return [["animation", animations[rest]]]; }
  if (rest === "in") { ctx.animation = "enter"; ctx.uses.add("animate"); return [["animation", enterExitAnimation("enter")]]; }
  if (rest === "out") { ctx.animation = "exit"; ctx.uses.add("animate"); return [["animation", enterExitAnimation("exit")]]; }
  const a = parseArb(rest); return a ? [["animation", a.value]] : null;
});
S({ "cursor-auto": "cursor: auto", "cursor-default": "cursor: default", "cursor-pointer": "cursor: pointer", "cursor-wait": "cursor: wait", "cursor-text": "cursor: text", "cursor-move": "cursor: move",
  "cursor-help": "cursor: help", "cursor-not-allowed": "cursor: not-allowed", "cursor-none": "cursor: none", "cursor-grab": "cursor: grab", "cursor-grabbing": "cursor: grabbing", "cursor-crosshair": "cursor: crosshair",
  "touch-auto": "touch-action: auto", "touch-none": "touch-action: none", "touch-manipulation": "touch-action: manipulation", "touch-pan-x": "touch-action: pan-x", "touch-pan-y": "touch-action: pan-y",
  resize: "resize: both", "resize-none": "resize: none", "resize-x": "resize: horizontal", "resize-y": "resize: vertical" });
// snap
S({ "snap-none": "scroll-snap-type: none", "snap-x": "scroll-snap-type: x var(--cs-scroll-snap-strictness)", "snap-y": "scroll-snap-type: y var(--cs-scroll-snap-strictness)", "snap-both": "scroll-snap-type: both var(--cs-scroll-snap-strictness)",
  "snap-mandatory": "--cs-scroll-snap-strictness: mandatory", "snap-proximity": "--cs-scroll-snap-strictness: proximity",
  "snap-align-none": "scroll-snap-align: none", "snap-start": "scroll-snap-align: start", "snap-end": "scroll-snap-align: end", "snap-center": "scroll-snap-align: center",
  "snap-normal": "scroll-snap-stop: normal", "snap-always": "scroll-snap-stop: always" });
for (const [root, prop] of [["scroll-m", "scroll-margin"], ["scroll-mx", "scroll-margin-inline"], ["scroll-my", "scroll-margin-block"], ["scroll-mt", "scroll-margin-top"], ["scroll-mr", "scroll-margin-right"], ["scroll-mb", "scroll-margin-bottom"], ["scroll-ml", "scroll-margin-left"],
  ["scroll-p", "scroll-padding"], ["scroll-px", "scroll-padding-inline"], ["scroll-py", "scroll-padding-block"], ["scroll-pt", "scroll-padding-top"], ["scroll-pr", "scroll-padding-right"], ["scroll-pb", "scroll-padding-bottom"], ["scroll-pl", "scroll-padding-left"]]) spacingFamily(root, (v) => [[prop, v]], { auto: "auto", px: "1px" });
S({ "list-inside": "list-style-position: inside", "list-outside": "list-style-position: outside", "list-none": "list-style-type: none", "list-disc": "list-style-type: disc", "list-decimal": "list-style-type: decimal",
  "appearance-none": "appearance: none", "appearance-auto": "appearance: auto" });
add("columns", (rest) => isNumber(rest) ? [["columns", rest]] : rest in containers ? [["columns", `var(--container-${rest})`]] : parseArb(rest) ? [["columns", parseArb(rest).value]] : null);

// grid / flex contenedor
const tracks = (prop) => (rest) => {
  if (rest === "none") return [[prop, "none"]]; if (rest === "subgrid") return [[prop, "subgrid"]];
  if (/^\d+$/.test(rest)) return [[prop, `repeat(${rest}, minmax(0, 1fr))`]];
  const a = parseArb(rest); return a ? [[prop, a.value]] : null;
};
add("grid-cols", tracks("grid-template-columns")); add("grid-rows", tracks("grid-template-rows"));
S({ "grid-flow-row": "grid-auto-flow: row", "grid-flow-col": "grid-auto-flow: column", "grid-flow-dense": "grid-auto-flow: dense", "grid-flow-row-dense": "grid-auto-flow: row dense", "grid-flow-col-dense": "grid-auto-flow: column dense" });
const autoTrack = (prop) => (rest) => { const m = { auto: "auto", min: "min-content", max: "max-content", fr: "minmax(0, 1fr)" }; if (rest in m) return [[prop, m[rest]]]; const a = parseArb(rest); return a ? [[prop, a.value]] : null; };
add("auto-cols", autoTrack("grid-auto-columns")); add("auto-rows", autoTrack("grid-auto-rows"));
S({ "flex-row": "flex-direction: row", "flex-row-reverse": "flex-direction: row-reverse", "flex-col": "flex-direction: column", "flex-col-reverse": "flex-direction: column-reverse",
  "flex-wrap": "flex-wrap: wrap", "flex-nowrap": "flex-wrap: nowrap", "flex-wrap-reverse": "flex-wrap: wrap-reverse" });
for (const [k, v] of Object.entries({ around: "space-around", baseline: "baseline", between: "space-between", center: "center", end: "end", evenly: "space-evenly", start: "start", stretch: "stretch", "center-safe": "safe center", "end-safe": "safe end" })) statics({ [`place-content-${k}`]: [["place-content", v]] });
for (const [k, v] of Object.entries({ start: "flex-start", end: "flex-end", center: "center", between: "space-between", around: "space-around", evenly: "space-evenly", stretch: "stretch", baseline: "baseline", normal: "normal", "center-safe": "safe center", "end-safe": "safe flex-end" })) statics({ [`content-${k}`]: [["align-content", v]] });
for (const [k, v] of Object.entries({ start: "flex-start", end: "flex-end", center: "center", baseline: "baseline", stretch: "stretch", "center-safe": "safe center", "end-safe": "safe flex-end", "baseline-last": "last baseline" })) statics({ [`items-${k}`]: [["align-items", v]] });
for (const [k, v] of Object.entries({ start: "flex-start", end: "flex-end", center: "center", between: "space-between", around: "space-around", evenly: "space-evenly", stretch: "stretch", baseline: "baseline", normal: "normal", "center-safe": "safe center", "end-safe": "safe flex-end" })) statics({ [`justify-${k}`]: [["justify-content", v]] });
for (const [k, v] of Object.entries({ start: "start", end: "end", center: "center", stretch: "stretch", normal: "normal", "center-safe": "safe center", "end-safe": "safe end" })) statics({ [`justify-items-${k}`]: [["justify-items", v]] });
for (const [k, v] of Object.entries({ start: "start", end: "end", center: "center", stretch: "stretch", baseline: "baseline" })) statics({ [`place-items-${k}`]: [["place-items", v]] });
// gap + space
spacingFamily("gap", (v) => [["gap", v]], { px: "1px" });
spacingFamily("gap-x", (v) => [["column-gap", v]], { px: "1px" });
spacingFamily("gap-y", (v) => [["row-gap", v]], { px: "1px" });
function spaceBetween(axis) {
  const [p0, p1] = axis === "y" ? ["margin-block-start", "margin-block-end"] : ["margin-inline-start", "margin-inline-end"];
  return (rest, ctx) => {
    if (rest === "reverse") return Object.assign([[`--cs-space-${axis}-reverse`, "1"]], { childSel: true });
    const v = spacing(rest, ctx.neg, { px: "1px" }); if (v == null) return null;
    return Object.assign([[`--cs-space-${axis}-reverse`, "0"], [p0, `calc(${v} * var(--cs-space-${axis}-reverse))`], [p1, `calc(${v} * calc(1 - var(--cs-space-${axis}-reverse)))`]], { childSel: true });
  };
}
add("space-y", spaceBetween("y")); add("space-x", spaceBetween("x"));
function divide(axis) {
  return (rest) => {
    if (rest === "reverse") return Object.assign([[`--cs-divide-${axis}-reverse`, "1"]], { childSel: true });
    const w = rest === "" ? "1px" : isNumber(rest) ? `${rest}px` : null; if (w == null) return null;
    const [a, b] = axis === "y" ? ["border-top-width", "border-bottom-width"] : ["border-inline-start-width", "border-inline-end-width"];
    return Object.assign([[`--cs-divide-${axis}-reverse`, "0"], [a, `calc(${w} * var(--cs-divide-${axis}-reverse))`], [b, `calc(${w} * calc(1 - var(--cs-divide-${axis}-reverse)))`]], { childSel: true });
  };
}
add("divide-x", divide("x")); add("divide-y", divide("y"));
for (const [k, v] of Object.entries({ auto: "auto", start: "start", end: "end", center: "center", stretch: "stretch", "center-safe": "safe center", "end-safe": "safe end" })) statics({ [`place-self-${k}`]: [["place-self", v]] });
for (const [k, v] of Object.entries({ auto: "auto", start: "flex-start", end: "flex-end", center: "center", stretch: "stretch", baseline: "baseline", "baseline-last": "last baseline", "center-safe": "safe center", "end-safe": "safe flex-end" })) statics({ [`self-${k}`]: [["align-self", v]] });
for (const [k, v] of Object.entries({ auto: "auto", start: "flex-start", end: "flex-end", center: "center", stretch: "stretch", "center-safe": "safe center", "end-safe": "safe flex-end" })) statics({ [`justify-self-${k}`]: [["justify-self", v]] });
S({ truncate: "overflow: hidden; text-overflow: ellipsis; white-space: nowrap",
  "overflow-auto": "overflow: auto", "overflow-hidden": "overflow: hidden", "overflow-clip": "overflow: clip", "overflow-visible": "overflow: visible", "overflow-scroll": "overflow: scroll",
  "overflow-x-auto": "overflow-x: auto", "overflow-x-hidden": "overflow-x: hidden", "overflow-x-clip": "overflow-x: clip", "overflow-x-visible": "overflow-x: visible", "overflow-x-scroll": "overflow-x: scroll",
  "overflow-y-auto": "overflow-y: auto", "overflow-y-hidden": "overflow-y: hidden", "overflow-y-clip": "overflow-y: clip", "overflow-y-visible": "overflow-y: visible", "overflow-y-scroll": "overflow-y: scroll",
  "overscroll-auto": "overscroll-behavior: auto", "overscroll-contain": "overscroll-behavior: contain", "overscroll-none": "overscroll-behavior: none",
  "overscroll-x-contain": "overscroll-behavior-x: contain", "overscroll-y-contain": "overscroll-behavior-y: contain", "overscroll-x-none": "overscroll-behavior-x: none", "overscroll-y-none": "overscroll-behavior-y: none",
  "scroll-auto": "scroll-behavior: auto", "scroll-smooth": "scroll-behavior: smooth", "no-scrollbar": "-ms-overflow-style: none; scrollbar-width: none" });

// ---------------------------------------------------------------------------------------------------
// 2. Bordes, radios, colores de fondo, degradados, mascaras
// ---------------------------------------------------------------------------------------------------
const radiusValue = (rest) => {
  if (rest === "none") return "0px"; if (rest === "full") return "calc(infinity * 1px)";
  if (rest === "") return "0.25rem";
  if (radii.includes(rest)) return `var(--radius-${rest})`;
  const a = parseArb(rest); return a ? a.value : null;
};
const corners = { "": ["border-radius"], s: ["border-start-start-radius", "border-end-start-radius"], e: ["border-start-end-radius", "border-end-end-radius"], t: ["border-top-left-radius", "border-top-right-radius"],
  r: ["border-top-right-radius", "border-bottom-right-radius"], b: ["border-bottom-right-radius", "border-bottom-left-radius"], l: ["border-top-left-radius", "border-bottom-left-radius"],
  ss: ["border-start-start-radius"], se: ["border-start-end-radius"], ee: ["border-end-end-radius"], es: ["border-end-start-radius"], tl: ["border-top-left-radius"], tr: ["border-top-right-radius"], br: ["border-bottom-right-radius"], bl: ["border-bottom-left-radius"] };
for (const [side, props] of Object.entries(corners)) add(side === "" ? "rounded" : `rounded-${side}`, (rest) => { const v = radiusValue(rest); return v == null ? null : props.map((p) => [p, v]); });

const borderWidth = (rest) => { if (rest === "") return "1px"; if (isNumber(rest)) return `${rest}px`; const a = parseArb(rest); if (a && (a.type === "length" || a.type === "line-width" || (!a.type && guessType(a.value) === "length"))) return a.value; return null; };
const bSides = { "": ["border-width"], x: ["border-inline-width"], y: ["border-block-width"], s: ["border-inline-start-width"], e: ["border-inline-end-width"], bs: ["border-block-start-width"], be: ["border-block-end-width"], t: ["border-top-width"], r: ["border-right-width"], b: ["border-bottom-width"], l: ["border-left-width"] };
for (const [side, props] of Object.entries(bSides)) add(side === "" ? "border" : `border-${side}`, (rest) => { const v = borderWidth(rest); return v == null ? null : props.map((p) => [p, v]); });
S({ "border-solid": "border-style: solid", "border-dashed": "border-style: dashed", "border-dotted": "border-style: dotted", "border-double": "border-style: double", "border-hidden": "border-style: hidden", "border-none": "border-style: none" });
// color de borde
const bColorProps = { "": ["border-color"], x: ["border-inline-color"], y: ["border-block-color"], s: ["border-inline-start-color"], e: ["border-inline-end-color"], t: ["border-top-color"], r: ["border-right-color"], b: ["border-bottom-color"], l: ["border-left-color"] };
for (const [side, props] of Object.entries(bColorProps)) add(side === "" ? "border" : `border-${side}`, (rest, ctx) => { const c = color(rest, ctx); return c == null ? null : props.map((p) => [p, c]); });

// fondo: color
add("bg", (rest, ctx) => {
  const a = parseArb(rest.split("/")[0] === rest ? rest : rest);
  if (a && a.type && a.type !== "color") return null;
  const c = color(rest, ctx); return c == null ? null : [["background-color", c]];
});
// degradados lineales/radiales/conicos
const DIRS = { t: "to top", tr: "to top right", r: "to right", br: "to bottom right", b: "to bottom", bl: "to bottom left", l: "to left", tl: "to top left" };
const GSTOPS = "var(--cs-gradient-via-stops, var(--cs-gradient-position), var(--cs-gradient-from) var(--cs-gradient-from-position), var(--cs-gradient-to) var(--cs-gradient-to-position))";
function gradient(fnName, dirOf) {
  return (rest, ctx) => {
    const pos = dirOf(rest, ctx); if (pos == null) return null;
    ctx.uses.add("gradient");
    return [["--cs-gradient-position", pos], ["background-image", `${fnName}(var(--cs-gradient-stops))`]];
  };
}
const linearDir = (compat) => (rest, ctx) => {
  if (rest in DIRS) return `${DIRS[rest]} in oklab`;
  if (isNumber(rest)) return `${ctx.neg ? "-" : ""}${rest}deg in oklab`;
  const a = parseArb(rest); return a ? a.value : null;
};
add("bg-linear-to", gradient("linear-gradient", (r, c) => (r in DIRS ? `${DIRS[r]} in oklab` : null)));
add("bg-linear", gradient("linear-gradient", (r, c) => linearDir()(r, c)));
add("bg-gradient-to", gradient("linear-gradient", (r) => (r in DIRS ? `${DIRS[r]} in oklab` : null)));
add("bg-radial", (rest, ctx) => { ctx.uses.add("gradient"); if (rest === "") return [["--cs-gradient-position", "in oklab"], ["background-image", "radial-gradient(var(--cs-gradient-stops))"]]; const a = parseArb(rest); return a ? [["--cs-gradient-position", a.value], ["background-image", "radial-gradient(var(--cs-gradient-stops))"]] : null; });
add("bg-conic", (rest, ctx) => { ctx.uses.add("gradient"); if (rest === "") return [["--cs-gradient-position", "from 0deg in oklab"], ["background-image", "conic-gradient(var(--cs-gradient-stops))"]]; if (isNumber(rest)) return [["--cs-gradient-position", `from ${ctx.neg ? "-" : ""}${rest}deg in oklab`], ["background-image", "conic-gradient(var(--cs-gradient-stops))"]]; const a = parseArb(rest); return a ? [["--cs-gradient-position", a.value], ["background-image", "conic-gradient(var(--cs-gradient-stops))"]] : null; });
for (const [stop, hasVia] of [["from", false], ["via", true], ["to", false]]) {
  add(stop, (rest, ctx) => {
    if (rest === "none" && stop === "via") return [["--cs-gradient-via-stops", "initial"]];
    const c = color(rest, ctx);
    if (c != null) {
      ctx.uses.add("gradient");
      if (stop === "via") return [["--cs-gradient-via", c], ["--cs-gradient-via-stops", "var(--cs-gradient-position), var(--cs-gradient-from) var(--cs-gradient-from-position), var(--cs-gradient-via) var(--cs-gradient-via-position), var(--cs-gradient-to) var(--cs-gradient-to-position)"], ["--cs-gradient-stops", "var(--cs-gradient-via-stops)"]];
      return [[`--cs-gradient-${stop}`, c], ["--cs-gradient-stops", GSTOPS]];
    }
    const pct = rest.match(/^(\d+(\.\d+)?)%$/) ? rest : parseArb(rest)?.value;
    if (pct && (rest.endsWith("%") || parseArb(rest))) { ctx.uses.add("gradient"); return [[`--cs-gradient-${stop}-position`, pct]]; }
    return null;
  });
}
// background-* y mascaras
S({ "bg-auto": "background-size: auto", "bg-cover": "background-size: cover", "bg-contain": "background-size: contain",
  "bg-fixed": "background-attachment: fixed", "bg-local": "background-attachment: local", "bg-scroll": "background-attachment: scroll",
  "bg-clip-border": "background-clip: border-box", "bg-clip-padding": "background-clip: padding-box", "bg-clip-content": "background-clip: content-box", "bg-clip-text": "background-clip: text",
  "bg-bottom": "background-position: bottom", "bg-bottom-left": "background-position: left bottom", "bg-bottom-right": "background-position: right bottom", "bg-center": "background-position: center",
  "bg-left": "background-position: left", "bg-left-bottom": "background-position: left bottom", "bg-left-top": "background-position: left top", "bg-right": "background-position: right",
  "bg-right-bottom": "background-position: right bottom", "bg-right-top": "background-position: right top", "bg-top": "background-position: top", "bg-top-left": "background-position: left top", "bg-top-right": "background-position: right top",
  "bg-no-repeat": "background-repeat: no-repeat", "bg-repeat": "background-repeat: repeat", "bg-repeat-x": "background-repeat: repeat-x", "bg-repeat-y": "background-repeat: repeat-y", "bg-repeat-round": "background-repeat: round", "bg-repeat-space": "background-repeat: space",
  "bg-origin-border": "background-origin: border-box", "bg-origin-padding": "background-origin: padding-box", "bg-origin-content": "background-origin: content-box", "bg-none": "background-image: none" });
add("bg", (rest) => {
  const a = parseArb(rest); if (!a) return null;
  const t = a.type ?? guessType(a.value);
  if (t === "image" || t === "url") return [["background-image", a.value]];
  if (t === "length" || t === "percentage" || t === "size" || t === "bg-size") return [["background-size", a.value]];
  if (t === "position") return [["background-position", a.value]];
  return null;
});
S({ "fill-none": "fill: none", "stroke-none": "stroke: none", "object-contain": "object-fit: contain", "object-cover": "object-fit: cover", "object-fill": "object-fit: fill", "object-none": "object-fit: none", "object-scale-down": "object-fit: scale-down",
  "object-center": "object-position: center", "object-top": "object-position: top", "object-bottom": "object-position: bottom", "object-left": "object-position: left", "object-right": "object-position: right" });
add("fill", (rest, ctx) => { const c = color(rest, ctx); return c == null ? null : [["fill", c]]; });
add("stroke", (rest, ctx) => { if (isNumber(rest)) return [["stroke-width", rest]]; const c = color(rest, ctx); return c == null ? null : [["stroke", c]]; });

// padding
const padExtras = { px: "1px" };
spacingFamily("p", (v) => [["padding", v]], padExtras); spacingFamily("px", (v) => [["padding-inline", v]], padExtras); spacingFamily("py", (v) => [["padding-block", v]], padExtras);
spacingFamily("ps", (v) => [["padding-inline-start", v]], padExtras); spacingFamily("pe", (v) => [["padding-inline-end", v]], padExtras);
spacingFamily("pt", (v) => [["padding-top", v]], padExtras); spacingFamily("pr", (v) => [["padding-right", v]], padExtras); spacingFamily("pb", (v) => [["padding-bottom", v]], padExtras); spacingFamily("pl", (v) => [["padding-left", v]], padExtras);

// ---------------------------------------------------------------------------------------------------
// 3. Tipografia
// ---------------------------------------------------------------------------------------------------
S({ "text-left": "text-align: left", "text-center": "text-align: center", "text-right": "text-align: right", "text-justify": "text-align: justify", "text-start": "text-align: start", "text-end": "text-align: end",
  "align-baseline": "vertical-align: baseline", "align-top": "vertical-align: top", "align-middle": "vertical-align: middle", "align-bottom": "vertical-align: bottom", "align-text-top": "vertical-align: text-top",
  "align-text-bottom": "vertical-align: text-bottom", "align-sub": "vertical-align: sub", "align-super": "vertical-align: super" });
add("indent", (rest, ctx) => { const v = spacing(rest, ctx.neg, { px: "1px" }); return v == null ? null : [["text-indent", v]]; });
add("font", (rest) => {
  const fams = { sans: "var(--font-sans)", serif: "var(--font-serif)", mono: "var(--font-mono)", heading: "var(--font-heading)" };
  if (rest in fams) return [["font-family", fams[rest]]];
  const a = parseArb(rest); if (a && (a.type === "family-name" || (a.kind === "var" && a.type === "family-name"))) return [["font-family", a.value]];
  return null;
});
add("text", (rest) => {
  if (rest in textSizes) return [["font-size", `var(--text-${rest})`], ["line-height", `var(--cs-leading, var(--text-${rest}--line-height))`]];
  const [name, mod] = splitModifier(rest);
  if (name in textSizes && mod != null) {
    const lh = isNumber(mod) ? `calc(var(--spacing) * ${mod})` : leadings[mod] ? `var(--leading-${mod})` : parseArb(mod)?.value;
    return lh ? [["font-size", `var(--text-${name})`], ["line-height", lh]] : null;
  }
  const a = parseArb(rest); if (!a) return null;
  const t = a.type ?? guessType(a.value);
  if (t === "length" || t === "percentage" || t === "absolute-size" || t === "relative-size" || (a.kind === "var" && a.type === "length")) return [["font-size", a.value]];
  return null;
});
add("leading", (rest, ctx) => {
  if (rest in leadings) { const v = rest === "none" ? "1" : `var(--leading-${rest})`; return [["--cs-leading", v], ["line-height", v]]; }
  if (isNumber(rest)) return [["--cs-leading", `calc(var(--spacing) * ${rest})`], ["line-height", `calc(var(--spacing) * ${rest})`]];
  const a = parseArb(rest); return a ? [["--cs-leading", a.value], ["line-height", a.value]] : null;
});
add("font", (rest) => {
  if (rest in fontWeights) return [["--cs-font-weight", `var(--font-weight-${rest})`], ["font-weight", `var(--font-weight-${rest})`]];
  const a = parseArb(rest); if (!a) return null;
  const t = a.type ?? guessType(a.value);
  if (t === "number" || a.type === "number" || /^\d+$/.test(a.value)) return [["--cs-font-weight", a.value], ["font-weight", a.value]];
  return null;
});
add("tracking", (rest, ctx) => {
  if (rest in tracking) return [["--cs-tracking", `var(--tracking-${rest})`], ["letter-spacing", `var(--tracking-${rest})`]];
  const a = parseArb(rest); return a ? [["--cs-tracking", a.value], ["letter-spacing", a.value]] : null;
});
S({ "text-wrap": "text-wrap: wrap", "text-nowrap": "text-wrap: nowrap", "text-balance": "text-wrap: balance", "text-pretty": "text-wrap: pretty",
  "break-normal": "overflow-wrap: normal; word-break: normal", "break-words": "overflow-wrap: break-word", "break-all": "word-break: break-all", "break-keep": "word-break: keep-all", "wrap-anywhere": "overflow-wrap: anywhere", "wrap-break-word": "overflow-wrap: break-word", "wrap-normal": "overflow-wrap: normal",
  "text-ellipsis": "text-overflow: ellipsis", "text-clip": "text-overflow: clip", "overflow-ellipsis": "text-overflow: ellipsis", "hyphens-none": "hyphens: none", "hyphens-manual": "hyphens: manual", "hyphens-auto": "hyphens: auto",
  "whitespace-normal": "white-space: normal", "whitespace-nowrap": "white-space: nowrap", "whitespace-pre": "white-space: pre", "whitespace-pre-line": "white-space: pre-line", "whitespace-pre-wrap": "white-space: pre-wrap", "whitespace-break-spaces": "white-space: break-spaces" });
// color de texto
add("text", (rest, ctx) => {
  const a = parseArb(rest.split("/")[0]);
  if (a && a.type && a.type !== "color") return null;
  const c = color(rest, ctx); return c == null ? null : [["color", c]];
});
S({ uppercase: "text-transform: uppercase", lowercase: "text-transform: lowercase", capitalize: "text-transform: capitalize", "normal-case": "text-transform: none", italic: "font-style: italic", "not-italic": "font-style: normal",
  underline: "text-decoration-line: underline", overline: "text-decoration-line: overline", "line-through": "text-decoration-line: line-through", "no-underline": "text-decoration-line: none",
  "tabular-nums": "font-variant-numeric: tabular-nums", "lining-nums": "font-variant-numeric: lining-nums", "oldstyle-nums": "font-variant-numeric: oldstyle-nums", "proportional-nums": "font-variant-numeric: proportional-nums", "slashed-zero": "font-variant-numeric: slashed-zero", "normal-nums": "font-variant-numeric: normal", ordinal: "font-variant-numeric: ordinal" });
for (const k of ["solid", "double", "dotted", "dashed", "wavy"]) statics({ [`decoration-${k}`]: [["text-decoration-style", k]] });
add("decoration", (rest, ctx) => {
  if (rest === "auto" || rest === "from-font") return [["text-decoration-thickness", rest]]; if (isNumber(rest)) return [["text-decoration-thickness", `${rest}px`]];
  const c = color(rest, ctx); return c == null ? null : [["text-decoration-color", c]];
});
add("underline-offset", (rest) => rest === "auto" ? [["text-underline-offset", "auto"]] : isNumber(rest) ? [["text-underline-offset", `${rest}px`]] : parseArb(rest) ? [["text-underline-offset", parseArb(rest).value]] : null);
S({ antialiased: "-webkit-font-smoothing: antialiased; -moz-osx-font-smoothing: grayscale", "subpixel-antialiased": "-webkit-font-smoothing: auto; -moz-osx-font-smoothing: auto" });
add("accent", (rest, ctx) => rest === "auto" ? [["accent-color", "auto"]] : (color(rest, ctx) != null ? [["accent-color", color(rest, ctx)]] : null));
add("caret", (rest, ctx) => (color(rest, ctx) != null ? [["caret-color", color(rest, ctx)]] : null));
S({ "scheme-normal": "color-scheme: normal", "scheme-dark": "color-scheme: dark", "scheme-light": "color-scheme: light", "scheme-light-dark": "color-scheme: light dark", "scheme-only-dark": "color-scheme: only dark", "scheme-only-light": "color-scheme: only light" });

// ---------------------------------------------------------------------------------------------------
// 4. Efectos
// ---------------------------------------------------------------------------------------------------
add("opacity", (rest) => { if (isNumber(rest)) return [["opacity", `${rest}%`]]; const a = parseArb(rest); return a ? [["opacity", a.value]] : null; });
S({ "mix-blend-normal": "mix-blend-mode: normal", "mix-blend-multiply": "mix-blend-mode: multiply", "mix-blend-screen": "mix-blend-mode: screen", "mix-blend-overlay": "mix-blend-mode: overlay", "mix-blend-darken": "mix-blend-mode: darken",
  "mix-blend-lighten": "mix-blend-mode: lighten", "mix-blend-difference": "mix-blend-mode: difference", "mix-blend-plus-lighter": "mix-blend-mode: plus-lighter", "mix-blend-plus-darker": "mix-blend-mode: plus-darker" });
const BOX_SHADOW = "var(--cs-inset-shadow), var(--cs-inset-ring-shadow), var(--cs-ring-offset-shadow), var(--cs-ring-shadow), var(--cs-shadow)";
const fmtLayers = (layers, inset = false) =>
  layers.map(([x, y, b, s, a]) => `${inset ? "inset " : ""}${x} ${y} ${b}${s !== 0 ? " " + s : " 0"} var(--cs-shadow-color, rgb(0 0 0 / ${a}))`).join(", ");
add("shadow", (rest, ctx) => {
  ctx.uses.add("shadow");
  if (rest === "none") return [["--cs-shadow", "0 0 #0000"], ["box-shadow", BOX_SHADOW]];
  const key = rest === "" ? "DEFAULT" : rest;
  if (key in shadows) {
    return [["--cs-shadow", fmtLayers(shadows[key])], ["box-shadow", BOX_SHADOW]];
  }
  if (key === "inner") return [["--cs-shadow", "inset 0 2px 4px 0 var(--cs-shadow-color, rgb(0 0 0 / 0.05))"], ["box-shadow", BOX_SHADOW]];
  const a = parseArb(rest);
  if (a && (a.type === "shadow" || (!a.type && !/^(#|rgb|hsl|oklch|color-mix)/.test(a.value) && /\d/.test(a.value)))) return [["--cs-shadow", a.value.replace(/(rgb|hsl)a?\([^)]*\)|#[0-9a-f]+/gi, (m) => `var(--cs-shadow-color, ${m})`)], ["box-shadow", BOX_SHADOW]];
  return null;
});
const ringWidth = (rest) => (rest === "" ? "1px" : isNumber(rest) ? `${rest}px` : (parseArb(rest) && (parseArb(rest).type === "length" || guessType(parseArb(rest).value) === "length") ? parseArb(rest).value : null));
add("ring", (rest, ctx) => { const w = ringWidth(rest); if (w == null) return null; ctx.uses.add("shadow"); return [["--cs-ring-shadow", `var(--cs-ring-inset, ) 0 0 0 calc(${w} + var(--cs-ring-offset-width)) var(--cs-ring-color, currentcolor)`], ["box-shadow", BOX_SHADOW]]; });
add("inset-ring", (rest, ctx) => { const w = ringWidth(rest); if (w == null) return null; ctx.uses.add("shadow"); return [["--cs-inset-ring-shadow", `inset 0 0 0 ${w} var(--cs-inset-ring-color, currentcolor)`], ["box-shadow", BOX_SHADOW]]; });
add("inset-shadow", (rest, ctx) => { ctx.uses.add("shadow"); const key = rest === "" ? "DEFAULT" : rest; if (rest === "none") return [["--cs-inset-shadow", "0 0 #0000"], ["box-shadow", BOX_SHADOW]]; if (key in insetShadows) return [["--cs-inset-shadow", fmtLayers(insetShadows[key], true).replace(/var\(--cs-shadow-color/g, "var(--cs-inset-shadow-color")], ["box-shadow", BOX_SHADOW]]; return null; });
S({ "ring-inset": [["--cs-ring-inset", "inset"]], "shadow-initial": [["--cs-shadow-color", "initial"]], "inset-shadow-initial": [["--cs-inset-shadow-color", "initial"]] });
add("shadow", (rest, ctx) => {
  const a = parseArb(rest); if (a && a.type && a.type !== "color") return null;
  const c = color(rest, ctx); if (c == null) return null; ctx.uses.add("shadow");
  const [, mod] = splitModifier(rest);
  return [["--cs-shadow-color", mod != null ? `color-mix(in oklab, ${c} var(--cs-shadow-alpha), transparent)` : c]];
});
add("ring", (rest, ctx) => { const c = color(rest, ctx); if (c == null) return null; ctx.uses.add("shadow"); return [["--cs-ring-color", c]]; });
add("ring-offset", (rest, ctx) => {
  if (isNumber(rest)) { ctx.uses.add("shadow"); return [["--cs-ring-offset-width", `${rest}px`], ["--cs-ring-offset-shadow", "var(--cs-ring-inset, ) 0 0 0 var(--cs-ring-offset-width) var(--cs-ring-offset-color)"]]; }
  const a = parseArb(rest); if (a && (a.type === "length" || guessType(a.value) === "length")) { ctx.uses.add("shadow"); return [["--cs-ring-offset-width", a.value], ["--cs-ring-offset-shadow", "var(--cs-ring-inset, ) 0 0 0 var(--cs-ring-offset-width) var(--cs-ring-offset-color)"]]; }
  return null;
});
add("ring-offset", (rest, ctx) => { const c = color(rest, ctx); if (c == null) return null; ctx.uses.add("shadow"); return [["--cs-ring-offset-color", c]]; });

// outline
add("outline", (rest, ctx) => {
  if (rest === "none") return [["--cs-outline-style", "none"], ["outline-style", "none"]];
  if (rest === "hidden") return [["outline", "2px solid transparent"], ["outline-offset", "2px"]];
  if (rest === "") return [["outline-style", "var(--cs-outline-style)"], ["outline-width", "1px"]];
  if (isNumber(rest)) return [["outline-style", "var(--cs-outline-style)"], ["outline-width", `${rest}px`]];
  for (const k of ["dashed", "dotted", "double", "solid"]) if (rest === k) return [["--cs-outline-style", k], ["outline-style", k]];
  const c = color(rest, ctx); return c == null ? null : [["outline-color", c]];
});
add("outline-offset", (rest, ctx) => isNumber(rest) ? [["outline-offset", `${ctx.neg ? "-" : ""}${rest}px`]] : null);

// filtros
const FILTERS = ["blur", "brightness", "contrast", "grayscale", "hue-rotate", "invert", "saturate", "sepia", "drop-shadow"];
const filterList = (p) => FILTERS.map((f) => `var(--cs-${p}${f}, )`).join(" ");
const bfList = () => ["blur", "brightness", "contrast", "grayscale", "hue-rotate", "invert", "opacity", "saturate", "sepia"].map((f) => `var(--cs-backdrop-${f}, )`).join(" ");
const filterFns = {
  blur: (rest) => { const k = rest === "" ? "DEFAULT" : rest; if (rest === "none") return "initial"; if (k in blurs) return `blur(${rest === "" ? "8px" : `var(--blur-${rest})`})`; const a = parseArb(rest); return a ? `blur(${a.value})` : null; },
  brightness: (rest) => (isNumber(rest) ? `brightness(${rest}%)` : parseArb(rest) ? `brightness(${parseArb(rest).value})` : null),
  contrast: (rest) => (isNumber(rest) ? `contrast(${rest}%)` : parseArb(rest) ? `contrast(${parseArb(rest).value})` : null),
  grayscale: (rest) => (rest === "" ? "grayscale(100%)" : isNumber(rest) ? `grayscale(${rest}%)` : null),
  "hue-rotate": (rest, neg) => (isNumber(rest) ? `hue-rotate(${neg ? "-" : ""}${rest}deg)` : null),
  invert: (rest) => (rest === "" ? "invert(100%)" : isNumber(rest) ? `invert(${rest}%)` : null),
  saturate: (rest) => (isNumber(rest) ? `saturate(${rest}%)` : parseArb(rest) ? `saturate(${parseArb(rest).value})` : null),
  sepia: (rest) => (rest === "" ? "sepia(100%)" : isNumber(rest) ? `sepia(${rest}%)` : null),
  opacity: (rest) => (isNumber(rest) ? `opacity(${rest}%)` : null),
};
for (const fn of ["blur", "brightness", "contrast", "grayscale", "hue-rotate", "invert", "saturate", "sepia"]) {
  add(fn, (rest, ctx) => { const v = filterFns[fn](rest, ctx.neg); if (v == null) return null; return [[`--cs-${fn}`, v], ["filter", filterList("")]]; });
}
add("drop-shadow", (rest, ctx) => {
  if (rest === "none") return [["--cs-drop-shadow", "drop-shadow(0 0 #0000)"], ["filter", filterList("")]];
  const t = { "": "0 1px 2px rgb(0 0 0 / 0.1), 0 1px 1px rgb(0 0 0 / 0.06)", xs: "0 1px 1px rgb(0 0 0 / 0.05)", sm: "0 1px 2px rgb(0 0 0 / 0.15)", md: "0 3px 3px rgb(0 0 0 / 0.12)", lg: "0 4px 4px rgb(0 0 0 / 0.15)", xl: "0 9px 7px rgb(0 0 0 / 0.1)", "2xl": "0 25px 25px rgb(0 0 0 / 0.15)" };
  if (rest in t) return [["--cs-drop-shadow", t[rest].split(/, (?=\d)/).map((s) => `drop-shadow(${s})`).join(" ")], ["filter", filterList("")]];
  return null;
});
S({ filter: [["filter", filterList("")]], "filter-none": "filter: none" });
for (const fn of ["blur", "brightness", "contrast", "grayscale", "hue-rotate", "invert", "opacity", "saturate", "sepia"]) {
  add(`backdrop-${fn}`, (rest, ctx) => {
    const v = filterFns[fn](rest, ctx.neg); if (v == null) return null;
    return [[`--cs-backdrop-${fn}`, v], ["-webkit-backdrop-filter", bfList()], ["backdrop-filter", bfList()]];
  });
}
S({ "backdrop-filter": [["-webkit-backdrop-filter", bfList()], ["backdrop-filter", bfList()]], "backdrop-filter-none": "-webkit-backdrop-filter: none; backdrop-filter: none" });

// transiciones
const TR_TIMING = [["transition-timing-function", "var(--cs-ease, var(--default-transition-timing-function))"], ["transition-duration", "var(--cs-duration, var(--default-transition-duration))"]];
const TR = {
  "": "color, background-color, border-color, outline-color, text-decoration-color, fill, stroke, --cs-gradient-from, --cs-gradient-via, --cs-gradient-to, opacity, box-shadow, transform, translate, scale, rotate, filter, -webkit-backdrop-filter, backdrop-filter, display, content-visibility, overlay, pointer-events",
  all: "all", colors: "color, background-color, border-color, outline-color, text-decoration-color, fill, stroke, --cs-gradient-from, --cs-gradient-via, --cs-gradient-to",
  opacity: "opacity", shadow: "box-shadow", transform: "transform, translate, scale, rotate",
};
add("transition", (rest) => {
  if (rest === "none") return [["transition-property", "none"]];
  if (rest in TR) return [["transition-property", TR[rest]], ...TR_TIMING];
  const a = parseArb(rest); return a ? [["transition-property", a.value], ...TR_TIMING] : null;
});
S({ "transition-discrete": "transition-behavior: allow-discrete", "transition-normal": "transition-behavior: normal" });
add("delay", (rest) => (isNumber(rest) ? [["transition-delay", `${rest}ms`]] : parseArb(rest) ? [["transition-delay", parseArb(rest).value]] : null));
add("duration", (rest) => (isNumber(rest) ? [["--cs-duration", `${rest}ms`], ["transition-duration", `${rest}ms`]] : rest === "initial" ? [["--cs-duration", "initial"]] : parseArb(rest) ? [["--cs-duration", parseArb(rest).value], ["transition-duration", parseArb(rest).value]] : null));
add("ease", (rest) => (rest in eases ? [["--cs-ease", eases[rest]], ["transition-timing-function", eases[rest]]] : parseArb(rest) ? [["--cs-ease", parseArb(rest).value], ["transition-timing-function", parseArb(rest).value]] : null));
S({ "will-change-auto": "will-change: auto", "will-change-scroll": "will-change: scroll-position", "will-change-contents": "will-change: contents", "will-change-transform": "will-change: transform" });
S({ "content-none": [["--cs-content", "none"], ["content", "none"]], "select-none": "-webkit-user-select: none; user-select: none", "select-text": "-webkit-user-select: text; user-select: text", "select-all": "-webkit-user-select: all; user-select: all", "select-auto": "-webkit-user-select: auto; user-select: auto",
  "forced-color-adjust-auto": "forced-color-adjust: auto", "forced-color-adjust-none": "forced-color-adjust: none" });
add("content", (rest) => { const a = parseArb(rest); return a ? [["--cs-content", a.value], ["content", "var(--cs-content)"]] : null; });

// animaciones "enter/exit" (entrada/salida tipo shadcn: fade-in, zoom-in, slide-in-from-*, …)
const pct = (n) => `${Number(n) / 100}`;
for (const kind of ["in", "out"]) {
  const p = kind === "in" ? "enter" : "exit";
  statics({ [`fade-${kind}`]: [[`--cs-${p}-opacity`, "0"]], [`zoom-${kind}`]: [[`--cs-${p}-scale`, "0"]], [`blur-${kind}`]: [[`--cs-${p}-blur`, "20px"]], [`spin-${kind}`]: [[`--cs-${p}-rotate`, "30deg"]] });
  add(`fade-${kind}`, (rest) => isNumber(rest) ? [[`--cs-${p}-opacity`, pct(rest)]] : null);
  add(`zoom-${kind}`, (rest) => isNumber(rest) ? [[`--cs-${p}-scale`, `${Number(rest) / 100}`]] : null);
  add(`blur-${kind}`, (rest) => isNumber(rest) ? [[`--cs-${p}-blur`, `${rest}px`]] : null);
  const dirs = kind === "in" ? { top: ["y", -1], bottom: ["y", 1], left: ["x", -1], right: ["x", 1] } : { top: ["y", -1], bottom: ["y", 1], left: ["x", -1], right: ["x", 1] };
  for (const [dir, [ax, sign]] of Object.entries(dirs)) {
    const root = kind === "in" ? `slide-in-from-${dir}` : `slide-out-to-${dir}`;
    statics({ [root]: [[`--cs-${p}-translate-${ax}`, `${sign * 100}%`]] });
    add(root, (rest) => { if (isNumber(rest)) return [[`--cs-${p}-translate-${ax}`, `calc(var(--spacing) * ${sign < 0 ? "-" : ""}${rest})`]]; const fr = rest.match(/^(\d+)\/(\d+)$/); if (fr) return [[`--cs-${p}-translate-${ax}`, `calc(${fr[1]} / ${fr[2]} * ${sign * 100}%)`]]; return null; });
  }
}
S({ running: "animation-play-state: running", paused: "animation-play-state: paused" });

// prose: colores (prose-neutral, prose-invert…) como utilidades de variables; la estructura esta en prose.css
import { proseThemes } from "./theme.mjs";
for (const [name, vars] of Object.entries(proseThemes)) {
  const decls = Object.entries(vars).map(([k, v]) => [`--cs-prose-${k}`, v]);
  statics({ [`prose-${name}`]: decls });
}
