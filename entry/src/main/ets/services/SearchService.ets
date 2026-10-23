import { AuthSession } from '../models/AuthModels';
import { SearchResultItem } from '../models/SearchModels';
import { TriliumNote } from '../models/TriliumModels';
import {
  ContentBlock,
  HtmlContentParser
} from '../utils/HtmlContentParser';
import { EtapiService } from './EtapiService';

const MAX_SEARCH_RESULTS: number = 12;
const DETAIL_BATCH_SIZE: number = 4;

/**
 * ETAPI search returns note payloads only (no path/highlight). This service
 * adds the two missing pieces:
 *   - path: walk parentNoteIds, sharing one per-search note cache
 *   - snippet: fetch text/code content and extract the query context
 */
export class SearchService {
  static async search(session: AuthSession, query: string): Promise<SearchResultItem[]> {
    const notes: TriliumNote[] = await EtapiService.search(session, query);
    const limited: TriliumNote[] = notes.slice(0, MAX_SEARCH_RESULTS);
    const noteCache: Map<string, TriliumNote> = new Map();
    const results: SearchResultItem[] = [];
    for (let index: number = 0; index < limited.length; index++) {
      const note: TriliumNote = limited[index];
      results.push(new SearchResultItem(note.noteId, note.title, note.type,
        '', '', note.isProtected));
    }

    for (let start: number = 0; start < results.length; start += DETAIL_BATCH_SIZE) {
      const end: number = Math.min(start + DETAIL_BATCH_SIZE, results.length);
      const batch: Promise<SearchResultItem>[] = [];
      for (let index: number = start; index < end; index++) {
        batch.push(SearchService.enrichItem(session, limited[index], results[index], query, noteCache));
      }
      const enriched: SearchResultItem[] = await Promise.all(batch);
      for (let index: number = 0; index < enriched.length; index++) {
        results[start + index] = enriched[index];
      }
    }
    return results;
  }

  private static async enrichItem(session: AuthSession, note: TriliumNote,
    item: SearchResultItem, query: string,
    noteCache: Map<string, TriliumNote>): Promise<SearchResultItem> {
    try {
      item.path = await SearchService.pathFor(session, note, noteCache);
    } catch (error) {
      if (error instanceof Error && error.message === 'AUTH_401') {
        throw error;
      }
      item.path = '根目录';
    }
    try {
      item.snippet = await SearchService.snippetFor(session, note, query);
    } catch (error) {
      if (error instanceof Error && error.message === 'AUTH_401') {
        throw error;
      }
      item.snippet = '';
    }
    return item;
  }

  private static async pathFor(session: AuthSession, note: TriliumNote,
    noteCache: Map<string, TriliumNote>): Promise<string> {
    const parts: string[] = [];
    let parentId: string = note.parentNoteIds.length > 0 ? note.parentNoteIds[0] : '';
    let guard: number = 0;
    while (parentId.length > 0 && parentId !== 'root' && guard < 10) {
      guard++;
      let parent: TriliumNote | undefined = noteCache.get(parentId);
      if (parent === undefined) {
        parent = await EtapiService.getNote(session, parentId);
        noteCache.set(parentId, parent);
      }
      if (parent.title.length > 0) {
        parts.unshift(parent.title);
      }
      parentId = parent.parentNoteIds.length > 0 ? parent.parentNoteIds[0] : '';
    }
    return parts.length > 0 ? parts.join(' / ') : '根目录';
  }

  private static async snippetFor(session: AuthSession, note: TriliumNote,
    query: string): Promise<string> {
    if (note.type !== 'text' && note.type !== 'code') {
      return '';
    }
    const content: string = await EtapiService.getNoteContent(session, note.noteId);
    if (content.trim().length === 0) {
      return '';
    }
    const blocks: ContentBlock[] = HtmlContentParser.parse(content, note.type, note.mime);
    const plain: string = HtmlContentParser.plainText(blocks)
      .replace(/\s+/g, ' ')
      .trim();
    if (plain.length === 0) {
      return '';
    }
    const lowerText: string = plain.toLowerCase();
    const lowerQuery: string = query.toLowerCase();
    const matchIndex: number = lowerText.indexOf(lowerQuery);
    let start: number = matchIndex >= 0 ? Math.max(0, matchIndex - 36) : 0;
    let end: number = matchIndex >= 0
      ? Math.min(plain.length, matchIndex + query.length + 80)
      : Math.min(plain.length, 120);
    let snippet: string = plain.substring(start, end);
    if (start > 0) {
      snippet = `…${snippet}`;
    }
    if (end < plain.length) {
      snippet = `${snippet}…`;
    }
    return snippet;
  }
}
