import { common } from '@kit.AbilityKit';
import fs from '@ohos.file.fs';
import image from '@ohos.multimedia.image';
import cryptoFramework from '@ohos.security.cryptoFramework';
import util from '@ohos.util';

const IMAGE_DIR_NAME: string = 'images';
const MAX_FILES: number = 80;
const MAX_BYTES: number = 50 * 1024 * 1024;

export class CachedImage {
  pixelMap: image.PixelMap;
  ratio: number;

  constructor(pixelMap: image.PixelMap, ratio: number) {
    this.pixelMap = pixelMap;
    this.ratio = ratio;
  }
}

/**
 * File-backed LRU cache for Trilium images.
 *
 * Files live under <cacheDir>/images/<md5>.img. Reading a file completely skips
 * the network; a successful download is written asynchronously and converted to
 * a PixelMap from the same ArrayBuffer.
 */
export class ImageDiskCache {
  private static directory(context: common.UIAbilityContext): string {
    return `${context.cacheDir}/${IMAGE_DIR_NAME}`;
  }

  private static ensureDirectory(context: common.UIAbilityContext): string {
    const dir: string = ImageDiskCache.directory(context);
    try {
      if (!fs.accessSync(dir)) {
        fs.mkdirSync(dir, true);
      }
    } catch (error) {
      // If the directory already exists, access/mkdir can still throw on some
      // sandbox implementations; callers will treat the cache as unavailable.
    }
    return dir;
  }

  static keyForSync(serverUrl: string, src: string): string {
    let path: string = src;
    const absolute: RegExpMatchArray | null = src.match(/^https?:\/\/[^/]+(\/.*)$/i);
    if (absolute !== null) {
      path = absolute[1];
    }
    if (path.length > 0 && !path.startsWith('/')) {
      path = `/${path}`;
    }
    return ImageDiskCache.fallbackHash(`v3|${path}`);
  }

  static async keyFor(serverUrl: string, src: string): Promise<string> {
    return ImageDiskCache.keyForSync(serverUrl, src);
  }

  private static async hash(value: string): Promise<string> {
    try {
      const encoder: util.TextEncoder = new util.TextEncoder();
      const bytes: Uint8Array = encoder.encodeInto(value);
      const md: cryptoFramework.Md = cryptoFramework.createMd('MD5');
      await md.update({ data: bytes });
      const digest: cryptoFramework.DataBlob = await md.digest();
      let hex: string = '';
      for (let index: number = 0; index < digest.data.length; index++) {
        hex += digest.data[index].toString(16).padStart(2, '0');
      }
      if (hex.length > 0) {
        return hex;
      }
    } catch (error) {
      // Fall through to the deterministic fallback below.
    }
    return ImageDiskCache.fallbackHash(value);
  }

  private static fallbackHash(value: string): string {
    let first: number = 2166136261;
    let second: number = 2246822519;
    for (let index: number = 0; index < value.length; index++) {
      const code: number = value.charCodeAt(index);
      first = Math.imul(first ^ code, 16777619);
      second = Math.imul(second ^ code, 3266489917);
    }
    return `${(first >>> 0).toString(16).padStart(8, '0')}${(second >>> 0).toString(16).padStart(8, '0')}`;
  }

  static async read(context: common.UIAbilityContext, key: string): Promise<CachedImage | null> {
    const dir: string = ImageDiskCache.ensureDirectory(context);
    const path: string = `${dir}/${key}.img`;
    try {
      if (!fs.accessSync(path)) {
        return null;
      }
      const source: image.ImageSource = image.createImageSource(path);
      try {
        const info: image.ImageInfo = await source.getImageInfo();
        const ratio: number = info.size.width > 0 && info.size.height > 0
          ? info.size.width / info.size.height : 1;
        const pixelMap: image.PixelMap = await source.createPixelMap();
        try {
          fs.utimes(path, Date.now());
        } catch (error) {
          // Touch is an LRU hint; a failed touch must not discard the image.
        }
        return new CachedImage(pixelMap, ratio);
      } finally {
        await source.release();
      }
    } catch (error) {
      try {
        if (fs.accessSync(path)) {
          fs.unlinkSync(path);
        }
      } catch (cleanupError) {
        // Ignore a corrupt cache entry that cannot be removed.
      }
      return null;
    }
  }

  static async write(context: common.UIAbilityContext, key: string,
    buffer: ArrayBuffer): Promise<void> {
    const dir: string = ImageDiskCache.ensureDirectory(context);
    const path: string = `${dir}/${key}.img`;
    const file: fs.File = fs.openSync(path,
      fs.OpenMode.CREATE | fs.OpenMode.READ_WRITE | fs.OpenMode.TRUNC);
    try {
      fs.writeSync(file.fd, buffer);
    } finally {
      fs.closeSync(file);
    }
    ImageDiskCache.evict(context);
  }

  static async readBuffer(context: common.UIAbilityContext,
    key: string): Promise<ArrayBuffer | null> {
    const dir: string = ImageDiskCache.ensureDirectory(context);
    const path: string = `${dir}/${key}.img`;
    try {
      if (!fs.accessSync(path)) {
        return null;
      }
      const stat: fs.Stat = fs.statSync(path);
      if (stat.size <= 0) {
        return null;
      }
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        fs.readSync(file.fd, buffer);
      } finally {
        fs.closeSync(file);
      }
      return buffer;
    } catch (error) {
      return null;
    }
  }

  static readBufferSync(context: common.UIAbilityContext,
    key: string): ArrayBuffer | null {
    const dir: string = ImageDiskCache.ensureDirectory(context);
    const path: string = `${dir}/${key}.img`;
    try {
      if (!fs.accessSync(path)) {
        return null;
      }
      const stat: fs.Stat = fs.statSync(path);
      if (stat.size <= 0) {
        return null;
      }
      const buffer: ArrayBuffer = new ArrayBuffer(stat.size);
      const file: fs.File = fs.openSync(path, fs.OpenMode.READ_ONLY);
      try {
        fs.readSync(file.fd, buffer);
      } finally {
        fs.closeSync(file);
      }
      return buffer;
    } catch (error) {
      return null;
    }
  }

  private static evict(context: common.UIAbilityContext): void {
    const dir: string = ImageDiskCache.directory(context);
    try {
      const names: string[] = fs.listFileSync(dir);
      const files: CacheFileInfo[] = [];
      let total: number = 0;
      for (let index: number = 0; index < names.length; index++) {
        if (!names[index].endsWith('.img')) {
          continue;
        }
        const path: string = `${dir}/${names[index]}`;
        try {
          const stat: fs.Stat = fs.statSync(path);
          files.push(new CacheFileInfo(path, stat.mtime, stat.size));
          total += stat.size;
        } catch (error) {
          // File disappeared between list and stat.
        }
      }
      files.sort((left: CacheFileInfo, right: CacheFileInfo) => left.mtime - right.mtime);
      let index: number = 0;
      while ((files.length - index > MAX_FILES || total > MAX_BYTES) && index < files.length) {
        try {
          fs.unlinkSync(files[index].path);
          total -= files[index].size;
        } catch (error) {
          // Best-effort eviction.
        }
        index++;
      }
    } catch (error) {
      // Cache maintenance is best-effort.
    }
  }

  static async clear(context: common.UIAbilityContext): Promise<void> {
    const dir: string = ImageDiskCache.directory(context);
    try {
      if (!fs.accessSync(dir)) {
        return;
      }
      const names: string[] = fs.listFileSync(dir);
      for (let index: number = 0; index < names.length; index++) {
        try {
          fs.unlinkSync(`${dir}/${names[index]}`);
        } catch (error) {
          // Continue clearing the remaining files.
        }
      }
    } catch (error) {
      // Nothing to clear or cache is unavailable.
    }
  }
}

class CacheFileInfo {
  path: string;
  mtime: number;
  size: number;

  constructor(path: string, mtime: number, size: number) {
    this.path = path;
    this.mtime = mtime;
    this.size = size;
  }
}
