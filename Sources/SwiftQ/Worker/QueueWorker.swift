//
//  QueueWorker.swift
//  SwiftQ
//
//  Created by John Connolly on 2017-05-07.
//  Copyright © 2017 John Connolly. All rights reserved.
//

import Foundation
import Redis
import Vapor

protocol QueueWorker {
    func run(in container: Container) -> Future<Void>
}

final class ScheduledWorker<Q: Queue>: QueueWorker {
    private let queue: Q
    private let middlewares: MiddlewareCollection
    private var repeatedTask: RepeatedTask?
    
    deinit {
        repeatedTask?.cancel()
    }
    
    init(middleware: [Middleware] = [], queue: Q) {
        self.middlewares = MiddlewareCollection(middleware)
        self.queue = queue
    }
    
    func run(in container: Container) -> Future<Void> {
        return self.queue.prepare(in: container).map {
            self.repeatedTask = container.eventLoop.scheduleRepeatedTask(initialDelay: .seconds(0), delay: .seconds(1)) { repeatedTask -> Future<Void> in
                return self.runNextTask(in: container).catchMap { error in
                    return
                }
            }
        }
    }
    
    private func runNextTask(in container: Container) -> Future<Void> {
        let enqueueScheduledTasks = self.queue.enqueueScheduledTasks(in: container)
 
        return enqueueScheduledTasks.flatMap {
            self.queue.dequeue(in: container).flatMap { task -> Future<Void> in
                guard let task = task else {
                    return container.eventLoop.future()
                }
                
                self.middlewares.before(task: task)
                
                return task.run(in: container).flatMap {
                    self.middlewares.after(task: task)
                    
                    return self.complete(task, in: container)
                }.catchFlatMap { error in
                    self.middlewares.after(task: task, with: error)
                    
                    return self.failure(task, error: error, in: container)
                }
            }
            
        }.transform(to: ())
    }
    
    private func complete(_ task: Q.TaskType, in container: Container) -> Future<Void> {
        switch task.storage.schedule?.kind {
        case .some(.periodic):
            return queue.requeue(task, in: container, success: true)
        default:
            return queue.complete(task, in: container, success: true)
        }
    }
    
    private func failure(_ task: Q.TaskType, error: Error, in container: Container) -> Future<Void> {
        switch task.recoveryStrategy {
        case .none:
            return queue.complete(task, in: container, success: false)
        case .retry(let retries):
            if task.shouldRetry(retries) {
                task.retry()
                return queue.requeue(task, in: container, success: false)
            } else {
                return queue.complete(task, in: container, success: false)
            }
            //            case .log:
            //                try queue.log(task: task, error: error)
        }
    }
}
