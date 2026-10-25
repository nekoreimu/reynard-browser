//
//  AddonCatalog.swift
//  Reynard
//
//  Created by Minh Ton on 20/10/26.
//

import Foundation

nonisolated enum AddonCatalog {
    static func resolve(id: String, engineVersion: String) async throws -> URL {
        var components = URLComponents()
        components.scheme = "https"
        components.host = "addons.mozilla.org"
        components.path = "/api/v5/addons/addon/\(id)/"
        guard let url = components.url else {
            throw AddonDataError.invalidFile
        }
        
        let detail: Detail
        do {
            detail = try await fetch(Detail.self, from: url)
        } catch AddonDataError.catalogHTTP(404) {
            try Task.checkCancellation()
            throw AddonDataError.catalog("The add-on is no longer available from Mozilla.")
        }
        
        guard detail.guid == id, detail.type == "extension", !detail.isDisabled else {
            throw AddonDataError.catalog("Mozilla returned invalid add-on information.")
        }
        
        if let version = detail.currentVersion, version.supports(engineVersion) {
            return try downloadURL(for: version)
        }
        
        let versionsURL = url.appendingPathComponent("versions/")
        var pageURL: URL? = versionsURL
        var visited = Set<URL>()
        var selected: Version?
        while let currentURL = pageURL {
            try Task.checkCancellation()
            guard currentURL.scheme == "https",
                  currentURL.host == url.host,
                  currentURL.path == versionsURL.path,
                  visited.insert(currentURL).inserted else {
                throw AddonDataError.catalog("Mozilla returned invalid add-on information.")
            }
            
            let page = try await fetch(Page.self, from: currentURL)
            for version in page.results where version.supports(engineVersion) {
                if let selected, AddonVersionOrder.compare(version.version, selected.version) <= 0 {
                    continue
                }
                
                selected = version
            }
            
            pageURL = page.next
        }
        
        guard let selected else {
            throw AddonDataError.catalog("No public Firefox Mobile version of the add-on supports the current engine.")
        }
        
        return try downloadURL(for: selected)
    }
    
    private static func downloadURL(for version: Version) throws -> URL {
        let location = version.file.url
        guard !location.contains("\0"),
              let url = URL(string: location),
              url.scheme?.lowercased() == "https",
              url.host?.isEmpty == false,
              url.user == nil, url.password == nil else {
            throw AddonDataError.catalog("Mozilla returned invalid add-on information.")
        }
        
        return url
    }
    
    private static func fetch<Value: Decodable & Sendable>(
        _ type: Value.Type, from url: URL
    ) async throws -> Value {
        let request = AddonCatalogRequest()
        let data: Data = try await withTaskCancellationHandler {
            try Task.checkCancellation()
            return try await withCheckedThrowingContinuation { continuation in
                let task = URLSession.shared.dataTask(with: url) { data, response, error in
                    if let error {
                        continuation.resume(throwing: error)
                    } else if let response = response as? HTTPURLResponse, response.statusCode != 200 {
                        continuation.resume(throwing: AddonDataError.catalogHTTP(response.statusCode))
                    } else if let data, response is HTTPURLResponse {
                        continuation.resume(returning: data)
                    } else {
                        continuation.resume(throwing: URLError(.badServerResponse))
                    }
                }
                request.start(task)
            }
        } onCancel: {
            request.cancel()
        }
        
        try Task.checkCancellation()
        return try JSONDecoder().decode(type, from: data)
    }
    
    private struct Detail: Decodable, Sendable {
        let guid: String
        let type: String
        let isDisabled: Bool
        let currentVersion: Version?
        
        enum CodingKeys: String, CodingKey {
            case guid, type
            case isDisabled = "is_disabled"
            case currentVersion = "current_version"
        }
    }
    
    private struct Page: Decodable, Sendable {
        let next: URL?
        let results: [Version]
    }
    
    private struct Version: Decodable, Sendable {
        struct Bounds: Decodable, Sendable {
            let min: String
            let max: String
        }
        
        struct File: Decodable, Sendable {
            let status: String
            let url: String
        }
        
        let version: String
        let compatibility: [String: Bounds]
        let isStrictCompatibilityEnabled: Bool
        let file: File
        
        enum CodingKeys: String, CodingKey {
            case version, compatibility, file
            case isStrictCompatibilityEnabled = "is_strict_compatibility_enabled"
        }
        
        func supports(_ engineVersion: String) -> Bool {
            guard file.status == "public",
                  compatibility["android"] != nil else {
                return false
            }
            
            for bounds in [compatibility["android"], compatibility["firefox"]].compactMap({ $0 }) {
                if AddonVersionOrder.compare(engineVersion, bounds.min) < 0 {
                    return false
                }
                
                if isStrictCompatibilityEnabled,
                   AddonVersionOrder.compare(engineVersion, bounds.max) > 0 {
                    return false
                }
            }
            
            return true
        }
    }
}

nonisolated private final class AddonCatalogRequest: @unchecked Sendable {
    private let lock = NSLock()
    private var task: URLSessionDataTask?
    private var isCancelled = false
    
    func start(_ task: URLSessionDataTask) {
        lock.lock()
        self.task = task
        let cancelled = isCancelled
        lock.unlock()
        
        if cancelled {
            task.cancel()
        }
        task.resume()
    }
    
    func cancel() {
        lock.lock()
        isCancelled = true
        let task = task
        lock.unlock()
        
        task?.cancel()
    }
}
