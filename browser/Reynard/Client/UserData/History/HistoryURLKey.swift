//
//  HistoryURLKey.swift
//  Reynard
//
//  Created by Minh Ton on 20/10/26.
//

import Foundation

nonisolated struct HistoryURLKey: Hashable {
    private let scheme: String
    private let host: String
    private let port: Int?
    private let user: String?
    private let password: String?
    private let path: String
    private let query: String?
    
    init(url: URL) {
        let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        scheme = url.scheme?.lowercased() ?? ""
        host = url.host?.lowercased() ?? ""
        user = components?.percentEncodedUser
        password = components?.percentEncodedPassword
        query = components?.percentEncodedQuery
        
        switch (scheme, url.port) {
        case ("http", 80), ("https", 443):
            port = nil
        default:
            port = url.port
        }
        
        let originalPath = components?.percentEncodedPath ?? url.path
        if originalPath.isEmpty || originalPath == "/" {
            path = "/"
        } else {
            path = originalPath.hasSuffix("/") ? String(originalPath.dropLast()) : originalPath
        }
    }
}
