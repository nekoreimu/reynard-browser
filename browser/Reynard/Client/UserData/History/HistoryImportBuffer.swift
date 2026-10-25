//
//  HistoryImportBuffer.swift
//  Reynard
//
//  Created by Minh Ton on 20/10/26.
//

import Foundation

nonisolated final class HistoryImportBuffer {
    private let writer: UserDataFileWriter
    private let encoder = PropertyListEncoder()
    
    init(fileURL: URL) throws {
        writer = try UserDataFileWriter(fileURL: fileURL)
        encoder.outputFormat = .binary
    }
    
    func append(_ record: HistoryImportRecord) throws {
        let data = try encoder.encode(record)
        
        var length = UInt64(data.count).bigEndian
        try withUnsafeBytes(of: &length) {
            try writer.append(Data($0))
        }
        
        try writer.append(data)
    }
    
    func finish() throws {
        try writer.finish()
    }
    
    static func enumerateRecords(
        from fileURL: URL,
        cancellation: UserDataCancellation,
        onRecord: (HistoryImportRecord) throws -> Void
    ) throws {
        guard let stream = InputStream(url: fileURL) else {
            throw CocoaError(.fileReadUnknown)
        }
        
        stream.open()
        defer {
            stream.close()
        }
        
        func read(_ count: Int) throws -> Data {
            var data = Data(count: count)
            let length = try data.withUnsafeMutableBytes { bytes -> Int in
                guard let start = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                    return 0
                }
                
                var offset = 0
                while offset < count {
                    try cancellation.checkCancellation()
                    let bytesRead = stream.read(start.advanced(by: offset), maxLength: min(count - offset, 65_536))
                    guard bytesRead >= 0 else {
                        throw stream.streamError ?? CocoaError(.fileReadUnknown)
                    }
                    
                    if bytesRead == 0 {
                        break
                    }
                    
                    offset += bytesRead
                }
                
                return offset
            }
            
            data.count = length
            return data
        }
        
        let decoder = PropertyListDecoder()
        while true {
            let header = try read(8)
            if header.isEmpty {
                return
            }
            
            guard header.count == 8,
                  let length = Int(exactly: header.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }),
                  length > 0 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            
            try autoreleasepool {
                let data = try read(length)
                guard data.count == length else {
                    throw CocoaError(.fileReadCorruptFile)
                }
                
                try onRecord(decoder.decode(HistoryImportRecord.self, from: data))
            }
        }
    }
}
