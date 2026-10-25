//
//  HistoryDataModels.swift
//  Reynard
//
//  Created by Minh Ton on 20/10/26.
//

import Foundation

nonisolated enum HistoryImportFormat: Sendable {
    case safari
    case chrome
}

nonisolated struct HistoryImportReport: Sendable {
    let format: HistoryImportFormat
    let importedRecordCount: Int
    let duplicateRecordCount: Int
    let invalidRecordCount: Int
    let recordsWithDiscardedDetails: Int
}

nonisolated enum HistoryDataError: LocalizedError {
    case invalidJSON
    case unrecognizedFormat
    case invalidMetadata
    case invalidDeduplicationTolerance
    case invalidStoredTimestamp
    case database(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidJSON:
            return NSLocalizedString("The history file contains invalid or incomplete JSON.", comment: "")
        case .unrecognizedFormat, .invalidMetadata:
            return NSLocalizedString("The file is not a valid Reynard, Safari, or Chrome Takeout history.", comment: "")
        case .invalidDeduplicationTolerance:
            return "The duplicate time tolerance must be zero or greater."
        case .invalidStoredTimestamp:
            return "A stored visit date cannot be exported as Unix microseconds."
        case .database(let message):
            return String.localizedStringWithFormat(
                NSLocalizedString("The history database operation failed: %@", comment: "Database error message"), message
            )
        }
    }
}

nonisolated struct HistoryImportRecord: Codable, Sendable {
    let url: URL
    let urlString: String
    var title: String
    let timeUsec: Int64
    var isRedirectSource = false
    var hasDiscardedDetails = false
    var visitDetails: HistoryVisitDetails?
    
    private enum ImportKeys: String, CodingKey {
        case url, title
        case timeUsec = "time_usec"
    }
    
    var timestamp: TimeInterval {
        return visitDetails?.timestamp ?? Double(timeUsec) / 1_000_000
    }
    
    var storedURL: String {
        return visitDetails == nil ? url.absoluteString : urlString
    }
    
    var visitedSecond: Int64 {
        let seconds = timeUsec / 1_000_000
        return timeUsec < 0 && timeUsec % 1_000_000 != 0 ? seconds - 1 : seconds
    }
    
    init(historyDecoder decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: ImportKeys.self)
        let text = try fields.decode(String.self, forKey: .url)
        let trimmedURL = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedURL.contains("\0"),
              let url = URL(string: trimmedURL),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host,
              !host.isEmpty else {
            throw DecodingError.dataCorruptedError(
                forKey: .url,
                in: fields,
                debugDescription: "Expected an HTTP(S) URL."
            )
        }
        
        let timeUsec = try fields.decode(HistoryInteger.self, forKey: .timeUsec).value
        let title = try? fields.decode(String.self, forKey: .title)
        self.url = url
        self.urlString = trimmedURL
        self.title = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        self.timeUsec = timeUsec
    }
}

nonisolated struct HistoryVisitDetails: Codable, Sendable {
    let timestamp: TimeInterval
    let isRedirectSource: Bool
    
    private enum CodingKeys: String, CodingKey {
        case version, timestamp
        case isRedirectSource = "is_redirect_source"
    }
    
    init(from decoder: Decoder) throws {
        let fields = try decoder.container(keyedBy: CodingKeys.self)
        guard try fields.decode(Int.self, forKey: .version) == 1 else {
            throw DecodingError.dataCorruptedError(
                forKey: .version,
                in: fields,
                debugDescription: "Unsupported visit details version."
            )
        }
        
        let text = try fields.decode(String.self, forKey: .timestamp)
        guard let timestamp = Double(text), timestamp.isFinite else {
            throw DecodingError.dataCorruptedError(
                forKey: .timestamp,
                in: fields,
                debugDescription: "Expected a finite visit date."
            )
        }
        
        self.timestamp = timestamp
        self.isRedirectSource = try fields.decode(Bool.self, forKey: .isRedirectSource)
    }
    
    func encode(to encoder: Encoder) throws {
        var fields = encoder.container(keyedBy: CodingKeys.self)
        try fields.encode(1, forKey: .version)
        try fields.encode(String(timestamp), forKey: .timestamp)
        try fields.encode(isRedirectSource, forKey: .isRedirectSource)
    }
}

nonisolated struct HistoryExportRecord {
    let url: String
    let title: String
    let timestamp: TimeInterval
    let isRedirectSource: Bool
}

nonisolated struct HistoryInteger: Decodable {
    let value: Int64
    
    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let text = try? container.decode(String.self) {
            guard let integer = Int64(text.trimmingCharacters(in: .whitespacesAndNewlines)) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "Expected an Int64.")
            }
            
            value = integer
        } else {
            value = try container.decode(Int64.self)
        }
    }
}
