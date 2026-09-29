import Foundation

struct Measurement {
    var size: Int64 = 0
    var growth24: Int64 = 0
    var growth7: Int64 = 0
    var lastModified: Date?
    var readable = true
}

/// Đo dung lượng thật trên đĩa (allocated size) và phần được ghi mới trong 24 giờ / 7 ngày theo ngày sửa tệp.
enum FileSizer {
    private static let keys: Set<URLResourceKey> = [
        .isRegularFileKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .contentModificationDateKey,
    ]

    static func measure(_ urls: [URL], now: Date = Date()) -> Measurement {
        urls.reduce(into: Measurement()) { total, url in
            let part = measure(url, now: now)
            total.size += part.size
            total.growth24 += part.growth24
            total.growth7 += part.growth7
            total.readable = total.readable && part.readable
            if let date = part.lastModified, date > (total.lastModified ?? .distantPast) { total.lastModified = date }
        }
    }

    static func measure(_ url: URL, now: Date = Date()) -> Measurement {
        var result = Measurement()
        let day = now.addingTimeInterval(-86_400)
        let week = now.addingTimeInterval(-7 * 86_400)

        func add(_ values: URLResourceValues) {
            let size = Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? 0)
            result.size += size
            guard let modified = values.contentModificationDate else { return }
            if modified > day { result.growth24 += size }
            if modified > week { result.growth7 += size }
            if modified > (result.lastModified ?? .distantPast) { result.lastModified = modified }
        }

        guard let rootValues = try? url.resourceValues(forKeys: keys) else {
            result.readable = FileManager.default.fileExists(atPath: url.path) == false
            return result
        }
        if rootValues.isSymbolicLink == true { return result }
        if rootValues.isRegularFile == true {
            add(rootValues)
            return result
        }

        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: Array(keys), options: [],
            errorHandler: { _, _ in result.readable = false; return true }
        ) else {
            result.readable = false
            return result
        }
        for case let file as URL in enumerator {
            guard let values = try? file.resourceValues(forKeys: keys),
                  values.isRegularFile == true, values.isSymbolicLink != true else { continue }
            add(values)
        }
        return result
    }
}
