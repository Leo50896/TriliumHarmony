import { common } from '@kit.AbilityKit';
import relationalStore from '@ohos.data.relationalStore';
import { AuthSession } from '../models/AuthModels';
import { CachedNote } from '../models/CacheModels';
import { EtapiAttributePayload, EtapiNotePayload, TriliumNote } from '../models/TriliumModels';
import { EtapiService } from './EtapiService';

const DATABASE_NAME: string = 'trilium_local.db';
const NOTES_TABLE: string = 'local_notes';
const META_TABLE: string = 'local_meta';
const CONTENT_LIMIT: number = 1500000;
const SYNC_BATCH: number = 4;

const CREATE_NOTES: string = `
CREATE TABLE IF NOT EXISTS local_notes (
  account_key TEXT NOT NULL,
  note_id TEXT NOT NULL,
  title TEXT NOT NULL,
  type TEXT NOT NULL,
  mime TEXT NOT NULL,
  date_created TEXT NOT NULL,
  date_modified TEXT NOT NULL,
  attributes TEXT NOT NULL,
  parent_ids TEXT NOT NULL,
  child_ids TEXT NOT NULL,
  is_protected INTEGER NOT NULL,
  note_position INTEGER NOT NULL DEFAULT 0,
  content TEXT NOT NULL,
  content_cached INTEGER NOT NULL,
  sync_status INTEGER NOT NULL DEFAULT 0,
  updated_at INTEGER NOT NULL,
  PRIMARY KEY (account_key, note_id)
)`;

const CREATE_META: string = `
CREATE TABLE IF NOT EXISTS local_meta (
  account_key TEXT NOT NULL PRIMARY KEY,
  full_sync_at INTEGER NOT NULL,
  note_count INTEGER NOT NULL,
  last_change_id TEXT NOT NULL DEFAULT '',
  last_sync_time INTEGER NOT NULL DEFAULT 0
)`;

export class LocalNote {
  note: TriliumNote;
  content: string;
  contentCached: boolean;

  constructor(note: TriliumNote, content: string, contentCached: boolean) {
    this.note = note;
    this.content = content;
    this.contentCached = contentCached;
  }
}

export enum LocalMutationKind {
  UPSERT = 0,
  DELETE = 1
}

export class LocalMutation {
  kind: LocalMutationKind;
  note: TriliumNote | null;
  content: string;
  contentCached: boolean;
  noteId: string;

  constructor(kind: LocalMutationKind, noteId: string, note: TriliumNote | null = null,
    content: string = '', contentCached: boolean = false) {
    this.kind = kind;
    this.noteId = noteId;
    this.note = note;
    this.content = content;
    this.contentCached = contentCached;
  }
}

/**
 * Full local SQLite copy of the note tree and textual note contents.
 *
 * Binary attachments (images/PDF) stay in ImageDiskCache/PdfDiskCache and are
 * never fetched by this store.
 */
export class LocalStore {
  private static store: relationalStore.RdbStore | null = null;
  private static syncing: boolean = false;

  private static async open(context: common.UIAbilityContext): Promise<relationalStore.RdbStore> {
    if (LocalStore.store !== null) {
      return LocalStore.store;
    }
    const config: relationalStore.StoreConfig = {
      name: DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const opened: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
    await opened.executeSql(CREATE_NOTES);
    await opened.executeSql(CREATE_META);
    try {
      await opened.executeSql(
        `ALTER TABLE ${NOTES_TABLE} ADD COLUMN sync_status INTEGER NOT NULL DEFAULT 0`);
    } catch (error) {
      // Column already exists.
    }
    try {
      await opened.executeSql(
        `ALTER TABLE ${META_TABLE} ADD COLUMN last_change_id TEXT NOT NULL DEFAULT ''`);
    } catch (error) {
      // Column already exists.
    }
    try {
      await opened.executeSql(
        `ALTER TABLE ${META_TABLE} ADD COLUMN last_sync_time INTEGER NOT NULL DEFAULT 0`);
    } catch (error) {
      // Column already exists.
    }
    try {
      await opened.executeSql(
        `ALTER TABLE ${NOTES_TABLE} ADD COLUMN note_position INTEGER NOT NULL DEFAULT 0`);
    } catch (error) {
      // Column already exists.
    }
    LocalStore.store = opened;
    return opened;
  }

  private static listJson(values: string[]): string {
    return JSON.stringify(values);
  }

  private static parseList(value: string): string[] {
    try {
      const parsed: string[] = JSON.parse(value) as string[];
      return Array.isArray(parsed) ? parsed : [];
    } catch (error) {
      return [];
    }
  }

  private static parseAttributes(value: string): EtapiAttributePayload[] {
    try {
      return JSON.parse(value) as EtapiAttributePayload[];
    } catch (error) {
      return [];
    }
  }

  private static toNote(resultSet: relationalStore.ResultSet): TriliumNote {
    const payload: EtapiNotePayload = {
      noteId: resultSet.getString(resultSet.getColumnIndex('note_id')),
      title: resultSet.getString(resultSet.getColumnIndex('title')),
      type: resultSet.getString(resultSet.getColumnIndex('type')),
      mime: resultSet.getString(resultSet.getColumnIndex('mime')),
      dateCreated: resultSet.getString(resultSet.getColumnIndex('date_created')),
      dateModified: resultSet.getString(resultSet.getColumnIndex('date_modified')),
      attributes: LocalStore.parseAttributes(resultSet.getString(resultSet.getColumnIndex('attributes'))),
      parentNoteIds: LocalStore.parseList(resultSet.getString(resultSet.getColumnIndex('parent_ids'))),
      childNoteIds: LocalStore.parseList(resultSet.getString(resultSet.getColumnIndex('child_ids'))),
      isProtected: resultSet.getLong(resultSet.getColumnIndex('is_protected')) === 1
    };
    const note: TriliumNote = new TriliumNote(payload);
    note.notePosition = resultSet.getLong(resultSet.getColumnIndex('note_position'));
    return note;
  }

  static async get(context: common.UIAbilityContext, accountKey: string,
    noteId: string): Promise<LocalNote | null> {
    if (accountKey.length === 0 || noteId.length === 0) {
      return null;
    }
    const store: relationalStore.RdbStore = await LocalStore.open(context);
    const rs: relationalStore.ResultSet = await store.querySql(
      `SELECT * FROM ${NOTES_TABLE} WHERE account_key = ? AND note_id = ?`,
      [accountKey, noteId]
    );
    try {
      if (!rs.goToFirstRow()) {
        return null;
      }
      const note: TriliumNote = LocalStore.toNote(rs);
      return new LocalNote(note, rs.getString(rs.getColumnIndex('content')),
        rs.getLong(rs.getColumnIndex('content_cached')) === 1);
    } finally {
      rs.close();
    }
  }

  static async all(context: common.UIAbilityContext, accountKey: string): Promise<TriliumNote[]> {
    const store: relationalStore.RdbStore = await LocalStore.open(context);
    const rs: relationalStore.ResultSet = await store.querySql(
      `SELECT * FROM ${NOTES_TABLE} WHERE account_key = ?`, [accountKey]);
    const notes: TriliumNote[] = [];
    try {
      while (rs.goToNextRow()) {
        notes.push(LocalStore.toNote(rs));
      }
    } finally {
      rs.close();
    }
    return notes;
  }

  static async recent(context: common.UIAbilityContext, accountKey: string,
    limit: number): Promise<CachedNote[]> {
    const store: relationalStore.RdbStore = await LocalStore.open(context);
    const rs: relationalStore.ResultSet = await store.querySql(
      `SELECT * FROM ${NOTES_TABLE} WHERE account_key = ?
       ORDER BY updated_at DESC LIMIT ?`, [accountKey, limit]);
    const notes: CachedNote[] = [];
    try {
      while (rs.goToNextRow()) {
        const note: TriliumNote = LocalStore.toNote(rs);
        notes.push(new CachedNote(note.noteId, note.title, note.type, note.mime,
          note.dateModified, note.visibleLabels(), note.isProtected,
          rs.getString(rs.getColumnIndex('content')),
          rs.getLong(rs.getColumnIndex('updated_at'))));
      }
    } finally {
      rs.close();
    }
    return notes;
  }

  static async put(context: common.UIAbilityContext, accountKey: string,
    note: TriliumNote, content: string): Promise<void> {
    if (accountKey.length === 0 || note.noteId.length === 0) {
      return;
    }
    const store: relationalStore.RdbStore = await LocalStore.open(context);
    const values: relationalStore.ValuesBucket = LocalStore.valuesFor(accountKey, note, content, true);
    await store.insert(NOTES_TABLE, values, relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
  }

  private static valuesFor(accountKey: string, note: TriliumNote,
    content: string, contentCached: boolean): relationalStore.ValuesBucket {
    const values: relationalStore.ValuesBucket = {
      'account_key': accountKey,
      'note_id': note.noteId,
      'title': note.title,
      'type': note.type,
      'mime': note.mime,
      'date_created': note.dateCreated,
      'date_modified': note.dateModified,
      'attributes': JSON.stringify(note.attributes),
      'parent_ids': LocalStore.listJson(note.parentNoteIds),
      'child_ids': LocalStore.listJson(note.childNoteIds),
      'is_protected': note.isProtected ? 1 : 0,
      'note_position': note.notePosition,
      'content': note.isProtected ? '' : content,
      'content_cached': contentCached ? 1 : 0,
      'sync_status': 0,
      'updated_at': Date.now()
    };
    return values;
  }

  static async hasData(context: common.UIAbilityContext, accountKey: string): Promise<boolean> {
    const store: relationalStore.RdbStore = await LocalStore.open(context);
    const rs: relationalStore.ResultSet = await store.querySql(
      `SELECT COUNT(*) AS total FROM ${NOTES_TABLE} WHERE account_key = ?`, [accountKey]);
    try {
      if (rs.goToFirstRow()) {
        return rs.getLong(rs.getColumnIndex('total')) > 0;
      }
    } finally {
      rs.close();
    }
    return false;
  }

  static async fullSyncAt(context: common.UIAbilityContext, accountKey: string): Promise<number> {
    const store: relationalStore.RdbStore = await LocalStore.open(context);
    const rs: relationalStore.ResultSet = await store.querySql(
      `SELECT full_sync_at FROM ${META_TABLE} WHERE account_key = ?`, [accountKey]);
    try {
      if (rs.goToFirstRow()) {
        return rs.getLong(rs.getColumnIndex('full_sync_at'));
      }
    } finally {
      rs.close();
    }
    return 0;
  }

  static async lastChangeId(context: common.UIAbilityContext, accountKey: string): Promise<string> {
    const store: relationalStore.RdbStore = await LocalStore.open(context);
    const rs: relationalStore.ResultSet = await store.querySql(
      `SELECT last_change_id FROM ${META_TABLE} WHERE account_key = ?`, [accountKey]);
    try {
      if (rs.goToFirstRow()) {
        return rs.getString(rs.getColumnIndex('last_change_id'));
      }
    } finally {
      rs.close();
    }
    return '';
  }

  static async setLastChangeId(context: common.UIAbilityContext, accountKey: string,
    changeId: string): Promise<void> {
    const store: relationalStore.RdbStore = await LocalStore.open(context);
    await store.executeSql(
      `UPDATE ${META_TABLE} SET last_change_id = ? WHERE account_key = ?`,
      [changeId, accountKey]);
  }

  static async lastSyncTime(context: common.UIAbilityContext, accountKey: string): Promise<number> {
    const store: relationalStore.RdbStore = await LocalStore.open(context);
    const rs: relationalStore.ResultSet = await store.querySql(
      `SELECT last_sync_time FROM ${META_TABLE} WHERE account_key = ?`, [accountKey]);
    try {
      if (rs.goToFirstRow()) {
        return rs.getLong(rs.getColumnIndex('last_sync_time'));
      }
    } finally {
      rs.close();
    }
    return 0;
  }

  static async setLastSyncTime(context: common.UIAbilityContext, accountKey: string,
    timestamp: number): Promise<void> {
    const store: relationalStore.RdbStore = await LocalStore.open(context);
    await store.executeSql(
      `UPDATE ${META_TABLE} SET last_sync_time = ?,
         note_count = (SELECT COUNT(*) FROM ${NOTES_TABLE} WHERE account_key = ?)
       WHERE account_key = ?`,
      [timestamp, accountKey, accountKey]);
  }

  static async deleteNote(context: common.UIAbilityContext, accountKey: string,
    noteId: string): Promise<void> {
    const store: relationalStore.RdbStore = await LocalStore.open(context);
    await store.executeSql(
      `DELETE FROM ${NOTES_TABLE} WHERE account_key = ? AND note_id = ?`,
      [accountKey, noteId]);
  }

  static async updateParents(context: common.UIAbilityContext, accountKey: string,
    noteId: string, parentIds: string[]): Promise<void> {
    const store: relationalStore.RdbStore = await LocalStore.open(context);
    await store.executeSql(
      `UPDATE ${NOTES_TABLE} SET parent_ids = ?, updated_at = ?
       WHERE account_key = ? AND note_id = ?`,
      [LocalStore.listJson(parentIds), Date.now(), accountKey, noteId]);
  }

  static async updatePosition(context: common.UIAbilityContext, accountKey: string,
    noteId: string, position: number): Promise<void> {
    const store: relationalStore.RdbStore = await LocalStore.open(context);
    await store.executeSql(
      `UPDATE ${NOTES_TABLE} SET note_position = ?, updated_at = ?
       WHERE account_key = ? AND note_id = ?`,
      [position, Date.now(), accountKey, noteId]);
  }

  static async updateAttributes(context: common.UIAbilityContext, accountKey: string,
    noteId: string, attributes: EtapiAttributePayload[]): Promise<void> {
    const store: relationalStore.RdbStore = await LocalStore.open(context);
    await store.executeSql(
      `UPDATE ${NOTES_TABLE} SET attributes = ?, updated_at = ?
       WHERE account_key = ? AND note_id = ?`,
      [JSON.stringify(attributes), Date.now(), accountKey, noteId]);
  }

  static async syncAll(context: common.UIAbilityContext, session: AuthSession,
    accountKey: string): Promise<number> {
    if (LocalStore.syncing) {
      return 0;
    }
    LocalStore.syncing = true;
    try {
      const notes: TriliumNote[] = await EtapiService.getAllNotes(session);
      const root: TriliumNote = await EtapiService.getRoot(session);
      let containsRoot: boolean = false;
      for (let index: number = 0; index < notes.length; index++) {
        if (notes[index].noteId === root.noteId) {
          containsRoot = true;
          break;
        }
      }
      if (!containsRoot) {
        notes.push(root);
      }
      const contents: Map<string, string> = new Map();
      const candidates: TriliumNote[] = notes.filter((note: TriliumNote) =>
        !note.isProtected && (note.type === 'text' || note.type === 'code' || note.type === 'spreadsheet'));
      for (let start: number = 0; start < candidates.length; start += SYNC_BATCH) {
        const batch: Promise<void>[] = [];
        const end: number = Math.min(start + SYNC_BATCH, candidates.length);
        for (let index: number = start; index < end; index++) {
          const note: TriliumNote = candidates[index];
          batch.push((async (): Promise<void> => {
            try {
              const content: string = await EtapiService.getNoteContent(session, note.noteId);
              if (content.length <= CONTENT_LIMIT) {
                contents.set(note.noteId, content);
              }
            } catch (error) {
              // Keep metadata; content can be fetched lazily later.
            }
          })());
        }
        await Promise.all(batch);
      }

      const rows: relationalStore.ValuesBucket[] = [];
      for (let index: number = 0; index < notes.length; index++) {
        const note: TriliumNote = notes[index];
        rows.push(LocalStore.valuesFor(accountKey, note, contents.get(note.noteId) ?? '',
          contents.has(note.noteId)));
      }

      const store: relationalStore.RdbStore = await LocalStore.open(context);
      store.beginTransaction();
      try {
        await store.executeSql(`DELETE FROM ${NOTES_TABLE} WHERE account_key = ?`, [accountKey]);
        await store.batchInsert(NOTES_TABLE, rows);
        await store.executeSql(
          `INSERT OR REPLACE INTO ${META_TABLE} (account_key, full_sync_at, note_count)
           VALUES (?, ?, ?)`, [accountKey, Date.now(), notes.length]);
        store.commit();
      } catch (error) {
        store.rollBack();
        if (error instanceof Error) {
          throw error;
        }
        throw new Error('LOCAL_SYNC_FAILED');
      }
      return notes.length;
    } finally {
      LocalStore.syncing = false;
    }
  }

  static async applyMutations(context: common.UIAbilityContext, accountKey: string,
    mutations: LocalMutation[], lastChangeId: string): Promise<void> {
    const store: relationalStore.RdbStore = await LocalStore.open(context);
    store.beginTransaction();
    try {
      for (let index: number = 0; index < mutations.length; index++) {
        const mutation: LocalMutation = mutations[index];
        if (mutation.kind === LocalMutationKind.DELETE) {
          await store.executeSql(
            `DELETE FROM ${NOTES_TABLE} WHERE account_key = ? AND note_id = ?`,
            [accountKey, mutation.noteId]);
        } else if (mutation.note !== null) {
          await store.insert(NOTES_TABLE,
            LocalStore.valuesFor(accountKey, mutation.note, mutation.content,
              mutation.contentCached),
            relationalStore.ConflictResolution.ON_CONFLICT_REPLACE);
        }
      }
      await store.executeSql(
        `UPDATE ${META_TABLE} SET last_change_id = ?, full_sync_at = ?
         WHERE account_key = ?`, [lastChangeId, Date.now(), accountKey]);
      store.commit();
    } catch (error) {
      store.rollBack();
      if (error instanceof Error) {
        throw error;
      }
      throw new Error('LOCAL_MUTATION_FAILED');
    }
  }

  static async clear(context: common.UIAbilityContext): Promise<void> {
    if (LocalStore.store === null) {
      return;
    }
    await LocalStore.store.executeSql(`DELETE FROM ${NOTES_TABLE}`);
    await LocalStore.store.executeSql(`DELETE FROM ${META_TABLE}`);
  }
}
