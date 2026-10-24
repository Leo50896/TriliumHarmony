import { ContentBlock, ContentBlockKind } from '../HtmlContentParser';
import { TriliumCodec } from './TriliumCodec';

class GoldenCase {
  name: string;
  input: string;
  format: string;

  constructor(name: string, input: string, format: string) {
    this.name = name;
    this.input = input;
    this.format = format;
  }
}

/**
 * Minimal in-app golden suite for the codec migration.
 *
 * It is intentionally plain ArkTS rather than a Hypium suite so it can run in
 * both the Previewer and a real device without adding a test-only dependency.
 */
export class CodecGoldenTests {
  static runAll(): boolean {
    const cases: GoldenCase[] = CodecGoldenTests.cases();
    let passed: number = 0;
    for (let i = 0; i < cases.length; i++) {
      const testCase: GoldenCase = cases[i];
      try {
        const blocks: ContentBlock[] = TriliumCodec.parseToModel(testCase.input, testCase.format);
        const output: string = TriliumCodec.serializeToRaw(blocks, testCase.format);
        if (output === testCase.input) {
          passed++;
          console.info(`CODEC_GOLDEN PASS ${testCase.name} blocks=${blocks.length}`);
        } else {
          console.error(`CODEC_GOLDEN FAIL ${testCase.name} ` +
            `in=${testCase.input.length} out=${output.length}`);
        }
      } catch (error) {
        console.error(`CODEC_GOLDEN ERROR ${testCase.name} ${JSON.stringify(error)}`);
      }
    }

    const htmlTable: string = CodecGoldenTests.complexTable();
    const tableBlocks: ContentBlock[] = TriliumCodec.parseToModel(htmlTable, 'html');
    let tableFound: boolean = false;
    let imageFound: boolean = false;
    let rawFound: boolean = false;
    for (let i = 0; i < tableBlocks.length; i++) {
      if (tableBlocks[i].kind === ContentBlockKind.TABLE && tableBlocks[i].table !== null) {
        tableFound = true;
      }
      if (tableBlocks[i].kind === ContentBlockKind.IMAGE) {
        imageFound = true;
      }
      if (tableBlocks[i].kind === ContentBlockKind.RAW) {
        rawFound = true;
      }
    }
    if (tableFound && imageFound && rawFound) {
      passed++;
      console.info('CODEC_GOLDEN PASS semantic-nodes table/image/unknown');
    } else {
      console.error(`CODEC_GOLDEN FAIL semantic-nodes table=${tableFound} ` +
        `image=${imageFound} raw=${rawFound}`);
    }

    const total: number = cases.length + 1;
    console.info(`CODEC_GOLDEN SUMMARY ${passed}/${total}`);
    return passed === total;
  }

  private static cases(): GoldenCase[] {
    return [
      new GoldenCase('html-complex-table', CodecGoldenTests.complexTable(), 'html'),
      new GoldenCase('markdown-table-image', CodecGoldenTests.markdownDocument(), 'markdown')
    ];
  }

  private static complexTable(): string {
    return '<!-- leading comment -->\n' +
      '<p class="lead">Intro <strong>bold</strong> and <code>x &lt; y</code></p>\n' +
      '<table class="tn-table" data-id="t1">\n' +
      '  <thead><tr><th colspan="2">Header</th><th>Note</th></tr></thead>\n' +
      '  <tbody>\n' +
      '    <tr><td rowspan="2"><img src="tn://abc/1.png" alt="pic" width="120"></td>' +
      '<td>R1C2</td><td>R1C3</td></tr>\n' +
      '    <tr><td>R2C2</td><td>R2C3</td></tr>\n' +
      '    <tr><td><strong>R3C1</strong></td><td>R3C2</td><td>R3C3</td></tr>\n' +
      '  </tbody>\n' +
      '</table>\n' +
      '<figure class="image"><img src="tn://abc/2.png" alt="figure">' +
      '<figcaption>Caption</figcaption></figure>\n' +
      '<custom-widget data-x="1"><span>opaque payload</span></custom-widget>\n';
  }

  private static markdownDocument(): string {
    return '# Title\n\n' +
      '| A | B |\n' +
      '| --- | --- |\n' +
      '| `a\\|b` | c |\n\n' +
      '![alt](tn://img.png "title")\n\n' +
      '> quoted **text**\n\n' +
      '- one\n' +
      '- two\n';
  }
}
