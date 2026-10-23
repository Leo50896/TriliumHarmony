export enum CodeTokenKind {
  PLAIN = 0,
  KEYWORD = 1,
  DECORATOR = 2,
  STRING = 3,
  NUMBER = 4,
  COMMENT = 5,
  FUNCTION = 6,
  PUNCTUATION = 7
}

export class CodeToken {
  text: string;
  kind: CodeTokenKind;

  constructor(text: string, kind: CodeTokenKind) {
    this.text = text;
    this.kind = kind;
  }
}

export class CodeLine {
  tokens: CodeToken[];

  constructor(tokens: CodeToken[]) {
    this.tokens = tokens;
  }
}

const KEYWORDS: string[] = [
  'struct', 'build', 'if', 'else', 'for', 'while', 'return', 'const', 'let', 'new',
  'this', 'true', 'false', 'number', 'string', 'boolean', 'void', 'async', 'await',
  'import', 'export', 'class', 'extends', 'implements', 'function'
];

const JS_KEYWORDS: string[] = [
  'const', 'let', 'var', 'function', 'return', 'if', 'else', 'for', 'while',
  'class', 'new', 'import', 'export', 'async', 'await', 'try', 'catch', 'throw',
  'typeof', 'instanceof', 'interface', 'type', 'enum', 'extends', 'implements',
  'public', 'private', 'protected', 'readonly', 'static', 'true', 'false', 'null',
  'undefined', 'this', 'super'
];

const PYTHON_KEYWORDS: string[] = [
  'def', 'class', 'import', 'from', 'return', 'if', 'elif', 'else', 'for',
  'while', 'try', 'except', 'finally', 'with', 'as', 'lambda', 'True', 'False',
  'None', 'pass', 'raise', 'in', 'is', 'not', 'and', 'or', 'yield', 'global',
  'nonlocal', 'assert', 'del', 'async', 'await'
];

const SQL_KEYWORDS: string[] = [
  'SELECT', 'FROM', 'WHERE', 'INSERT', 'INTO', 'VALUES', 'UPDATE', 'SET',
  'DELETE', 'CREATE', 'TABLE', 'INDEX', 'ALTER', 'DROP', 'JOIN', 'ON', 'AND',
  'OR', 'NOT', 'NULL', 'AS', 'GROUP', 'BY', 'ORDER', 'LIMIT', 'HAVING',
  'PRIMARY', 'KEY', 'FOREIGN', 'REFERENCES', 'DEFAULT', 'UNIQUE', 'INTEGER',
  'TEXT', 'REAL', 'BLOB'
];

const SHELL_KEYWORDS: string[] = [
  'if', 'then', 'else', 'elif', 'fi', 'for', 'in', 'do', 'done', 'case', 'esac',
  'function', 'export', 'local', 'echo', 'cd', 'sudo', 'apt', 'docker', 'npm',
  'git', 'curl', 'wget', 'mkdir', 'rm', 'cp', 'mv', 'cat', 'grep'
];

const HTML_KEYWORDS: string[] = [
  'html', 'head', 'body', 'div', 'span', 'p', 'a', 'img', 'ul', 'ol', 'li',
  'table', 'tr', 'td', 'th', 'section', 'aside', 'pre', 'code', 'h1', 'h2',
  'h3', 'h4', 'h5', 'h6', 'script', 'style', 'link', 'meta', 'input', 'button'
];

const CSS_KEYWORDS: string[] = [
  'color', 'background', 'background-color', 'margin', 'padding', 'border',
  'display', 'flex', 'grid', 'position', 'top', 'left', 'right', 'bottom',
  'width', 'height', 'font-size', 'font-weight', 'line-height', 'opacity'
];

const COMMON_KEYWORDS: string[] = [
  'if', 'else', 'for', 'while', 'return', 'class', 'public', 'private',
  'protected', 'static', 'void', 'int', 'float', 'double', 'string', 'boolean',
  'true', 'false', 'null', 'new', 'import', 'package', 'using', 'namespace',
  'func', 'function', 'def', 'val', 'var', 'let', 'const', 'interface', 'enum'
];

/**
 * A deliberately small ArkTS tokenizer for the read view. It is not meant to
 * replace a full language service; it only needs to light up decorators,
 * keywords, literals and call sites in a fenced code block.
 */
export class CodeHighlighter {
  private static readonly TOKEN_PATTERN: RegExp =
    /(@[A-Za-z_][A-Za-z0-9_]*|\/\/.*$|`[^`]*`|'[^']*'|"[^"]*"|\b(?:struct|build|if|else|for|while|return|const|let|new|this|true|false|number|string|boolean|void|async|await|import|export|class|extends|implements|function)\b|\b\d+(?:\.\d+)?\b|\b[A-Za-z_][A-Za-z0-9_]*(?=\s*\()|[{}();,.=:+\-*/<>])/g;

  static highlight(lines: string[], language: string = 'ARKTS'): CodeLine[] {
    const result: CodeLine[] = [];
    const normalized: string = language.trim().toLowerCase();
    const keywords: string[] = CodeHighlighter.keywordsFor(normalized);
    const hashComments: boolean = normalized.indexOf('python') >= 0 ||
      normalized.indexOf('shell') >= 0 || normalized === 'bash' ||
      normalized.indexOf('ruby') >= 0 || normalized.indexOf('perl') >= 0 ||
      normalized.indexOf('yaml') >= 0 || normalized.indexOf('elixir') >= 0;
    const dashComments: boolean = normalized.indexOf('sql') >= 0 ||
      normalized.indexOf('haskell') >= 0;
    for (let index: number = 0; index < lines.length; index++) {
      if (normalized.indexOf('yaml') >= 0 || normalized === 'yml') {
        result.push(new CodeLine(CodeHighlighter.tokenizeYaml(lines[index])));
      } else if (normalized === 'plain text' || normalized === 'text') {
        result.push(new CodeLine([new CodeToken(lines[index].length > 0 ? lines[index] : ' ',
          CodeTokenKind.PLAIN)]));
      } else if (normalized.indexOf('markdown') >= 0) {
        result.push(new CodeLine(CodeHighlighter.tokenizeMarkdown(lines[index])));
      } else {
        result.push(new CodeLine(CodeHighlighter.tokenizeLanguage(
          lines[index], keywords, hashComments, dashComments)));
      }
    }
    return result;
  }

  private static keywordsFor(language: string): string[] {
    if (language.indexOf('javascript') >= 0 || language.indexOf('typescript') >= 0 ||
      language === 'js' || language === 'ts') {
      return JS_KEYWORDS;
    }
    if (language.indexOf('python') >= 0 || language === 'py') {
      return PYTHON_KEYWORDS;
    }
    if (language.indexOf('sql') >= 0) {
      return SQL_KEYWORDS;
    }
    if (language.indexOf('shell') >= 0 || language === 'bash' || language === 'sh') {
      return SHELL_KEYWORDS;
    }
    if (language.indexOf('html') >= 0 || language.indexOf('xml') >= 0) {
      return HTML_KEYWORDS;
    }
    if (language.indexOf('css') >= 0) {
      return CSS_KEYWORDS;
    }
    if (language.indexOf('arkts') >= 0) {
      return KEYWORDS;
    }
    return COMMON_KEYWORDS;
  }

  private static tokenizeMarkdown(line: string): CodeToken[] {
    const tokens: CodeToken[] = [];
    if (/^#{1,6}\s+/.test(line)) {
      tokens.push(new CodeToken(line, CodeTokenKind.KEYWORD));
    } else if (/^```/.test(line.trim())) {
      tokens.push(new CodeToken(line, CodeTokenKind.DECORATOR));
    } else {
      tokens.push(new CodeToken(line.length > 0 ? line : ' ', CodeTokenKind.PLAIN));
    }
    return tokens;
  }

  private static tokenizeLanguage(line: string, keywords: string[],
    hashComments: boolean, dashComments: boolean): CodeToken[] {
    const tokens: CodeToken[] = [];
    let index: number = 0;
    while (index < line.length) {
      const rest: string = line.substring(index);
      if ((hashComments && rest.startsWith('#')) ||
        rest.startsWith('//') || (dashComments && rest.startsWith('--'))) {
        tokens.push(new CodeToken(rest, CodeTokenKind.COMMENT));
        break;
      }
      const char: string = line.charAt(index);
      if (char === ' ' || char === '\t') {
        let end: number = index;
        while (end < line.length && (line.charAt(end) === ' ' || line.charAt(end) === '\t')) {
          end++;
        }
        tokens.push(new CodeToken(line.substring(index, end), CodeTokenKind.PLAIN));
        index = end;
        continue;
      }
      if (char === '"' || char === '\'' || char === '`') {
        const quote: string = char;
        let end: number = index + 1;
        while (end < line.length) {
          if (line.charAt(end) === '\\') {
            end += 2;
            continue;
          }
          if (line.charAt(end) === quote) {
            end++;
            break;
          }
          end++;
        }
        tokens.push(new CodeToken(line.substring(index, end), CodeTokenKind.STRING));
        index = end;
        continue;
      }
      if (char >= '0' && char <= '9') {
        let end: number = index + 1;
        while (end < line.length && /[0-9a-fx._]/i.test(line.charAt(end))) {
          end++;
        }
        tokens.push(new CodeToken(line.substring(index, end), CodeTokenKind.NUMBER));
        index = end;
        continue;
      }
      if (/[A-Za-z_@$]/.test(char)) {
        let end: number = index + 1;
        while (end < line.length && /[A-Za-z0-9_@$]/.test(line.charAt(end))) {
          end++;
        }
        const word: string = line.substring(index, end);
        const kind: CodeTokenKind = word.startsWith('@') ? CodeTokenKind.DECORATOR :
          (keywords.indexOf(word) >= 0 ? CodeTokenKind.KEYWORD : CodeTokenKind.PLAIN);
        tokens.push(new CodeToken(word, kind));
        index = end;
        continue;
      }
      if (/[{}()[\];,.:=+\-*/<>!&|?]/.test(char)) {
        tokens.push(new CodeToken(char, CodeTokenKind.PUNCTUATION));
        index++;
        continue;
      }
      tokens.push(new CodeToken(char, CodeTokenKind.PLAIN));
      index++;
    }
    if (tokens.length === 0) {
      tokens.push(new CodeToken(' ', CodeTokenKind.PLAIN));
    }
    return tokens;
  }

  private static findYamlComment(value: string): number {
    let quote: string = '';
    for (let index: number = 0; index < value.length; index++) {
      const char: string = value.charAt(index);
      if (quote.length > 0) {
        if (char === quote) {
          quote = '';
        }
        continue;
      }
      if (char === '"' || char === '\'') {
        quote = char;
        continue;
      }
      if (char === '#' && (index === 0 || value.charAt(index - 1) === ' ')) {
        return index;
      }
    }
    return -1;
  }

  private static pushYamlValue(tokens: CodeToken[], value: string): void {
    if (value.length === 0) {
      return;
    }
    const trimmed: string = value.trim();
    if (trimmed.startsWith('"') || trimmed.startsWith('\'')) {
      tokens.push(new CodeToken(value, CodeTokenKind.STRING));
    } else if (/^-?\d+(\.\d+)?$/.test(trimmed)) {
      tokens.push(new CodeToken(value, CodeTokenKind.NUMBER));
    } else if (trimmed === 'true' || trimmed === 'false' || trimmed === 'null' ||
      trimmed === 'yes' || trimmed === 'no' || trimmed === 'on' || trimmed === 'off') {
      tokens.push(new CodeToken(value, CodeTokenKind.KEYWORD));
    } else {
      tokens.push(new CodeToken(value, CodeTokenKind.PLAIN));
    }
  }

  private static tokenizeYaml(line: string): CodeToken[] {
    const tokens: CodeToken[] = [];
    if (line.trim().length === 0) {
      tokens.push(new CodeToken(line.length > 0 ? line : ' ', CodeTokenKind.PLAIN));
      return tokens;
    }
    const commentAt: number = CodeHighlighter.findYamlComment(line);
    const codePart: string = commentAt >= 0 ? line.substring(0, commentAt) : line;
    const commentPart: string = commentAt >= 0 ? line.substring(commentAt) : '';
    const match: RegExpMatchArray | null =
      codePart.match(/^(\s*)(-\s+)?([A-Za-z0-9_.\/-]+)(\s*:)([\s\S]*)$/);
    if (match !== null) {
      if (match[1].length > 0) {
        tokens.push(new CodeToken(match[1], CodeTokenKind.PLAIN));
      }
      if (match[2] !== undefined && match[2].length > 0) {
        tokens.push(new CodeToken(match[2], CodeTokenKind.PUNCTUATION));
      }
      tokens.push(new CodeToken(match[3], CodeTokenKind.KEYWORD));
      tokens.push(new CodeToken(match[4], CodeTokenKind.PUNCTUATION));
      CodeHighlighter.pushYamlValue(tokens, match[5]);
    } else if (/^\s*-\s+/.test(codePart)) {
      const dash: RegExpMatchArray | null = codePart.match(/^(\s*-\s+)([\s\S]*)$/);
      if (dash !== null) {
        tokens.push(new CodeToken(dash[1], CodeTokenKind.PUNCTUATION));
        CodeHighlighter.pushYamlValue(tokens, dash[2]);
      }
    } else {
      tokens.push(new CodeToken(codePart, CodeTokenKind.PLAIN));
    }
    if (commentPart.length > 0) {
      tokens.push(new CodeToken(commentPart, CodeTokenKind.COMMENT));
    }
    if (tokens.length === 0) {
      tokens.push(new CodeToken(' ', CodeTokenKind.PLAIN));
    }
    return tokens;
  }

  private static tokenize(line: string): CodeToken[] {
    const tokens: CodeToken[] = [];
    const parts: string[] = line.split(CodeHighlighter.TOKEN_PATTERN);
    for (let index: number = 0; index < parts.length; index++) {
      const part: string = parts[index];
      if (part.length === 0) {
        continue;
      }
      tokens.push(new CodeToken(part, CodeHighlighter.classify(part)));
    }
    if (tokens.length === 0) {
      tokens.push(new CodeToken(' ', CodeTokenKind.PLAIN));
    }
    return tokens;
  }

  private static classify(value: string): CodeTokenKind {
    if (value.startsWith('@')) {
      return CodeTokenKind.DECORATOR;
    }
    if (value.startsWith('//')) {
      return CodeTokenKind.COMMENT;
    }
    if (value.startsWith('\'') || value.startsWith('"') || value.startsWith('`')) {
      return CodeTokenKind.STRING;
    }
    if (value.length > 0 && value.charCodeAt(0) >= 48 && value.charCodeAt(0) <= 57) {
      return CodeTokenKind.NUMBER;
    }
    if (KEYWORDS.indexOf(value) >= 0) {
      return CodeTokenKind.KEYWORD;
    }
    if (/^[{}();,.=:+\-*/<>]+$/.test(value)) {
      return CodeTokenKind.PUNCTUATION;
    }
    if (/^[A-Za-z_][A-Za-z0-9_]*$/.test(value)) {
      return CodeTokenKind.FUNCTION;
    }
    return CodeTokenKind.PLAIN;
  }
}
