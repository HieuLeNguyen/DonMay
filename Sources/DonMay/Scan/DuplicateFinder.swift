import CryptoKit
import Foundation

/// Tìm tệp trùng theo nội dung: gom theo dung lượng trước, chỉ băm SHA-256 những nhóm cùng cỡ.
enum DuplicateFinder {
    /// Trả về các bản thừa; bản cũ nhất của mỗi nhóm được giữ.
    static func duplicates(in files: [URL]) -> [URL] {
        let bySize = Dictionary(grouping: files) { url in
            (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        }
        var extras: [URL] = []
        for (size, group) in bySize where size > 0 && group.count > 1 {
            let byHash = Dictionary(grouping: group) { hash(of: $0) ?? UUID().uuidString }
            for same in byHash.values where same.count > 1 {
                let sorted = same.sorted { creation($0) < creation($1) }
                extras.append(contentsOf: sorted.dropFirst())
            }
        }
        return extras
    }

    private static func creation(_ url: URL) -> Date {
        (try? url.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantFuture
    }

    private static func hash(of url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try? handle.read(upToCount: 4 * 1024 * 1024), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}
