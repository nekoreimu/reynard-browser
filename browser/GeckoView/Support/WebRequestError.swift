//
//  WebRequestError.swift
//  Reynard
//
//  Created by Minh Ton on 18/10/26.
//

import Foundation

public struct WebRequestError: Equatable {
    public enum Kind: String {
        case unknown
        case securitySSL
        case securityBadCertificate
        case netInterrupt
        case netTimeout
        case connectionRefused
        case localNetworkAccessDenied
        case unknownSocketType
        case redirectLoop
        case offline
        case portBlocked
        case netReset
        case unsafeContentType
        case corruptedContent
        case contentCrashed
        case invalidContentEncoding
        case unknownHost
        case noInternet
        case malformedURI
        case unknownProtocol
        case fileNotFound
        case fileAccessDenied
        case proxyConnectionRefused
        case unknownProxyHost
        case malware
        case unwanted
        case harmful
        case phishing
        case harmfulAddon
        case httpsOnly
        case badHSTSCertificate
    }
    
    public var kind: Kind
    public let uri: String?
    private let pageID: String
    
    public var pageURI: String {
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "errorPage", value: pageID),
            URLQueryItem(name: "kind", value: kind.rawValue),
            URLQueryItem(name: "uri", value: uri ?? ""),
        ]
        let query = components.percentEncodedQuery!.replacingOccurrences(of: "+", with: "%2B")
        return "data:text/html,#\(query)"
    }
    
    public init(kind: Kind, uri: String?) {
        self.kind = kind
        self.uri = uri
        pageID = UUID().uuidString
    }
    
    init(message: [String: Any?]?) {
        let code = UInt32(truncatingIfNeeded: PayloadValue.int(message?["error"] ?? nil) ?? 0)
        let errorClass = PayloadValue.int(message?["errorClass"] ?? nil) ?? 0
        let name = WebRequestErrorBridge.loadErrorName(forCode: code, errorClass: errorClass)
        self.init(kind: Kind(rawValue: name) ?? .unknown, uri: message?["uri"] as? String)
    }
    
    init?(pageURI: String) {
        guard pageURI.hasPrefix("data:text/html,#"),
              let fragment = URLComponents(string: pageURI)?.percentEncodedFragment,
              let items = URLComponents(string: "?\(fragment)")?.queryItems,
              let pageID = items.first(where: { $0.name == "errorPage" })?.value,
              let name = items.first(where: { $0.name == "kind" })?.value,
              let kind = Kind(rawValue: name) else {
            return nil
        }
        
        self.kind = kind
        uri = items.first(where: { $0.name == "uri" })?.value
        self.pageID = pageID
    }
}
