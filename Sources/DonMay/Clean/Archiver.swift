import AppleArchive
import Foundation
import System

/// Nén một thư mục thành `.aar` (LZFSE) và giải nén ngược lại.
enum Archiver {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func archive(directory source: URL, to destination: URL) throws -> Int64 {
        try FileManager.default.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        try write(source, destination)
        let size = (try? destination.resourceValues(forKeys: [.totalFileAllocatedSizeKey]).totalFileAllocatedSize) ?? 0
        return Int64(size)
    }

    private static func write(_ source: URL, _ destination: URL) throws {
        guard let file = ArchiveByteStream.fileStream(path: FilePath(destination.path), mode: .writeOnly,
                                                      options: [.create, .truncate],
                                                      permissions: FilePermissions(rawValue: 0o600)) else {
            throw Failure(message: L("Không tạo được tệp nén", "Couldn't create the archive"))
        }
        defer { try? file.close() }
        guard let compressor = ArchiveByteStream.compressionStream(using: .lzfse, writingTo: file) else {
            throw Failure(message: L("Không mở được luồng nén", "Couldn't open the compression stream"))
        }
        defer { try? compressor.close() }
        guard let encoder = ArchiveStream.encodeStream(writingTo: compressor),
              let keys = ArchiveHeader.FieldKeySet("TYP,PAT,LNK,DEV,DAT,UID,GID,MOD,FLG,MTM,BTM,CTM") else {
            throw Failure(message: L("Không mở được luồng lưu trữ", "Couldn't open the archive stream"))
        }
        defer { try? encoder.close() }
        try encoder.writeDirectoryContents(archiveFrom: FilePath(source.path), keySet: keys)
    }

    static func extract(_ archive: URL, into destination: URL) throws {
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        guard let file = ArchiveByteStream.fileStream(path: FilePath(archive.path), mode: .readOnly, options: [],
                                                      permissions: FilePermissions(rawValue: 0o600)) else {
            throw Failure(message: L("Không mở được tệp nén", "Couldn't open the archive"))
        }
        defer { try? file.close() }
        guard let decompressor = ArchiveByteStream.decompressionStream(readingFrom: file),
              let decoder = ArchiveStream.decodeStream(readingFrom: decompressor),
              let extractor = ArchiveStream.extractStream(extractingTo: FilePath(destination.path),
                                                          flags: [.ignoreOperationNotPermitted]) else {
            throw Failure(message: L("Không mở được luồng giải nén", "Couldn't open the decompression stream"))
        }
        defer {
            try? extractor.close()
            try? decoder.close()
            try? decompressor.close()
        }
        _ = try ArchiveStream.process(readingFrom: decoder, writingTo: extractor)
    }
}
