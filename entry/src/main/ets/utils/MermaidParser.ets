export class MermaidNode {
  id: string;
  label: string;

  constructor(id: string, label: string) {
    this.id = id;
    this.label = label;
  }
}

export class MermaidGraph {
  nodes: MermaidNode[];
  edges: string[][];

  constructor(nodes: MermaidNode[], edges: string[][]) {
    this.nodes = nodes;
    this.edges = edges;
  }
}

export class MermaidParser {
  static parse(lines: string[]): MermaidGraph {
    const nodes: MermaidNode[] = [];
    const ids: string[] = [];
    const edges: string[][] = [];

    const ensure = (id: string, label: string): void => {
      if (ids.indexOf(id) >= 0) {
        return;
      }
      ids.push(id);
      nodes.push(new MermaidNode(id, label.length > 0 ? label : id));
    };

    for (let i = 0; i < lines.length; i++) {
      const line: string = lines[i].trim();
      const match: RegExpMatchArray | null =
        line.match(/^([A-Za-z0-9_]+)(?:\[([^\]]*)\])?\s*-->\s*([A-Za-z0-9_]+)(?:\[([^\]]*)\])?/);
      if (match === null) {
        continue;
      }
      ensure(match[1], match[2] ?? '');
      ensure(match[3], match[4] ?? '');
      edges.push([match[1], match[3]]);
    }
    return new MermaidGraph(nodes, edges);
  }
}
