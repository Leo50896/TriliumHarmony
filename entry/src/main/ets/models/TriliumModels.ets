export interface EtapiAttributePayload {
  attributeId?: string;
  noteId?: string;
  type?: string;
  name?: string;
  value?: string;
  isInheritable?: boolean;
}

/**
 * ETAPI notes are the external representation of Trilium notes. Only the
 * fields needed by the tree are modelled here; content is fetched separately.
 */
export interface EtapiNotePayload {
  noteId?: string;
  title?: string;
  type?: string;
  mime?: string;
  parentNoteIds?: string[];
  childNoteIds?: string[];
  parentBranchIds?: string[];
  childBranchIds?: string[];
  attributes?: EtapiAttributePayload[];
  dateCreated?: string;
  dateModified?: string;
  isProtected?: boolean;
}

export interface EtapiSearchPayload {
  results?: EtapiNotePayload[];
}

export class TriliumNote {
  noteId: string;
  title: string;
  type: string;
  mime: string;
  parentNoteIds: string[];
  childNoteIds: string[];
  attributes: EtapiAttributePayload[];
  dateCreated: string;
  dateModified: string;
  isProtected: boolean;
  notePosition: number;

  constructor(payload: EtapiNotePayload) {
    this.noteId = payload.noteId ?? '';
    this.title = payload.title ?? '';
    this.type = payload.type ?? 'text';
    this.mime = payload.mime ?? '';
    this.parentNoteIds = payload.parentNoteIds ?? [];
    this.childNoteIds = payload.childNoteIds ?? [];
    this.attributes = payload.attributes ?? [];
    this.dateCreated = payload.dateCreated ?? '';
    this.dateModified = payload.dateModified ?? '';
    this.isProtected = payload.isProtected ?? false;
    this.notePosition = 0;
  }

  hasVisibleChildren(): boolean {
    for (let index: number = 0; index < this.childNoteIds.length; index++) {
      if (!this.childNoteIds[index].startsWith('_')) {
        return true;
      }
    }
    return false;
  }

  visibleLabels(): string[] {
    const labels: string[] = [];
    for (let index: number = 0; index < this.attributes.length; index++) {
      const attribute: EtapiAttributePayload = this.attributes[index];
      if (attribute.type !== 'label' || attribute.name === undefined) {
        continue;
      }
      if (attribute.name.startsWith('_') || attribute.name.startsWith('child:') ||
        attribute.name.indexOf(':') >= 0) {
        continue;
      }
      const value: string = attribute.value ?? '';
      labels.push(value.length > 0 ? `#${attribute.name}=${value}` : `#${attribute.name}`);
      if (labels.length >= 4) {
        break;
      }
    }
    return labels;
  }
}

export class DrawerTreeNode {
  noteId: string;
  title: string;
  level: number;
  hasChildren: boolean;
  expanded: boolean;
  selected: boolean;
  type: string;
  isProtected: boolean;
  iconClass: string;

  constructor(noteId: string, title: string, level: number, hasChildren: boolean,
    expanded: boolean, selected: boolean, type: string, isProtected: boolean,
    iconClass: string = '') {
    this.noteId = noteId;
    this.title = title;
    this.level = level;
    this.hasChildren = hasChildren;
    this.expanded = expanded;
    this.selected = selected;
    this.type = type;
    this.isProtected = isProtected;
    this.iconClass = iconClass;
  }
}

export function isHiddenNoteId(noteId: string): boolean {
  return noteId.startsWith('_');
}

export class EtapiNoteTitlePatch {
  title: string;

  constructor(title: string) {
    this.title = title;
  }
}
