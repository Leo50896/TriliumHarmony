import { ContentBlockKind } from '../utils/HtmlContentParser';

/**
 * Address of one editable target inside a block.
 *
 * `childPath` is reserved for nested block trees (list items, quote children,
 * table cells). It is empty when the block itself is the target.
 */
export class BlockTarget {
  blockId: string;
  childPath: number[];
  kind: ContentBlockKind;

  constructor(blockId: string, childPath: number[] = [], kind: ContentBlockKind = ContentBlockKind.PARAGRAPH) {
    this.blockId = blockId;
    this.childPath = childPath.slice();
    this.kind = kind;
  }

  isSame(other: BlockTarget | null): boolean {
    if (other === null || this.blockId !== other.blockId || this.kind !== other.kind) {
      return false;
    }
    if (this.childPath.length !== other.childPath.length) {
      return false;
    }
    for (let i = 0; i < this.childPath.length; i++) {
      if (this.childPath[i] !== other.childPath[i]) {
        return false;
      }
    }
    return true;
  }

  static forBlock(blockId: string, kind: ContentBlockKind, childPath: number[] = []): BlockTarget {
    return new BlockTarget(blockId, childPath, kind);
  }
}
