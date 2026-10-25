//
//  BookmarkImporter.swift
//  Reynard
//
//  Created by Minh Ton on 20/10/26.
//

import Foundation

enum BookmarkImporter {
    static func importBookmarks(from fileURL: URL) async throws -> BookmarkImportReport {
        guard fileURL.isFileURL else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        
        guard !fileURL.path.contains("\0") else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        
        let task = Task.detached(priority: .userInitiated) {
            let hasAccess = fileURL.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }
            
            try Task.checkCancellation()
            return try BookmarkHTMLParser.parse(fileURL: fileURL)
        }
        
        let document = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        
        return try await importBookmarks(document)
    }
    
    static func importBookmarks(_ document: BookmarkHTMLDocument) async throws -> BookmarkImportReport {
        let store = BookmarkStore.shared
        let cancellation = UserDataCancellation()
        let report = try await withTaskCancellationHandler {
            try await store.performBookmarkDataOperation { database in
                let storage = BookmarkDataStorage(database: database)
                return try storage.importDocument(document, cancellation: cancellation)
            }
        } onCancel: {
            cancellation.cancel()
        }
        
        if report.importedBookmarkCount > 0 || report.importedFolderCount > 0 {
            NotificationCenter.default.post(name: .bookmarkStoreDidChange, object: store)
        }
        
        return report
    }
}
