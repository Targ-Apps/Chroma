#!/usr/bin/env node
/**
 * Runs the host Chroma app's Node test suite (node --test).
 *
 * Usage (from project root with vendored plugin):
 *   node plugins/chroma-t2t/node/run-tests.mjs
 *
 * Usage (from Chroma-t2t canonical source, three levels up = workspace root):
 *   node Chroma-t2t/node/run-tests.mjs
 *
 * Set CHROMA_T2T_PROJECT_ROOT to override the detected project root.
 */
import { spawn } from "node:child_process";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";

const here = dirname(fileURLToPath(import.meta.url));
const defaultRoot = join(here, "../../..");
const projectRoot = resolve(process.env.CHROMA_T2T_PROJECT_ROOT ?? defaultRoot);
const testCommand = process.env.CHROMA_T2T_TEST_COMMAND ?? "npm test";

const [bin, ...args] = testCommand.split(/\s+/);

const child = spawn(bin, args, {
    cwd: projectRoot,
    stdio: "inherit",
    shell: true,
});

child.on("exit", (code) => {
    process.exit(code ?? 1);
});
