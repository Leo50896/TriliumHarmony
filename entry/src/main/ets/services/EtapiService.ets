import http from '@ohos.net.http';
import { AuthSession } from '../models/AuthModels';
import {
  EtapiAttributePayload,
  EtapiNotePayload,
  EtapiNoteTitlePatch,
  EtapiSearchPayload,
  isHiddenNoteId,
  TriliumNote
} from '../models/TriliumModels';
import { HttpService } from './HttpService';

const MAX_CONCURRENT_NOTE_REQUESTS: number = 6;

/**
 * Small ETAPI client for the drawer tree. It uses the ETAPI token from
 * `/api/login/token` directly in the Authorization header (no "Bearer").
 *
 * Tree loading is intentionally lazy: the root is fetched first, then only the
 * children of an expanded folder are requested. This keeps a large knowledge
 * base from producing one huge request on every app start.
 */
export class EtapiService {
  static async getNote(session: AuthSession, noteId: string): Promise<TriliumNote> {
    const baseUrl: string = EtapiService.normalizeBaseUrl(session.serverUrl);
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: {
        'Authorization': session.accessToken,
        'Accept': 'application/json'
      },
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 15000
    };

    const response: http.HttpResponse = await HttpService.request(
      `${baseUrl}/etapi/notes/${encodeURIComponent(noteId)}`,
      options
    );
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(`ETAPI_HTTP_${response.responseCode}`);
    }
    const text: string = typeof response.result === 'string'
      ? response.result : JSON.stringify(response.result);
    const payload: EtapiNotePayload = JSON.parse(text) as EtapiNotePayload;
    return new TriliumNote(payload);
  }

  static async getNotes(session: AuthSession, noteIds: string[]): Promise<TriliumNote[]> {
    const notes: TriliumNote[] = [];
    for (let start: number = 0; start < noteIds.length; start += MAX_CONCURRENT_NOTE_REQUESTS) {
      const batch: Promise<TriliumNote>[] = [];
      const end: number = Math.min(start + MAX_CONCURRENT_NOTE_REQUESTS, noteIds.length);
      for (let index: number = start; index < end; index++) {
        batch.push(EtapiService.getNote(session, noteIds[index]));
      }
      const loaded: TriliumNote[] = await Promise.all(batch);
      for (let index: number = 0; index < loaded.length; index++) {
        notes.push(loaded[index]);
      }
    }
    return notes;
  }

  static async getRoot(session: AuthSession): Promise<TriliumNote> {
    return EtapiService.getNote(session, 'root');
  }

  static async search(session: AuthSession, query: string): Promise<TriliumNote[]> {
    const baseUrl: string = EtapiService.normalizeBaseUrl(session.serverUrl);
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: {
        'Authorization': session.accessToken,
        'Accept': 'application/json'
      },
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 20000
    };

    const response: http.HttpResponse = await HttpService.request(
      `${baseUrl}/etapi/notes?search=${encodeURIComponent(query)}`,
      options
    );
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(`ETAPI_HTTP_${response.responseCode}`);
    }
    const text: string = typeof response.result === 'string'
      ? response.result : JSON.stringify(response.result);
    const payload: EtapiSearchPayload = JSON.parse(text) as EtapiSearchPayload;
    const rawResults: EtapiNotePayload[] = payload.results ?? [];
    const notes: TriliumNote[] = [];
    for (let index: number = 0; index < rawResults.length; index++) {
      const note: TriliumNote = new TriliumNote(rawResults[index]);
      if (note.noteId.length > 0 && !isHiddenNoteId(note.noteId)) {
        notes.push(note);
      }
    }
    return notes;
  }

  static async getAllNotes(session: AuthSession): Promise<TriliumNote[]> {
    const root: TriliumNote = await EtapiService.getRoot(session);
    console.info(`ETAPI_BFS rootChildren=${root.childNoteIds.length}`);
    const notes: TriliumNote[] = [root];
    const seen: Set<string> = new Set();
    const pending: string[] = root.childNoteIds.slice();
    for (let index: number = 0; index < pending.length; index++) {
      seen.add(pending[index]);
    }
    while (pending.length > 0) {
      const batchIds: string[] = pending.splice(0, 50);
      const loaded: TriliumNote[] = await EtapiService.getNotes(session, batchIds);
      console.info(`ETAPI_BFS batch=${batchIds.length} loaded=${loaded.length} total=${notes.length}`);
      for (let index: number = 0; index < loaded.length; index++) {
        const note: TriliumNote = loaded[index];
        if (isHiddenNoteId(note.noteId)) {
          continue;
        }
        notes.push(note);
        for (let child: number = 0; child < note.childNoteIds.length; child++) {
          const childId: string = note.childNoteIds[child];
          if (!seen.has(childId)) {
            seen.add(childId);
            pending.push(childId);
          }
        }
      }
    }
    console.info(`ETAPI_BFS done total=${notes.length}`);
    const byId: Map<string, TriliumNote> = new Map();
    for (let index: number = 0; index < notes.length; index++) {
      byId.set(notes[index].noteId, notes[index]);
    }
    for (let index: number = 0; index < notes.length; index++) {
      const parent: TriliumNote = notes[index];
      for (let childIndex: number = 0; childIndex < parent.childNoteIds.length; childIndex++) {
        const child: TriliumNote | undefined = byId.get(parent.childNoteIds[childIndex]);
        if (child !== undefined) {
          child.notePosition = childIndex;
        }
      }
    }
    return notes;
  }

  static async getNoteBinaryContent(session: AuthSession, noteId: string): Promise<ArrayBuffer> {
    const baseUrl: string = EtapiService.normalizeBaseUrl(session.serverUrl);
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: {
        'Authorization': session.accessToken,
        'Accept': 'application/pdf, application/octet-stream, */*'
      },
      expectDataType: http.HttpDataType.ARRAY_BUFFER,
      connectTimeout: 10000,
      readTimeout: 30000
    };
    const response: http.HttpResponse = await HttpService.request(
      `${baseUrl}/etapi/notes/${encodeURIComponent(noteId)}/content`,
      options
    );
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(`ETAPI_HTTP_${response.responseCode}`);
    }
    if (response.result instanceof ArrayBuffer) {
      return response.result;
    }
    throw new Error('ETAPI_BINARY_INVALID');
  }

  static async getNoteContent(session: AuthSession, noteId: string): Promise<string> {    const baseUrl: string = EtapiService.normalizeBaseUrl(session.serverUrl);
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.GET,
      header: {
        'Authorization': session.accessToken,
        'Accept': 'text/plain'
      },
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 20000
    };

    const response: http.HttpResponse = await HttpService.request(
      `${baseUrl}/etapi/notes/${encodeURIComponent(noteId)}/content`,
      options
    );
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(`ETAPI_HTTP_${response.responseCode}`);
    }
    return typeof response.result === 'string' ? response.result : '';
  }

  static async updateNoteContent(session: AuthSession, noteId: string, content: string): Promise<void> {
    const baseUrl: string = EtapiService.normalizeBaseUrl(session.serverUrl);
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.PUT,
      header: {
        'Authorization': session.accessToken,
        'Content-Type': 'text/plain; charset=utf-8',
        'Accept': 'application/json'
      },
      extraData: content,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 20000
    };

    const response: http.HttpResponse = await HttpService.request(
      `${baseUrl}/etapi/notes/${encodeURIComponent(noteId)}/content`,
      options
    );
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(`ETAPI_HTTP_${response.responseCode}`);
    }
  }

  private static async attributeRequest(session: AuthSession, method: http.RequestMethod,
    path: string, body: string): Promise<string> {
    const baseUrl: string = EtapiService.normalizeBaseUrl(session.serverUrl);
    const response: http.HttpResponse = await HttpService.request(`${baseUrl}${path}`, {
      method: method,
      header: {
        'Authorization': session.accessToken,
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      extraData: body,
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 20000
    });
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(`ETAPI_HTTP_${response.responseCode}`);
    }
    return typeof response.result === 'string' ? response.result : '';
  }

  static async addAttribute(session: AuthSession, noteId: string, type: string,
    name: string, value: string): Promise<EtapiAttributePayload> {
    const body: string = JSON.stringify({
      'noteId': noteId,
      'type': type,
      'name': name,
      'value': value
    });
    const text: string = await EtapiService.attributeRequest(session,
      http.RequestMethod.POST, '/etapi/attributes', body);
    try {
      return JSON.parse(text) as EtapiAttributePayload;
    } catch (error) {
      return {};
    }
  }

  static async updateAttribute(session: AuthSession, attributeId: string,
    value: string): Promise<void> {
    await EtapiService.attributeRequest(session, http.RequestMethod.PATCH,
      `/etapi/attributes/${encodeURIComponent(attributeId)}`,
      JSON.stringify({ 'value': value }));
  }

  static async deleteAttribute(session: AuthSession, attributeId: string): Promise<void> {
    const baseUrl: string = EtapiService.normalizeBaseUrl(session.serverUrl);
    const response: http.HttpResponse = await HttpService.request(
      `${baseUrl}/etapi/attributes/${encodeURIComponent(attributeId)}`, {
        method: http.RequestMethod.DELETE,
        header: {
          'Authorization': session.accessToken,
          'Accept': 'application/json'
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 20000
      });
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(`ETAPI_HTTP_${response.responseCode}`);
    }
  }

  static async deleteNote(session: AuthSession, noteId: string): Promise<void> {
    const baseUrl: string = EtapiService.normalizeBaseUrl(session.serverUrl);
    const response: http.HttpResponse = await HttpService.request(
      `${baseUrl}/etapi/notes/${encodeURIComponent(noteId)}`, {
        method: http.RequestMethod.DELETE,
        header: {
          'Authorization': session.accessToken,
          'Accept': 'application/json'
        },
        expectDataType: http.HttpDataType.STRING,
        connectTimeout: 10000,
        readTimeout: 20000
      });
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(`ETAPI_HTTP_${response.responseCode}`);
    }
  }

  static async updateNoteTitle(session: AuthSession, noteId: string, title: string): Promise<TriliumNote> {
    const baseUrl: string = EtapiService.normalizeBaseUrl(session.serverUrl);
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.PATCH,
      header: {
        'Authorization': session.accessToken,
        'Content-Type': 'application/json',
        'Accept': 'application/json'
      },
      extraData: JSON.stringify(new EtapiNoteTitlePatch(title)),
      expectDataType: http.HttpDataType.STRING,
      connectTimeout: 10000,
      readTimeout: 15000
    };

    const response: http.HttpResponse = await HttpService.request(
      `${baseUrl}/etapi/notes/${encodeURIComponent(noteId)}`,
      options
    );
    if (response.responseCode < 200 || response.responseCode >= 300) {
      throw new Error(`ETAPI_HTTP_${response.responseCode}`);
    }
    const text: string = typeof response.result === 'string'
      ? response.result : JSON.stringify(response.result);
    return new TriliumNote(JSON.parse(text) as EtapiNotePayload);
  }

  private static normalizeBaseUrl(value: string): string {
    let result: string = value.trim();
    while (result.endsWith('/')) {
      result = result.substring(0, result.length - 1);
    }
    return result;
  }
}
