type StorageBackendType = "indexeddb" | "filesystem";
type PlatformKind = "static" | "desktop";
interface IndexedDbSettings {
    dbName?: string;
    storeName?: string;
}
interface StorageSettings {
    backend?: StorageBackendType;
    basePath?: string;
    indexedDb?: IndexedDbSettings;
}
interface ChromaFsConfig {
    storage: StorageSettings;
}
type FileKind = "file" | "directory";
interface FileEntry {
    name: string;
    path: string;
    kind: FileKind;
    size?: number;
    modifiedAt?: number;
}
interface RemoveOptions {
    recursive?: boolean;
}
interface Storage {
    readFile(path: string): Promise<Uint8Array>;
    readText(path: string): Promise<string>;
    writeFile(path: string, data: string | Uint8Array): Promise<void>;
    delete(path: string): Promise<void>;
    exists(path: string): Promise<boolean>;
    list(path?: string): Promise<FileEntry[]>;
    mkdir(path: string): Promise<void>;
    rmdir(path: string, options?: RemoveOptions): Promise<void>;
    stat(path: string): Promise<FileEntry | null>;
}
interface TauriDirEntry {
    name: string;
    isDirectory: boolean;
    isFile: boolean;
}
interface TauriFileStat {
    isDirectory: boolean;
    isFile: boolean;
    size: number;
    mtime?: number | null;
}
interface TauriFsAdapter {
    readFile(path: string): Promise<Uint8Array>;
    readTextFile(path: string): Promise<string>;
    writeFile(path: string, data: Uint8Array): Promise<void>;
    writeTextFile(path: string, data: string): Promise<void>;
    remove(path: string, options?: RemoveOptions): Promise<void>;
    exists(path: string): Promise<boolean>;
    readDir(path: string): Promise<TauriDirEntry[]>;
    mkdir(path: string, options?: {
        recursive?: boolean;
    }): Promise<void>;
    stat(path: string): Promise<TauriFileStat | null>;
}
interface CreateStorageOptions {
    config?: Partial<ChromaFsConfig>;
    configPath?: string;
    adapter?: TauriFsAdapter;
}

interface FilesystemBackendOptions {
    basePath: string;
    adapter?: TauriFsAdapter;
}
declare class FilesystemStorage implements Storage {
    private readonly basePath;
    private readonly adapter;
    constructor(options: FilesystemBackendOptions);
    static create(options: FilesystemBackendOptions): Promise<FilesystemStorage>;
    readFile(path: string): Promise<Uint8Array>;
    readText(path: string): Promise<string>;
    writeFile(path: string, data: string | Uint8Array): Promise<void>;
    delete(path: string): Promise<void>;
    exists(path: string): Promise<boolean>;
    list(path?: string): Promise<FileEntry[]>;
    mkdir(path: string): Promise<void>;
    rmdir(path: string, options?: {
        recursive?: boolean;
    }): Promise<void>;
    stat(path: string): Promise<FileEntry | null>;
    private ensureParentDirectories;
}
declare function createFilesystemStorage(options: FilesystemBackendOptions): Promise<Storage>;

interface IndexedDbBackendOptions {
    dbName: string;
    storeName: string;
}
declare class IndexedDbStorage implements Storage {
    private readonly dbName;
    private readonly storeName;
    private dbPromise;
    constructor(options: IndexedDbBackendOptions);
    readFile(path: string): Promise<Uint8Array>;
    readText(path: string): Promise<string>;
    writeFile(path: string, data: string | Uint8Array): Promise<void>;
    delete(path: string): Promise<void>;
    exists(path: string): Promise<boolean>;
    list(path?: string): Promise<FileEntry[]>;
    mkdir(path: string): Promise<void>;
    rmdir(path: string, options?: {
        recursive?: boolean;
    }): Promise<void>;
    stat(path: string): Promise<FileEntry | null>;
    get databaseName(): string;
    close(): Promise<void>;
    private toEntry;
    private ensureParentDirectories;
    private openDb;
    private withStore;
    private getRecord;
    private putRecord;
    private deleteRecord;
    private getAllRecords;
}
declare function createIndexedDbStorage(options: IndexedDbBackendOptions): Storage;

declare function createPostMessageAdapter(): TauriFsAdapter;
declare function isInIframe(): boolean;
declare function hasTauriRuntime(): boolean;

declare class ChromaFs implements Storage {
    private readonly storage;
    constructor(storage: Storage);
    static create(options?: CreateStorageOptions): Promise<ChromaFs>;
    readFile(path: string): Promise<Uint8Array>;
    readText(path: string): Promise<string>;
    writeFile(path: string, data: string | Uint8Array): Promise<void>;
    delete(path: string): Promise<void>;
    exists(path: string): Promise<boolean>;
    list(path?: string): Promise<FileEntry[]>;
    mkdir(path: string): Promise<void>;
    rmdir(path: string, options?: RemoveOptions): Promise<void>;
    stat(path: string): Promise<FileEntry | null>;
}
declare function createChromaFs(options?: CreateStorageOptions): Promise<ChromaFs>;

declare function createDefaultTauriFsAdapter(basePath?: string): Promise<TauriFsAdapter>;

declare function mergeConfig(partial?: Partial<ChromaFsConfig>): ChromaFsConfig;
declare function parseConfig(raw: unknown): ChromaFsConfig;
declare function loadConfig(configPath?: string): Promise<ChromaFsConfig>;
declare function detectPlatform(): PlatformKind;
declare function resolveBackend(config: ChromaFsConfig, platform: PlatformKind): StorageBackendType;
declare function defaultConfig(): ChromaFsConfig;

declare function normalizePath(path: string): string;
declare function joinPath(base: string, path: string): string;
declare function parentPath(path: string): string;
declare function baseName(path: string): string;
declare function childPath(parent: string, name: string): string;
declare function isDirectChild(parent: string, candidate: string): boolean;
declare function stripLeadingSlash(path: string): string;
declare function stripTrailingSlash(path: string): string;
declare function directoryPrefix(path: string): string;
declare function toText(data: string | Uint8Array): string;
declare function toBytes(data: string | Uint8Array): Uint8Array;

/** Chroma plugin contract — see chroma.plugin.json */
declare function bootstrapFs(): Promise<Storage>;
declare function createStorage(options?: CreateStorageOptions): Promise<Storage>;

export { ChromaFs, type ChromaFsConfig, type CreateStorageOptions, type FileEntry, type FileKind, FilesystemStorage, type IndexedDbSettings, IndexedDbStorage, type PlatformKind, type RemoveOptions, type Storage, type StorageBackendType, type StorageSettings, type TauriDirEntry, type TauriFileStat, type TauriFsAdapter, baseName, bootstrapFs, childPath, createChromaFs, createDefaultTauriFsAdapter, createFilesystemStorage, createIndexedDbStorage, createPostMessageAdapter, createStorage, defaultConfig, detectPlatform, directoryPrefix, hasTauriRuntime, isDirectChild, isInIframe, joinPath, loadConfig, mergeConfig, normalizePath, parentPath, parseConfig, resolveBackend, stripLeadingSlash, stripTrailingSlash, toBytes, toText };
