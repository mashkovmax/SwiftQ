//
//  Task.swift
//  SwiftQ
//
//  Created by John Connolly on 2017-05-07.
//  Copyright © 2017 John Connolly. All rights reserved.
//

import Foundation
import Vapor

public protocol Task: Codable {
    var storage: Storage { get }
    
    var recoveryStrategy: RecoveryStrategy { get }
    
    func run(in container: Container) -> Future<Void>
}

extension Task {

    public var recoveryStrategy: RecoveryStrategy {
        return .none
    }
    
    var uuid: String {
        return storage.uuid
    }
    
//    func log(with error: Error, consumer: String) throws -> Data {
//        let log = Log(message: error.localizedDescription, consumer: consumer, date: Date().unixTime)
//        storage.set(log: log)
//        return try data()
//    }
    
//    func data() throws -> Data {
//        let encoder = JSONEncoder()
//        return try encoder.encode(self)
//    }
    
    func shouldRetry(_ retries: Int) -> Bool {
        return retries > storage.retryCount
    }
    
    func retry() {
        storage.incRetry()
    }
}

