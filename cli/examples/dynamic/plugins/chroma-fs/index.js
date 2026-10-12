var __defProp = Object.defineProperty;
var __getOwnPropNames = Object.getOwnPropertyNames;
var __esm = (fn, res) => function __init() {
  return fn && (res = (0, fn[__getOwnPropNames(fn)[0]])(fn = 0)), res;
};
var __export = (target, all) => {
  for (var name in all)
    __defProp(target, name, { get: all[name], enumerable: true });
};

// src/path.ts
function normalizePath(path) {
  const trimmed = path.trim().replace(/\\/g, "/");
  if (!trimmed || trimmed === ".") {
    return "";
  }
  const segments = trimmed.split("/").filter((segment) => segment.length > 0 && segment !== ".");
  const stack = [];
  for (const segment of segments) {
    if (segment === "..") {
      stack.pop();
      continue;
    }
    stack.push(segment);
  }
  return stack.join("/");
}
function joinPath(base, path) {
  const normalizedBase = normalizePath(base);
  const normalizedPath = normalizePath(path);
  if (!normalizedBase) {
    return normalizedPath;
  }
  if (!normalizedPath) {
    return normalizedBase;
  }
  return `${normalizedBase}/${normalizedPath}`;
}
function parentPath(path) {
  const normalized = normalizePath(path);
  const index = normalized.lastIndexOf("/");
  return index === -1 ? "" : normalized.slice(0, index);
}
function baseName(path) {
  const normalized = normalizePath(path);
  const index = normalized.lastIndexOf("/");
  return index === -1 ? normalized : normalized.slice(index + 1);
}
function childPath(parent, name) {
  return joinPath(parent, name);
}
function isDirectChild(parent, candidate) {
  const normalizedParent = normalizePath(parent);
  const normalizedCandidate = normalizePath(candidate);
  if (normalizedParent === normalizedCandidate) {
    return false;
  }
  if (!normalizedParent) {
    return !normalizedCandidate.includes("/");
  }
  if (!normalizedCandidate.startsWith(`${normalizedParent}/`)) {
    return false;
  }
  const remainder = normalizedCandidate.slice(normalizedParent.length + 1);
  return remainder.length > 0 && !remainder.includes("/");
}
function stripLeadingSlash(path) {
  return path.replace(LEADING_SLASHES, "");
}
function stripTrailingSlash(path) {
  return path.replace(TRAILING_SLASHES, "");
}
function directoryPrefix(path) {
  const normalized = normalizePath(path);
  return normalized ? `${normalized}/` : "";
}
function toText(data) {
  if (typeof data === "string") {
    return data;
  }
  return new TextDecoder().decode(data);
}
function toBytes(data) {
  if (typeof data === "string") {
    return new TextEncoder().encode(data);
  }
  return data;
}
var LEADING_SLASHES, TRAILING_SLASHES;
var init_path = __esm({
  "src/path.ts"() {
    LEADING_SLASHES = /^\/+/;
    TRAILING_SLASHES = /\/+$/;
  }
});

// src/tauri/fs-wrapper.ts
var fs_wrapper_exports = {};
__export(fs_wrapper_exports, {
  createDefaultTauriFsAdapter: () => createDefaultTauriFsAdapter
});
function resolveRelativePath(basePath, path) {
  const normalizedBase = normalizePath(basePath.replace(/^\.\//, ""));
  const normalizedPath = normalizePath(path);
  return normalizedBase ? normalizedPath ? `${normalizedBase}/${normalizedPath}` : normalizedBase : normalizedPath;
}
async function loadTauriFs() {
  try {
    return await import('@tauri-apps/plugin-fs');
  } catch {
    throw new Error(
      "Filesystem backend requires @tauri-apps/plugin-fs. Install it in the host app and enable the fs plugin in Tauri."
    );
  }
}
async function createDefaultTauriFsAdapter(basePath = "./data") {
  const fs = await loadTauriFs();
  const options = { baseDir: fs.BaseDirectory.AppLocalData };
  const resolve = (path) => resolveRelativePath(basePath, path);
  return {
    async readFile(path) {
      return fs.readFile(resolve(path), options);
    },
    async readTextFile(path) {
      return fs.readTextFile(resolve(path), options);
    },
    async writeFile(path, data) {
      await fs.writeFile(resolve(path), data, options);
    },
    async writeTextFile(path, data) {
      await fs.writeTextFile(resolve(path), data, options);
    },
    async remove(path, removeOptions) {
      await fs.remove(resolve(path), {
        ...options,
        recursive: removeOptions?.recursive ?? false
      });
    },
    async exists(path) {
      return fs.exists(resolve(path), options);
    },
    async readDir(path) {
      const entries = await fs.readDir(resolve(path), options);
      return entries.map((entry) => mapDirEntry(entry));
    },
    async mkdir(path, mkdirOptions) {
      await fs.mkdir(resolve(path), {
        ...options,
        recursive: mkdirOptions?.recursive ?? false
      });
    },
    async stat(path) {
      try {
        const stat = await fs.stat(resolve(path), options);
        return mapStat(stat);
      } catch {
        return null;
      }
    }
  };
}
function mapDirEntry(entry) {
  return {
    name: entry.name,
    isDirectory: entry.isDirectory,
    isFile: entry.isFile
  };
}
function mapStat(stat) {
  return {
    isDirectory: stat.isDirectory,
    isFile: stat.isFile,
    size: stat.size,
    mtime: stat.mtime ? stat.mtime.getTime() : null
  };
}
var init_fs_wrapper = __esm({
  "src/tauri/fs-wrapper.ts"() {
    init_path();
  }
});

// src/backends/filesystem.ts
init_path();
var FilesystemStorage = class _FilesystemStorage {
  basePath;
  adapter;
  constructor(options) {
    this.basePath = options.basePath;
    this.adapter = options.adapter;
  }
  static async create(options) {
    const { createDefaultTauriFsAdapter: createDefaultTauriFsAdapter2 } = await Promise.resolve().then(() => (init_fs_wrapper(), fs_wrapper_exports));
    const adapter = options.adapter ?? await createDefaultTauriFsAdapter2(options.basePath);
    return new _FilesystemStorage({
      ...options,
      adapter
    });
  }
  async readFile(path) {
    const normalizedPath = normalizePath(path);
    if (!await this.adapter.exists(normalizedPath)) {
      throw new Error(`File not found: ${normalizedPath}`);
    }
    return this.adapter.readFile(normalizedPath);
  }
  async readText(path) {
    const normalizedPath = normalizePath(path);
    if (!await this.adapter.exists(normalizedPath)) {
      throw new Error(`File not found: ${normalizedPath}`);
    }
    return this.adapter.readTextFile(normalizedPath);
  }
  async writeFile(path, data) {
    const normalizedPath = normalizePath(path);
    await this.ensureParentDirectories(normalizedPath);
    if (typeof data === "string") {
      await this.adapter.writeTextFile(normalizedPath, data);
      return;
    }
    await this.adapter.writeFile(normalizedPath, toBytes(data));
  }
  async delete(path) {
    const normalizedPath = normalizePath(path);
    if (!await this.adapter.exists(normalizedPath)) {
      return;
    }
    const stat = await this.adapter.stat(normalizedPath);
    if (stat?.isDirectory) {
      const children = await this.list(normalizedPath);
      if (children.length > 0) {
        throw new Error(`Directory not empty: ${normalizedPath}`);
      }
    }
    await this.adapter.remove(normalizedPath);
  }
  async exists(path) {
    return this.adapter.exists(normalizePath(path));
  }
  async list(path = "") {
    const normalizedPath = normalizePath(path);
    const entries = await this.adapter.readDir(normalizedPath);
    return entries.map((entry) => ({
      name: entry.name,
      path: childPath(normalizedPath, entry.name),
      kind: entry.isDirectory ? "directory" : "file"
    })).sort((left, right) => left.name.localeCompare(right.name));
  }
  async mkdir(path) {
    const normalizedPath = normalizePath(path);
    if (!normalizedPath) {
      throw new Error("Cannot create the root directory.");
    }
    if (await this.adapter.exists(normalizedPath)) {
      const stat = await this.adapter.stat(normalizedPath);
      if (stat?.isFile) {
        throw new Error(`Path already exists as a file: ${normalizedPath}`);
      }
      return;
    }
    await this.adapter.mkdir(normalizedPath, { recursive: true });
  }
  async rmdir(path, options) {
    const normalizedPath = normalizePath(path);
    if (!await this.adapter.exists(normalizedPath)) {
      return;
    }
    const stat = await this.adapter.stat(normalizedPath);
    if (!stat?.isDirectory) {
      throw new Error(`Not a directory: ${normalizedPath}`);
    }
    await this.adapter.remove(normalizedPath, {
      recursive: options?.recursive ?? false
    });
  }
  async stat(path) {
    const normalizedPath = normalizePath(path);
    const stat = await this.adapter.stat(normalizedPath);
    if (!stat) {
      return null;
    }
    return {
      name: normalizedPath.split("/").pop() ?? normalizedPath,
      path: normalizedPath,
      kind: stat.isDirectory ? "directory" : "file",
      ...stat.isFile ? { size: stat.size } : {},
      ...stat.mtime != null ? { modifiedAt: stat.mtime } : {}
    };
  }
  async ensureParentDirectories(path) {
    const parent = parentPath(path);
    if (!parent || await this.adapter.exists(parent)) {
      return;
    }
    await this.adapter.mkdir(parent, { recursive: true });
  }
};
async function createFilesystemStorage(options) {
  return FilesystemStorage.create(options);
}

// src/backends/indexeddb.ts
init_path();
var IndexedDbStorage = class {
  dbName;
  storeName;
  dbPromise = null;
  constructor(options) {
    this.dbName = options.dbName;
    this.storeName = options.storeName;
  }
  async readFile(path) {
    const record = await this.getRecord(path);
    if (!record || record.kind !== "file") {
      throw new Error(`File not found: ${normalizePath(path)}`);
    }
    return record.content ? new Uint8Array(record.content) : new Uint8Array();
  }
  async readText(path) {
    const bytes = await this.readFile(path);
    return toText(bytes);
  }
  async writeFile(path, data) {
    const normalizedPath = normalizePath(path);
    await this.ensureParentDirectories(normalizedPath);
    const content = toBytes(data);
    await this.putRecord(normalizedPath, {
      kind: "file",
      content,
      modifiedAt: Date.now(),
      size: content.byteLength
    });
  }
  async delete(path) {
    const normalizedPath = normalizePath(path);
    const record = await this.getRecord(normalizedPath);
    const children = await this.list(normalizedPath);
    if (!record) {
      if (children.length > 0) {
        throw new Error(`Directory not empty: ${normalizedPath}`);
      }
      return;
    }
    if (record.kind === "directory" && children.length > 0) {
      throw new Error(`Directory not empty: ${normalizedPath}`);
    }
    await this.deleteRecord(normalizedPath);
  }
  async exists(path) {
    const record = await this.getRecord(path);
    return record != null;
  }
  async list(path = "") {
    const normalizedPath = normalizePath(path);
    const prefix = directoryPrefix(normalizedPath);
    const records = await this.getAllRecords();
    const entries = /* @__PURE__ */ new Map();
    for (const [recordPath, record] of records) {
      if (prefix && !recordPath.startsWith(prefix)) {
        continue;
      }
      const relativePath = prefix ? recordPath.slice(prefix.length) : recordPath;
      if (!relativePath) {
        continue;
      }
      const slashIndex = relativePath.indexOf("/");
      const name = slashIndex === -1 ? relativePath : relativePath.slice(0, slashIndex);
      if (!name || entries.has(name)) {
        continue;
      }
      const entryPath = childPath(normalizedPath, name);
      const directRecord = records.get(entryPath);
      if (directRecord) {
        entries.set(name, this.toEntry(name, entryPath, directRecord));
        continue;
      }
      entries.set(name, {
        name,
        path: entryPath,
        kind: "directory"
      });
    }
    return [...entries.values()].sort(
      (left, right) => left.name.localeCompare(right.name)
    );
  }
  async mkdir(path) {
    const normalizedPath = normalizePath(path);
    if (!normalizedPath) {
      throw new Error("Cannot create the root directory.");
    }
    if (await this.exists(normalizedPath)) {
      const record = await this.getRecord(normalizedPath);
      if (record?.kind === "file") {
        throw new Error(`Path already exists as a file: ${normalizedPath}`);
      }
      return;
    }
    await this.ensureParentDirectories(normalizedPath);
    await this.putRecord(normalizedPath, {
      kind: "directory",
      modifiedAt: Date.now(),
      size: 0
    });
  }
  async rmdir(path, options) {
    const normalizedPath = normalizePath(path);
    const record = await this.getRecord(normalizedPath);
    if (!record) {
      return;
    }
    if (record.kind !== "directory") {
      throw new Error(`Not a directory: ${normalizedPath}`);
    }
    const children = await this.list(normalizedPath);
    if (children.length > 0 && !options?.recursive) {
      throw new Error(`Directory not empty: ${normalizedPath}`);
    }
    if (options?.recursive) {
      for (const child of children) {
        if (child.kind === "directory") {
          await this.rmdir(child.path, { recursive: true });
        } else {
          await this.delete(child.path);
        }
      }
    }
    await this.deleteRecord(normalizedPath);
  }
  async stat(path) {
    const normalizedPath = normalizePath(path);
    const record = await this.getRecord(normalizedPath);
    if (!record) {
      return null;
    }
    return this.toEntry(baseName(normalizedPath), normalizedPath, record);
  }
  get databaseName() {
    return this.dbName;
  }
  async close() {
    if (!this.dbPromise) {
      return;
    }
    const db = await this.dbPromise;
    db.close();
    this.dbPromise = null;
  }
  toEntry(name, path, record) {
    return {
      name,
      path,
      kind: record.kind,
      ...record.kind === "file" ? { size: record.size } : {},
      modifiedAt: record.modifiedAt
    };
  }
  async ensureParentDirectories(path) {
    const parent = parentPath(path);
    if (!parent || await this.exists(parent)) {
      return;
    }
    await this.ensureParentDirectories(parent);
    await this.putRecord(parent, {
      kind: "directory",
      modifiedAt: Date.now(),
      size: 0
    });
  }
  openDb() {
    if (this.dbPromise) {
      return this.dbPromise;
    }
    this.dbPromise = new Promise((resolve, reject) => {
      const request = indexedDB.open(this.dbName, 1);
      request.onupgradeneeded = () => {
        const db = request.result;
        if (!db.objectStoreNames.contains(this.storeName)) {
          db.createObjectStore(this.storeName);
        }
      };
      request.onsuccess = () => resolve(request.result);
      request.onerror = () => reject(request.error ?? new Error("Unable to open IndexedDB."));
    });
    return this.dbPromise;
  }
  async withStore(mode, run) {
    const db = await this.openDb();
    return new Promise((resolve, reject) => {
      const transaction = db.transaction(this.storeName, mode);
      const store = transaction.objectStore(this.storeName);
      const result = run(store);
      if (result instanceof Promise) {
        result.then(resolve).catch(reject);
        return;
      }
      let value;
      result.onsuccess = () => {
        value = result.result;
        if (mode === "readonly") {
          resolve(value);
        }
      };
      transaction.oncomplete = () => {
        if (mode === "readwrite") {
          resolve(value);
        }
      };
      result.onerror = () => reject(result.error ?? new Error("IndexedDB request failed."));
      transaction.onerror = () => reject(transaction.error ?? new Error("IndexedDB transaction failed."));
    });
  }
  async getRecord(path) {
    const normalizedPath = normalizePath(path);
    const record = await this.withStore(
      "readonly",
      (store) => store.get(normalizedPath)
    );
    return record ?? null;
  }
  async putRecord(path, record) {
    const normalizedPath = normalizePath(path);
    await this.withStore("readwrite", (store) => store.put(record, normalizedPath));
  }
  async deleteRecord(path) {
    const normalizedPath = normalizePath(path);
    await this.withStore("readwrite", (store) => store.delete(normalizedPath));
  }
  async getAllRecords() {
    const db = await this.openDb();
    return new Promise((resolve, reject) => {
      const transaction = db.transaction(this.storeName, "readonly");
      const store = transaction.objectStore(this.storeName);
      const keysRequest = store.getAllKeys();
      const valuesRequest = store.getAll();
      valuesRequest.onsuccess = () => {
        const keys = keysRequest.result;
        const values = valuesRequest.result;
        const records = /* @__PURE__ */ new Map();
        for (let index = 0; index < keys.length; index += 1) {
          const key = String(keys[index]);
          const value = values[index];
          if (value) {
            records.set(key, value);
          }
        }
        resolve(records);
      };
      keysRequest.onerror = () => reject(keysRequest.error ?? new Error("IndexedDB request failed."));
      valuesRequest.onerror = () => reject(valuesRequest.error ?? new Error("IndexedDB request failed."));
      transaction.onerror = () => reject(transaction.error ?? new Error("IndexedDB transaction failed."));
    });
  }
};
function createIndexedDbStorage(options) {
  return new IndexedDbStorage(options);
}

// src/bridge/post-message-adapter.ts
var CHANNEL = "chroma-fs";
var requestCounter = 0;
function nextId() {
  requestCounter += 1;
  return `${Date.now()}-${requestCounter}`;
}
function bytesToBase64(bytes) {
  let binary = "";
  for (const byte of bytes) {
    binary += String.fromCharCode(byte);
  }
  return btoa(binary);
}
function base64ToBytes(base64) {
  const binary = atob(base64);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i += 1) {
    bytes[i] = binary.charCodeAt(i);
  }
  return bytes;
}
function getTargetWindow() {
  if (typeof window === "undefined") {
    throw new Error("postMessage bridge requires a browser environment.");
  }
  return window.parent;
}
function createPostMessageAdapter() {
  const pending = /* @__PURE__ */ new Map();
  if (typeof window !== "undefined") {
    window.addEventListener("message", (event) => {
      const data = event.data;
      if (!data || data.channel !== CHANNEL || !data.id) {
        return;
      }
      const handler = pending.get(data.id);
      if (!handler) {
        return;
      }
      pending.delete(data.id);
      if (data.ok) {
        handler.resolve(data.result);
      } else {
        handler.reject(new Error(data.error ?? "Chroma-Fs bridge request failed."));
      }
    });
  }
  function send(op, args = {}) {
    const id = nextId();
    const message = { channel: CHANNEL, id, op, args };
    return new Promise((resolve, reject) => {
      pending.set(id, {
        resolve: (value) => resolve(value),
        reject
      });
      try {
        getTargetWindow().postMessage(message, "*");
      } catch (error) {
        pending.delete(id);
        reject(error instanceof Error ? error : new Error(String(error)));
      }
    });
  }
  return {
    async readFile(path) {
      const base64 = await send("readFile", { path });
      return base64ToBytes(base64);
    },
    async readTextFile(path) {
      return send("readTextFile", { path });
    },
    async writeFile(path, data) {
      await send("writeFile", { path, data: bytesToBase64(data) });
    },
    async writeTextFile(path, data) {
      await send("writeTextFile", { path, data });
    },
    async remove(path, options) {
      await send("remove", {
        path,
        recursive: options?.recursive ?? false
      });
    },
    async exists(path) {
      return send("exists", { path });
    },
    async readDir(path) {
      return send("readDir", { path });
    },
    async mkdir(path, options) {
      await send("mkdir", {
        path,
        recursive: options?.recursive ?? false
      });
    },
    async stat(path) {
      return send("stat", { path });
    }
  };
}
function isInIframe() {
  if (typeof window === "undefined") {
    return false;
  }
  try {
    return window.parent !== window;
  } catch {
    return true;
  }
}
function hasTauriRuntime() {
  if (typeof window === "undefined") {
    return false;
  }
  const globals = window;
  return Boolean(globals.__TAURI__ || globals.__TAURI_INTERNALS__);
}

// src/config.ts
var DEFAULT_BASE_PATH = "./data";
var DEFAULT_DB_NAME = "chroma-fs";
var DEFAULT_STORE_NAME = "files";
var DEFAULT_CONFIG = {
  storage: {
    indexedDb: {
      dbName: DEFAULT_DB_NAME,
      storeName: DEFAULT_STORE_NAME
    }
  }
};
function mergeConfig(partial) {
  const storagePartial = partial?.storage;
  return {
    storage: {
      basePath: typeof storagePartial?.basePath === "string" ? storagePartial.basePath : DEFAULT_BASE_PATH,
      ...storagePartial?.backend ? { backend: storagePartial.backend } : {},
      indexedDb: {
        dbName: storagePartial?.indexedDb?.dbName ?? DEFAULT_CONFIG.storage.indexedDb?.dbName ?? "chroma-fs",
        storeName: storagePartial?.indexedDb?.storeName ?? DEFAULT_CONFIG.storage.indexedDb?.storeName ?? "files"
      }
    }
  };
}
function parseConfig(raw) {
  if (!raw || typeof raw !== "object") {
    throw new Error("Invalid Chroma-Fs config: expected a JSON object.");
  }
  const candidate = raw;
  const storage = candidate.storage;
  if (!storage || typeof storage !== "object") {
    throw new Error("Invalid Chroma-Fs config: missing storage section.");
  }
  const storageRecord = storage;
  const backend = storageRecord.backend;
  if (backend !== void 0 && backend !== "indexeddb" && backend !== "filesystem") {
    throw new Error(
      'Invalid Chroma-Fs config: storage.backend must be "indexeddb" or "filesystem".'
    );
  }
  const indexedDb = storageRecord.indexedDb;
  if (indexedDb !== void 0 && typeof indexedDb !== "object") {
    throw new Error("Invalid Chroma-Fs config: storage.indexedDb must be an object.");
  }
  const indexedDbRecord = indexedDb && typeof indexedDb === "object" ? indexedDb : null;
  const parsedIndexedDb = indexedDbRecord ? {
    ...typeof indexedDbRecord.dbName === "string" ? { dbName: indexedDbRecord.dbName } : {},
    ...typeof indexedDbRecord.storeName === "string" ? { storeName: indexedDbRecord.storeName } : {}
  } : DEFAULT_CONFIG.storage.indexedDb;
  return mergeConfig({
    storage: {
      ...backend ? { backend } : {},
      ...typeof storageRecord.basePath === "string" ? { basePath: storageRecord.basePath } : {},
      ...parsedIndexedDb ? { indexedDb: parsedIndexedDb } : {}
    }
  });
}
async function loadConfig(configPath = "chroma-fs.json") {
  const response = await fetch(configPath, { cache: "no-store" });
  if (!response.ok) {
    throw new Error(`Unable to load Chroma-Fs config from ${configPath}.`);
  }
  const raw = await response.json();
  return parseConfig(raw);
}
function detectPlatform() {
  if (typeof window === "undefined") {
    return "static";
  }
  const globals = window;
  if (globals.__TAURI__ || globals.__TAURI_INTERNALS__) {
    return "desktop";
  }
  if (isInIframe()) {
    return "desktop";
  }
  return "static";
}
function resolveBackend(config, platform) {
  if (config.storage.backend) {
    return config.storage.backend;
  }
  return platform === "desktop" ? "filesystem" : "indexeddb";
}
function defaultConfig() {
  return mergeConfig();
}

// src/chroma-fs.ts
var ChromaFs = class _ChromaFs {
  storage;
  constructor(storage) {
    this.storage = storage;
  }
  static async create(options = {}) {
    const storage = await createChromaFsStorage(options);
    return new _ChromaFs(storage);
  }
  readFile(path) {
    return this.storage.readFile(path);
  }
  readText(path) {
    return this.storage.readText(path);
  }
  writeFile(path, data) {
    return this.storage.writeFile(path, data);
  }
  delete(path) {
    return this.storage.delete(path);
  }
  exists(path) {
    return this.storage.exists(path);
  }
  list(path) {
    return this.storage.list(path);
  }
  mkdir(path) {
    return this.storage.mkdir(path);
  }
  rmdir(path, options) {
    return this.storage.rmdir(path, options);
  }
  stat(path) {
    return this.storage.stat(path);
  }
};
async function createChromaFs(options = {}) {
  return ChromaFs.create(options);
}
async function createChromaFsStorage(options) {
  const config = await resolveChromaFsConfig(options);
  const platform = detectPlatform();
  const backend = resolveBackend(config, platform);
  if (options.adapter) {
    return createFilesystemStorage({
      basePath: config.storage.basePath ?? "./data",
      adapter: options.adapter
    });
  }
  if (backend === "filesystem") {
    if (isInIframe()) {
      return createFilesystemStorage({
        basePath: config.storage.basePath ?? "./data",
        adapter: createPostMessageAdapter()
      });
    }
    if (hasTauriRuntime() && !isInIframe()) {
      return createFilesystemStorage({
        basePath: config.storage.basePath ?? "./data"
      });
    }
    throw new Error(
      "Filesystem backend requires Chroma Desktop (postMessage bridge) or a Tauri host with @tauri-apps/plugin-fs."
    );
  }
  return createIndexedDbStorage({
    dbName: config.storage.indexedDb?.dbName ?? "chroma-fs",
    storeName: config.storage.indexedDb?.storeName ?? "files"
  });
}
async function resolveChromaFsConfig(options) {
  if (options.configPath) {
    const loaded = await loadConfig(options.configPath);
    return options.config ? mergeConfig({ storage: { ...loaded.storage, ...options.config.storage } }) : loaded;
  }
  if (options.config) {
    return mergeConfig(options.config);
  }
  try {
    return await loadConfig("chroma-fs.json");
  } catch {
    return mergeConfig();
  }
}

// src/index.ts
init_fs_wrapper();
init_path();
async function bootstrapFs() {
  return createStorage({ configPath: "./chroma-fs.json" });
}
async function createStorage(options = {}) {
  const config = await resolveConfig(options);
  const platform = detectPlatform();
  const backend = resolveBackend(config, platform);
  if (options.adapter) {
    return createFilesystemStorage({
      basePath: config.storage.basePath ?? "./data",
      adapter: options.adapter
    });
  }
  if (backend === "filesystem") {
    if (isInIframe()) {
      return createFilesystemStorage({
        basePath: config.storage.basePath ?? "./data",
        adapter: createPostMessageAdapter()
      });
    }
    if (hasTauriRuntime() && !isInIframe()) {
      return createFilesystemStorage({
        basePath: config.storage.basePath ?? "./data"
      });
    }
    throw new Error(
      "Filesystem backend requires Chroma Desktop (postMessage bridge) or a Tauri host with @tauri-apps/plugin-fs."
    );
  }
  return createIndexedDbStorage({
    dbName: config.storage.indexedDb?.dbName ?? "chroma-fs",
    storeName: config.storage.indexedDb?.storeName ?? "files"
  });
}
async function resolveConfig(options) {
  if (options.configPath) {
    const loaded = await loadConfig(options.configPath);
    return options.config ? mergeConfig({ storage: { ...loaded.storage, ...options.config.storage } }) : loaded;
  }
  if (options.config) {
    return mergeConfig(options.config);
  }
  try {
    return await loadConfig("chroma-fs.json");
  } catch {
    return mergeConfig();
  }
}

export { ChromaFs, FilesystemStorage, IndexedDbStorage, baseName, bootstrapFs, childPath, createChromaFs, createDefaultTauriFsAdapter, createFilesystemStorage, createIndexedDbStorage, createPostMessageAdapter, createStorage, defaultConfig, detectPlatform, directoryPrefix, hasTauriRuntime, isDirectChild, isInIframe, joinPath, loadConfig, mergeConfig, normalizePath, parentPath, parseConfig, resolveBackend, stripLeadingSlash, stripTrailingSlash, toBytes, toText };
//# sourceMappingURL=index.js.map
//# sourceMappingURL=index.js.map