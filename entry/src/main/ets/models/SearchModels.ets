export class SearchResultItem {
  noteId: string;
  title: string;
  type: string;
  path: string;
  snippet: string;
  isProtected: boolean;

  constructor(noteId: string, title: string, type: string, path: string,
    snippet: string, isProtected: boolean) {
    this.noteId = noteId;
    this.title = title;
    this.type = type;
    this.path = path;
    this.snippet = snippet;
    this.isProtected = isProtected;
  }
}
