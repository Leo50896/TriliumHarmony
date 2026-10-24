import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';

/**
 * Scroll offsets and the last opened note.
 *
 * The in-memory map keeps scrolling cheap; a debounced write mirrors the map
 * into preferences so a cold start can reopen the same note and offset.
 */
export class ReadingPositionStore {
  private static readonly FILE: string = 'trilium_reading';
  private static readonly KEY_LAST_NOTE: string = 'lastNoteId';
  private static readonly KEY_POSITIONS: string = 'positions';
  private static positions: Map<string, number> = new Map();
  private static lastNote: string = '';
  private static store: preferences.Preferences | null = null;
  private static writeTimer: number = -1;

  static async initialize(context: common.UIAbilityContext): Promise<void> {
    try {
      ReadingPositionStore.store = await preferences.getPreferences(context, ReadingPositionStore.FILE);
      const positionsValue: preferences.ValueType =
        await ReadingPositionStore.store.get(ReadingPositionStore.KEY_POSITIONS, '');
      if (typeof positionsValue === 'string' && positionsValue.length > 0) {
        const parsed: Record<string, number> = JSON.parse(positionsValue) as Record<string, number>;
        const keys: string[] = Object.keys(parsed);
        for (let i = 0; i < keys.length; i++) {
          const key: string = keys[i];
          const value: number = parsed[key];
          if (typeof value === 'number' && !isNaN(value)) {
            ReadingPositionStore.positions.set(key, Math.max(0, value));
          }
        }
      }
      const lastValue: preferences.ValueType =
        await ReadingPositionStore.store.get(ReadingPositionStore.KEY_LAST_NOTE, '');
      ReadingPositionStore.lastNote = typeof lastValue === 'string' ? lastValue : '';
    } catch (error) {
      ReadingPositionStore.store = null;
    }
  }

  static save(noteId: string, yOffset: number): void {
    if (noteId.length === 0 || isNaN(yOffset)) {
      return;
    }
    ReadingPositionStore.positions.set(noteId, Math.max(0, yOffset));
    ReadingPositionStore.scheduleWrite();
  }

  static get(noteId: string): number {
    if (noteId.length === 0) {
      return 0;
    }
    return ReadingPositionStore.positions.get(noteId) ?? 0;
  }

  static setLastNote(noteId: string): void {
    ReadingPositionStore.lastNote = noteId;
    ReadingPositionStore.scheduleWrite();
  }

  static lastNoteId(): string {
    return ReadingPositionStore.lastNote;
  }

  static clear(): void {
    ReadingPositionStore.positions.clear();
    ReadingPositionStore.lastNote = '';
    ReadingPositionStore.scheduleWrite();
  }

  static async flush(): Promise<void> {
    if (ReadingPositionStore.writeTimer !== -1) {
      clearTimeout(ReadingPositionStore.writeTimer);
      ReadingPositionStore.writeTimer = -1;
    }
    await ReadingPositionStore.persist();
  }

  private static scheduleWrite(): void {
    if (ReadingPositionStore.writeTimer !== -1) {
      clearTimeout(ReadingPositionStore.writeTimer);
    }
    ReadingPositionStore.writeTimer = setTimeout(() => {
      ReadingPositionStore.writeTimer = -1;
      ReadingPositionStore.persist();
    }, 600);
  }

  private static async persist(): Promise<void> {
    const store: preferences.Preferences | null = ReadingPositionStore.store;
    if (store === null) {
      return;
    }
    try {
      const noteIds: string[] = [];
      ReadingPositionStore.positions.forEach((value: number, key: string) => {
        noteIds.push(key);
      });
      const serialized: Record<string, number> = {};
      for (let i = 0; i < noteIds.length; i++) {
        const noteId: string = noteIds[i];
        serialized[noteId] = ReadingPositionStore.positions.get(noteId) ?? 0;
      }
      await store.put(ReadingPositionStore.KEY_POSITIONS, JSON.stringify(serialized));
      await store.put(ReadingPositionStore.KEY_LAST_NOTE, ReadingPositionStore.lastNote);
      await store.flush();
    } catch (error) {
      // A failed write must not interrupt reading; the in-memory map remains.
    }
  }
}
