//
//  HistoryImporter.swift
//  Reynard
//
//  Created by Minh Ton on 20/10/26.
//

import Foundation

enum HistoryImporter {
    static func importHistory(
        from fileURL: URL,
        format: HistoryImportFormat,
        nearDuplicateToleranceSeconds: Int,
        decodeRecord: @escaping @Sendable (JSONDecoder, Data) throws -> HistoryImportRecord
    ) async throws -> HistoryImportReport {
        guard nearDuplicateToleranceSeconds >= 0 else {
            throw HistoryDataError.invalidDeduplicationTolerance
        }
        
        let store = HistoryStore.shared
        let databaseURL = try HistoryDataStorage.databaseURL()
        let cancellation = UserDataCancellation()
        let task = Task.detached(priority: .userInitiated) {
            let hasAccess = fileURL.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }
            
            try Task.checkCancellation()
            let stagedURL = FileManager.default.temporaryDirectory
                .appendingPathComponent("History-\(UUID().uuidString).tmp")
            defer {
                try? FileManager.default.removeItem(at: stagedURL)
            }
            
            let buffer = try HistoryImportBuffer(fileURL: stagedURL)
            let reader = try HistoryJSONReader(fileURL: fileURL)
            let decoder = JSONDecoder()
            var recordCount = 0
            var invalid = 0
            var discardedDetails = 0
            
            let detectedFormat = try reader.read { json, source in
                guard source == format else {
                    throw HistoryDataError.unrecognizedFormat
                }
                
                let record: HistoryImportRecord
                do {
                    record = try decodeRecord(decoder, json)
                } catch is DecodingError {
                    invalid += 1
                    return
                }
                
                guard Int64(exactly: (record.timestamp * 1_000_000).rounded()) != nil else {
                    invalid += 1
                    return
                }
                
                if record.hasDiscardedDetails {
                    discardedDetails += 1
                }
                
                try buffer.append(record)
                recordCount += 1
            }
            guard detectedFormat == format else {
                throw HistoryDataError.unrecognizedFormat
            }
            
            try buffer.finish()
            
            return try await store.performHistoryImport { [recordCount, invalid, discardedDetails] in
                try cancellation.checkCancellation()
                let storage = try HistoryDataStorage(databaseURL: databaseURL, cancellation: cancellation)
                var committed = false
                defer {
                    if !committed {
                        storage.rollbackImport()
                    }
                }
                
                try storage.beginImport()
                var imported = 0
                var duplicates = 0
                try HistoryImportBuffer.enumerateRecords(from: stagedURL, cancellation: cancellation) { record in
                    if try storage.insert(record, toleranceSeconds: nearDuplicateToleranceSeconds) {
                        imported += 1
                    } else {
                        duplicates += 1
                    }
                }
                
                guard imported + duplicates == recordCount else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                
                try storage.finishImport()
                committed = true
                
                return HistoryImportReport(
                    format: format,
                    importedRecordCount: imported,
                    duplicateRecordCount: duplicates,
                    invalidRecordCount: invalid,
                    recordsWithDiscardedDetails: discardedDetails
                )
            }
        }
        
        let report = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            cancellation.cancel()
            task.cancel()
        }
        
        if report.importedRecordCount > 0 {
            NotificationCenter.default.post(name: .historyStoreDidChange, object: store)
        }
        
        return report
    }
}
