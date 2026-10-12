/**
 * @chroma/t2t — generic test helpers for Chroma apps.
 *
 * Migrated from Targ-Apps-Finance/plugins/chroma-test/helpers.js and generalized
 * to accept app-provided adapters instead of hard-coded finance imports.
 */

/**
 * @typedef {object} PersistAdapters
 * @property {() => void} reset
 * @property {() => unknown} createMemoryStorage
 * @property {(opts: { storage: unknown }) => Promise<void>} hydrate
 * @property {(key: string, value: unknown) => void} setPersisted
 * @property {() => Promise<void>} flush
 * @property {() => object} getSnapshot
 * @property {() => object} buildExportPayload
 * @property {(payload: object) => string} serializeExport
 * @property {(text: string) => { ok: boolean, data?: object, error?: string }} parseImport
 * @property {(data: object) => { valid: boolean, error?: string }} validateImport
 * @property {(data: object) => void} applyImport
 */

/**
 * @typedef {object} PersistRoundTripOptions
 * @property {Record<string, unknown>} [seed] Key/value pairs passed to setPersisted before flush.
 * @property {(snapshot: object) => void} [verify] Called after re-import; throw to fail.
 */

/**
 * Assert export → reset → import round-trip through chroma-fs style persistence.
 * @param {PersistAdapters} adapters
 * @param {PersistRoundTripOptions} [options]
 */
export async function assertPersistRoundTrip(adapters, options = {}) {
    const {
        reset,
        createMemoryStorage,
        hydrate,
        setPersisted,
        flush,
        getSnapshot,
        buildExportPayload,
        serializeExport,
        parseImport,
        validateImport,
        applyImport,
    } = adapters;

    if (!reset || !createMemoryStorage || !hydrate || !setPersisted || !flush) {
        throw new Error("assertPersistRoundTrip: missing required persist adapters.");
    }
    if (!getSnapshot || !buildExportPayload || !serializeExport) {
        throw new Error("assertPersistRoundTrip: missing export/snapshot adapters.");
    }
    if (!parseImport || !validateImport || !applyImport) {
        throw new Error("assertPersistRoundTrip: missing import adapters.");
    }

    reset();
    const fs = createMemoryStorage();
    await hydrate({ storage: fs });

    const seed = options.seed ?? {};
    for (const [key, value] of Object.entries(seed)) {
        setPersisted(key, value);
    }
    await flush();

    const text = serializeExport(buildExportPayload());

    reset();
    await hydrate({ storage: fs });

    const parsed = parseImport(text);
    if (!parsed.ok) throw new Error(parsed.error ?? "Import parse failed.");
    const validation = validateImport(parsed.data);
    if (!validation.valid) throw new Error(validation.error ?? "Import validation failed.");
    applyImport(parsed.data);
    await flush();

    const snapshot = getSnapshot();
    if (options.verify) {
        options.verify(snapshot);
    }

    return { ok: true, snapshot };
}

/**
 * Smoke-check that snapshot collections are arrays.
 * @param {object} snapshot
 * @param {string[]} collectionKeys
 */
export function smokeSnapshot(snapshot, collectionKeys) {
    if (!snapshot || typeof snapshot !== "object") {
        throw new Error("Smoke failed: snapshot must be an object.");
    }

    for (const key of collectionKeys) {
        if (!Array.isArray(snapshot[key])) {
            throw new Error(`Smoke failed: ${key} must be an array.`);
        }
    }

    return {
        ok: true,
        counts: Object.fromEntries(collectionKeys.map((key) => [key, snapshot[key].length])),
    };
}

/**
 * Bind adapters into a single assertPersistRoundTrip function.
 * @param {PersistAdapters} adapters
 * @param {PersistRoundTripOptions} [defaults]
 */
export function createPersistRoundTrip(adapters, defaults = {}) {
    return (overrides = {}) =>
        assertPersistRoundTrip(adapters, { ...defaults, ...overrides });
}

/**
 * Bind getSnapshot + collection keys into a smokeSnapshot function.
 * @param {() => object} getSnapshot
 * @param {string[]} collectionKeys
 */
export function createSnapshotSmoke(getSnapshot, collectionKeys) {
    return (snapshot) => smokeSnapshot(snapshot ?? getSnapshot(), collectionKeys);
}
