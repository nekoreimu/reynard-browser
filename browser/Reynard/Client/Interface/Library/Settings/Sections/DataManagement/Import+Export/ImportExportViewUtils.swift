//
//  ImportExportViewUtils.swift
//  Reynard
//
//  Created by Minh Ton on 22/10/26.
//

import Darwin
import Foundation
import ZIPFoundation

enum ImportExportViewUtils {
    static func title(for type: UserDataType) -> String {
        switch type {
        case .bookmarks:
            return NSLocalizedString("Bookmarks", comment: "")
        case .history:
            return NSLocalizedString("History", comment: "")
        case .extensions:
            return NSLocalizedString("Add-ons", comment: "")
        }
    }
    
    static func iconName(for type: UserDataType) -> String {
        switch type {
        case .bookmarks:
            return "reynard.book"
        case .history:
            return "reynard.clock"
        case .extensions:
            return "reynard.puzzlepiece.extension"
        }
    }
    
    static func countDescription(_ count: Int, for type: UserDataType) -> String {
        switch type {
        case .bookmarks:
            return String.localizedStringWithFormat(NSLocalizedString("%d bookmarks", comment: "Bookmark count"), count)
        case .history:
            return String.localizedStringWithFormat(NSLocalizedString("%d websites", comment: "Website count"), count)
        case .extensions:
            return String.localizedStringWithFormat(NSLocalizedString("%d add-ons", comment: "Add-on count"), count)
        }
    }
    
    static func exportErrorMessage(for error: Error) -> String {
        var fileError = error as NSError
        while true {
            switch (fileError.domain, fileError.code) {
            case (NSCocoaErrorDomain, CocoaError.Code.fileWriteOutOfSpace.rawValue),
                (NSPOSIXErrorDomain, Int(ENOSPC)),
                (NSPOSIXErrorDomain, Int(EDQUOT)):
                return NSLocalizedString("There isn’t enough space to export your data. Free up space and try again.", comment: "")
            case (NSCocoaErrorDomain, CocoaError.Code.fileWriteNoPermission.rawValue),
                (NSCocoaErrorDomain, CocoaError.Code.fileWriteVolumeReadOnly.rawValue),
                (NSPOSIXErrorDomain, Int(EACCES)),
                (NSPOSIXErrorDomain, Int(EPERM)),
                (NSPOSIXErrorDomain, Int(EROFS)):
                return NSLocalizedString("The export couldn’t be saved in the selected folder. Choose another location and try again.", comment: "")
            default:
                break
            }
            
            guard let underlyingError = fileError.userInfo[NSUnderlyingErrorKey] as? NSError else {
                break
            }
            fileError = underlyingError
        }
        
        switch error {
        case is BookmarkDataError:
            return NSLocalizedString("Your bookmarks couldn’t be exported. Try again.", comment: "")
        case is HistoryDataError:
            return NSLocalizedString("Your history couldn’t be exported. Try again.", comment: "")
        case is AddonDataError:
            return NSLocalizedString("Your add-ons couldn’t be exported. Try again.", comment: "")
        case is Archive.ArchiveError:
            return NSLocalizedString("The export archive couldn’t be created. Try again or choose another location.", comment: "")
        default:
            return NSLocalizedString("Your data couldn’t be exported. Try again or choose another location.", comment: "")
        }
    }
}
