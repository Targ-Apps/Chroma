import { hookState, render, e, cva, cx } from "./pkg/chroma.js";
import { loadPlugins } from "./plugins/loader.js";

const plugins = await loadPlugins();
if (plugins.style) {
    globalThis.__chromaStyle = plugins.style.bootstrapStyle({ cva, cx });
}
globalThis.__chromaPlugins = plugins;

function Counter() {
    const [count, setCount] = hookState(0);
    return e(
        "button",
        { onClick: () => setCount(count() + 1) },
        "Count: ",
        count,
    );
}

function App() {
    return e(
        "main",
        null,
        e("h1", null, "Chroma app"),
        e(Counter),
    );
}

render(App, document.getElementById("app"));
