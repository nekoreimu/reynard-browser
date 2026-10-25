//
//  ImportDataSummary.swift
//  Reynard
//
//  Created by Minh Ton on 22/10/26.
//

import Foundation

struct ImportDataSummary {
    private struct Counts {
        var imported = 0
        var skipped = 0
    }
    
    private var counts: [UserDataType: Counts] = [:]
    private var failedTypes = Set<UserDataType>()
    private var hasUnrestoredAddonSettings = false
    private(set) var hasImportedData = false
    private(set) var issues: [String] = []
    
    mutating func record(_ result: UserDataImportResult) {
        switch result {
        case .bookmarks(_, let report):
            if report.importedBookmarkCount > 0 || report.importedFolderCount > 0 {
                hasImportedData = true
            }
            
            counts[.bookmarks, default: Counts()].imported += report.importedBookmarkCount
            let skipped = report.duplicateBookmarkCount + report.invalidBookmarkCount + report.readingList.count
            counts[.bookmarks, default: Counts()].skipped += skipped
        case .history(_, let report):
            if report.importedRecordCount > 0 {
                hasImportedData = true
            }
            
            counts[.history, default: Counts()].imported += report.importedRecordCount
            counts[.history, default: Counts()].skipped += report.duplicateRecordCount + report.invalidRecordCount
        case .extensions(_, let report):
            let imported = report.restoredAddonCount + report.partiallyRestoredAddonCount
            if imported > 0 {
                hasImportedData = true
            }
            
            let skipped = Set(report.issues.map(\.addonID)).count - report.partiallyRestoredAddonCount
            counts[.extensions, default: Counts()].imported += imported
            counts[.extensions, default: Counts()].skipped += skipped
            if report.partiallyRestoredAddonCount > 0 {
                hasUnrestoredAddonSettings = true
            }
        case .skipped:
            break
        case .failed(let fileName, let dataType, let message):
            if let dataType {
                failedTypes.insert(dataType)
            }
            issues.append("\(fileName): \(message)")
        }
    }
    
    func subtitle(for type: UserDataType) -> String {
        if failedTypes.contains(type), counts[type] == nil {
            return NSLocalizedString("Import failed", comment: "")
        }
        
        let count = counts[type] ?? Counts()
        var subtitle: String
        if count.skipped > 0 {
            subtitle = String.localizedStringWithFormat(
                NSLocalizedString("%d imported · %d skipped", comment: "Imported and skipped record counts"),
                count.imported, count.skipped
            )
        } else {
            subtitle = String.localizedStringWithFormat(NSLocalizedString("%d imported", comment: "Imported record count"), count.imported)
        }
        
        if type == .extensions, hasUnrestoredAddonSettings {
            subtitle += "\n" + NSLocalizedString("Some add-on settings couldn’t be restored.", comment: "")
        }
        
        if failedTypes.contains(type) {
            subtitle += "\n" + NSLocalizedString("Some data couldn’t be imported.", comment: "")
        }
        return subtitle
    }
}
