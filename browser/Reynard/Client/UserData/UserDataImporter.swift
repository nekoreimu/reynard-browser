//
//  UserDataImporter.swift
//  Reynard
//
//  Created by Minh Ton on 21/10/26.
//

import Darwin
import Foundation
import ZIPFoundation

enum UserDataImporter {
    static func importData(
        from fileURL: URL, onTypeDetected: ((UserDataType) async -> Void)? = nil
    ) async throws -> UserDataImportReport {
        guard fileURL.isFileURL else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        
        guard !fileURL.path.contains("\0") else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        
        let fileExtension = fileURL.pathExtension.lowercased()
        guard ["html", "json", "zip"].contains(fileExtension) else {
            throw UserDataError.unsupportedFile
        }
        
        let isArchive = fileExtension == "zip"
        let hasAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("UserData-\(UUID().uuidString)", isDirectory: true)
        if isArchive {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        defer {
            if isArchive {
                try? FileManager.default.removeItem(at: directory)
            }
        }
        
        let progress = Progress(totalUnitCount: 0)
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            if isArchive {
                return try extract(fileURL, into: directory, progress: progress)
            }
            
            return [Source(url: fileURL, name: fileURL.lastPathComponent)]
        }
        let sources = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            progress.cancel()
            task.cancel()
        }
        
        var report = UserDataImportReport()
        for source in sources {
            try Task.checkCancellation()
            var dataType: UserDataType?
            do {
                let inspection = Task.detached(priority: .userInitiated) {
                    try format(of: source.url, requiresExportMetadata: isArchive)
                }
                let detectedFormat: Format
                do {
                    detectedFormat = try await withTaskCancellationHandler {
                        try await inspection.value
                    } onCancel: {
                        inspection.cancel()
                    }
                } catch {
                    try Task.checkCancellation()
                    guard isArchive else {
                        throw error
                    }
                    
                    switch error {
                    case UserDataError.unsupportedFile, HistoryDataError.invalidJSON, BookmarkDataError.unrecognizedFormat:
                        continue
                    default:
                        throw error
                    }
                }
                
                dataType = detectedFormat.dataType
                await onTypeDetected?(detectedFormat.dataType)
                try Task.checkCancellation()
                
                switch detectedFormat {
                case .bookmarks(let document):
                    let result = try await BookmarkImporter.importBookmarks(document)
                    report.results.append(.bookmarks(fileName: source.name, report: result))
                case .safariHistory:
                    let result = try await SafariHistoryImporter.importHistory(from: source.url)
                    report.results.append(.history(fileName: source.name, report: result))
                case .chromeHistory:
                    let result = try await ChromeHistoryImporter.importHistory(from: source.url)
                    report.results.append(.history(fileName: source.name, report: result))
                case .extensions:
                    let result = try await AddonImporter.importAddons(from: source.url)
                    report.results.append(.extensions(fileName: source.name, report: result))
                case .safariExtensions:
                    report.results.append(.skipped(
                        fileName: source.name,
                        reason: UserDataError.unsupportedSafariExtensions.localizedDescription
                    ))
                }
            } catch {
                try Task.checkCancellation()
                report.results.append(.failed(fileName: source.name, dataType: dataType, message: error.localizedDescription))
            }
        }
        
        guard !isArchive || !report.results.isEmpty else {
            throw UserDataError.noImportableFiles
        }
        
        return report
    }
    
    nonisolated private struct Source: Sendable {
        let url: URL
        let name: String
    }
    
    nonisolated private enum Format: Sendable {
        case bookmarks(BookmarkHTMLDocument)
        case safariHistory
        case chromeHistory
        case extensions
        case safariExtensions
        
        var dataType: UserDataType {
            switch self {
            case .bookmarks:
                return .bookmarks
            case .safariHistory, .chromeHistory:
                return .history
            case .extensions, .safariExtensions:
                return .extensions
            }
        }
    }
    
    nonisolated private static func format(of url: URL, requiresExportMetadata: Bool) throws -> Format {
        try Task.checkCancellation()
        if url.pathExtension.lowercased() == "html" {
            let document = try BookmarkHTMLParser.parse(fileURL: url, requiresExportMetadata: requiresExportMetadata)
            return .bookmarks(document)
        }
        
        let reader = try HistoryJSONReader(fileURL: url)
        switch try reader.firstRootKey(in: ["history", "Browser History", "extensions"]) {
        case "history":
            return .safariHistory
        case "Browser History":
            return .chromeHistory
        case "extensions":
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            if let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
               root["extensions"] is [Any] {
                return .safariExtensions
            }
            return .extensions
        default:
            throw UserDataError.unsupportedFile
        }
    }
    
    nonisolated private static func extract(
        _ url: URL, into directory: URL, progress: Progress
    ) throws -> [Source] {
        let expectedEntryCount = try archiveEntryCount(at: url)
        let archive = try Archive(url: url, accessMode: .read)
        var sources: [Source] = []
        var entryCount: UInt64 = 0
        for entry in archive {
            try Task.checkCancellation()
            entryCount += 1
            let path = entry.path
            let fileExtension = (path as NSString).pathExtension
            guard entry.type == .file,
                  !path.split(separator: "/").contains("__MACOSX"),
                  ["html", "json"].contains(fileExtension.lowercased()) else {
                continue
            }
            
            let destination = directory.appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(fileExtension)
            let checksum = try archive.extract(entry, to: destination, progress: progress)
            let attributes = try FileManager.default.attributesOfItem(atPath: destination.path)
            guard let size = attributes[.size] as? NSNumber,
                  size.uint64Value == entry.uncompressedSize,
                  checksum == entry.checksum else {
                throw UserDataError.invalidArchiveEntry(path)
            }
            sources.append(Source(url: destination, name: path))
        }
        
        guard entryCount == expectedEntryCount else {
            throw UserDataError.invalidArchive
        }
        
        guard !sources.isEmpty else {
            throw UserDataError.noImportableFiles
        }
        
        return sources
    }
    
    nonisolated private static func archiveEntryCount(at url: URL) throws -> UInt64 {
        guard let file = fopen(url.path, "rb") else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        defer {
            fclose(file)
        }
        guard fseeko(file, 0, SEEK_END) == 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let end = ftello(file)
        guard end >= 0 else {
            throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
        }
        let fileSize = UInt64(end)
        
        func read(at offset: UInt64, count: Int) throws -> Data {
            guard offset <= fileSize, UInt64(count) <= fileSize - offset else {
                throw UserDataError.invalidArchive
            }
            
            guard fseeko(file, off_t(offset), SEEK_SET) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            var data = Data(count: count)
            let length = data.withUnsafeMutableBytes {
                fread($0.baseAddress, 1, count, file)
            }
            guard length == count else {
                if ferror(file) != 0 {
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                throw UserDataError.invalidArchive
            }
            return data
        }
        
        func integer(in data: Data, at offset: Int, count: Int) -> UInt64 {
            return (0..<count).reduce(0) { value, index in
                value | (UInt64(data[offset + index]) << (index * 8))
            }
        }
        
        // The ZIP footer is 22 bytes, followed by a comment of at most UInt16.max bytes.
        let tailSize = min(fileSize, UInt64(UInt16.max) + 22)
        let tail = try read(at: fileSize - tailSize, count: Int(tailSize))
        guard tail.count >= 22 else {
            throw UserDataError.invalidArchive
        }
        
        var footerOffset: Int?
        for offset in stride(from: tail.count - 22, through: 0, by: -1) {
            guard integer(in: tail, at: offset, count: 4) == 0x06054B50 else { // ZIP end-of-directory signature.
                continue
            }
            
            let commentLength = integer(in: tail, at: offset + 20, count: 2)
            if UInt64(offset + 22) + commentLength == tailSize {
                footerOffset = offset
                break
            }
        }
        
        guard let footerOffset else {
            throw UserDataError.invalidArchive
        }
        
        let footer = tail.subdata(in: footerOffset..<(footerOffset + 22))
        let footerPosition = fileSize - tailSize + UInt64(footerOffset)
        if footerPosition >= 20 {
            let locator = try read(at: footerPosition - 20, count: 20)
            if integer(in: locator, at: 0, count: 4) == 0x07064B50 { // ZIP64 end-of-directory locator.
                guard integer(in: locator, at: 4, count: 4) == 0,
                      integer(in: locator, at: 16, count: 4) == 1 else {
                    throw UserDataError.invalidArchive
                }
                
                let recordOffset = integer(in: locator, at: 8, count: 8)
                guard recordOffset <= footerPosition - 20,
                      footerPosition - 20 - recordOffset >= 56 else {
                    throw UserDataError.invalidArchive
                }
                
                let record = try read(at: recordOffset, count: 56)
                guard integer(in: record, at: 0, count: 4) == 0x06064B50, // ZIP64 end-of-directory signature.
                      integer(in: record, at: 4, count: 8) >= 44,
                      integer(in: record, at: 16, count: 4) == 0,
                      integer(in: record, at: 20, count: 4) == 0,
                      integer(in: record, at: 24, count: 8) == integer(in: record, at: 32, count: 8) else {
                    throw UserDataError.invalidArchive
                }
                
                return integer(in: record, at: 32, count: 8)
            }
        }
        
        let count = integer(in: footer, at: 10, count: 2)
        guard integer(in: footer, at: 4, count: 2) == 0,
              integer(in: footer, at: 6, count: 2) == 0,
              integer(in: footer, at: 8, count: 2) == count else {
            throw UserDataError.invalidArchive
        }
        return count
    }
}
