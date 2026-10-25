//
//  AddonDataFile.swift
//  Reynard
//
//  Created by Minh Ton on 23/10/26.
//

import Foundation

nonisolated enum AddonDataFile {
    struct Document: Sendable {
        var records: [String: AddonDataRecord] = [:]
        var issues: [AddonImportIssue] = []
    }
    
    static func read(from fileURL: URL) throws -> Document {
        guard fileURL.isFileURL else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        
        guard !fileURL.path.contains("\0") else {
            throw CocoaError(.fileReadInvalidFileName)
        }
        
        let hasAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        
        try Task.checkCancellation()
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let metadata = root["metadata"] as? [String: Any],
              let extensions = root["extensions"] as? [String: Any] else {
            throw AddonDataError.invalidFile
        }
        
        try rejectDuplicateKeys(in: data)
        let decoder = JSONDecoder()
        let header = try decoder.decode(
            AddonDataMetadata.self, from: JSONSerialization.data(withJSONObject: metadata)
        )
        guard header.schemaVersion == 1 else {
            throw AddonDataError.unsupportedSchema(header.schemaVersion)
        }
        
        guard !header.browserName.isEmpty,
              header.dataType == "extensions",
              header.exportTimeUsec >= 0 else {
            throw AddonDataError.invalidFile
        }
        
        var document = Document()
        for (id, value) in extensions.sorted(by: { $0.key < $1.key }) {
            try Task.checkCancellation()
            do {
                guard isValidID(id), let object = value as? [String: Any] else {
                    throw AddonDataError.invalidFile
                }
                
                let record = try decoder.decode(
                    AddonDataRecord.self, from: JSONSerialization.data(withJSONObject: object)
                )
                try record.validate()
                document.records[id] = record
            } catch {
                document.issues.append(AddonImportIssue(addonID: id, message: error.localizedDescription))
            }
        }
        
        return document
    }
    
    static func isValidID(_ value: String) -> Bool {
        let pattern = #"(?i)^(\{[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}\}|[a-z0-9._-]*@[a-z0-9._-]+)$"#
        return value.range(of: pattern, options: .regularExpression) == (value.startIndex..<value.endIndex)
    }
    
    private static func rejectDuplicateKeys(in data: Data) throws {
        guard let text = String(data: data, encoding: .utf8) else {
            throw AddonDataError.invalidFile
        }
        
        let bytes = Array(text.utf8)
        var objects: [Set<String>?] = [] // Arrays have no keys and use nil.
        var index = 0
        let decoder = JSONDecoder()
        while index < bytes.count {
            try Task.checkCancellation()
            switch bytes[index] {
            case 0x7B: // {
                objects.append([])
            case 0x5B: // [
                objects.append(nil)
            case 0x7D, 0x5D: // } or ]
                objects.removeLast()
            case 0x22: // "
                let start = index
                index += 1
                while index < bytes.count {
                    if bytes[index] == 0x5C { // Backslash escapes the following byte.
                        index += 2
                    } else if bytes[index] == 0x22 {
                        break
                    } else {
                        index += 1
                    }
                }
                
                var next = index + 1
                while next < bytes.count && [0x20, 0x09, 0x0A, 0x0D].contains(bytes[next]) {
                    next += 1 // Space, tab, line feed, or carriage return.
                }
                
                if next < bytes.count, bytes[next] == 0x3A { // :
                    let key = try decoder.decode(String.self, from: Data(bytes[start...index]))
                    let last = objects.count - 1
                    if objects[last]?.insert(key).inserted == false {
                        throw AddonDataError.duplicateKey(key)
                    }
                }
            default:
                break
            }
            
            index += 1
        }
    }
}
