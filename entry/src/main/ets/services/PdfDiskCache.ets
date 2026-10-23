import fs from '@ohos.file.fs';
import { common } from '@kit.AbilityKit';

/**
 * Small LRU disk cache for PDF binaries.
 *
 * Files live under <cacheDir>/pdf/<noteId>.pdf and are passed directly to
 * PdfController.loadDocument, so the PDF Kit never needs the network once a
 * document has been cached.
 */
export class PdfDiskCache {
  private static readonly DIR_NAME: string = 'pdf';
  private static readonly MAX_FILES: number = 5;
  private static readonly MAX_BYTES: number = 50 * 1024 * 1024;

  private static directory(context: common.UIAbilityContext): string {
    return `${context.cacheDir}/${PdfDiskCache.DIR_NAME}`;
  }

  private static filePath(context: common.UIAbilityContext, noteId: string): string {
    return `${PdfDiskCache.directory(context)}/${encodeURIComponent(noteId)}.pdf`;
  }

  static find(context: common.UIAbilityContext, noteId: string): string {
    const path: string = PdfDiskCache.filePath(context, noteId);
    try {
      if (!fs.accessSync(path)) {
        return '';
      }
      const stat: fs.Stat = fs.statSync(path);
      return stat.size > 0 ? path : '';
    } catch (error) {
      return '';
    }
  }

  static async write(context: common.UIAbilityContext, noteId: string,
    buffer: ArrayBuffer): Promise<string> {
    const dir: string = PdfDiskCache.directory(context);
    const path: string = PdfDiskCache.filePath(context, noteId);
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir);
      }
      const file: fs.File = fs.openSync(path,
        fs.OpenMode.CREATE | fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
      try {
        fs.writeSync(file.fd, buffer);
      } finally {
        fs.closeSync(file);
      }
      PdfDiskCache.trim(context);
      return path;
    } catch (error) {
      return '';
    }
  }

  private static trim(context: common.UIAbilityContext): void {
    try {
      const dir: string = PdfDiskCache.directory(context);
      const names: string[] = fs.listFileSync(dir);
      const entries: CacheEntry[] = [];
      for (let i: number = 0; i < names.length; i++) {
        if (!names[i].endsWith('.pdf')) {
          continue;
        }
        const path: string = `${dir}/${names[i]}`;
        try {
          const stat: fs.Stat = fs.statSync(path);
          entries.push(new CacheEntry(path, stat.size, stat.mtime * 1000));
        } catch (error) {
          // Ignore a file that disappeared during the scan.
        }
      }
      entries.sort((a: CacheEntry, b: CacheEntry): number => b.modifiedAt - a.modifiedAt);
      let total: number = 0;
      for (let i: number = 0; i < entries.length; i++) {
        total += entries[i].size;
        if (i >= PdfDiskCache.MAX_FILES || total > PdfDiskCache.MAX_BYTES) {
          try {
            fs.unlinkSync(entries[i].path);
          } catch (error) {
            // Best-effort eviction only.
          }
        }
      }
    } catch (error) {
      // Cache trimming must never block PDF loading.
    }
  }
}

class CacheEntry {
  path: string;
  size: number;
  modifiedAt: number;

  constructor(path: string, size: number, modifiedAt: number) {
    this.path = path;
    this.size = size;
    this.modifiedAt = modifiedAt;
  }
}
