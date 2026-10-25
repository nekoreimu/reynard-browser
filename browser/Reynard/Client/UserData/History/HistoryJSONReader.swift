//
//  HistoryJSONReader.swift
//  Reynard
//
//  Created by Minh Ton on 20/10/26.
//

import Foundation

nonisolated final class HistoryJSONReader {
    private let stream: InputStream
    private var buffer = [UInt8](repeating: 0, count: 65_536)
    private var offset = 0
    private var length = 0
    
    init(fileURL: URL) throws {
        guard fileURL.isFileURL, let stream = InputStream(url: fileURL) else {
            throw CocoaError(.fileReadUnsupportedScheme)
        }
        
        self.stream = stream
        stream.open()
    }
    
    deinit {
        stream.close()
    }
    
    func firstRootKey(in keys: Set<String>) throws -> String? {
        guard try beginObject() else {
            return nil
        }
        
        var seenKeys = Set<String>()
        if try peek() != 0x7D { // }
            while true {
                try Task.checkCancellation()
                guard let key = try jsonValue(value()) as? String, seenKeys.insert(key).inserted else {
                    throw HistoryDataError.invalidJSON
                }
                try expect(0x3A) // :
                if keys.contains(key) {
                    return key
                }
                
                _ = try jsonValue(value())
                if try peek() == 0x7D { // }
                    break
                }
                try expect(0x2C) // ,
            }
        }
        
        try expect(0x7D) // }
        guard try peek() == nil else {
            throw HistoryDataError.invalidJSON
        }
        
        return nil
    }
    
    func read(onRecord: (Data, HistoryImportFormat) throws -> Void) throws -> HistoryImportFormat {
        guard try beginObject() else {
            throw HistoryDataError.unrecognizedFormat
        }
        
        var keys = Set<String>()
        var format: HistoryImportFormat?
        var metadata: [String: Any]?
        
        if try peek() != 0x7D { // }
            while true {
                guard let key = try jsonValue(value()) as? String, keys.insert(key).inserted else {
                    throw HistoryDataError.invalidJSON
                }
                
                try expect(0x3A) // :
                
                if key == "history" || key == "Browser History" {
                    guard format == nil else {
                        throw HistoryDataError.unrecognizedFormat
                    }
                    
                    let source: HistoryImportFormat = key == "history" ? .safari : .chrome
                    format = source
                    try array { try onRecord($0, source) }
                } else if key == "metadata" {
                    metadata = try jsonValue(value()) as? [String: Any]
                } else {
                    _ = try jsonValue(value())
                }
                
                if try peek() == 0x7D { // }
                    break
                }
                try expect(0x2C) // ,
            }
        }
        
        try expect(0x7D) // }
        guard try peek() == nil else {
            throw HistoryDataError.invalidJSON
        }
        
        guard let format else {
            throw HistoryDataError.unrecognizedFormat
        }
        
        if format == .safari {
            let browserName = (metadata?["browser_name"] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
            let dataType = (metadata?["data_type"] as? String)?.lowercased()
            guard let browserName, !browserName.isEmpty, dataType == "history" else {
                throw HistoryDataError.invalidMetadata
            }
        }
        
        return format
    }
    
    private func beginObject() throws -> Bool {
        if try rawByte() == 0xEF { // First byte of the UTF-8 byte order mark.
            for byte in [UInt8(0xEF), 0xBB, 0xBF] { // UTF-8 byte order mark.
                guard try rawByte() == byte else {
                    throw HistoryDataError.invalidJSON
                }
                
                offset += 1
            }
        }
        
        guard try peek() == 0x7B else { // {
            return false
        }
        
        offset += 1
        return true
    }
    
    private func array(onValue: (Data) throws -> Void) throws {
        try expect(0x5B) // [
        if try peek() != 0x5D { // ]
            while true {
                try Task.checkCancellation()
                try autoreleasepool {
                    let data = try value()
                    _ = try jsonValue(data)
                    try onValue(data)
                }
                
                if try peek() == 0x5D { // ]
                    break
                }
                try expect(0x2C) // ,
            }
        }
        try expect(0x5D) // ]
    }
    
    private func value() throws -> Data {
        guard let first = try peek() else {
            throw HistoryDataError.invalidJSON
        }
        
        var data = Data()
        var closingBrackets: [UInt8] = []
        var inString = false
        var escaped = false
        let startsString = first == 0x22 // "
        let startsContainer = first == 0x7B || first == 0x5B // { [
        let isPrimitive = !startsString && !startsContainer
        
        while let byte = try rawByte() {
            if isPrimitive {
                let isSeparator = byte == 0x2C || byte == 0x5D || byte == 0x7D // , ] }
                if Self.isWhitespace(byte) || isSeparator {
                    break
                }
            }
            
            offset += 1
            data.append(byte)
            if inString {
                if escaped {
                    escaped = false
                } else if byte == 0x5C { // Backslash.
                    escaped = true
                } else if byte == 0x22 { // Double quote.
                    inString = false
                }
            } else {
                switch byte {
                case 0x22: // "
                    inString = true
                case 0x7B: // {
                    closingBrackets.append(0x7D) // }
                case 0x5B: // [
                    closingBrackets.append(0x5D) // ]
                case 0x7D, 0x5D: // } ]
                    guard closingBrackets.popLast() == byte else {
                        throw HistoryDataError.invalidJSON
                    }
                default:
                    break
                }
            }
            
            guard closingBrackets.count <= 512 else {
                throw HistoryDataError.invalidJSON
            }
            
            if !isPrimitive && !inString && closingBrackets.isEmpty {
                break
            }
        }
        
        guard !inString, closingBrackets.isEmpty else {
            throw HistoryDataError.invalidJSON
        }
        
        return data
    }
    
    private func jsonValue(_ data: Data) throws -> Any {
        do {
            return try JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
        } catch {
            throw HistoryDataError.invalidJSON
        }
    }
    
    private func expect(_ byte: UInt8) throws {
        guard try peek() == byte else {
            throw HistoryDataError.invalidJSON
        }
        
        offset += 1
    }
    
    private func peek() throws -> UInt8? {
        while let byte = try rawByte() {
            if !Self.isWhitespace(byte) {
                return byte
            }
            
            offset += 1
        }
        
        return nil
    }
    
    private func rawByte() throws -> UInt8? {
        if offset == length {
            try Task.checkCancellation()
            let capacity = buffer.count
            length = stream.read(&buffer, maxLength: capacity)
            offset = 0
            if length < 0 {
                throw stream.streamError ?? CocoaError(.fileReadUnknown)
            }
            
            if length == 0 {
                return nil
            }
        }
        
        return buffer[offset]
    }
    
    private static func isWhitespace(_ byte: UInt8) -> Bool {
        return byte == 0x20 || byte == 0x09 || byte == 0x0A || byte == 0x0D // Space, tab, LF, CR.
    }
}
