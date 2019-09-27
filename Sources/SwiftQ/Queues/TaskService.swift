//
//  TaskService.swift
//  App
//
//  Created by Max on 30.07.2019.
//

import Foundation
import Vapor

public final class TaskService: Service {
    private var queues = [String: Any]()
    private var workers = [QueueWorker]()
    
    public init() {
        
    }
    
    public func run(in container: Container) -> Future<Void> {
        return workers.map { worker in
            let subContainer = container.subContainer(on: container.next())
            
            return worker.run(in: subContainer)
        }.flatten(on: container)
    }
    
    public func add<T>(_ id: QueueIdentifier<T>, middleware: [Middleware] = []) {
        let queue = RedisQueue<T>(name: id.uid)
        
        let worker = ScheduledWorker(middleware: middleware, queue: queue)
        
        assert(queues[id.uid] == nil, "A queue with id '\(id.uid)' is already registered.")
        queues[id.uid] = queue
        
        workers.append(worker)
    }
    
    public func enqueue<T>(_ task: T, to id: QueueIdentifier<T>, in container: Container, schedule: Schedule? = nil) -> Future<Void> {
        return container.future().flatMap {
            guard let queue = self.queues[id.uid] as? RedisQueue<T> else {
                throw Abort(.internalServerError)
            }
            
            return queue.enqueue(task, in: container, schedule: schedule)
        }
    }
}
