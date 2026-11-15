/**
 * Resolucion de valores: numeros de escala, fracciones, valores arbitrarios [..] y (--var),
 * normalizacion de calc()/min()/max(), colores con modificador de opacidad.
 */
import { palette, baseColors, semanticColors } from "./theme.mjs";

const MATH_FN = /^(calc|min|max|clamp)\($/;

/** `a_b` -> `a b` (excepto dentro de url()), `\_` -> `_`; espacia operadores dentro de calc/min/max/clamp. */
export function normalizeArbitrary(raw) {
  let out = "";
  const stack = []; // true = funcion matematica abierta, "v" = var()/env() (opaca)
  let i = 0;
  const lastNonSpace = () => { for (let k = out.length - 1; k >= 0; k--) if (out[k] !== " ") return out[k]; return ""; };
  while (i < raw.length) {
    const c = raw[i];
    if (c === "\\" && raw[i + 1] === "_") { out += "_"; i += 2; continue; }
    // url(...) se copia tal cual
    if (raw.startsWith("url(", i)) {
      const end = raw.indexOf(")", i);
      const stop = end < 0 ? raw.length : end + 1;
      out += raw.slice(i, stop); i = stop; continue;
    }
    const inMath = stack.length && stack[stack.length - 1] === true;
    const inOpaque = stack.includes("v");
    if (c === "(") {
      const head = out.match(/[a-z-]+$/i)?.[0] ?? "";
      stack.push(MATH_FN.test(head + "(") ? true : /^(var|env)$/.test(head) ? "v" : false);
      out += c; i++; continue;
    }
    if (c === ")") { stack.pop(); out += c; i++; continue; }
    if (c === "_") { out += " "; i++; continue; }
    if (inMath && !inOpaque) {
      if (c === "," ) { out += ", "; i++; if (raw[i] === "_") i++; continue; }
      if (c === "*" || c === "/") { out = out.replace(/ $/, "") + ` ${c} `; i++; continue; }
      if (c === "+" || c === "-") {
        const prev = lastNonSpace();
        const binary = prev && prev !== "(" && prev !== "," && !"+-*/".includes(prev) && (/[\w%)]/.test(prev));
        if (binary && (raw[i + 1] === "_" || /[\d.(a-z]/i.test(raw[i + 1] ?? "") || true)) {
          // `a-b` solo es resta si lo anterior es un numero/unidad/parentesis
          out = out.replace(/ $/, "") + ` ${c} `; i++; if (raw[i] === "_") i++; continue;
        }
      }
    }
    out += c; i++;
  }
  return out.replace(/ {2,}/g, " ").trim();
}

/** Devuelve { kind:"arb"|"var", value, type } para `[..]` / `(..)`; null si no es arbitrario. */
export function parseArb(rest) {
  if (rest.startsWith("[") && rest.endsWith("]")) {
    let inner = rest.slice(1, -1);
    let type = null;
    const m = inner.match(/^([a-z-]+):(?!:)(.*)$/s);
    if (m && /^(color|length|percentage|number|integer|url|image|position|size|angle|ratio|line-width|family-name|absolute-size|relative-size|bg-size|any|shadow|time|string|flex)$/.test(m[1])) { type = m[1]; inner = m[2]; }
    return { kind: "arb", value: normalizeArbitrary(inner), type };
  }
  if (rest.startsWith("(") && rest.endsWith(")")) {
    let inner = rest.slice(1, -1);
    let type = null;
    const m = inner.match(/^([a-z-]+):(--.*)$/);
    if (m) { type = m[1]; inner = m[2]; }
    return { kind: "var", value: `var(${inner})`, type };
  }
  return null;
}

/** Decide el tipo probable de un valor arbitrario cuando no hay pista `type:`. */
export function guessType(v) {
  if (/^(#|rgb|hsl|oklch|oklab|lab|lch|color-mix|color\(|currentcolor$|transparent$)/i.test(v)) return "color";
  if (/^(url\(|image-set|(repeating-)?(linear|radial|conic)-gradient)/i.test(v)) return "image";
  if (/^-?[\d.]+(px|rem|em|vw|vh|vmin|vmax|svh|dvh|lvh|ch|ex|cm|mm|in|pt|pc|%|lh|rlh|cqw|cqh)$/i.test(v) || /^(calc|min|max|clamp)\(/.test(v)) return "length";
  if (/^-?[\d.]+(deg|rad|turn|grad)$/.test(v)) return "angle";
  if (/^-?[\d.]+$/.test(v)) return "number";
  return null;
}

export const isNumber = (s) => /^-?\d*\.?\d+$/.test(s);

/** Valor de escala de espaciado. `extras` mapea palabras clave (auto, full, px…). */
export function spacing(rest, neg, extras = {}) {
  const wrapNeg = (v) => (neg ? `calc(${v} * -1)` : v);
  if (rest in extras) return neg ? `calc(${extras[rest]} * -1)` : extras[rest];
  if (/^\d*\.?\d+$/.test(rest)) {
    const n = Number(rest);
    if (n === 0) return "0px";
    if (neg) return `calc(var(--spacing) * -${rest})`;
    return n === 1 ? "var(--spacing)" : `calc(var(--spacing) * ${rest})`;
  }
  const frac = rest.match(/^(\d+)\/(\d+)$/);
  if (frac) return wrapNeg(`calc(${frac[1]} / ${frac[2]} * 100%)`);
  const arb = parseArb(rest);
  if (arb) {
    if (arb.kind === "var") return wrapNeg(arb.value);
    return wrapNeg(arb.value);
  }
  return null;
}

/** Color con modificador de opacidad. Devuelve el CSS del color o null. */
export function color(rest, ctx = {}) {
  let [name, mod] = splitModifier(rest);
  let base = null;
  const arb = parseArb(name);
  if (arb) {
    if (arb.type && arb.type !== "color") return null;
    if (!arb.type && arb.kind === "arb" && guessType(arb.value) !== "color") return null;
    if (!arb.type && arb.kind === "var" && ctx.strict) return null;
    base = arb.value;
  } else if (name in baseColors) { base = `var(--color-${name})`; ctx.uses?.add(`color-${name}`); }
  else if (semanticColors.includes(name)) base = `var(--${name})`;
  else if (name === "transparent") return "transparent";
  else if (name === "current") base = "currentcolor";
  else if (name === "inherit") return "inherit";
  else {
    const m = name.match(/^([a-z]+)-(\d+)$/);
    if (m && palette[m[1]]?.[m[2]]) { base = `var(--color-${name})`; ctx.uses?.add(`color-${name}`); }
    else if (ctx.extraColors?.[name]) base = ctx.extraColors[name];
  }
  if (!base) return null;
  if (mod == null) return base;
  const pct = opacityPercent(mod);
  if (!pct) return null;
  return `color-mix(in oklab, ${base} ${pct}, transparent)`;
}

export function opacityPercent(mod) {
  if (/^\d+(\.\d+)?$/.test(mod)) return `${mod}%`;
  const arb = parseArb(mod);
  if (arb) { if (arb.kind === "var") return `calc(${arb.value} * 100%)`; if (/^[\d.]+%$/.test(arb.value)) return arb.value; if (/^[\d.]+$/.test(arb.value)) return `${+(Number(arb.value) * 100).toFixed(4)}%`; }
  return null;
}

/** `name/mod` respetando corchetes y parentesis. */
export function splitModifier(s) {
  let depth = 0, idx = -1;
  for (let i = 0; i < s.length; i++) {
    const c = s[i];
    if (c === "[" || c === "(") depth++;
    else if (c === "]" || c === ")") depth--;
    else if (c === "/" && depth === 0) idx = i;
  }
  return idx < 0 ? [s, null] : [s.slice(0, idx), s.slice(idx + 1)];
}

/** Escapa un nombre de clase para usarlo en un selector CSS. */
export function cssEscape(s) {
  return s.replace(/[^a-zA-Z0-9_-]/g, (ch) => (/[\u0080-￿]/.test(ch) ? ch : "\\" + ch)).replace(/^(-?)(\d)/, (m, a, d) => `${a}\\3${d} `);
}
