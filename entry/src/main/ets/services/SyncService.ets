import { common } from '@kit.AbilityKit';
import { AuthSession } from '../models/AuthModels';
import { TriliumNote } from '../models/TriliumModels';
import { EtapiService } from './EtapiService';
import {
  LocalMutation,
  LocalMutationKind,
  LocalNote,
  LocalStore
} from './LocalStore';

export class SyncResult {
  fullSync: boolean;
  pulled: number;
  maxChangeId: string;

  constructor(fullSync: boolean, pulled: number, maxChangeId: string) {
    this.fullSync = fullSync;
    this.pulled = pulled;
    this.maxChangeId = maxChangeId;
  }
}

/**
 * Pure ETAPI synchronisation.
 *
 * The server metadata tree is pulled in full (a few KB for a normal notebook)
 * and compared with the local copy. Content is fetched only for new or changed
 * notes. This intentionally has no dependency on the browser session or
 * /api/sync.
 */
export class SyncService {
  static readonly NOTES_UPDATED_KEY: string = 'notesUpdated';

  private static isSystemNote(noteId: string): boolean {
    return noteId === 'root' || noteId === 'trilium' || noteId.startsWith('_');
  }

  private static async etapiDelta(context: common.UIAbilityContext, session: AuthSession,
    accountKey: string): Promise<SyncResult> {
    // Push local edits before pulling. If this fails, a stale remote copy must
    // not overwrite the dirty local rows.
    const pending: number = await LocalStore.pendingCount(context, accountKey);
    if (pending > 0) {
      await SyncService.pushPending(context, session, accountKey);
    }
    const remote: TriliumNote[] = await EtapiService.getAllNotes(session);
    const local: TriliumNote[] = await LocalStore.all(context, accountKey);
    const lastSync: number = await LocalStore.lastSyncTime(context, accountKey);
    console.info(`ETAPI_DELTA remote=${remote.length} local=${local.length} lastSync=${lastSync}`);

    const localById: Map<string, TriliumNote> = new Map();
    for (let index: number = 0; index < local.length; index++) {
      localById.set(local[index].noteId, local[index]);
    }
    const remoteIds: Set<string> = new Set();
    for (let index: number = 0; index < remote.length; index++) {
      remoteIds.add(remote[index].noteId);
    }

    const mutations: LocalMutation[] = [];
    const parentUpdates: string[] = [];
    const positionUpdates: string[] = [];
    const attributeUpdates: TriliumNote[] = [];
    let inserts: number = 0;
    let updates: number = 0;
    let deletes: number = 0;

    for (let index: number = 0; index < remote.length; index++) {
      if (index > 0 && index % 8 === 0) {
        await SyncService.yieldToUi();
      }
      const note: TriliumNote = remote[index];
      const existing: TriliumNote | undefined = localById.get(note.noteId);
      if (existing !== undefined && JSON.stringify(existing.parentNoteIds) !==
        JSON.stringify(note.parentNoteIds)) {
        parentUpdates.push(note.noteId);
      }
      if (existing !== undefined && existing.notePosition !== note.notePosition) {
        positionUpdates.push(note.noteId);
      }
      if (existing !== undefined && existing.dateModified === note.dateModified) {
        if (JSON.stringify(existing.attributes) !== JSON.stringify(note.attributes)) {
          attributeUpdates.push(note);
        }
        continue;
      }
      console.info(`ETAPI_DELTA change id=${note.noteId} date=${note.dateModified} ` +
        `existing=${existing !== undefined ? existing.dateModified : 'missing'}`);
      let content: string = '';
      let contentCached: boolean = false;
      if (!note.isProtected && (note.type === 'text' || note.type === 'code' ||
        note.type === 'spreadsheet')) {
        try {
          content = await EtapiService.getNoteContent(session, note.noteId);
          contentCached = true;
        } catch (error) {
          content = '';
          contentCached = false;
        }
      }
      mutations.push(new LocalMutation(LocalMutationKind.UPSERT, note.noteId,
        note, content, contentCached));
      if (existing === undefined) {
        inserts++;
      } else {
        updates++;
      }
    }

    if (remote.length > 0) {
      for (let index: number = 0; index < local.length; index++) {
        if (index > 0 && index % 20 === 0) {
          await SyncService.yieldToUi();
        }
        const noteId: string = local[index].noteId;
        if (!remoteIds.has(noteId) && !SyncService.isSystemNote(noteId)) {
          console.info(`ETAPI_DELTA delete id=${noteId}`);
          mutations.push(new LocalMutation(LocalMutationKind.DELETE, noteId));
          deletes++;
        }
      }
    }

    if (mutations.length > 0) {
      try {
        await LocalStore.applyMutations(context, accountKey, mutations, '');
      } catch (error) {
        console.error(`ETAPI_DELTA apply failed ${error instanceof Error ? error.message : 'unknown'}`);
        if (error instanceof Error) {
          throw error;
        }
        throw new Error('LOCAL_MUTATION_FAILED');
      }
    }
    for (let index: number = 0; index < parentUpdates.length; index++) {
      const noteId: string = parentUpdates[index];
      const note: TriliumNote | undefined = remote.find((item: TriliumNote) => item.noteId === noteId);
      if (note !== undefined) {
        await LocalStore.updateParents(context, accountKey, noteId, note.parentNoteIds);
      }
    }
    for (let index: number = 0; index < positionUpdates.length; index++) {
      const noteId: string = positionUpdates[index];
      const note: TriliumNote | undefined = remote.find((item: TriliumNote) => item.noteId === noteId);
      if (note !== undefined) {
        await LocalStore.updatePosition(context, accountKey, noteId, note.notePosition);
      }
    }
    for (let index: number = 0; index < attributeUpdates.length; index++) {
      await LocalStore.updateAttributes(context, accountKey,
        attributeUpdates[index].noteId, attributeUpdates[index].attributes);
    }
    if (mutations.length > 0 || parentUpdates.length > 0 || positionUpdates.length > 0 ||
      attributeUpdates.length > 0) {
      AppStorage.setOrCreate(SyncService.NOTES_UPDATED_KEY, true);
      console.info(`ETAPI_DELTA signal notesUpdated=true inserted=${inserts} ` +
        `updated=${updates} deleted=${deletes} parents=${parentUpdates.length} ` +
        `positions=${positionUpdates.length}`);
    }
    await LocalStore.setLastSyncTime(context, accountKey, Date.now());
    console.info(`ETAPI_DELTA done changes=${mutations.length}`);
    return new SyncResult(false, mutations.length + parentUpdates.length + positionUpdates.length, '');
  }

  static async pushPending(context: common.UIAbilityContext, session: AuthSession,
    accountKey: string): Promise<number> {
    const pending: LocalNote[] = await LocalStore.pendingNotes(context, accountKey);
    let pushed: number = 0;
    for (let index: number = 0; index < pending.length; index++) {
      const local: LocalNote = pending[index];
      await EtapiService.updateNoteTitle(session, local.note.noteId, local.note.title);
      await EtapiService.updateNoteContent(session, local.note.noteId, local.content);
      await LocalStore.markSynced(context, accountKey, local.note.noteId);
      pushed++;
      console.info(`SYNC_PUSH_OK note=${local.note.noteId} remaining=${pending.length - index - 1}`);
    }
    return pushed;
  }

  static async sync(context: common.UIAbilityContext, session: AuthSession,
    accountKey: string): Promise<SyncResult> {
    if (!(await LocalStore.hasData(context, accountKey))) {
      const count: number = await LocalStore.syncAll(context, session, accountKey);
      await LocalStore.setLastSyncTime(context, accountKey, Date.now());
      AppStorage.setOrCreate(SyncService.NOTES_UPDATED_KEY, true);
      return new SyncResult(true, count, '');
    }
    return SyncService.etapiDelta(context, session, accountKey);
  }

  private static yieldToUi(): Promise<void> {
    return new Promise<void>((resolve: () => void) => {
      setTimeout(() => resolve(), 0);
    });
  }
}
