/**
 * @chroma/style — design tokens, utility CSS, and cva presets for Chroma.
 *
 * Canonical source: Chroma-Style/ (see Chroma/docs/PLUGIN-STANDARD.md).
 * Call `bootstrapStyle({ cva, cx })` once at startup with WASM engine helpers.
 */

import { createVariants, createPresets } from "./variants.js";

const STYLESHEETS = ["tokens.css", "utilities.css"];

/** Available utility class names (for docs / autocomplete). */
export const utilityClasses = {
    background: [
        "bg-background", "bg-foreground", "bg-card", "bg-primary", "bg-secondary",
        "bg-muted", "bg-accent", "bg-destructive", "bg-transparent",
    ],
    text: [
        "text-foreground", "text-card-foreground", "text-primary", "text-primary-foreground",
        "text-secondary-foreground", "text-muted-foreground", "text-accent-foreground",
        "text-destructive", "text-destructive-foreground", "text-center",
        "text-xs", "text-sm", "text-base", "text-lg", "text-xl", "text-2xl",
        "font-sans", "font-normal", "font-medium", "font-semibold", "font-bold",
    ],
    border: [
        "border", "border-0", "border-2", "border-input", "border-destructive", "border-transparent",
    ],
    rounded: [
        "rounded-none", "rounded-sm", "rounded-md", "rounded-lg", "rounded-xl", "rounded-2xl", "rounded-full",
    ],
    shadow: ["shadow-none", "shadow-sm", "shadow-md", "shadow-lg", "shadow-xl"],
    layout: [
        "flex", "inline-flex", "flex-col", "items-center", "justify-center", "justify-between",
        "gap-1", "gap-2", "gap-4", "w-full",
    ],
    spacing: [
        "p-2", "p-4", "px-2", "px-3", "px-4", "py-1", "py-2",
        "m-0", "mt-2", "mt-4", "mb-2", "mb-4",
    ],
    interaction: [
        "transition-colors", "focus-ring", "is-disabled",
        "disabled:opacity-50", "disabled:pointer-events-none",
    ],
    components: [
        "cs-card", "cs-btn", "cs-btn-primary", "cs-btn-secondary", "cs-btn-outline",
        "cs-btn-ghost", "cs-btn-destructive", "cs-btn-sm", "cs-btn-md", "cs-btn-lg",
    ],
    animate: ['data-animate="fade-up"', 'data-animate="fade-in"', 'data-animate="scale-in"'],
    presets: ["button", "badge", "card", "input"],
};

/** Injects tokens.css + utilities.css into document.head (idempotent). */
export function injectStyles() {
    if (typeof document === "undefined") return;

    for (const href of STYLESHEETS) {
        const marker = `chroma-style:${href}`;
        if (document.querySelector(`link[data-chroma-plugin="${marker}"]`)) continue;

        const link = document.createElement("link");
        link.rel = "stylesheet";
        link.href = new URL(`./${href}`, import.meta.url).href;
        link.dataset.chromaPlugin = marker;
        document.head.appendChild(link);
    }
}

/**
 * Class-name merger — pass the engine's `cx` for full parity, or use standalone.
 * @param {(...parts: any[]) => string} [cxFn]
 */
export function createTw(cxFn) {
    const merge = cxFn ?? ((...parts) => parts.flat(Infinity).filter(Boolean).join(" "));
    return (...parts) => merge(...parts);
}

export { createVariants, createPresets };

/**
 * Bootstrap: inject CSS. Pass engine `cva`/`cx` to get presets and tw helper.
 * @param {{ cva?: Function, cx?: Function }} [engine]
 */
export function bootstrapStyle(engine = {}) {
    injectStyles();
    const tw = createTw(engine.cx);
    const presets = engine.cva ? createVariants(engine.cva) : null;
    return { tw, presets, utilityClasses, injectStyles, createVariants };
}

/** Chroma plugin contract — see chroma.plugin.json */
export const plugin = {
    name: "chroma-style",
    capabilities: ["styling", "design-tokens"],
    hooks: {
        bootstrap: bootstrapStyle,
        styles: injectStyles,
    },
};

export default plugin;
