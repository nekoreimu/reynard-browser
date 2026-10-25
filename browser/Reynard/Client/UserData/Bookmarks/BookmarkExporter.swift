//
//  BookmarkExporter.swift
//  Reynard
//
//  Created by Minh Ton on 20/10/26.
//

import Darwin
import Foundation

enum BookmarkExporter {
    static func exportBookmarks(to fileURL: URL) async throws -> Int {
        guard fileURL.isFileURL else {
            throw CocoaError(.fileWriteUnsupportedScheme)
        }
        
        guard !fileURL.path.contains("\0") else {
            throw CocoaError(.fileWriteInvalidFileName)
        }
        
        let store = BookmarkStore.shared
        let cancellation = UserDataCancellation()
        let nodes = try await withTaskCancellationHandler {
            try await store.performBookmarkDataOperation { database in
                return try BookmarkDataStorage(database: database).readNodes(cancellation: cancellation)
            }
        } onCancel: {
            cancellation.cancel()
        }
        
        let task = Task.detached(priority: .userInitiated) {
            let hasAccess = fileURL.startAccessingSecurityScopedResource()
            defer {
                if hasAccess {
                    fileURL.stopAccessingSecurityScopedResource()
                }
            }
            
            try Task.checkCancellation()
            let temporaryURL = fileURL.deletingLastPathComponent()
                .appendingPathComponent(".\(UUID().uuidString).html")
            defer {
                try? FileManager.default.removeItem(at: temporaryURL)
            }
            
            let count = try BookmarkHTMLWriter.write(nodes, to: temporaryURL)
            try Task.checkCancellation()
            
            guard rename(temporaryURL.path, fileURL.path) == 0 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            
            return count
        }
        
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

nonisolated private enum BookmarkHTMLWriter {
    static func write(_ nodes: [BookmarkDataStorage.Node], to fileURL: URL) throws -> Int {
        let writer = try UserDataFileWriter(fileURL: fileURL)
        
        try writer.append("""
            <!DOCTYPE NETSCAPE-Bookmark-file-1>
            <!-- This is an automatically generated file. -->
            <META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">
            <META HTTP-EQUIV="Content-Security-Policy" CONTENT="default-src 'none'">
            <TITLE>Bookmarks</TITLE>
            <H1>Bookmarks</H1>
            <DL><p>
            
            """.utf8)
        
        let children = Dictionary(grouping: nodes.filter { $0.parent != nil }, by: { $0.parent! })
        var pending = Array((children["root________"] ?? []).reversed())
        var visited: Set<String> = ["root________"]
        var folders = ["root________"]
        var bookmarkCount = 0
        while let node = pending.popLast() {
            try Task.checkCancellation()
            
            guard visited.insert(node.guid).inserted else {
                throw BookmarkDataError.invalidStoredData
            }
            
            while folders.last != node.parent {
                guard !folders.isEmpty else {
                    throw BookmarkDataError.invalidStoredData
                }
                
                folders.removeLast()
                try writer.append("</DL><p>\n".utf8)
            }
            
            guard let seconds = Int64(exactly: node.dateAdded.rounded(.down)) else {
                throw BookmarkDataError.invalidStoredData
            }
            
            let dateAttribute = " ADD_DATE=\"\(seconds)\""
            let title = escaped(node.title)
            if let urlString = node.url {
                guard !urlString.contains("\0"), let url = URL(string: urlString), url.scheme?.isEmpty == false else {
                    throw BookmarkDataError.invalidStoredData
                }
                
                try writer.append("<DT><A HREF=\"\(escaped(urlString))\"\(dateAttribute)>\(title)</A>\n".utf8)
                bookmarkCount += 1
            } else {
                let attributes = node.guid == "favorites___" ?
                " ID=\"BookmarksBar\" PERSONAL_TOOLBAR_FOLDER=\"true\"" : ""
                try writer.append("<DT><H3\(attributes)\(dateAttribute)>\(title)</H3>\n<DL><p>\n".utf8)
                folders.append(node.guid)
                for child in (children[node.guid] ?? []).reversed() {
                    pending.append(child)
                }
            }
        }
        
        guard visited.count == nodes.count else {
            throw BookmarkDataError.invalidStoredData
        }
        
        for _ in folders {
            try writer.append("</DL><p>\n".utf8)
        }
        
        try writer.finish()
        
        return bookmarkCount
    }
    
    private static func escaped(_ value: String) -> String {
        return value
            .replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
    }
}
