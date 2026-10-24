import { ContentBlock, ContentBlockKind } from '../utils/HtmlContentParser';

export enum BlockEditMode {
  INLINE = 0,
  CODE = 1,
  STRUCTURED = 2,
  OPAQUE = 3
}

export class BlockRendererSpec {
  mode: BlockEditMode;
  inlineEditable: boolean;
  editorKey: string;

  constructor(mode: BlockEditMode, inlineEditable: boolean, editorKey: string) {
    this.mode = mode;
    this.inlineEditable = inlineEditable;
    this.editorKey = editorKey;
  }
}

/**
 * Strategy table for block rendering/editing.
 *
 * This class deliberately contains no UI and no save logic: it only decides
 * which editor family a block belongs to.
 */
export class BlockRendererRegistry {
  static resolve(block: ContentBlock): BlockRendererSpec {
    switch (block.kind) {
      case ContentBlockKind.PARAGRAPH:
        return new BlockRendererSpec(BlockEditMode.INLINE, true, 'paragraph');
      case ContentBlockKind.HEADING:
        return new BlockRendererSpec(BlockEditMode.INLINE, true, 'heading');
      case ContentBlockKind.LIST:
        return new BlockRendererSpec(BlockEditMode.STRUCTURED, false, 'list');
      case ContentBlockKind.QUOTE:
        return new BlockRendererSpec(BlockEditMode.STRUCTURED, false, 'quote');
      case ContentBlockKind.CODE:
        return new BlockRendererSpec(BlockEditMode.CODE, false, 'code');
      case ContentBlockKind.TABLE:
        return new BlockRendererSpec(BlockEditMode.STRUCTURED, false, 'table');
      case ContentBlockKind.IMAGE:
        return new BlockRendererSpec(BlockEditMode.STRUCTURED, false, 'image');
      case ContentBlockKind.CALLOUT:
        return new BlockRendererSpec(BlockEditMode.STRUCTURED, false, 'callout');
      case ContentBlockKind.COLLAPSIBLE:
        return new BlockRendererSpec(BlockEditMode.STRUCTURED, false, 'collapsible');
      case ContentBlockKind.INCLUDE:
        return new BlockRendererSpec(BlockEditMode.STRUCTURED, false, 'include');
      case ContentBlockKind.LINK_EMBED:
        return new BlockRendererSpec(BlockEditMode.STRUCTURED, false, 'link-embed');
      case ContentBlockKind.FOOTNOTES:
        return new BlockRendererSpec(BlockEditMode.STRUCTURED, false, 'footnotes');
      case ContentBlockKind.RAW:
        return new BlockRendererSpec(BlockEditMode.OPAQUE, false, 'raw');
      default:
        return new BlockRendererSpec(BlockEditMode.OPAQUE, false, 'unknown');
    }
  }
}
