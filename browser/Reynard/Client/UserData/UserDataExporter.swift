//
//  UserDataExporter.swift
//  Reynard
//
//  Created by Minh Ton on 21/10/26.
//

import Darwin
import Foundation
import ZIPFoundation

enum UserDataExporter {
    static func exportData(
        to fileURL: URL, types: Set<UserDataType> = Set(UserDataType.allCases)
    ) async throws -> UserDataExportReport {
        guard fileURL.isFileURL else {
            throw CocoaError(.fileWriteUnsupportedScheme)
        }
        
        guard !fileURL.path.contains("\0") else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        
        let selectedTypes = UserDataType.allCases.filter { types.contains($0) }
        let fileExtension = fileURL.pathExtension.lowercased()
        let isArchive = fileExtension == "zip"
        guard !selectedTypes.isEmpty else {
            throw UserDataError.invalidExportSelection
        }
        
        switch fileExtension {
        case "zip":
            break
        case "html" where types == [.bookmarks]:
            break
        case "json" where types == [.history] || types == [.extensions]:
            break
        default:
            throw UserDataError.invalidExportSelection
        }
        
        let destinationURL = isArchive
        ? fileURL.deletingLastPathComponent().appendingPathComponent(archiveFileName)
        : fileURL
        
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
        
        var report = UserDataExportReport(fileURL: destinationURL)
        for type in selectedTypes {
            try Task.checkCancellation()
            let destination = isArchive ? directory.appendingPathComponent(type.fileName) : destinationURL
            let count: Int
            switch type {
            case .bookmarks:
                count = try await BookmarkExporter.exportBookmarks(to: destination)
            case .history:
                count = try await SafariHistoryExporter.exportHistory(to: destination)
            case .extensions:
                count = try await AddonExporter.exportAddons(to: destination)
            }
            report.recordCounts[type] = count
        }
        
        if isArchive {
            try await writeArchive(from: directory, types: selectedTypes, to: destinationURL)
        }
        
        return report
    }
    
    static var archiveFileName: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return "Reynard Export \(formatter.string(from: Date())).zip"
    }
    
    private static func writeArchive(from directory: URL, types: [UserDataType], to fileURL: URL) async throws {
        let progress = Progress(totalUnitCount: 0)
        let task = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let coordinator = NSFileCoordinator()
            var coordinationError: NSError?
            var result: Result<Void, Error> = .success(())
            
            coordinator.coordinate(writingItemAt: fileURL, options: .forReplacing, error: &coordinationError) { destination in
                result = Result {
                    try Task.checkCancellation()
                    let temporaryURL = destination.deletingLastPathComponent()
                        .appendingPathComponent(".\(UUID().uuidString).zip")
                    defer {
                        try? FileManager.default.removeItem(at: temporaryURL)
                    }
                    
                    do {
                        let archive = try Archive(url: temporaryURL, accessMode: .create)
                        for type in types {
                            try Task.checkCancellation()
                            try archive.addEntry(
                                with: type.fileName, relativeTo: directory,
                                compressionMethod: .deflate, progress: progress
                            )
                        }
                    }
                    
                    try Task.checkCancellation()
                    guard rename(temporaryURL.path, destination.path) == 0 else {
                        throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                    }
                }
            }
            
            if let coordinationError {
                throw coordinationError
            }
            try result.get()
        }
        
        try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            progress.cancel()
            task.cancel()
        }
    }
}
