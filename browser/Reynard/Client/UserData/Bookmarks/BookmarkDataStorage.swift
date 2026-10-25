//
//  BookmarkDataStorage.swift
//  Reynard
//
//  Created by Minh Ton on 20/10/26.
//

import Foundation
import SQLite3

nonisolated final class BookmarkDataStorage {
    struct Node: Sendable {
        let guid: String
        let parent: String?
        let title: String
        let url: String?
        let dateAdded: Double
        let position: Int64
    }
    
    private struct Match: Hashable {
        let parent: String
        let title: String
        let url: String?
    }
    
    private let database: OpaquePointer
    private var statements: [String: OpaquePointer] = [:]
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    init(database: OpaquePointer) {
        self.database = database
    }
    
    deinit {
        for statement in statements.values {
            sqlite3_finalize(statement)
        }
    }
    
    func importDocument(
        _ document: BookmarkHTMLDocument, cancellation: UserDataCancellation
    ) throws -> BookmarkImportReport {
        try cancellation.checkCancellation()
        if document.items.isEmpty {
            return document.report
        }
        
        try execute("BEGIN IMMEDIATE;")
        var committed = false
        defer {
            if !committed {
                for statement in statements.values {
                    sqlite3_reset(statement)
                }
                try? execute("ROLLBACK;")
            }
        }
        
        let nodes = try readNodes(cancellation: cancellation)
        var matches: [Match: String] = [:]
        var nextIndices: [String: Int64] = [:]
        var folderTitles: [String: String] = [:]
        for node in nodes {
            if node.url == nil {
                folderTitles[node.guid] = node.title
            }
            
            guard let parent = node.parent else {
                continue
            }
            
            guard node.position < Int64.max else {
                throw BookmarkDataError.invalidStoredData
            }
            
            let nextIndex = node.position + 1
            nextIndices[parent] = max(nextIndices[parent] ?? nextIndex, nextIndex)
            
            if node.guid != "favorites___" {
                let match = Match(parent: parent, title: node.title, url: node.url)
                if matches[match] == nil {
                    matches[match] = node.guid
                }
            }
        }
        
        var resolvedGUIDs: [String] = []
        resolvedGUIDs.reserveCapacity(document.items.count)
        var report = document.report
        let now = Date().timeIntervalSince1970
        for item in document.items {
            try cancellation.checkCancellation()
            let parent = item.parent.map { resolvedGUIDs[$0] } ?? "root________"
            let match = Match(parent: parent, title: item.title, url: item.url)
            let existing: String?
            
            switch item.specialFolder {
            case .bookmarks:
                existing = "root________"
            case .favorites:
                existing = folderTitles["favorites___"] != nil ? "favorites___" : nil
            case nil:
                existing = matches[match]
            }
            
            if let existing {
                resolvedGUIDs.append(existing)
                if item.url == nil {
                    report.mergedFolderCount += 1
                } else {
                    report.duplicateBookmarkCount += 1
                }
                
                continue
            }
            
            let guid = item.specialFolder == .favorites ? "favorites___" : UUID().uuidString.lowercased()
            let date = item.dateAdded ?? now
            let insert = try statement(
                """
                INSERT INTO bookmarks (guid, type, date_added, parentid, parentName, title, url, host, stripped_url)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?);
                """
            )
            try bind(guid, to: insert, at: 1)
            sqlite3_bind_int64(insert, 2, item.url == nil ? 2 : 1)
            sqlite3_bind_double(insert, 3, date)
            try bind(parent, to: insert, at: 4)
            try bind(folderTitles[parent] ?? "", to: insert, at: 5)
            try bind(item.title, to: insert, at: 6)
            try bind(item.url, to: insert, at: 7)
            try bind(item.url.flatMap(URL.init(string:))?.host?.lowercased() ?? "", to: insert, at: 8)
            
            try bind(URLUtils.normalizedURLStringForMatching(from: item.url ?? ""), to: insert, at: 9)
            try finish(insert)
            
            let index = nextIndices[parent] ?? 0
            guard index < Int64.max else {
                throw BookmarkDataError.invalidStoredData
            }
            
            let placement = try statement("INSERT INTO bookmark_structure (parent, child, idx) VALUES (?, ?, ?);")
            try bind(parent, to: placement, at: 1)
            try bind(guid, to: placement, at: 2)
            sqlite3_bind_int64(placement, 3, index)
            try finish(placement)
            
            nextIndices[parent] = index + 1
            if item.specialFolder == nil {
                matches[match] = guid
            }
            
            resolvedGUIDs.append(guid)
            
            if item.url == nil {
                folderTitles[guid] = item.title
                report.importedFolderCount += 1
            } else {
                report.importedBookmarkCount += 1
            }
        }
        
        try cancellation.checkCancellation()
        try execute("COMMIT;")
        committed = true
        
        return report
    }
    
    func readNodes(cancellation: UserDataCancellation) throws -> [Node] {
        let query = try statement(
            """
            SELECT b.guid, b.parentid, b.title, b.url, b.date_added, b.type, s.parent, s.idx
            FROM bookmarks b LEFT JOIN bookmark_structure s ON s.child = b.guid
            ORDER BY s.idx, b.id;
            """
        )
        defer {
            sqlite3_reset(query)
        }
        
        var nodes: [Node] = []
        while try step(query) == SQLITE_ROW {
            try cancellation.checkCancellation()
            let type = sqlite3_column_int64(query, 5)
            let isFolder = type == 2
            let isRoot = text(query, 0) == "root________"
            let parent = sqlite3_column_type(query, 1) == SQLITE_NULL ? nil : text(query, 1)
            let hasMatchingParent = isRoot || (parent != nil && parent == text(query, 6))
            
            guard type == 1 || isFolder,
                  hasMatchingParent,
                  isFolder || sqlite3_column_type(query, 3) != SQLITE_NULL else {
                throw BookmarkDataError.invalidStoredData
            }
            
            nodes.append(Node(
                guid: text(query, 0),
                parent: parent,
                title: text(query, 2),
                url: isFolder ? nil : text(query, 3),
                dateAdded: sqlite3_column_double(query, 4),
                position: sqlite3_column_int64(query, 7)
            ))
        }
        
        guard nodes.contains(where: {
            $0.guid == "root________" && $0.parent == nil && $0.url == nil
        }) else {
            throw BookmarkDataError.invalidStoredData
        }
        
        return nodes
    }
    
    private func statement(_ sql: String) throws -> OpaquePointer {
        if let statement = statements[sql] {
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
            return statement
        }
        
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, sql, -1, &statement, nil) == SQLITE_OK, let statement else {
            if let statement {
                sqlite3_finalize(statement)
            }
            
            throw failure()
        }
        
        statements[sql] = statement
        return statement
    }
    
    private func bind(_ value: String?, to statement: OpaquePointer, at index: Int32) throws {
        let result: Int32
        if let value {
            guard let length = Int32(exactly: value.utf8.count) else {
                throw BookmarkDataError.database("Text exceeds SQLite's supported length.")
            }
            
            result = value.withCString {
                sqlite3_bind_text(statement, index, $0, length, transient)
            }
        } else {
            result = sqlite3_bind_null(statement, index)
        }
        
        guard result == SQLITE_OK else {
            throw failure()
        }
    }
    
    private func step(_ statement: OpaquePointer) throws -> Int32 {
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW || result == SQLITE_DONE else {
            throw failure()
        }
        
        return result
    }
    
    private func finish(_ statement: OpaquePointer) throws {
        defer {
            sqlite3_reset(statement)
        }
        
        guard try step(statement) == SQLITE_DONE else {
            throw failure()
        }
    }
    
    private func execute(_ sql: String) throws {
        try finish(statement(sql))
    }
    
    private func text(_ statement: OpaquePointer, _ column: Int32) -> String {
        guard let value = sqlite3_column_text(statement, column) else {
            return ""
        }
        
        let bytes = UnsafeBufferPointer(start: value, count: Int(sqlite3_column_bytes(statement, column)))
        return String(decoding: bytes, as: UTF8.self)
    }
    
    private func failure() -> BookmarkDataError {
        return .database(String(cString: sqlite3_errmsg(database)))
    }
}
