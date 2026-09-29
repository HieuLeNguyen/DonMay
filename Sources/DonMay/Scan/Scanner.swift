import Foundation

enum ScanEvent {
    case finding(AppKind)
    case planned([AppKind: Int])
    case measuring(AppKind, String)
    case measured(AppKind, CleanItem?)
}

enum Scanner {
    static func scan(events: @escaping @Sendable (ScanEvent) -> Void) async -> [CleanItem] {
        let candidates = await Task.detached(priority: .userInitiated) {
            Rules.all { events(.finding($0)) }
        }.value
        events(.planned(Dictionary(grouping: candidates, by: \.app).mapValues(\.count)))

        return await withTaskGroup(of: (AppKind, CleanItem?).self) { group in
            var iterator = candidates.makeIterator()
            func start(_ candidate: Candidate) {
                events(.measuring(candidate.app, candidate.name))
                group.addTask { (candidate.app, measure(candidate)) }
            }
            for _ in 0..<6 {
                guard let next = iterator.next() else { break }
                start(next)
            }
            var items: [CleanItem] = []
            while let (app, result) = await group.next() {
                if let result { items.append(result) }
                events(.measured(app, result))
                if let next = iterator.next() { start(next) }
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
}
