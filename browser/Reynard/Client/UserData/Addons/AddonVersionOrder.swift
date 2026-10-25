//
//  AddonVersionOrder.swift
//  Reynard
//
//  Created by Minh Ton on 20/10/26.
//

import Darwin
import Foundation

nonisolated enum AddonVersionOrder {
    static func compare(_ lhs: String, _ rhs: String) -> Int {
        let left = lhs.components(separatedBy: ".")
        let right = rhs.components(separatedBy: ".")
        for index in 0..<max(left.count, right.count) {
            let leftPart = Part(index < left.count ? left[index] : "")
            let rightPart = Part(index < right.count ? right[index] : "")
            if leftPart.number != rightPart.number {
                return leftPart.number < rightPart.number ? -1 : 1
            }
            
            let suffixOrder = compareSuffix(leftPart.suffix, rightPart.suffix)
            if suffixOrder != 0 {
                return suffixOrder
            }
            
            if leftPart.suffixNumber != rightPart.suffixNumber {
                return leftPart.suffixNumber < rightPart.suffixNumber ? -1 : 1
            }
            
            let tailOrder = compareSuffix(leftPart.tail, rightPart.tail)
            if tailOrder != 0 {
                return tailOrder
            }
        }
        
        return 0
    }
    
    private static func compareSuffix(_ lhs: String?, _ rhs: String?) -> Int {
        if lhs == rhs {
            return 0
        }
        
        guard let lhs, let rhs else {
            return lhs == nil ? 1 : -1
        }
        
        return lhs.utf8.lexicographicallyPrecedes(rhs.utf8) ? -1 : 1
    }
    
    private struct Part {
        var number: Int32
        var suffix: String?
        var suffixNumber: Int32 = 0
        var tail: String?
        
        init(_ text: String) {
            if text == "*" {
                number = Int32.max
                return
            }
            
            let (value, remainder) = Self.readNumber(text)
            number = value
            if remainder.hasPrefix("+") {
                number = number &+ 1
                suffix = "pre"
            } else if let start = remainder.firstIndex(where: { "0123456789+-".contains($0) }) {
                suffix = String(remainder[..<start])
                let (numericSuffix, extra) = Self.readNumber(String(remainder[start...]))
                suffixNumber = numericSuffix
                tail = extra.isEmpty ? nil : extra
            } else if !remainder.isEmpty {
                suffix = remainder
            }
        }
        
        private static func readNumber(_ text: String) -> (Int32, String) {
            return text.withCString { start in
                var end: UnsafeMutablePointer<CChar>?
                errno = 0
                let number = strtol(start, &end, 10)
                let value = errno == 0 ? Int32(exactly: number) ?? 0 : 0
                return (value, end.map { String(cString: $0) } ?? text)
            }
        }
    }
}
