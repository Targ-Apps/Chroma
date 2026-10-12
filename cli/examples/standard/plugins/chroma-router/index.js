/**
 * @chroma/router — HTTP-like routing for Chroma apps (browser JS, NOT Node).
 *
 * Reserved methods: GET, POST, PUT, DELETE, CUSTOM.
 * CUSTOM handlers receive (req, operation) where operation comes from
 * the X-Custom-Operation header or req.customOperation.
 */

/** @type {readonly ["GET", "POST", "PUT", "DELETE", "CUSTOM"]} */
export const CHROMA_METHODS = Object.freeze(["GET", "POST", "PUT", "DELETE", "CUSTOM"]);

const METHOD_SET = new Set(CHROMA_METHODS);
const API_PREFIX = "/api";

function chromaRouterDebug(...args) {
    if (globalThis.__CHROMA_DEBUG__) {
        console.log(...args);
    }
}

/**
 * Converts a file path under api/ to a route path.
 * @example filePathToRoute("users/[id]/GET.js") => "/api/users/:id"
 */
export function filePathToRoute(relPath) {
    const methodFile = relPath.split("/").pop() ?? "";
    const method = methodFile.replace(/\.js$/, "");
    if (!METHOD_SET.has(method)) return null;

    let routeDir = relPath.slice(0, -(methodFile.length + 1));
    routeDir = routeDir.replace(/\[([^\]]+)\]/g, ":$1");
    return `/api${routeDir ? `/${routeDir}` : ""}`;
}

/**
 * Parses routes-manifest.json entries into { path, module } pairs.
 * @param {{ routes?: Array<{ path: string, module: string }> }} manifest
 */
export function parseRoutesManifest(manifest) {
    return (manifest.routes ?? []).map((entry) => ({
        path: entry.path,
        module: entry.module,
    }));
}

export class ChromaRouter {
    constructor() {
        /** @type {Array<{ path: string, regex: RegExp, paramNames: string[], handlers: Record<string, Function> }>} */
        this.routes = [];
        /** @type {Map<string, { path: string, regex: RegExp, paramNames: string[], handlers: Record<string, Function> }>} */
        this._byPath = new Map();
        this._hasApiRoutes = false;
    }

    /**
     * @param {string} pathname
     * @returns {{ route: { path: string, regex: RegExp, paramNames: string[], handlers: Record<string, Function> }, match: RegExpExecArray } | null}
     */
    _matchPathname(pathname) {
        for (const route of this.routes) {
            const match = route.regex.exec(pathname);
            if (match) return { route, match };
        }
        return null;
    }

    /**
     * @param {string} routePath e.g. "/api/users/:id"
     * @param {Record<string, Function>} handlers module with GET, POST, …
     */
    registerRoute(routePath, handlers) {
        const existing = this._byPath.get(routePath);
        if (existing) {
            Object.assign(existing.handlers, handlers);
            return;
        }

        const paramNames = [];
        const regexString = routePath.replace(/:([^/]+)/g, (_, key) => {
            paramNames.push(key);
            return "([^/]+)";
        });

        const entry = {
            path: routePath,
            regex: new RegExp(`^${regexString}$`),
            paramNames,
            handlers: { ...handlers },
        };
        this._byPath.set(routePath, entry);
        this.routes.push(entry);
        if (routePath === API_PREFIX || routePath.startsWith(`${API_PREFIX}/`)) {
            this._hasApiRoutes = true;
        }
    }

    /**
     * @param {Array<{ path: string, handlers: Record<string, Function> }>} entries
     */
    registerRoutes(entries) {
        for (const { path, handlers } of entries) {
            this.registerRoute(path, handlers);
        }
    }

    /**
     * Dynamic import by manifest paths.
     * @param {Array<{ path: string, module: string }>} entries
     */
    async loadFromManifest(entries) {
        const byPath = new Map();

        for (const { path, module: mod } of entries) {
            const handlers = await import(mod);
            const routePath = path.includes("/api") ? path : `/api${path.startsWith("/") ? path : `/${path}`}`;
            if (!byPath.has(routePath)) byPath.set(routePath, {});
            Object.assign(byPath.get(routePath), handlers);
        }

        for (const [routePath, handlers] of byPath) {
            this.registerRoute(routePath, handlers);
        }
    }

    /**
     * @param {string} method
     * @param {string} url
     * @param {any} [body]
     * @param {string | null} [customOperation]
     */
    async dispatch(method, url, body = null, customOperation = null) {
        const upper = method.toUpperCase();
        if (!METHOD_SET.has(upper)) {
            return { status: 405, error: `Method ${method} Not Allowed` };
        }

        const urlObj = new URL(url, typeof window !== "undefined" ? window.location.origin : "http://localhost");
        const path = urlObj.pathname;
        const query = Object.fromEntries(urlObj.searchParams.entries());

        const matched = this._matchPathname(path);
        if (!matched) {
            return { status: 404, error: "Not Found" };
        }

        const { route, match } = matched;
        const params = {};
        route.paramNames.forEach((name, i) => {
            params[name] = match[i + 1];
        });

        const handler = route.handlers[upper];
        if (!handler) {
            return { status: 405, error: `Method ${upper} Not Allowed on ${path}` };
        }

        const req = { method: upper, url, path, params, query, body, customOperation };

        try {
            const response =
                upper === "CUSTOM" ? await handler(req, customOperation) : await handler(req);
            return response ?? { status: 200, message: "OK" };
        } catch (err) {
            console.error(`[ChromaRouter] ${upper} ${path}:`, err);
            return { status: 500, error: err?.message ?? String(err) };
        }
    }

    /** Intercept local fetch calls matching registered routes. */
    hijackFetch() {
        if (typeof window === "undefined" || this.routes.length === 0) return;
        const originalFetch = window.fetch.bind(window);
        const origin = window.location.origin;

        window.fetch = async (input, init = {}) => {
            const url = typeof input === "string" ? input : input.url;
            const pathname = url.startsWith("http://") || url.startsWith("https://")
                ? new URL(url).pathname
                : new URL(url, origin).pathname;

            if (this._hasApiRoutes && !pathname.startsWith(API_PREFIX)) {
                return originalFetch(input, init);
            }
            if (!this._matchPathname(pathname)) {
                return originalFetch(input, init);
            }

            const method = (init.method || "GET").toUpperCase();
            let body = null;
            if (init.body) {
                try {
                    body = typeof init.body === "string" ? JSON.parse(init.body) : init.body;
                } catch {
                    body = init.body;
                }
            }

            const headers = init.headers instanceof Headers
                ? Object.fromEntries(init.headers.entries())
                : init.headers ?? {};

            const customOp =
                headers["X-Custom-Operation"] ??
                headers["x-custom-operation"] ??
                null;

            if (METHOD_SET.has(method)) {
                const result = await this.dispatch(method, url, body, customOp);
                return new Response(JSON.stringify(result), {
                    status: result.status || 200,
                    headers: { "Content-Type": "application/json" },
                });
            }

            return originalFetch(input, init);
        };

        chromaRouterDebug("[ChromaRouter] fetch hijack active for local API routes.");
    }
}

/** @returns {ChromaRouter} */
export function createRouter() {
    return new ChromaRouter();
}

/**
 * Bootstrap router from routes-manifest.json and optionally hijack fetch.
 * @param {{ manifestUrl?: string, manifest?: object, hijackFetch?: boolean }} [options]
 */
export async function bootstrapRouter(options = {}) {
    const router = createRouter();
    const { manifestUrl = "./api/routes-manifest.json", hijackFetch: hijack = true } = options;

    let manifest = options.manifest;
    if (!manifest) {
        try {
            const res = await fetch(manifestUrl, { cache: "no-store" });
            if (res.ok) manifest = await res.json();
        } catch {
            /* no manifest — caller may register routes manually */
        }
    }

    if (manifest?.routes?.length) {
        await router.loadFromManifest(parseRoutesManifest(manifest));
    }

    if (hijack) router.hijackFetch();
    return router;
}

/** Chroma plugin contract — see chroma.plugin.json */
export const plugin = {
    name: "chroma-router",
    capabilities: ["routing", "fetch-intercept"],
    hooks: {
        bootstrap: bootstrapRouter,
    },
};

export default plugin;
