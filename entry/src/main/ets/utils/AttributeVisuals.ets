/**
 * Small, shared attribute-to-visual mapping used by the drawer and the editor.
 * Trilium stores iconClass in Boxicons syntax (e.g. "bx bx-code") and color as
 * a CSS-like name or hex value.
 */
import { BOXICONS_ALL_MAP, BOXICONS_MAP } from './BoxiconsMap';

export class AttributeVisuals {
  static readonly FONT_FAMILY: string = 'boxicons';
  static color(value: string): string {
    const raw: string = value.trim();
    if (/^#([0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(raw)) {
      return raw;
    }
    if (/^([0-9a-f]{3}|[0-9a-f]{4}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(raw)) {
      return `#${raw}`;
    }
    const named: Record<string, string> = {
      'red': '#D92D20',
      'blue': '#2F80ED',
      'green': '#1F9D5A',
      'yellow': '#D4A017',
      'orange': '#E07A1F',
      'purple': '#8B5CF6',
      'pink': '#DB2777',
      'teal': '#0F9D9D',
      'cyan': '#0891B2',
      'brown': '#8B5E3C',
      'gray': '#6B7280',
      'grey': '#6B7280',
      'black': '#111827',
      'white': '#F9FAFB'
    };
    const key: string = raw.toLowerCase();
    return named[key] !== undefined ? named[key] : '#8A94A6';
  }

  /** Extracts the Boxicons name, e.g. "bx bx-code" -> "code". */
  static iconName(value: string): string {
    const match: RegExpMatchArray | null = value.match(/bx-([a-z0-9-]+)/i);
    return match !== null ? match[1].toLowerCase() : '';
  }

  /** Returns the exact glyph from Trilium's icon pack, or '' when unknown. */
  static glyph(value: string): string {
    const fullMatch: RegExpMatchArray | null =
      value.match(/\b(bx[s|l]?-[a-z0-9-]+)/i);
    if (fullMatch !== null) {
      const fullGlyph: string | undefined = BOXICONS_ALL_MAP[fullMatch[1]];
      if (fullGlyph !== undefined) {
        return fullGlyph;
      }
    }
    const name: string = AttributeVisuals.iconName(value);
    const glyph: string | undefined = BOXICONS_MAP[name];
    return glyph !== undefined ? glyph : '';
  }

  static hasGlyph(value: string): boolean {
    return AttributeVisuals.glyph(value).length > 0;
  }

  static hslToHex(hue: number, saturation: number, lightness: number): string {
    const h: number = ((hue % 360) + 360) % 360 / 360;
    const s: number = Math.max(0, Math.min(100, saturation)) / 100;
    const l: number = Math.max(0, Math.min(100, lightness)) / 100;
    if (s === 0) {
      const gray: number = Math.round(l * 255);
      return `#${AttributeVisuals.hex2(gray)}${AttributeVisuals.hex2(gray)}${AttributeVisuals.hex2(gray)}`;
    }
    const q: number = l < 0.5 ? l * (1 + s) : l + s - l * s;
    const p: number = 2 * l - q;
    return `#${AttributeVisuals.hex2(Math.round(AttributeVisuals.hue2rgb(p, q, h + 1 / 3) * 255))}` +
      `${AttributeVisuals.hex2(Math.round(AttributeVisuals.hue2rgb(p, q, h) * 255))}` +
      `${AttributeVisuals.hex2(Math.round(AttributeVisuals.hue2rgb(p, q, h - 1 / 3) * 255))}`;
  }

  static hexToHsl(value: string): number[] {
    const raw: string = AttributeVisuals.color(value).replace('#', '');
    if (raw.length < 6) {
      return [0, 0, 50];
    }
    const r: number = parseInt(raw.substring(0, 2), 16) / 255;
    const g: number = parseInt(raw.substring(2, 4), 16) / 255;
    const b: number = parseInt(raw.substring(4, 6), 16) / 255;
    const max: number = Math.max(r, g, b);
    const min: number = Math.min(r, g, b);
    const l: number = (max + min) / 2;
    if (max === min) {
      return [0, 0, Math.round(l * 100)];
    }
    const d: number = max - min;
    const s: number = l > 0.5 ? d / (2 - max - min) : d / (max + min);
    let h: number = 0;
    if (max === r) {
      h = (g - b) / d + (g < b ? 6 : 0);
    } else if (max === g) {
      h = (b - r) / d + 2;
    } else {
      h = (r - g) / d + 4;
    }
    return [Math.round(h * 60), Math.round(s * 100), Math.round(l * 100)];
  }

  private static hex2(value: number): string {
    const text: string = Math.max(0, Math.min(255, value)).toString(16);
    return text.length === 1 ? `0${text}` : text;
  }

  private static hue2rgb(p: number, q: number, t: number): number {
    let value: number = t;
    if (value < 0) {
      value += 1;
    }
    if (value > 1) {
      value -= 1;
    }
    if (value < 1 / 6) {
      return p + (q - p) * 6 * value;
    }
    if (value < 1 / 2) {
      return q;
    }
    if (value < 2 / 3) {
      return p + (q - p) * (2 / 3 - value) * 6;
    }
    return p;
  }

  /** Trilium's default icon family by note type. */
  static defaultGlyph(type: string, hasChildren: boolean = false): string {
    if (type === 'text' && hasChildren) {
      const folderGlyph: string | undefined = BOXICONS_MAP['folder'];
      return folderGlyph !== undefined ? folderGlyph : '';
    }
    const names: Record<string, string> = {
      'text': 'note',
      'code': 'code',
      'book': 'book',
      'image': 'image',
      'file': 'file',
      'spreadsheet': 'table',
      'pdf': 'file',
      'search': 'file-find',
      'relationMap': 'shape-polygon',
      'mindMap': 'sitemap',
      'canvas': 'pen',
      'webView': 'globe-alt',
      'launcher': 'link'
    };
    const name: string = names[type] ?? '';
    const glyph: string | undefined = BOXICONS_MAP[name];
    return glyph !== undefined ? glyph : '';
  }

  static icon(value: string): Resource {
    const name: string = AttributeVisuals.iconName(value);
    if (name.indexOf('code') >= 0) {
      return $r('app.media.ic_code');
    }
    if (name.indexOf('book') >= 0) {
      return $r('app.media.ic_book');
    }
    if (name.indexOf('calendar') >= 0 || name.indexOf('time') >= 0 ||
      name.indexOf('clock') >= 0 || name.indexOf('history') >= 0) {
      return $r('app.media.ic_calendar');
    }
    if (name.indexOf('check') >= 0 || name.indexOf('task') >= 0) {
      return $r('app.media.ic_checklist');
    }
    if (name.indexOf('folder') >= 0 || name.indexOf('archive') >= 0) {
      return $r('app.media.ic_folder');
    }
    if (name.indexOf('grid') >= 0 || name.indexOf('layout') >= 0 ||
      name.indexOf('table') >= 0) {
      return $r('app.media.ic_layout');
    }
    if (name.indexOf('tag') >= 0 || name.indexOf('purchase') >= 0) {
      return $r('app.media.ic_tag');
    }
    if (name.indexOf('lock') >= 0 || name.indexOf('shield') >= 0) {
      return $r('app.media.ic_lock');
    }
    if (name.indexOf('search') >= 0) {
      return $r('app.media.ic_search');
    }
    if (name.indexOf('cog') >= 0 || name.indexOf('setting') >= 0 ||
      name.indexOf('slider') >= 0) {
      return $r('app.media.ic_settings');
    }
    if (name.indexOf('server') >= 0 || name.indexOf('data') >= 0) {
      return $r('app.media.ic_server');
    }
    if (name.indexOf('sync') >= 0 || name.indexOf('refresh') >= 0) {
      return $r('app.media.ic_sync');
    }
    if (name.indexOf('palette') >= 0 || name.indexOf('color') >= 0 ||
      name.indexOf('paint') >= 0) {
      return $r('app.media.ic_theme');
    }
    if (name.indexOf('user') >= 0 || name.indexOf('group') >= 0) {
      return $r('app.media.ic_user');
    }
    if (name.indexOf('bookmark') >= 0 || name.indexOf('star') >= 0) {
      return $r('app.media.ic_bookmark');
    }
    if (name.indexOf('note') >= 0 || name.indexOf('file') >= 0 ||
      name.indexOf('doc') >= 0 || name.indexOf('notepad') >= 0) {
      return $r('app.media.ic_doc');
    }
    return $r('app.media.ic_doc');
  }
}
