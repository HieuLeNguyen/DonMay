import Foundation

/// Một vị trí có thể dọn, trước khi đo. `classify` quyết mức an toàn sau khi biết dung lượng và ngày sửa.
struct Candidate {
    var id: String
    var app: AppKind
    var name: String
    var urls: [URL]
    var action: RemovalAction
    var undo: UndoPolicy
    var regenerateHint: String
    var knownSize: Int64?
    var lastUsed: Date?
    var classify: (Measurement) -> (Risk, String)

    init(app: AppKind, name: String, urls: [URL], undo: UndoPolicy = .regenerate, regenerateHint: String = "",
         action: RemovalAction? = nil, knownSize: Int64? = nil, lastUsed: Date? = nil, id: String? = nil,
         classify: @escaping (Measurement) -> (Risk, String)) {
        self.app = app
        self.name = name
        self.urls = urls
        self.undo = undo
        self.regenerateHint = regenerateHint
        self.action = action ?? .files(urls.map(\.path))
        self.knownSize = knownSize
        self.lastUsed = lastUsed
        self.id = id ?? app.rawValue + ":" + urls.map(\.path).joined(separator: "|")
        self.classify = classify
    }

    static func fixed(_ app: AppKind, _ name: String, _ url: URL, _ risk: Risk, _ reason: String,
                      undo: UndoPolicy = .regenerate, hint: String? = nil) -> Candidate {
        Candidate(app: app, name: name, urls: [url], undo: undo, regenerateHint: hint ?? reason) { _ in (risk, reason) }
    }

    var displayPath: String {
        urls.count == 1 ? Format.abbreviatingHome(urls[0].path)
            : Format.abbreviatingHome(urls[0].deletingLastPathComponent().path) + " · \(urls.count) mục"
    }
}

extension URL {
    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    func children() -> [URL] {
        (try? FileManager.default.contentsOfDirectory(at: self, includingPropertiesForKeys: [.isDirectoryKey],
                                                       options: [])) ?? []
    }

    var isDirectory: Bool { (try? resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }

    var modificationDate: Date? { try? resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate }

    func under(_ components: String...) -> URL {
        components.reduce(self) { $0.appendingPathComponent($1) }
    }
}
