#!/usr/bin/env node
/** Tests of the JS grammar (lib/, used at runtime by tw.js) and of twMerge: `node test/selftest.mjs`. No dependencies.
 *  The build-time generator is the native Rust plugin chroma-style; it is checked against this grammar by byte-parity fixtures. */
import { compile, sortRules, printRules } from "../lib/generate.mjs";
import { twMerge } from "../tw.js";

let fail = 0;
const css = (cls) => { const r = compile(cls, {}); return r ? printRules(sortRules(r), { minify: true }) : null; };
const expect = (cls, ...parts) => {
  const out = css(cls);
  const ok = out && parts.every((p) => out.includes(p));
  if (!ok) { fail++; console.error(`FAIL ${cls}\n  got: ${out}\n  want: ${parts.join(" ... ")}`); }
};
const unknown = (cls) => { if (css(cls)) { fail++; console.error(`FAIL ${cls} deberia ser desconocida`); } };

// escala y valores
expect("p-4", "padding:calc(var(--spacing) * 4)"); expect("p-px", "padding:1px"); expect("-mx-1", "margin-inline:calc(var(--spacing) * -1)");
expect("w-1/2", "width:calc(1 / 2 * 100%)"); expect("top-1/2", "top:calc(1 / 2 * 100%)"); expect("h-screen", "height:100vh");
expect("max-w-2xl", "max-width:var(--container-2xl)"); expect("gap-(--gap)", "gap:var(--gap)"); expect("lg:-ml-[30%]", "margin-left:calc(30% * -1)");
expect("w-[calc(100%+0.5rem)]", "width:calc(100% + 0.5rem)"); expect("max-h-[min(70vh,24rem)]", "max-height:min(70vh, 24rem)");
expect("grid-cols-[1.1fr_1fr]", "grid-template-columns:1.1fr 1fr"); expect("[--gap:1rem]", "--gap:1rem"); expect("[mask-type:alpha]", "mask-type:alpha");
// color
expect("bg-primary", "background-color:var(--primary)"); expect("bg-primary/80", "color-mix(in oklab, var(--primary) 80%, transparent)");
expect("text-white/65", "var(--color-white) 65%"); expect("bg-[#0088cc]", "background-color:#0088cc"); expect("bg-red-500", "var(--color-red-500)");
expect("text-[13vw]", "font-size:13vw"); expect("text-[color:red]", "color:red"); expect("text-sm", "font-size:var(--text-sm)", "line-height:var(--cs-leading, var(--text-sm--line-height))");
// efectos
expect("shadow-lg", "--cs-shadow:0 10px 15px -3px"); expect("ring-2", "calc(2px + var(--cs-ring-offset-width))"); expect("focus-visible:ring-ring/50", ":focus-visible", "--cs-ring-color:color-mix");
expect("bg-linear-to-br", "to bottom right in oklab"); expect("from-primary", "--cs-gradient-from:var(--primary)"); expect("backdrop-blur-md", "blur(var(--blur-md))");
expect("translate-y-2", "--cs-translate-y:calc(var(--spacing) * 2)", "translate:var(--cs-translate-x) var(--cs-translate-y)"); expect("scale-105", "--cs-scale-x:105%");
expect("animate-spin", "animation:spin 1s linear infinite"); expect("animate-in", "animation:enter"); expect("fade-in", "--cs-enter-opacity:0"); expect("slide-in-from-top-2", "--cs-enter-translate-y:calc(var(--spacing) * -2)");
expect("size-3!", "width:calc(var(--spacing) * 3) !important");
// variantes
expect("hover:bg-muted", "@media (hover: hover){.hover\\:bg-muted:hover{"); expect("md:flex", "@media (width >= 48rem)"); expect("max-md:hidden", "@media (width < 48rem)");
expect("dark:bg-input/30", ':is(.dark *, [data-theme="dark"] *)'); expect("group-hover:opacity-80", ":is(:where(.group):hover *)"); expect("group-hover/btn:text-white", ":where(.group\\/btn):hover");
expect("peer-checked:block", ":is(:where(.peer):checked ~ *)"); expect("data-[state=open]:flex", '[data-state="open"]'); expect("data-horizontal:h-px", '[data-orientation="horizontal"]');
expect("aria-expanded:bg-muted", '[aria-expanded="true"]'); expect("has-data-[icon=inline-end]:pr-2", ':has([data-icon="inline-end"])'); expect("in-data-[slot=button-group]:rounded-lg", ':where([data-slot="button-group"]) ');
expect("active:not-aria-[haspopup]:translate-y-px", ":active:not([aria-haspopup])"); expect("before:absolute", "::before", "content:var(--cs-content)"); expect("[&_svg]:shrink-0", " svg{");
expect("[&>svg]:size-3", " > svg{"); expect("motion-safe:group-hover/visual:scale-105", "@media (prefers-reduced-motion: no-preference){@media (hover: hover){");
// orden: variantes responsive despues de las base, y mas grandes despues
{
  const r = sortRules(["md:p-2", "p-4", "lg:p-6", "hover:p-3"].flatMap((c) => compile(c, {}))).map((x) => x.token);
  if (r.join() !== "p-4,hover:p-3,md:p-2,lg:p-6") { fail++; console.error("FAIL orden de variantes:", r.join()); }
}
unknown("not-a-utility"); unknown("bg-nonexistent"); unknown("text-xyz");

// twMerge
const t = (input, want) => { const got = twMerge(input); if (got !== want) { fail++; console.error(`FAIL twMerge(${JSON.stringify(input)}) = ${JSON.stringify(got)}, want ${JSON.stringify(want)}`); } };
t("p-4 px-2", "p-4 px-2"); t("px-2 p-4", "p-4"); t("bg-red-500 hover:bg-red-600 bg-primary", "hover:bg-red-600 bg-primary"); t("text-red-500 text-lg text-white", "text-lg text-white");
t("rounded-md rounded-lg", "rounded-lg"); t("rounded-lg rounded-t-md", "rounded-lg rounded-t-md"); t("h-9 size-8", "size-8"); t("md:flex md:hidden flex", "md:hidden flex");
t("group/btn foo p-2 p-3 custom", "group/btn foo p-3 custom"); t("shadow-lg ring-2 shadow-md", "ring-2 shadow-md"); t("w-full !w-4 w-2", "!w-4 w-2"); t("ml-2 mx-4", "mx-4");
t(["a", false, null, ["b", { c: true, d: 0 }]], "a b c");

console.log(fail ? `${fail} fallo(s)` : "chroma-style selftest: OK");
process.exit(fail ? 1 : 0);
