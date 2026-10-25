//
//  HistoryImporter+Chrome.swift
//  Reynard
//
//  Created by Minh Ton on 20/10/26.
//

import Foundation

enum ChromeHistoryImporter {
    static func importHistory(
        from fileURL: URL,
        nearDuplicateToleranceSeconds: Int = 1
    ) async throws -> HistoryImportReport {
        return try await HistoryImporter.importHistory(
            from: fileURL,
            format: .chrome,
            nearDuplicateToleranceSeconds: nearDuplicateToleranceSeconds,
            decodeRecord: { decoder, data in
                try decoder.decode(ChromeHistoryRecord.self, from: data).visit
            }
        )
    }
}

nonisolated private struct ChromeHistoryRecord: Decodable {
    let visit: HistoryImportRecord
    
    init(from decoder: Decoder) throws {
        visit = try HistoryImportRecord(historyDecoder: decoder)
    }
}
