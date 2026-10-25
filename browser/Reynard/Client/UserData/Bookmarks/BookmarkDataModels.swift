//
//  BookmarkDataModels.swift
//  Reynard
//
//  Created by Minh Ton on 20/10/26.
//

import Foundation

nonisolated struct BookmarkReadingListEntry: Sendable {
    let title: String
    let url: URL
    let dateAdded: Date?
}

nonisolated struct BookmarkImportReport: Sendable {
    var importedBookmarkCount = 0
    var importedFolderCount = 0
    var duplicateBookmarkCount = 0
    var mergedFolderCount = 0
    var invalidBookmarkCount = 0
    var readingList: [BookmarkReadingListEntry] = []
}

nonisolated enum BookmarkDataError: LocalizedError {
    case invalidHTML
    case unrecognizedFormat
    case fileTooLarge
    case databaseUnavailable
    case database(String)
    case invalidStoredData
    
    var errorDescription: String? {
        switch self {
        case .invalidHTML, .unrecognizedFormat:
            return NSLocalizedString("The file does not contain readable HTML bookmarks.", comment: "")
        case .fileTooLarge:
            return NSLocalizedString("The bookmarks file is too large to parse.", comment: "")
        case .databaseUnavailable:
            return NSLocalizedString("The bookmarks database is unavailable.", comment: "")
        case .database(let message):
            return String.localizedStringWithFormat(
                NSLocalizedString("The bookmarks database reported an error: %@", comment: "Database error message"), message
            )
        case .invalidStoredData:
            return NSLocalizedString("The bookmarks database contains an invalid bookmark or folder structure.", comment: "")
        }
    }
}

nonisolated enum BookmarkHTMLSpecialFolder: Sendable {
    case bookmarks
    case favorites
}

nonisolated struct BookmarkHTMLItem: Sendable {
    let parent: Int?
    let title: String
    let url: String?
    let dateAdded: Double?
    let specialFolder: BookmarkHTMLSpecialFolder?
}

nonisolated struct BookmarkHTMLDocument: Sendable {
    var items: [BookmarkHTMLItem] = []
    var report = BookmarkImportReport()
}
