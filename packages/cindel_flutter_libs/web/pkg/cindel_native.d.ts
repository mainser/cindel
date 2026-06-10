/* tslint:disable */
/* eslint-disable */

export class CindelWebEngine {
    private constructor();
    free(): void;
    [Symbol.dispose](): void;
    allocateId(collection: string): Uint8Array;
    allocateIds(collection: string, count: number): Uint8Array;
    delete(collection: string, ids: Uint8Array): void;
    deleteAll(collection: string, ids: Uint8Array): void;
    deleteNativeAll(collection: string, ids: Uint8Array): boolean;
    documentIds(collection: string): Uint8Array;
    get(collection: string, ids: Uint8Array): Uint8Array;
    getAll(collection: string, ids: Uint8Array): Uint8Array;
    getAllStored(collection: string, ids: Uint8Array): Uint8Array;
    getStored(collection: string, ids: Uint8Array): Uint8Array;
    static openWithSchemas(db_name: string, manifest_bytes: Uint8Array): Promise<CindelWebEngine>;
    put(collection: string, document_batch: Uint8Array): void;
    putAll(collection: string, document_batch: Uint8Array): void;
    putNativeAll(collection: string, document_batch: Uint8Array): boolean;
    queryIndexEqual(collection: string, index: string, value: Uint8Array): Uint8Array;
    queryIndexRange(collection: string, index: string, lower_present: boolean, lower: Uint8Array, upper_present: boolean, upper: Uint8Array): Uint8Array;
    queryPlanAggregate(collection: string, plan: Uint8Array, field: string, operation: string): Uint8Array;
    queryPlanCount(collection: string, plan: Uint8Array): Uint8Array;
    queryPlanDocuments(collection: string, plan: Uint8Array): Uint8Array;
    queryPlanIds(collection: string, plan: Uint8Array): Uint8Array;
    queryPlanProject(collection: string, plan: Uint8Array, field: string): Uint8Array;
    schemaVersion(collection: string): number;
    storageMetadataJson(): string;
}

export type InitInput = RequestInfo | URL | Response | BufferSource | WebAssembly.Module;

export interface InitOutput {
    readonly memory: WebAssembly.Memory;
    readonly cindel_abi_version: () => number;
    readonly cindel_open: (a: number, b: number) => number;
    readonly cindel_open_with_backend: (a: number, b: number, c: number) => number;
    readonly cindel_open_with_backend_and_schemas: (a: number, b: number, c: number, d: number, e: number) => number;
    readonly cindel_close: (a: number) => void;
    readonly cindel_begin_read_txn: (a: number) => number;
    readonly cindel_begin_write_txn: (a: number) => number;
    readonly cindel_commit_txn: (a: number) => number;
    readonly cindel_rollback_txn: (a: number) => number;
    readonly cindel_put: (a: number, b: number, c: number, d: bigint, e: number, f: number) => number;
    readonly cindel_allocate_id: (a: number, b: number, c: number, d: number) => number;
    readonly cindel_register_schemas: (a: number, b: number, c: number) => number;
    readonly cindel_put_indexed: (a: number, b: number, c: number, d: bigint, e: number, f: number, g: number, h: number) => number;
    readonly cindel_put_many_indexed: (a: number, b: number, c: number, d: number, e: number) => number;
    readonly cindel_put_many_stored: (a: number, b: number, c: number, d: number, e: number) => number;
    readonly cindel_native_batch_writer_new: (a: number, b: number, c: number, d: number) => number;
    readonly cindel_native_batch_writer_begin_document: (a: number, b: bigint) => void;
    readonly cindel_native_batch_writer_write_null: (a: number, b: number) => void;
    readonly cindel_native_batch_writer_write_bool: (a: number, b: number, c: number) => void;
    readonly cindel_native_batch_writer_write_int: (a: number, b: number, c: bigint) => void;
    readonly cindel_native_batch_writer_write_double: (a: number, b: number, c: number) => void;
    readonly cindel_native_batch_writer_write_bytes: (a: number, b: number, c: number, d: number) => void;
    readonly cindel_native_batch_writer_begin_list: (a: number, b: number, c: number) => number;
    readonly cindel_native_batch_writer_end_list: (a: number, b: number) => void;
    readonly cindel_native_batch_writer_begin_object: (a: number, b: number, c: number, d: number) => number;
    readonly cindel_native_batch_writer_end_object: (a: number, b: number) => void;
    readonly cindel_native_batch_writer_save_document: (a: number, b: bigint) => void;
    readonly cindel_native_batch_writer_end_document: (a: number) => void;
    readonly cindel_native_batch_writer_finish: (a: number, b: number, c: number, d: number) => number;
    readonly cindel_native_batch_writer_finish_with_options: (a: number, b: number, c: number, d: number, e: number) => number;
    readonly cindel_native_batch_writer_abort: (a: number) => void;
    readonly cindel_native_document_reader_new: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => number;
    readonly cindel_native_document_reader_new_from_query_plan: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => number;
    readonly cindel_native_document_reader_len: (a: number) => number;
    readonly cindel_native_document_reader_is_streaming: (a: number) => number;
    readonly cindel_native_document_reader_next: (a: number) => number;
    readonly cindel_native_document_reader_is_present: (a: number, b: number) => number;
    readonly cindel_native_document_reader_read_id: (a: number, b: number, c: number) => number;
    readonly cindel_native_document_reader_read_id_value: (a: number, b: number) => bigint;
    readonly cindel_native_document_reader_read_current_id_value: (a: number) => bigint;
    readonly cindel_native_document_reader_read_bool: (a: number, b: number, c: number, d: number) => number;
    readonly cindel_native_document_reader_read_bool_value: (a: number, b: number, c: number) => number;
    readonly cindel_native_document_reader_read_current_bool_value: (a: number, b: number) => number;
    readonly cindel_native_document_reader_read_int: (a: number, b: number, c: number, d: number) => number;
    readonly cindel_native_document_reader_read_int_value: (a: number, b: number, c: number) => bigint;
    readonly cindel_native_document_reader_read_current_int_value: (a: number, b: number) => bigint;
    readonly cindel_native_document_reader_read_double: (a: number, b: number, c: number, d: number) => number;
    readonly cindel_native_document_reader_read_double_value: (a: number, b: number, c: number) => number;
    readonly cindel_native_document_reader_read_current_double_value: (a: number, b: number) => number;
    readonly cindel_native_document_reader_read_bytes: (a: number, b: number, c: number, d: number, e: number) => number;
    readonly cindel_native_document_reader_read_current_bytes: (a: number, b: number, c: number, d: number) => number;
    readonly cindel_native_document_reader_read_string_value: (a: number, b: number, c: number, d: number, e: number) => number;
    readonly cindel_native_document_reader_read_current_string_value: (a: number, b: number, c: number, d: number) => number;
    readonly cindel_native_document_reader_read_string: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => number;
    readonly cindel_native_document_reader_read_list: (a: number, b: number, c: number) => number;
    readonly cindel_native_document_reader_read_current_list: (a: number, b: number) => number;
    readonly cindel_native_document_reader_read_object: (a: number, b: number, c: number, d: number, e: number) => number;
    readonly cindel_native_document_reader_read_current_object: (a: number, b: number, c: number, d: number) => number;
    readonly cindel_native_document_reader_free: (a: number) => void;
    readonly cindel_get: (a: number, b: number, c: number, d: bigint, e: number, f: number) => number;
    readonly cindel_get_many: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => number;
    readonly cindel_get_many_stored: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => number;
    readonly cindel_document_ids: (a: number, b: number, c: number, d: number, e: number) => number;
    readonly cindel_delete: (a: number, b: number, c: number, d: bigint) => number;
    readonly cindel_delete_many: (a: number, b: number, c: number, d: number, e: number) => number;
    readonly cindel_delete_many_native_documents: (a: number, b: number, c: number, d: number, e: number) => number;
    readonly cindel_collection_revision: (a: number, b: number, c: number, d: number) => number;
    readonly cindel_take_changes: (a: number, b: number, c: number) => number;
    readonly cindel_discard_changes: (a: number) => number;
    readonly cindel_schema_version: (a: number, b: number, c: number, d: number) => number;
    readonly cindel_query_index_equal: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number) => number;
    readonly cindel_query_index_range: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number, j: number, k: number) => number;
    readonly cindel_query_filter: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number) => number;
    readonly cindel_query_project: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number) => number;
    readonly cindel_query_aggregate: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number, j: number, k: number) => number;
    readonly cindel_query_plan_ids: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => number;
    readonly cindel_query_plan_documents: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => number;
    readonly cindel_query_plan_count: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => number;
    readonly cindel_query_plan_project: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number) => number;
    readonly cindel_query_plan_aggregate: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number, j: number, k: number) => number;
    readonly cindel_query_plan_delete: (a: number, b: number, c: number, d: number, e: number, f: number, g: number) => number;
    readonly cindel_query_plan_update: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number) => number;
    readonly cindel_free_buffer: (a: number, b: number) => void;
    readonly __wbg_cindelwebengine_free: (a: number, b: number) => void;
    readonly cindelwebengine_openWithSchemas: (a: number, b: number, c: number, d: number) => number;
    readonly cindelwebengine_schemaVersion: (a: number, b: number, c: number, d: number) => void;
    readonly cindelwebengine_storageMetadataJson: (a: number, b: number) => void;
    readonly cindelwebengine_allocateId: (a: number, b: number, c: number, d: number) => void;
    readonly cindelwebengine_allocateIds: (a: number, b: number, c: number, d: number, e: number) => void;
    readonly cindelwebengine_put: (a: number, b: number, c: number, d: number, e: number, f: number) => void;
    readonly cindelwebengine_putAll: (a: number, b: number, c: number, d: number, e: number, f: number) => void;
    readonly cindelwebengine_putNativeAll: (a: number, b: number, c: number, d: number, e: number, f: number) => void;
    readonly cindelwebengine_get: (a: number, b: number, c: number, d: number, e: number, f: number) => void;
    readonly cindelwebengine_getAll: (a: number, b: number, c: number, d: number, e: number, f: number) => void;
    readonly cindelwebengine_getStored: (a: number, b: number, c: number, d: number, e: number, f: number) => void;
    readonly cindelwebengine_getAllStored: (a: number, b: number, c: number, d: number, e: number, f: number) => void;
    readonly cindelwebengine_delete: (a: number, b: number, c: number, d: number, e: number, f: number) => void;
    readonly cindelwebengine_deleteAll: (a: number, b: number, c: number, d: number, e: number, f: number) => void;
    readonly cindelwebengine_deleteNativeAll: (a: number, b: number, c: number, d: number, e: number, f: number) => void;
    readonly cindelwebengine_documentIds: (a: number, b: number, c: number, d: number) => void;
    readonly cindelwebengine_queryIndexEqual: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number) => void;
    readonly cindelwebengine_queryIndexRange: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number, j: number, k: number, l: number) => void;
    readonly cindelwebengine_queryPlanIds: (a: number, b: number, c: number, d: number, e: number, f: number) => void;
    readonly cindelwebengine_queryPlanDocuments: (a: number, b: number, c: number, d: number, e: number, f: number) => void;
    readonly cindelwebengine_queryPlanCount: (a: number, b: number, c: number, d: number, e: number, f: number) => void;
    readonly cindelwebengine_queryPlanProject: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number) => void;
    readonly cindelwebengine_queryPlanAggregate: (a: number, b: number, c: number, d: number, e: number, f: number, g: number, h: number, i: number, j: number) => void;
    readonly cindel_native_document_reader_read_current_list_bytes: (a: number, b: number, c: number, d: number) => number;
    readonly cindel_get_stored: (a: number, b: number, c: number, d: bigint, e: number, f: number) => number;
    readonly cindel_native_document_reader_read_list_bytes: (a: number, b: number, c: number, d: number, e: number) => number;
    readonly rust_sqlite_wasm_getentropy: (a: number, b: number) => number;
    readonly rust_sqlite_wasm_assert_fail: (a: number, b: number, c: number, d: number) => void;
    readonly rust_sqlite_wasm_abort: () => void;
    readonly rust_sqlite_wasm_localtime: (a: number) => number;
    readonly rust_sqlite_wasm_malloc: (a: number) => number;
    readonly rust_sqlite_wasm_free: (a: number) => void;
    readonly rust_sqlite_wasm_realloc: (a: number, b: number) => number;
    readonly rust_sqlite_wasm_calloc: (a: number, b: number) => number;
    readonly sqlite3_os_init: () => number;
    readonly sqlite3_os_end: () => number;
    readonly __wasm_bindgen_func_elem_2724: (a: number, b: number, c: number, d: number) => void;
    readonly __wasm_bindgen_func_elem_2749: (a: number, b: number, c: number, d: number) => void;
    readonly __wbindgen_export: (a: number, b: number) => number;
    readonly __wbindgen_export2: (a: number, b: number, c: number, d: number) => number;
    readonly __wbindgen_export3: (a: number) => void;
    readonly __wbindgen_export4: (a: number, b: number) => void;
    readonly __wbindgen_add_to_stack_pointer: (a: number) => number;
    readonly __wbindgen_export5: (a: number, b: number, c: number) => void;
}

export type SyncInitInput = BufferSource | WebAssembly.Module;

/**
 * Instantiates the given `module`, which can either be bytes or
 * a precompiled `WebAssembly.Module`.
 *
 * @param {{ module: SyncInitInput }} module - Passing `SyncInitInput` directly is deprecated.
 *
 * @returns {InitOutput}
 */
export function initSync(module: { module: SyncInitInput } | SyncInitInput): InitOutput;

/**
 * If `module_or_path` is {RequestInfo} or {URL}, makes a request and
 * for everything else, calls `WebAssembly.instantiate` directly.
 *
 * @param {{ module_or_path: InitInput | Promise<InitInput> }} module_or_path - Passing `InitInput` directly is deprecated.
 *
 * @returns {Promise<InitOutput>}
 */
export default function __wbg_init (module_or_path?: { module_or_path: InitInput | Promise<InitInput> } | InitInput | Promise<InitInput>): Promise<InitOutput>;
