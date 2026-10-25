//
//  UserDataFileWriter.swift
//  Reynard
//
//  Created by Minh Ton on 20/10/26.
//

import Foundation

nonisolated final class UserDataFileWriter {
    private let stream: OutputStream
    private var buffer = Data()
    
    init(fileURL: URL) throws {
        guard let stream = OutputStream(url: fileURL, append: false) else {
            throw CocoaError(.fileWriteUnknown)
        }
        
        self.stream = stream
        stream.open()
    }
    
    deinit {
        stream.close()
    }
    
    func append<Bytes: Sequence>(_ bytes: Bytes) throws where Bytes.Element == UInt8 {
        buffer.append(contentsOf: bytes)
        if buffer.count >= 65_536 {
            try flush()
        }
    }
    
    func finish() throws {
        try flush()
        stream.close()
    }
    
    private func flush() throws {
        try buffer.withUnsafeBytes { bytes in
            guard let start = bytes.baseAddress?.assumingMemoryBound(to: UInt8.self) else {
                return
            }
            
            var offset = 0
            while offset < bytes.count {
                try Task.checkCancellation()
                let written = stream.write(start.advanced(by: offset), maxLength: bytes.count - offset)
                guard written > 0 else {
                    throw stream.streamError ?? CocoaError(.fileWriteUnknown)
                }
                
                offset += written
            }
        }
        
        buffer.removeAll(keepingCapacity: true)
    }
}
