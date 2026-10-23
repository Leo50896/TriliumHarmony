import { StateKeys } from '../constants/StateKeys';

/**
 * Intercepts Trilium internal note links such as:
 *   #root/abc123
 *   #abc123
 *   /root/abc123
 *   trilium://root/abc123
 *
 * The selected note is written to AppStorage; EditorView is the only listener,
 * so no router stack or new page is involved.
 */
export class TriliumLinkRouter {
  static noteIdFromHref(href: string): string {
    let value: string = href.trim();
    try {
      value = decodeURIComponent(value);
    } catch (error) {
      // Keep the raw value when it is not valid percent-encoding.
    }
    const patterns: RegExp[] = [
      /^#root\/(?:[A-Za-z0-9_-]+\/)*([A-Za-z0-9_-]+)(?:\?|$)/,
      /^#([A-Za-z0-9_-]+)$/,
      /^\/root\/(?:[A-Za-z0-9_-]+\/)*([A-Za-z0-9_-]+)(?:\?|$)/,
      /^trilium:\/\/root\/(?:[A-Za-z0-9_-]+\/)*([A-Za-z0-9_-]+)(?:\?|$)/
    ];
    for (let index: number = 0; index < patterns.length; index++) {
      const match: RegExpMatchArray | null = value.match(patterns[index]);
      if (match !== null && match[1].length > 0) {
        return match[1];
      }
    }
    return '';
  }

  static open(href: string): boolean {
    const noteId: string = TriliumLinkRouter.noteIdFromHref(href);
    if (noteId.length === 0) {
      return false;
    }
    AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_ID, noteId);
    AppStorage.setOrCreate(StateKeys.SELECTED_NOTE_TITLE, '');
    return true;
  }
}
