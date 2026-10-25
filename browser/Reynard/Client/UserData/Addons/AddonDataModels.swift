//
//  AddonDataModels.swift
//  Reynard
//
//  Created by Minh Ton on 20/10/26.
//

import Foundation

nonisolated struct AddonDataMetadata: Codable, Sendable {
    let browserName: String
    let browserVersion: String
    let dataType: String
    let exportTimeUsec: Int64
    let schemaVersion: Int
    
    enum CodingKeys: String, CodingKey {
        case browserName = "browser_name"
        case browserVersion = "browser_version"
        case dataType = "data_type"
        case exportTimeUsec = "export_time_usec"
        case schemaVersion = "schema_version"
    }
}

nonisolated struct AddonDataRecord: Codable, Sendable {
    let name: String?
    let version: String
    let disabledFlags: [String]?
    let settings: AddonDataSettings?
    
    enum CodingKeys: String, CodingKey {
        case name, version, settings
        case disabledFlags = "disabled_flags"
    }
    
    func validate() throws {
        guard !version.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              !version.contains("\0") else {
            throw AddonDataError.invalidFile
        }
        
        let grants = (settings?.grantedOptionalPermissions ?? []) +
        (settings?.grantedOptionalOrigins ?? []) +
        (settings?.grantedOptionalDataCollectionPermissions ?? [])
        let invalidCharacters = CharacterSet.whitespacesAndNewlines.union(.controlCharacters)
        for value in grants {
            guard !value.isEmpty,
                  !value.hasPrefix("internal:"),
                  value.rangeOfCharacter(from: invalidCharacters) == nil else {
                throw AddonDataError.invalidFile
            }
        }
    }
}

nonisolated struct AddonDataSettings: Codable, Sendable {
    let enabled: Bool?
    let allowedInPrivateBrowsing: Bool?
    let grantedOptionalPermissions: [String]?
    let grantedOptionalOrigins: [String]?
    let grantedOptionalDataCollectionPermissions: [String]?
    
    enum CodingKeys: String, CodingKey {
        case enabled
        case allowedInPrivateBrowsing = "allowed_in_private_browsing"
        case grantedOptionalPermissions = "granted_optional_permissions"
        case grantedOptionalOrigins = "granted_optional_origins"
        case grantedOptionalDataCollectionPermissions = "granted_optional_data_collection_permissions"
    }
}

nonisolated struct AddonImportIssue: Sendable {
    let addonID: String
    let message: String
}

nonisolated struct AddonImportVersionChange: Sendable {
    let addonID: String
    let exportedVersion: String
    let installedVersion: String
}

nonisolated struct AddonImportReport: Sendable {
    var restoredAddonCount = 0
    var partiallyRestoredAddonCount = 0
    var versionChanges: [AddonImportVersionChange] = []
    var issues: [AddonImportIssue] = []
    
    mutating func recordRestoration(
        addonID: String, exportedVersion: String, installedVersion: String, issues: [String]
    ) {
        if issues.isEmpty {
            restoredAddonCount += 1
        } else {
            partiallyRestoredAddonCount += 1
        }
        
        self.issues += issues.map { AddonImportIssue(addonID: addonID, message: $0) }
        
        if exportedVersion != installedVersion {
            versionChanges.append(AddonImportVersionChange(
                addonID: addonID, exportedVersion: exportedVersion, installedVersion: installedVersion
            ))
        }
    }
}

nonisolated enum AddonDataError: LocalizedError {
    case invalidFile
    case unsupportedSchema(Int)
    case duplicateKey(String)
    case operationInProgress
    case catalogHTTP(Int)
    case catalog(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidFile:
            return NSLocalizedString("The file does not contain valid add-on data.", comment: "")
        case .unsupportedSchema(let version):
            return String.localizedStringWithFormat(
                NSLocalizedString("Add-on schema version %ld is not supported.", comment: "Schema version"), version
            )
        case .duplicateKey(let key):
            return String.localizedStringWithFormat(
                NSLocalizedString("The add-on file contains a duplicate key: %@", comment: "JSON key"), key
            )
        case .operationInProgress:
            return NSLocalizedString("An add-on import is already in progress.", comment: "")
        case .catalogHTTP(let status):
            return "The add-on catalog returned HTTP \(status)."
        case .catalog(let message):
            return message
        }
    }
}
