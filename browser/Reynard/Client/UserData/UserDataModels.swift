//
//  UserDataModels.swift
//  Reynard
//
//  Created by Minh Ton on 21/10/26.
//

import Foundation

nonisolated enum UserDataType: String, CaseIterable, Sendable {
    case bookmarks
    case history
    case extensions
    
    var fileName: String {
        switch self {
        case .bookmarks:
            return "Bookmarks.html"
        case .history:
            return "History.json"
        case .extensions:
            return "Extensions.json"
        }
    }
}

nonisolated enum UserDataImportResult: Sendable {
    case bookmarks(fileName: String, report: BookmarkImportReport)
    case history(fileName: String, report: HistoryImportReport)
    case extensions(fileName: String, report: AddonImportReport)
    case skipped(fileName: String, reason: String)
    case failed(fileName: String, dataType: UserDataType?, message: String)
}

nonisolated struct UserDataImportReport: Sendable {
    var results: [UserDataImportResult] = []
}

nonisolated struct UserDataExportReport: Sendable {
    let fileURL: URL
    var recordCounts: [UserDataType: Int] = [:]
}

nonisolated enum UserDataError: LocalizedError {
    case unsupportedFile
    case noImportableFiles
    case invalidArchive
    case invalidArchiveEntry(String)
    case unsupportedSafariExtensions
    case invalidExportSelection
    
    var errorDescription: String? {
        switch self {
        case .unsupportedFile, .noImportableFiles:
            return NSLocalizedString("The file does not contain supported bookmarks, history, or add-on data.", comment: "")
        case .invalidArchive:
            return NSLocalizedString("The ZIP archive is damaged or incomplete and couldn’t be read.", comment: "")
        case .invalidArchiveEntry(let path):
            return String.localizedStringWithFormat(
                NSLocalizedString("The ZIP archive contains a damaged file: %@", comment: "File path in the archive"), path
            )
        case .unsupportedSafariExtensions:
            return "Safari extension information cannot be used to reinstall Firefox add-ons."
        case .invalidExportSelection:
            return "Choose bookmarks for HTML, history or add-ons for JSON, or a ZIP for multiple categories."
        }
    }
}
