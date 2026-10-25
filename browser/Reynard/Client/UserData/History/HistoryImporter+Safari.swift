//
//  HistoryImporter+Safari.swift
//  Reynard
//
//  Created by Minh Ton on 20/10/26.
//

import Foundation

enum SafariHistoryImporter {
    static func importHistory(
        from fileURL: URL,
        nearDuplicateToleranceSeconds: Int = 1
    ) async throws -> HistoryImportReport {
        return try await HistoryImporter.importHistory(
            from: fileURL,
            format: .safari,
            nearDuplicateToleranceSeconds: nearDuplicateToleranceSeconds,
            decodeRecord: { decoder, data in
                try decoder.decode(SafariHistoryRecord.self, from: data).visit
            }
        )
    }
}

nonisolated private struct SafariHistoryRecord: Decodable {
    let visit: HistoryImportRecord
    
    private enum CodingKeys: String, CodingKey {
        case title
        case visitDetails = "visit_details"
        case count = "visit_count"
        case alternateCount = "visits_count"
        case sourceURL = "source_url"
        case sourceTime = "source_time_usec"
        case destinationURL = "destination_url"
        case destinationTime = "destination_time_usec"
        case wasHTTPGet = "latest_visit_was_http_get"
        case wasLoadFailure = "latest_visit_was_load_failure"
    }
    
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        var record = try HistoryImportRecord(historyDecoder: decoder)
        
        if fields.contains(.visitDetails) {
            let details = try fields.decode(HistoryVisitDetails.self, forKey: .visitDetails)
            guard Int64(exactly: (details.timestamp * 1_000_000).rounded()) == record.timeUsec,
                  try fields.decode(HistoryInteger.self, forKey: .count).value == 1 else {
                throw DecodingError.dataCorruptedError(
                    forKey: .visitDetails,
                    in: fields,
                    debugDescription: "The visit details do not match the history entry."
                )
            }
            
            record.visitDetails = details
            record.isRedirectSource = details.isRedirectSource
            record.title = try fields.decode(String.self, forKey: .title)
            visit = record
            return
        }
        
        let count = (try? fields.decode(HistoryInteger.self, forKey: .count).value)
        ?? (try? fields.decode(HistoryInteger.self, forKey: .alternateCount).value)
        ?? 1
        let destination = (try? fields.decode(String.self, forKey: .destinationURL))?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let destinationURL = URL(string: destination)
        record.isRedirectSource = destinationURL?.scheme != nil && destinationURL?.host != nil
        
        let optionalDetails: [CodingKeys] = [
            .sourceURL, .sourceTime, .destinationURL, .destinationTime, .wasHTTPGet, .wasLoadFailure
        ]
        record.hasDiscardedDetails = count > 1 || optionalDetails.contains {
            fields.contains($0) && (try? fields.decodeNil(forKey: $0)) == false
        }
        
        visit = record
    }
}
