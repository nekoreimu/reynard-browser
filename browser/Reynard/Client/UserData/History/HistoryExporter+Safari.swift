//
//  HistoryExporter+Safari.swift
//  Reynard
//
//  Created by Minh Ton on 20/10/26.
//

import Darwin
import Foundation

enum SafariHistoryExporter {
    static func exportHistory(to fileURL: URL) async throws -> Int {
        guard fileURL.isFileURL else {
            throw CocoaError(.fileWriteUnsupportedScheme)
        }
        
        guard !fileURL.path.contains("\0") else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        
        _ = HistoryStore.shared
        let databaseURL = try HistoryDataStorage.databaseURL()
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        let cancellation = UserDataCancellation()
        let task = Task.detached(priority: .userInitiated) {
            let hasAccess = fileURL.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }
            
            let temporaryURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent(".\(UUID().uuidString).json")
            defer {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
            
            let storage = try HistoryDataStorage(databaseURL: databaseURL, cancellation: cancellation)
            let writer = try SafariHistoryWriter(fileURL: temporaryURL, browserVersion: version)
            var count = 0
            try storage.enumerateVisits { record in
                try writer.append(record)
                count += 1
            }
            try writer.finish()
            try Task.checkCancellation()
            
            guard rename(temporaryURL.path, fileURL.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            
            return count
        }
        
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            cancellation.cancel()
            task.cancel()
        }
    }
}

nonisolated private final class SafariHistoryWriter {
    private let writer: UserDataFileWriter
    private var hasRecords = false
    
    init(fileURL: URL, browserVersion: String) throws {
        writer = try UserDataFileWriter(fileURL: fileURL)
        
        let metadata: [String: Any] = [
            "browser_name": "Safari",
            "browser_version": "Reynard \(browserVersion)",
            "data_type": "history",
            "export_time_usec": Int64((Date().timeIntervalSince1970 * 1_000_000).rounded()),
            "schema_version": 1
        ]
        try writer.append(Data("{\"metadata\":".utf8))
        try writer.append(JSONSerialization.data(withJSONObject: metadata, options: [.sortedKeys]))
        try writer.append(Data(",\"history\":[".utf8))
    }
    
    func append(_ record: HistoryExportRecord) throws {
        guard let timeUsec = Int64(exactly: (record.timestamp * 1_000_000).rounded()) else {
            throw HistoryDataError.invalidStoredTimestamp
        }
        
        if hasRecords {
            try writer.append(Data([0x2C])) // ,
        }
        
        let fields: [String: Any] = [
            "url": record.url,
            "title": record.title,
            "time_usec": timeUsec,
            "visit_count": 1,
            "visit_details": [
                "version": 1,
                "timestamp": String(record.timestamp),
                "is_redirect_source": record.isRedirectSource
            ] as [String: Any]
        ]
        try writer.append(JSONSerialization.data(withJSONObject: fields, options: [.sortedKeys]))
        hasRecords = true
    }
    
    func finish() throws {
        try writer.append(Data("]}".utf8))
        try writer.finish()
    }
}
