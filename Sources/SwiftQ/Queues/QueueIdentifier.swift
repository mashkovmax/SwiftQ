//
//  QueueIdentifier.swift
//  App
//
//  Created by Max on 30.07.2019.
//

import Foundation

public struct QueueIdentifier<T: Task>: Equatable, Hashable, CustomStringConvertible, ExpressibleByStringLiteral {
    /// The unique id.
    public let uid: String
    
    /// See `CustomStringConvertible`.
    public var description: String {
        return uid
    }
    
    /// Create a new `DatabaseIdentifier`.
    public init(_ uid: String) {
        self.uid = uid
    }
    
    /// See `ExpressibleByStringLiteral`.
    public init(stringLiteral value: String) {
        self.init(value)
    }
}
