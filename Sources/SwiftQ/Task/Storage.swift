//
//  Storage.swift
//  SwiftQ
//
//  Created by John Connolly on 2017-06-22.
//
//

import Foundation
import Vapor

public final class Storage: Codable {
    let uuid: String
    var enqueuedAt: Int?
    var retryCount = 0
    var schedule: Schedule?
    
    public init() {
        self.uuid = UUID().uuidString
    }
    
    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(uuid, forKey: .uuid)
        try container.encode(enqueuedAt ?? Date().unixTime, forKey: .enqueuedAt)
        try container.encode(retryCount, forKey: .retryCount)
        try container.encodeIfPresent(schedule, forKey: .schedule)
    }
    
    func incRetry() {
        retryCount += 1
    }
}
