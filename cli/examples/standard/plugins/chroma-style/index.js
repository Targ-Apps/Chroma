/**
 * @chroma/style — tokens de diseno, generador de utilidades, tw() y presets cva para Chroma.
 *
 * Fuente canonica: Chroma-Style/ (ver Chroma/docs/PLUGIN-STANDARD.md).
 *
 *   import { cva, cx } from "../pkg/chroma.js";
 *   import { bootstrapStyle, twMerge } from "../plugins/chroma-style/index.js";
 *   const { tw, presets } = bootstrapStyle({ cva, cx, styles: false });  // styles:false = el CSS ya lo enlaza el HTML
 *
 * CSS: la forma recomendada es generarlo en build con el plugin nativo chroma-style del CLI (solo las utilidades usadas; se activa con pluginOptions.chroma-style en chroma.json).
 * Sin paso de build, `injectStyles()` enlaza tokens.css + base.css + utilities.css (subconjunto de arranque, ya con sus componentes).
 */
import { createVariants, createPresets } from "./variants.js";
import { twMerge, tw as twAlias, createTw } from "./tw.js";

export const VERSION = "0.3.0";

/** Hojas que enlaza `injectStyles()` (en este orden: define el orden de capas tokens < base < components < utilities). */
const STYLESHEETS = ["tokens.css", "base.css", "utilities.css"];

/** Resumen de la gramatica de utilidades (documentacion / autocompletado). Ver docs: chroma-style/utilities. */
export const utilityClasses = {
    layout: ["flex", "grid", "hidden", "relative", "absolute", "inset-0", "z-10", "overflow-hidden", "container", "aspect-video", "size-4"],
    flexGrid: ["flex-col", "items-center", "justify-between", "gap-4", "grid-cols-3", "col-span-2", "space-y-2"],
    spacing: ["p-4", "px-2", "mt-6", "-mx-1", "m-[3px]", "p-(--pad)"],
    sizing: ["w-full", "h-screen", "max-w-2xl", "min-h-0", "w-1/2", "w-[calc(100%-2rem)]"],
    typography: ["text-sm", "text-[13vw]", "font-semibold", "tracking-tight", "leading-snug", "uppercase", "truncate", "line-clamp-3", "prose"],
    color: ["bg-primary", "text-muted-foreground", "border-border", "bg-primary/80", "text-white/65", "ring-ring/50", "bg-[#0088cc]", "from-primary", "to-transparent"],
    border: ["border", "border-b-2", "rounded-lg", "rounded-full", "divide-y", "ring-2", "outline-none"],
    effects: ["shadow-md", "opacity-60", "backdrop-blur-md", "mix-blend-overlay", "blur-sm"],
    transform: ["translate-y-2", "-translate-y-1/2", "scale-105", "rotate-180", "origin-left"],
    motion: ["transition-colors", "duration-300", "ease-out", "animate-spin", "animate-in", "fade-in", "zoom-in-95", "slide-in-from-top-2", "animate-marquee"],
    variants: ["hover:", "focus-visible:", "disabled:", "md:", "max-md:", "dark:", "group-hover:", "peer-checked:", "data-[state=open]:", "aria-expanded:", "has-[...]:", "before:", "[&_svg]:"],
    components: ["cs-card", "cs-btn", "cs-btn-primary", "cs-btn-outline", "focus-ring", "is-disabled"],
    presets: ["button", "badge", "card", "input"],
};

/**
 * Enlaza las hojas del plugin en document.head (idempotente). Solo para apps sin paso de build.
 * `base` = URL de la carpeta del plugin (p. ej. "/plugins/chroma-style/"); por defecto, junto a este modulo.
 * Con un bundle (chroma build) `import.meta.url` apunta al bundle: pasa `base` explicitamente.
 */
export function injectStyles({ base } = {}) {
    if (typeof document === "undefined") return;

    for (const href of STYLESHEETS) {
        const marker = `chroma-style:${href}`;
        if (document.querySelector(`link[data-chroma-plugin="${marker}"]`)) continue;

        const link = document.createElement("link");
        link.rel = "stylesheet";
        link.href = base ? `${base.replace(/\/?$/, "/")}${href}` : new URL(`./${href}`, import.meta.url).href;
        link.dataset.chromaPlugin = marker;
        document.head.appendChild(link);
    }
}

export { createVariants, createPresets, twMerge, createTw };
export const tw = twAlias;

/**
 * Arranque. Pasa `cva`/`cx` del motor para obtener los presets y un `tw` que primero une con `cx`.
 * `styles: false` evita enlazar CSS (usa esto cuando el HTML ya enlaza el CSS generado por el plugin chroma-style);
 * `base` = URL de la carpeta del plugin para `injectStyles`.
 * @param {{ cva?: Function, cx?: Function, styles?: boolean, base?: string }} [engine]
 */
export function bootstrapStyle(engine = {}) {
    if (engine.styles !== false) injectStyles({ base: engine.base });
    const merge = createTw(engine.cx);
    const presets = engine.cva ? createVariants(engine.cva) : null;
    return { tw: merge, twMerge, presets, utilityClasses, injectStyles, createVariants, version: VERSION };
}

/** Contrato de plugin Chroma — ver chroma.plugin.json */
export const plugin = {
    name: "chroma-style",
    capabilities: ["styling", "design-tokens", "utility-generator"],
    hooks: {
        bootstrap: bootstrapStyle,
        styles: injectStyles,
    },
};

export default plugin;
