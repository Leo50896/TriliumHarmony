import { common } from '@kit.AbilityKit';
import relationalStore from '@ohos.data.relationalStore';
import { CachedNote } from '../models/CacheModels';
import { TriliumNote } from '../models/TriliumModels';

const DATABASE_NAME: string = 'trilium_offline.db';
const TABLE_NAME: string = 'note_cache';
const MAX_CACHED_NOTES: number = 20;
const MAX_CONTENT_LENGTH: number = 1500000;
const CREATE_TABLE: string = `
CREATE TABLE IF NOT EXISTS note_cache (
  note_id TEXT NOT NULL,
  account_key TEXT NOT NULL,
  title TEXT NOT NULL,
  type TEXT NOT NULL,
  mime TEXT NOT NULL,
  date_modified TEXT NOT NULL,
  tags TEXT NOT NULL,
  is_protected INTEGER NOT NULL,
  content TEXT NOT NULL,
  cached_at INTEGER NOT NULL,
  last_viewed INTEGER NOT NULL,
  PRIMARY KEY (account_key, note_id)
)`;

/**
 * Small RDB-backed offline cache for recently opened text/code/spreadsheet notes.
 *
 * The cache stores note metadata plus raw HTML/source or spreadsheet JSON.
 * Images are not cached; offline notes therefore fall back to image
 * placeholders/errors.
 */
export class NoteCacheStore {
  private static store: relationalStore.RdbStore | null = null;

  private static async open(context: common.UIAbilityContext): Promise<relationalStore.RdbStore> {
    if (NoteCacheStore.store !== null) {
      return NoteCacheStore.store;
    }
    const config: relationalStore.StoreConfig = {
      name: DATABASE_NAME,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const opened: relationalStore.RdbStore = await relationalStore.getRdbStore(context, config);
    await opened.executeSql(CREATE_TABLE);
    NoteCacheStore.store = opened;
    return opened;
  }

  static async put(context: common.UIAbilityContext, accountKey: string,
    note: TriliumNote, content: string): Promise<void> {
    if (accountKey.length === 0 || note.noteId.length === 0) {
      return;
    }
    if (note.type !== 'text' && note.type !== 'code' && note.type !== 'spreadsheet') {
      return;
    }
    if (note.isProtected || content.length === 0 || content.length > MAX_CONTENT_LENGTH) {
      return;
    }
    const store: relationalStore.RdbStore = await NoteCacheStore.open(context);
    const now: number = Date.now();
    const args: relationalStore.ValueType[] = [
      note.noteId,
      accountKey,
      note.title,
      note.type,
      note.mime,
      note.dateModified,
      JSON.stringify(note.visibleLabels()),
      note.isProtected ? 1 : 0,
      content,
      now,
      now
    ];
    await store.executeSql(
      `INSERT OR REPLACE INTO ${TABLE_NAME}
       (note_id, account_key, title, type, mime, date_modified, tags,
        is_protected, content, cached_at, last_viewed)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`,
      args
    );
    await store.executeSql(
      `DELETE FROM ${TABLE_NAME}
       WHERE account_key = ? AND note_id NOT IN (
         SELECT note_id FROM ${TABLE_NAME}
         WHERE account_key = ? ORDER BY last_viewed DESC LIMIT ${MAX_CACHED_NOTES}
       )`,
      [accountKey, accountKey]
    );
  }

  static async get(context: common.UIAbilityContext, accountKey: string,
    noteId: string): Promise<CachedNote | null> {
    if (accountKey.length === 0 || noteId.length === 0) {
      return null;
    }
    const store: relationalStore.RdbStore = await NoteCacheStore.open(context);
    const resultSet: relationalStore.ResultSet = await store.querySql(
      `SELECT note_id, title, type, mime, date_modified, tags,
              is_protected, content, cached_at
       FROM ${TABLE_NAME}
       WHERE note_id = ? AND account_key = ?`,
      [noteId, accountKey]
    );
    try {
      if (!resultSet.goToFirstRow()) {
        return null;
      }
      let tags: string[] = [];
      try {
        const parsed: string[] = JSON.parse(resultSet.getString(5)) as string[];
        if (Array.isArray(parsed)) {
          tags = parsed;
        }
      } catch (error) {
        tags = [];
      }
      return new CachedNote(
        resultSet.getString(0),
        resultSet.getString(1),
        resultSet.getString(2),
        resultSet.getString(3),
        resultSet.getString(4),
        tags,
        resultSet.getLong(6) === 1,
        resultSet.getString(7),
        resultSet.getLong(8)
      );
    } finally {
      resultSet.close();
    }
  }

  static async recent(context: common.UIAbilityContext, accountKey: string,
    limit: number): Promise<CachedNote[]> {
    const store: relationalStore.RdbStore = await NoteCacheStore.open(context);
    const resultSet: relationalStore.ResultSet = await store.querySql(
      `SELECT note_id, title, type, mime, date_modified, tags,
              is_protected, content, cached_at
       FROM ${TABLE_NAME}
       WHERE account_key = ?
       ORDER BY last_viewed DESC LIMIT ?`,
      [accountKey, limit]
    );
    const notes: CachedNote[] = [];
    try {
      while (resultSet.goToNextRow()) {
        let tags: string[] = [];
        try {
          const parsed: string[] = JSON.parse(resultSet.getString(5)) as string[];
          if (Array.isArray(parsed)) {
            tags = parsed;
          }
        } catch (error) {
          tags = [];
        }
        notes.push(new CachedNote(
          resultSet.getString(0),
          resultSet.getString(1),
          resultSet.getString(2),
          resultSet.getString(3),
          resultSet.getString(4),
          tags,
          resultSet.getLong(6) === 1,
          resultSet.getString(7),
          resultSet.getLong(8)
        ));
      }
    } finally {
      resultSet.close();
    }
    return notes;
  }

  static async clear(context: common.UIAbilityContext): Promise<void> {
    if (NoteCacheStore.store === null) {
      return;
    }
    await NoteCacheStore.store.executeSql(`DELETE FROM ${TABLE_NAME}`);
  }
}
