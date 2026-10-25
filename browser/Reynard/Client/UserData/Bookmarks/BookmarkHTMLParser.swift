//
//  BookmarkHTMLParser.swift
//  Reynard
//
//  Created by Minh Ton on 20/10/26.
//

import Foundation
import libxml2

nonisolated enum BookmarkHTMLParser {
    private struct Container {
        let parent: Int?
        let isReadingList: Bool
    }
    
    static func parse(fileURL: URL, requiresExportMetadata: Bool = false) throws -> BookmarkHTMLDocument {
        let data = try Data(contentsOf: fileURL, options: .mappedIfSafe)
        guard !data.isEmpty else {
            throw BookmarkDataError.unrecognizedFormat
        }
        
        guard let length = Int32(exactly: data.count) else {
            throw BookmarkDataError.fileTooLarge
        }
        
        guard let context = htmlNewParserCtxt() else {
            throw BookmarkDataError.invalidHTML
        }
        defer {
            htmlFreeParserCtxt(context)
        }
        
        let options = HTML_PARSE_RECOVER.rawValue | HTML_PARSE_NONET.rawValue |
        HTML_PARSE_NOERROR.rawValue | HTML_PARSE_NOWARNING.rawValue
        let document = data.withUnsafeBytes { bytes in
            htmlCtxtReadMemory(
                context, bytes.baseAddress?.assumingMemoryBound(to: CChar.self),
                length, nil, nil, Int32(options)
            )
        }
        
        guard let document else {
            throw BookmarkDataError.unrecognizedFormat
        }
        defer {
            xmlFreeDoc(document)
        }
        
        let hasExportDeclaration = document.pointee.intSubset.map {
            String(cString: $0.pointee.name).lowercased() == "netscape-bookmark-file-1"
        } ?? false
        guard context.pointee.lastError.level != XML_ERR_FATAL,
              let input = context.pointee.input,
              input.pointee.cur == input.pointee.end else {
            if requiresExportMetadata, !hasExportDeclaration {
                throw BookmarkDataError.unrecognizedFormat
            }
            
            throw BookmarkDataError.invalidHTML
        }
        
        var result = BookmarkHTMLDocument()
        var current = Container(parent: nil, isReadingList: false)
        var pending: Container?
        var containers: [Container] = []
        var hasBookmarkStructure = hasExportDeclaration
        var node = xmlDocGetRootElement(document)
        
        while let element = node {
            try Task.checkCancellation()
            let name = String(cString: element.pointee.name).lowercased()
            
            if element.pointee.type == XML_ELEMENT_NODE {
                if ["dl", "ul", "menu"].contains(name) {
                    hasBookmarkStructure = true
                    containers.append(current)
                    if let pending {
                        current = pending
                    }
                    pending = nil
                } else if ["h2", "h3", "h4", "h5", "h6"].contains(name) {
                    let title = content(element).trimmingCharacters(in: .whitespacesAndNewlines)
                    let identifier = attribute("id", of: element)
                    let isReadingList = current.isReadingList || identifier == "com.apple.ReadingList"
                    if isReadingList {
                        pending = Container(parent: current.parent, isReadingList: true)
                    } else {
                        let isAtRoot = current.parent.map {
                            result.items[$0].specialFolder == .bookmarks
                        } ?? true
                        let specialFolder = isAtRoot ? protectedFolder(for: element) : nil
                        let index = result.items.count
                        result.items.append(BookmarkHTMLItem(
                            parent: current.parent,
                            title: title,
                            url: nil,
                            dateAdded: dateAdded(element),
                            specialFolder: specialFolder
                        ))
                        pending = Container(parent: index, isReadingList: false)
                    }
                } else if name == "a" {
                    pending = nil
                    let href = attribute("href", of: element)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    
                    if !href.contains("\0"), let url = URL(string: href), url.scheme?.isEmpty == false {
                        let title = content(element).trimmingCharacters(in: .whitespacesAndNewlines)
                        let date = dateAdded(element)
                        
                        if current.isReadingList {
                            result.report.readingList.append(BookmarkReadingListEntry(
                                title: title,
                                url: url,
                                dateAdded: date.map(Date.init(timeIntervalSince1970:))
                            ))
                        } else {
                            result.items.append(BookmarkHTMLItem(
                                parent: current.parent,
                                title: title,
                                url: url.absoluteString,
                                dateAdded: date,
                                specialFolder: nil
                            ))
                        }
                    } else {
                        result.report.invalidBookmarkCount += 1
                    }
                }
            }
            
            let shouldSkipChildren = ["a", "h1", "h2", "h3", "h4", "h5", "h6", "script", "style"].contains(name)
            if !shouldSkipChildren, let child = element.pointee.children {
                node = child
                continue
            }
            
            var finishedNode = element
            while true {
                let finishedName = String(cString: finishedNode.pointee.name).lowercased()
                if finishedNode.pointee.type == XML_ELEMENT_NODE,
                   ["dl", "ul", "menu"].contains(finishedName) {
                    current = containers.removeLast()
                    pending = nil
                }
                
                if let next = finishedNode.pointee.next {
                    node = next
                    break
                }
                
                guard let parent = finishedNode.pointee.parent, parent.pointee.type != XML_DOCUMENT_NODE,
                      parent.pointee.type != XML_HTML_DOCUMENT_NODE else {
                    node = nil
                    break
                }
                
                finishedNode = parent
            }
        }
        
        guard hasBookmarkStructure else {
            throw BookmarkDataError.unrecognizedFormat
        }
        
        if requiresExportMetadata, !hasExportDeclaration {
            let hasExportMetadata = result.items.contains { $0.specialFolder != nil || $0.dateAdded != nil } ||
            !result.report.readingList.isEmpty
            guard hasExportMetadata else {
                throw BookmarkDataError.unrecognizedFormat
            }
        }
        
        return result
    }
    
    private static func protectedFolder(for node: xmlNodePtr) -> BookmarkHTMLSpecialFolder? {
        let identifier = attribute("id", of: node)
        if identifier == "BookmarksBar" || attribute("personal_toolbar_folder", of: node) != nil {
            return .favorites
        }
        
        let isBookmarksRoot = identifier == "BookmarksMenu" ||
        attribute("bookmarks_menu", of: node) != nil ||
        attribute("unfiled_bookmarks_folder", of: node) != nil ||
        attribute("places_root", of: node) != nil
        
        return isBookmarksRoot ? .bookmarks : nil
    }
    
    private static func content(_ node: xmlNodePtr) -> String {
        guard let value = xmlNodeGetContent(node) else {
            return ""
        }
        defer {
            xmlFree(value)
        }
        
        return String(cString: value)
    }
    
    private static func attribute(_ name: String, of node: xmlNodePtr) -> String? {
        let value = name.withCString { name in
            xmlGetProp(node, UnsafeRawPointer(name).assumingMemoryBound(to: xmlChar.self))
        }
        
        guard let value else {
            return nil
        }
        defer {
            xmlFree(value)
        }
        
        return String(cString: value)
    }
    
    private static func dateAdded(_ node: xmlNodePtr) -> Double? {
        for name in ["add_date", "last_modified"] {
            if let value = attribute(name, of: node),
               let seconds = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)),
               Int64(exactly: seconds.rounded(.down)) != nil {
                return seconds
            }
        }
        
        return nil
    }
}
