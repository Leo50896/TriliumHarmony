/**
 * Scroll offsets keyed by noteId.
 *
 * Kept in a process-wide Map instead of AppStorage because it is high-frequency
 * transient data and must not trigger UI updates. It survives note switches and
 * is cleared when the session is cleared.
 */
export class ReadingPositionStore {
  private static positions: Map<string, number> = new Map();

  static save(noteId: string, yOffset: number): void {
    if (noteId.length === 0 || isNaN(yOffset)) {
      return;
    }
    ReadingPositionStore.positions.set(noteId, Math.max(0, yOffset));
  }

  static get(noteId: string): number {
    if (noteId.length === 0) {
      return 0;
    }
    return ReadingPositionStore.positions.get(noteId) ?? 0;
  }

  static clear(): void {
    ReadingPositionStore.positions.clear();
  }
}
