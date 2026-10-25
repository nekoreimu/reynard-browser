//
//  HistoryDataStorage.swift
//  Reynard
//
//  Created by Minh Ton on 20/10/26.
//

import Foundation
import SQLite3

nonisolated final class HistoryDataStorage {
    private enum Value {
        case text(String)
        case integer(Int64)
        case real(Double)
    }
    
    private let database: OpaquePointer
    private let cancellation: UserDataCancellation
    private var statements: [String: OpaquePointer] = [:]
    private var siteIDsByDuplicateKey: [HistoryURLKey: [Int64]]?
    private var changedSiteIDs = Set<Int64>()
    private let transient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
    
    static func databaseURL() throws -> URL {
        let directory = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        )
        
        return directory.appendingPathComponent("AppData/History/History", isDirectory: false)
    }
    
    init(databaseURL: URL, cancellation: UserDataCancellation) throws {
        self.cancellation = cancellation
        var connection: OpaquePointer?
        let result = sqlite3_open_v2(
            databaseURL.path,
            &connection,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_FULLMUTEX,
            nil
        )
        guard result == SQLITE_OK, let connection else {
            let message = connection.map { String(cString: sqlite3_errmsg($0)) }
            ?? NSLocalizedString("Unable to open database.", comment: "")
            if let connection {
                sqlite3_close(connection)
            }
            
            throw HistoryDataError.database(message)
        }
        
        database = connection
        sqlite3_busy_timeout(database, 2_500)
        sqlite3_progress_handler(database, 1_000, { context in
            guard let context else {
                return 0
            }
            
            let cancellation = Unmanaged<UserDataCancellation>.fromOpaque(context).takeUnretainedValue()
            return cancellation.isCancelled ? 1 : 0
        }, Unmanaged.passUnretained(cancellation).toOpaque())
        try execute("PRAGMA foreign_keys = ON;")
    }
    
    deinit {
        sqlite3_progress_handler(database, 0, nil, nil)
        for statement in statements.values {
            sqlite3_finalize(statement)
        }
        
        sqlite3_close(database)
    }
    
    func beginImport() throws {
        try execute("BEGIN IMMEDIATE TRANSACTION;")
    }
    
    func insert(_ record: HistoryImportRecord, toleranceSeconds: Int) throws -> Bool {
        let isNative = record.visitDetails != nil
        var existingSiteID: Int64?
        
        if isNative {
            let match = try statement(
                """
                SELECT id, EXISTS (
                    SELECT 1 FROM visits WHERE siteID = history.id AND date = ?
                )
                FROM history WHERE url = ?;
                """,
                values: [.real(record.timestamp), .text(record.storedURL)]
            )
            defer {
                sqlite3_reset(match)
            }
            
            if try step(match) == SQLITE_ROW {
                if sqlite3_column_int(match, 1) != 0 {
                    return false
                }
                
                existingSiteID = sqlite3_column_int64(match, 0)
            }
        } else {
            if siteIDsByDuplicateKey == nil {
                var siteIDs: [HistoryURLKey: [Int64]] = [:]
                let sites = try statement("SELECT id, url FROM history;")
                defer {
                    sqlite3_reset(sites)
                }
                
                while try step(sites) == SQLITE_ROW {
                    try cancellation.checkCancellation()
                    guard let url = URL(string: text(sites, column: 1)) else {
                        continue
                    }
                    
                    siteIDs[HistoryURLKey(url: url), default: []]
                        .append(sqlite3_column_int64(sites, 0))
                }
                
                siteIDsByDuplicateKey = siteIDs
            }
            
            let key = HistoryURLKey(url: record.url)
            let second = Double(record.visitedSecond)
            let tolerance = Double(toleranceSeconds)
            for siteID in siteIDsByDuplicateKey?[key] ?? [] {
                let match = try statement(
                    """
                    SELECT 1 FROM visits
                    WHERE siteID = ? AND (date = ? OR (date >= ? AND date < ?))
                    LIMIT 1;
                    """,
                    values: [
                        .integer(siteID), .real(record.timestamp),
                        .real(second - tolerance), .real(second + tolerance + 1)
                    ]
                )
                defer {
                    sqlite3_reset(match)
                }
                
                if try step(match) == SQLITE_ROW {
                    return false
                }
            }
        }
        
        let url = record.storedURL
        let title = !isNative && record.title.isEmpty ? record.url.host ?? url : record.title
        try execute(
            """
            INSERT INTO history (url, host, stripped_url, title, created_at, updated_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(url) DO UPDATE SET
                title = CASE
                    WHEN excluded.updated_at >= history.updated_at AND ? THEN excluded.title
                    ELSE history.title
                END,
                created_at = MIN(history.created_at, excluded.created_at),
                updated_at = MAX(history.updated_at, excluded.updated_at);
            """,
            values: [
                .text(url), .text(record.url.host?.lowercased() ?? ""),
                .text(URLUtils.normalizedURLStringForMatching(from: record.url.absoluteString)),
                .text(title), .real(record.timestamp), .real(record.timestamp),
                .integer(isNative || !record.title.isEmpty ? 1 : 0)
            ]
        )
        
        let siteID: Int64
        if isNative {
            siteID = existingSiteID ?? sqlite3_last_insert_rowid(database)
        } else {
            let site = try statement("SELECT id FROM history WHERE url = ?;", values: [.text(url)])
            defer {
                sqlite3_reset(site)
            }
            
            guard try step(site) == SQLITE_ROW else {
                throw failure()
            }
            
            siteID = sqlite3_column_int64(site, 0)
        }
        
        try execute(
            "INSERT INTO visits (siteID, date, is_redirect_source) VALUES (?, ?, ?);",
            values: [.integer(siteID), .real(record.timestamp), .integer(record.isRedirectSource ? 1 : 0)]
        )
        
        if siteIDsByDuplicateKey != nil {
            let key = HistoryURLKey(url: record.url)
            if !(siteIDsByDuplicateKey?[key] ?? []).contains(siteID) {
                siteIDsByDuplicateKey?[key, default: []].append(siteID)
            }
        }
        changedSiteIDs.insert(siteID)
        
        return true
    }
    
    func finishImport() throws {
        let now = Date().timeIntervalSince1970
        for siteID in changedSiteIDs {
            try cancellation.checkCancellation()
            let stats = try statement(
                """
                SELECT COUNT(*), COALESCE(SUM(
                    CASE
                        WHEN date > ? THEN 100
                        WHEN date > ? THEN 70
                        WHEN date > ? THEN 50
                        WHEN date > ? THEN 30
                        ELSE 10
                    END / CASE WHEN is_redirect_source != 0 THEN 4 ELSE 1 END
                ), 0)
                FROM visits WHERE siteID = ?;
                """,
                values: [
                    .real(now - 86_400), .real(now - 7 * 86_400),
                    .real(now - 30 * 86_400), .real(now - 90 * 86_400), .integer(siteID)
                ]
            )
            guard try step(stats) == SQLITE_ROW else {
                throw failure()
            }
            
            let count = sqlite3_column_int64(stats, 0)
            let frecency = sqlite3_column_int64(stats, 1)
            sqlite3_reset(stats)
            try execute(
                "UPDATE history SET visit_count = ?, frecency = ? WHERE id = ?;",
                values: [.integer(count), .integer(frecency), .integer(siteID)]
            )
        }
        
        try cancellation.checkCancellation()
        try execute("COMMIT TRANSACTION;")
    }
    
    func rollbackImport() {
        sqlite3_progress_handler(database, 0, nil, nil)
        for statement in statements.values {
            sqlite3_reset(statement)
        }
        
        guard sqlite3_get_autocommit(database) == 0 else {
            return
        }
        
        try? execute("ROLLBACK TRANSACTION;")
    }
    
    func enumerateVisits(_ onRecord: (HistoryExportRecord) throws -> Void) throws {
        let statement = try statement(
            """
            SELECT history.url, history.title, visits.date, visits.is_redirect_source
            FROM visits JOIN history ON history.id = visits.siteID
            ORDER BY visits.date, visits.id;
            """
        )
        defer {
            sqlite3_reset(statement)
        }
        
        while try step(statement) == SQLITE_ROW {
            try cancellation.checkCancellation()
            try autoreleasepool {
                try onRecord(HistoryExportRecord(
                    url: text(statement, column: 0),
                    title: text(statement, column: 1),
                    timestamp: sqlite3_column_double(statement, 2),
                    isRedirectSource: sqlite3_column_int(statement, 3) != 0
                ))
            }
        }
    }
    
    private func statement(_ sql: String, values: [Value] = []) throws -> OpaquePointer {
        let statement: OpaquePointer
        if let cached = statements[sql] {
            statement = cached
            sqlite3_reset(statement)
            sqlite3_clear_bindings(statement)
        } else {
            var prepared: OpaquePointer?
            guard sqlite3_prepare_v2(database, sql, -1, &prepared, nil) == SQLITE_OK,
                  let prepared else {
                if let prepared {
                    sqlite3_finalize(prepared)
                }
                
                try cancellation.checkCancellation()
                throw failure()
            }
            
            statements[sql] = prepared
            statement = prepared
        }
        
        for (offset, value) in values.enumerated() {
            let index = Int32(offset + 1)
            let result: Int32
            switch value {
            case .text(let text):
                guard let length = Int32(exactly: text.utf8.count) else {
                    throw HistoryDataError.database("Text exceeds SQLite's supported length.")
                }
                
                result = text.withCString {
                    sqlite3_bind_text(statement, index, $0, length, transient)
                }
            case .integer(let integer):
                result = sqlite3_bind_int64(statement, index, integer)
            case .real(let real):
                result = sqlite3_bind_double(statement, index, real)
            }
            
            guard result == SQLITE_OK else {
                throw failure()
            }
        }
        
        return statement
    }
    
    private func step(_ statement: OpaquePointer) throws -> Int32 {
        let result = sqlite3_step(statement)
        guard result == SQLITE_ROW || result == SQLITE_DONE else {
            try cancellation.checkCancellation()
            throw failure()
        }
        
        return result
    }
    
    private func execute(_ sql: String, values: [Value] = []) throws {
        let prepared = try statement(sql, values: values)
        defer {
            sqlite3_reset(prepared)
        }
        
        guard try step(prepared) == SQLITE_DONE else {
            throw failure()
        }
    }
    
    private func failure() -> HistoryDataError {
        return .database(String(cString: sqlite3_errmsg(database)))
    }
    
    private func text(_ statement: OpaquePointer, column: Int32) -> String {
        guard let bytes = sqlite3_column_text(statement, column) else {
            return ""
        }
        
        let count = Int(sqlite3_column_bytes(statement, column))
        return String(decoding: UnsafeBufferPointer(start: bytes, count: count), as: UTF8.self)
    }
    
}
