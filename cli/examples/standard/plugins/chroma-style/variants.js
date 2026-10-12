/**
 * shadcn-style component variant presets, built on top of Chroma's own
 * `cva`/`cx` (see Chroma/src/variants.rs) instead of a separate JS reimplementation.
 *
 * `cva` is injected rather than imported from a fixed relative path, because
 * this plugin gets vendored into apps at an arbitrary depth.
 */
export function createVariants(cva) {
    const button = cva({
        base: "inline-flex items-center justify-center gap-2 rounded-md text-sm font-medium transition-colors focus-ring disabled:opacity-50 disabled:pointer-events-none border",
        variants: {
            variant: {
                primary: "bg-primary text-primary-foreground border-transparent",
                secondary: "bg-secondary text-secondary-foreground border-transparent",
                outline: "bg-transparent text-foreground border-input",
                ghost: "bg-transparent text-foreground border-transparent",
                destructive: "bg-destructive text-destructive-foreground border-transparent",
            },
            size: {
                sm: "px-3 py-1 text-xs",
                md: "px-4 py-2 text-sm",
                lg: "px-4 py-2 text-base",
            },
        },
        defaultVariants: { variant: "primary", size: "md" },
    });

    const badge = cva({
        base: "inline-flex items-center gap-1 rounded-full border px-2 py-1 text-xs font-semibold",
        variants: {
            variant: {
                default: "bg-primary text-primary-foreground border-transparent",
                secondary: "bg-secondary text-secondary-foreground border-transparent",
                outline: "bg-transparent text-foreground border-input",
                destructive: "bg-destructive text-destructive-foreground border-transparent",
            },
        },
        defaultVariants: { variant: "default" },
    });

    const card = cva({
        base: "bg-card text-card-foreground rounded-xl border",
        variants: {
            padding: {
                none: "",
                sm: "px-3 py-2",
                md: "px-4 py-4",
            },
            shadow: {
                none: "shadow-none",
                sm: "shadow-sm",
                md: "shadow-md",
                lg: "shadow-lg",
            },
        },
        defaultVariants: { padding: "md", shadow: "sm" },
    });

    const input = cva({
        base: "bg-background text-foreground border-input rounded-md px-3 py-2 text-sm focus-ring disabled:opacity-50 disabled:pointer-events-none border w-full",
        variants: {
            invalid: {
                true: "border-destructive",
            },
        },
    });

    return { button, badge, card, input };
}

/** @deprecated Use createVariants — kept for older examples. */
export const createPresets = createVariants;
