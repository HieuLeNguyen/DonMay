import Foundation

enum Scanner {
    static func scan(progress: @escaping @Sendable (Double) -> Void) async -> [CleanItem] {
        let candidates = await Task.detached(priority: .userInitiated) { Rules.all() }.value
        let total = Double(max(candidates.count, 1))
        let counter = Counter()

        return await withTaskGroup(of: CleanItem?.self) { group in
            var iterator = candidates.makeIterator()
            let width = 6
            for _ in 0..<width {
                guard let next = iterator.next() else { break }
                group.addTask { measure(next) }
            }
            var items: [CleanItem] = []
            while let result = await group.next() {
                if let result { items.append(result) }
                progress(await counter.increment() / total)
                if let next = iterator.next() { group.addTask { measure(next) } }
            }
            return items.sorted { $0.size > $1.size }
        }
    }

    private static func measure(_ candidate: Candidate) -> CleanItem? {
        var m = candidate.knownSize.map { Measurement(size: $0) } ?? FileSizer.measure(candidate.urls)
        if m.lastModified == nil { m.lastModified = candidate.lastUsed }
        guard m.size >= .mb else { return nil }
        let (risk, reason) = candidate.classify(m)
        return CleanItem(id: candidate.id, app: candidate.app, name: candidate.name, reason: reason,
                         displayPath: candidate.displayPath, size: m.size, lastUsed: candidate.lastUsed ?? m.lastModified,
                         risk: risk, undo: candidate.undo, growth24: m.growth24, growth7: m.growth7,
                         action: candidate.action, regenerateHint: candidate.regenerateHint)
    }

    private actor Counter {
        var value = 0.0
        func increment() -> Double { value += 1; return value }
    }
}
