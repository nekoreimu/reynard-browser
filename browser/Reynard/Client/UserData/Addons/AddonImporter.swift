//
//  AddonImporter.swift
//  Reynard
//
//  Created by Minh Ton on 20/10/26.
//

import Foundation
import GeckoView

enum AddonImporter {
    private static var isImporting = false
    private static var installingAddonID: String?
    private(set) static var importingAddonIDs = Set<String>()
    
    static func importAddons(from fileURL: URL) async throws -> AddonImportReport {
        guard !isImporting else {
            throw AddonDataError.operationInProgress
        }
        
        isImporting = true
        defer {
            isImporting = false
            importingAddonIDs.removeAll()
        }
        
        let task = Task.detached(priority: .userInitiated) {
            return try AddonDataFile.read(from: fileURL)
        }
        let document = try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
        
        importingAddonIDs = Set(document.records.keys)
        
        try Task.checkCancellation()
        var report = AddonImportReport()
        report.issues = document.issues
        
        guard !document.records.isEmpty else {
            return report
        }
        
        let runtime = AddonRuntime.shared
        let installed = try await runtime.list()
        let engineVersion = GeckoRuntime.version
        
        for (id, record) in document.records.sorted(by: { $0.key < $1.key }) {
            try Task.checkCancellation()
            
            do {
                var addon = installed.first(where: { $0.id == id })
                if addon == nil {
                    let downloadURL = try await AddonCatalog.resolve(id: id, engineVersion: engineVersion)
                    try Task.checkCancellation()
                    
                    addon = try await runtime.list().first(where: { $0.id == id })
                    if addon == nil {
                        try Task.checkCancellation()
                        installingAddonID = id
                        defer {
                            installingAddonID = nil
                        }
                        addon = try await runtime.install(url: downloadURL.absoluteString, installMethod: .manager)
                    }
                }
                
                guard let addon, addon.id == id, !addon.isBuiltIn else {
                    throw AddonDataError.catalog("The package is built-in or has a different add-on ID. Its settings were not restored.")
                }
                
                let issues = try await restore(record, on: addon)
                report.recordRestoration(
                    addonID: id, exportedVersion: record.version,
                    installedVersion: addon.metaData.version, issues: issues
                )
            } catch {
                try Task.checkCancellation()
                report.issues.append(AddonImportIssue(addonID: id, message: error.localizedDescription))
            }
        }
        
        return report
    }
    
    static func installationResponse(for prompt: AddonPermissionPrompt) -> AddonPermissionPromptResponse? {
        guard prompt.kind == .install, prompt.addon.id == installingAddonID else {
            return nil
        }
        
        return AddonPermissionPromptResponse(allow: true)
    }
    
    private static func restore(_ record: AddonDataRecord, on addon: Addon) async throws -> [String] {
        let runtime = AddonRuntime.shared
        var current = addon
        var issues: [String] = []
        
        func apply(_ label: String, operation: (Addon) async throws -> Addon) async throws {
            try Task.checkCancellation()
            do {
                current = try await operation(current)
            } catch {
                try Task.checkCancellation()
                issues.append("\(label): \(error.localizedDescription)")
            }
        }
        
        let settings = record.settings
        let flags = record.disabledFlags
        let userDisabled = flags?.contains("userDisabled") ?? settings?.enabled.map { !$0 }
        let appDisabled = flags?.contains("appDisabled")
        
        if userDisabled == true, !current.metaData.disabledFlags.contains("userDisabled") {
            try await apply("Disable add-on") {
                try await runtime.disable($0, source: .user)
            }
        }
        
        if appDisabled == true, !current.metaData.disabledFlags.contains("appDisabled") {
            try await apply("Disable add-on for the app") {
                try await runtime.disable($0, source: .app)
            }
        }
        
        if let allowed = settings?.allowedInPrivateBrowsing,
           allowed != current.metaData.allowedInPrivateBrowsing {
            if allowed && current.metaData.incognito == .notAllowed {
                issues.append("This version does not allow private browsing access.")
            } else {
                try await apply("Private browsing access") {
                    try await runtime.setAllowedInPrivateBrowsing($0, allowed: allowed)
                }
            }
        }
        
        for kind in PermissionKind.allCases {
            guard let saved = kind.saved(in: settings) else {
                continue
            }
            
            let desired = Set(saved)
            let granted = Set(kind.granted(in: current.metaData))
            for value in granted.subtracting(desired).sorted() {
                if kind == .permission, value == "<all_urls>" {
                    continue
                }
                
                // Required permissions belong to the installed package and cannot be revoked here.
                if kind.required(in: current.metaData).contains(value) {
                    issues.append("This version requires \(kind.rawValue): \(value). It could not be revoked.")
                    continue
                }
                
                try await apply("Remove \(kind.rawValue): \(value)") {
                    try await runtime.removeOptionalPermissions(kind.request(value), from: $0)
                }
            }
            
            for value in desired.sorted() {
                if kind.granted(in: current.metaData).contains(value) ||
                    kind.required(in: current.metaData).contains(value) {
                    continue
                }
                
                // <all_urls> is also returned as an API permission when its origin is granted.
                if kind == .permission, value == "<all_urls>" {
                    continue
                }
                
                if kind != .origin, !kind.available(in: current.metaData).contains(value) {
                    issues.append("This version no longer offers optional \(kind.rawValue): \(value)")
                    continue
                }
                
                try await apply("Grant \(kind.rawValue): \(value)") {
                    try await runtime.addOptionalPermissions(kind.request(value), to: $0)
                }
            }
        }
        
        if appDisabled == false, current.metaData.disabledFlags.contains("appDisabled") {
            try await apply("Enable add-on for the app") {
                try await runtime.enable($0, source: .app)
            }
        }
        
        if userDisabled == false, current.metaData.disabledFlags.contains("userDisabled") {
            try await apply("Enable add-on") {
                try await runtime.enable($0, source: .user)
            }
        }
        
        if settings?.enabled == true, !current.metaData.enabled {
            issues.append("The add-on is still inactive: \(current.metaData.disabledFlags.joined(separator: ", ")).")
        }
        
        try Task.checkCancellation()
        return issues
    }
    
    private enum PermissionKind: String, CaseIterable {
        case permission
        case origin
        case dataCollection = "data collection permission"
        
        func saved(in settings: AddonDataSettings?) -> [String]? {
            switch self {
            case .permission:
                return settings?.grantedOptionalPermissions
            case .origin:
                if let origins = settings?.grantedOptionalOrigins {
                    return origins
                }
                
                return settings?.grantedOptionalPermissions?.contains("<all_urls>") == true ? ["<all_urls>"] : nil
            case .dataCollection:
                return settings?.grantedOptionalDataCollectionPermissions
            }
        }
        
        func granted(in metadata: AddonMetaData) -> [String] {
            switch self {
            case .permission:
                return metadata.grantedOptionalPermissions
            case .origin:
                return metadata.grantedOptionalOrigins
            case .dataCollection:
                return metadata.grantedOptionalDataCollectionPermissions
            }
        }
        
        func available(in metadata: AddonMetaData) -> [String] {
            switch self {
            case .permission:
                return metadata.optionalPermissions
            case .origin:
                return metadata.optionalOrigins
            case .dataCollection:
                return metadata.optionalDataCollectionPermissions
            }
        }
        
        func required(in metadata: AddonMetaData) -> [String] {
            switch self {
            case .permission:
                return metadata.requiredPermissions
            case .origin:
                return metadata.requiredOrigins
            case .dataCollection:
                return metadata.requiredDataCollectionPermissions
            }
        }
        
        func request(_ value: String) -> AddonPermissionChangeRequest {
            switch self {
            case .permission:
                return AddonPermissionChangeRequest(permissions: [value])
            case .origin:
                return AddonPermissionChangeRequest(origins: [value])
            case .dataCollection:
                return AddonPermissionChangeRequest(dataCollectionPermissions: [value])
            }
        }
    }
}
