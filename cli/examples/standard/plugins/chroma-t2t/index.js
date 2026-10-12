/**
 * @chroma/t2t — test-to-test utilities for Chroma apps.
 *
 * Canonical source: Chroma-t2t/ (see Chroma/docs/PLUGIN-STANDARD.md).
 * Provides Node test bridge, snapshot smoke checks, and persist round-trip helpers.
 */

import {
    assertPersistRoundTrip,
    createPersistRoundTrip,
    createSnapshotSmoke,
    smokeSnapshot,
} from "./helpers.js";

const DEFAULT_GLOBAL_KEY = "__chromaT2t";

/**
 * @typedef {import("./helpers.js").PersistAdapters} PersistAdapters
 * @typedef {import("./helpers.js").PersistRoundTripOptions} PersistRoundTripOptions
 */

/**
 * @typedef {object} BootstrapT2tOptions
 * @property {boolean} [exposeGlobal=true]
 * @property {string} [globalKey="__chromaT2t"]
 * @property {{ adapters: PersistAdapters, seed?: Record<string, unknown>, verify?: (snapshot: object) => void }} [persist]
 * @property {{ getSnapshot: () => object, collectionKeys: string[] }} [snapshot]
 * @property {{ projectRoot?: string, command?: string, script?: string }} [node]
 */

/**
 * Run Node test suite via child_process (Node-only).
 * In browser contexts returns usage info without spawning.
 * @param {{ projectRoot?: string, command?: string, args?: string[] }} [options]
 */
export async function runNodeTests(options = {}) {
    const command = options.command ?? "npm test";
    const projectRoot = options.projectRoot ?? process.cwd?.();

    if (typeof process === "undefined" || !process.versions?.node) {
        return {
            ok: false,
            skipped: true,
            reason: "runNodeTests requires Node.js — use npm test or node plugins/chroma-t2t/node/run-tests.mjs",
            command,
            projectRoot,
        };
    }

    const { spawn } = await import("node:child_process");
    const [bin, ...args] = command.split(/\s+/);

    return new Promise((resolve) => {
        const child = spawn(bin, args, {
            cwd: projectRoot,
            stdio: "inherit",
            shell: true,
        });

        child.on("exit", (code) => {
            if (code === 0) resolve({ ok: true, command, projectRoot });
            else resolve({ ok: false, command, projectRoot, exitCode: code ?? 1 });
        });
    });
}

/**
 * Build the t2t API from bootstrap options.
 * @param {BootstrapT2tOptions} [options]
 */
export function createTestApi(options = {}) {
    const nodeOpts = options.node ?? {};
    const npmTestCommand = nodeOpts.command ?? "npm test";
    const npmTestScript =
        nodeOpts.script ?? "node plugins/chroma-t2t/node/run-tests.mjs";

    const assertPersist =
        options.persist?.adapters
            ? createPersistRoundTrip(options.persist.adapters, {
                  seed: options.persist.seed,
                  verify: options.persist.verify,
              })
            : async () => ({
                  ok: false,
                  skipped: true,
                  reason: "No persist adapters configured — pass options.persist.adapters to bootstrapT2t.",
              });

    const smoke =
        options.snapshot?.getSnapshot && options.snapshot?.collectionKeys
            ? createSnapshotSmoke(
                  options.snapshot.getSnapshot,
                  options.snapshot.collectionKeys,
              )
            : () => ({
                  ok: false,
                  skipped: true,
                  reason: "No snapshot hook configured — pass options.snapshot to bootstrapT2t.",
              });

    async function runAll(runOptions = {}) {
        const results = { smoke: null, persist: null, node: null };

        const smokeFn = runOptions.smokeSnapshot ?? smoke;
        const persistFn = runOptions.assertPersistRoundTrip ?? assertPersist;

        results.smoke = smokeFn();
        results.persist = await persistFn();

        if (runOptions.includeNodeTests) {
            results.node = await runNodeTests({
                projectRoot: nodeOpts.projectRoot,
                command: npmTestCommand,
            });
            if (!results.node.ok && !results.node.skipped) {
                throw new Error(`Node tests failed (exit ${results.node.exitCode}).`);
            }
        }

        if (results.smoke?.skipped === true && results.persist?.skipped === true) {
            throw new Error(
                "runAll: configure options.snapshot and/or options.persist before calling runAll().",
            );
        }

        return { ok: true, results };
    }

    return {
        smokeSnapshot: smoke,
        assertPersistRoundTrip: assertPersist,
        runNodeTests: (overrides = {}) =>
            runNodeTests({
                projectRoot: nodeOpts.projectRoot,
                command: npmTestCommand,
                ...overrides,
            }),
        runAll,
        npmTestCommand,
        npmTestScript,
    };
}

/**
 * Bootstrap dev/test utilities for Chroma apps.
 * @param {BootstrapT2tOptions} [options]
 */
export async function bootstrapT2t(options = {}) {
    const globalKey = options.globalKey ?? DEFAULT_GLOBAL_KEY;
    const api = createTestApi(options);

    if (options.exposeGlobal !== false && typeof globalThis !== "undefined") {
        globalThis[globalKey] = api;
    }

    if (typeof console !== "undefined") {
        console.info(
            `[chroma-t2t] Ready — globalThis.${globalKey}.runAll() or ${api.npmTestCommand}`,
        );
    }

    return api;
}

export {
    assertPersistRoundTrip,
    createPersistRoundTrip,
    createSnapshotSmoke,
    smokeSnapshot,
};

/** Chroma plugin contract — see chroma.plugin.json */
export const plugin = {
    name: "chroma-t2t",
    capabilities: ["testing", "dev-tools"],
    hooks: {
        bootstrap: bootstrapT2t,
    },
};

export default plugin;
