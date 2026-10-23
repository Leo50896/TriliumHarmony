import {
  EtapiAttributePayload,
  EtapiNotePayload,
  TriliumNote
} from './TriliumModels';

export class CachedNote {
  noteId: string;
  title: string;
  type: string;
  mime: string;
  dateModified: string;
  tags: string[];
  isProtected: boolean;
  content: string;
  cachedAt: number;

  constructor(noteId: string, title: string, type: string, mime: string,
    dateModified: string, tags: string[], isProtected: boolean,
    content: string, cachedAt: number) {
    this.noteId = noteId;
    this.title = title;
    this.type = type;
    this.mime = mime;
    this.dateModified = dateModified;
    this.tags = tags;
    this.isProtected = isProtected;
    this.content = content;
    this.cachedAt = cachedAt;
  }

  toTriliumNote(): TriliumNote {
    const attributes: EtapiAttributePayload[] = [];
    for (let index: number = 0; index < this.tags.length; index++) {
      const tag: string = this.tags[index].startsWith('#')
        ? this.tags[index].substring(1) : this.tags[index];
      attributes.push({
        type: 'label',
        name: tag,
        value: ''
      });
    }
    const payload: EtapiNotePayload = {
      noteId: this.noteId,
      title: this.title,
      type: this.type,
      mime: this.mime,
      dateModified: this.dateModified,
      attributes: attributes,
      isProtected: this.isProtected
    };
    return new TriliumNote(payload);
  }
}
