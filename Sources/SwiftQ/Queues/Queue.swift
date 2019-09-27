import Foundation
import Dispatch
import Redis

public protocol Queue {
    associatedtype TaskType: Task
    
    func prepare(in container: Container) -> Future<Void>
    func enqueue(_ task: TaskType, in container: Container, schedule: Schedule?) -> Future<Void>
    func dequeue(in container: Container) -> Future<TaskType?>
    func complete(_ task: TaskType, in container: Container, success: Bool) -> Future<Void>
    func requeue(_ task: TaskType, in container: Container, success: Bool) -> Future<Void>
    func enqueueScheduledTasks(in: Container) -> Future<Void>
}

final class RedisQueue<T: Task>: Queue {

    private struct Keys {
        let work: String
        let processing: String
        let scheduled: String
        let success: String
        let failure: String
        let logs: String
        
        init(name: String) {
            self.work = name + ":workq"
            self.processing = name + ":processingq"
            self.scheduled = name + ":scheduledq"
            self.success = name + ":success"
            self.failure = name + ":failure"
            self.logs = name + ":logs"
        }
    }
    private let keys: Keys
    
    init(name: String) {
    
        self.keys = Keys(name: name)
    }

    func prepare(in container: Container) -> Future<Void> {
        let keys = self.keys
        
        return container.withPooledConnection(to: .redis) { client in
            let range = ClosedRange<Int>(uncheckedBounds: (lower: 0, upper: -1))

            return client.lrange(list: keys.processing, range: range).flatMap { data in
                guard let array = data.array, !array.isEmpty else {
                    return client.eventLoop.future()
                }
                
                return client.lpush(array, into: keys.work).flatMap { _ in
                    return client.delete(keys.processing)
                }.transform(to: ())
            }
        }
    }
    
    func enqueue(_ task: T, in container: Container, schedule: Schedule? = nil) -> Future<Void> {
        let keys = self.keys
        
        return container.withPooledConnection(to: .redis) { client in
            let uuid = try task.uuid.convertToRedisData()
            task.storage.schedule = schedule
            
            let data = try JSONEncoder().encode(task)
            
            if let time = task.storage.schedule?.time {
                let score = time.description
                
                let item = try (score, task.uuid.convertToRedisData())

                return client.zadd(keys.scheduled, items: [item]).flatMap { _ in
                    return client.set(task.uuid, to: data)
                }
            } else {
                return client.lpush([uuid], into: keys.work).flatMap { _ in
                    return client.set(task.uuid, to: data)
                }
            }
        }
    }
    
    func dequeue(in container: Container) -> Future<T?> {
        let keys = self.keys
        
        return container.withPooledConnection(to: .redis) { client -> Future<T?> in
            return client.rpoplpush(source: keys.work, destination: keys.processing).flatMap { data -> Future<T?> in
                guard let uuid = data.string else {
                    return client.future(nil)
                }
                
                return client.rawGet(uuid).map { data in
                    guard let data = data.data else {
                        return nil
                    }
                    
                    let task = try JSONDecoder().decode(T.self, from: data)
                    
                    return task
                }
            }
        }
    }
    
    func complete(_ task: T, in container: Container, success: Bool) -> Future<Void> {
        let keys = self.keys
        
        let incrementKey = success ? keys.success : keys.failure
        
        return container.withPooledConnection(to: .redis) { client in
            
            let value = try task.uuid.convertToRedisData()
            
            return client.lrem(keys.processing, count: 0, value: value).flatMap { _ in
                return client.increment(incrementKey)
            }.flatMap { _ in
                return client.delete(task.uuid)
            }
        }
    }
    
    func requeue(_ task: T, in container: Container, success: Bool) -> Future<Void> {
        let keys = self.keys
        
        let incrementKey = success ? keys.success : keys.failure
        
        return container.withPooledConnection(to: .redis) { client in
            let uuid = try task.uuid.convertToRedisData()
            
            return client.lrem(keys.processing, count: 0, value: uuid).flatMap { _ in
                return client.increment(incrementKey)
            }.flatMap { _ in
                let uuid = try task.uuid.convertToRedisData()
                
                if let time = task.storage.schedule?.time {
                    let score = time.description

                    return client.zadd(keys.scheduled, items: [(score, uuid)]).transform(to: ())
                } else {
                    let data = try JSONEncoder().encode(task).convertToRedisData()

                    return client.set(task.uuid, to: data).flatMap {
                        return client.lpush([uuid], into: keys.work).transform(to: ())
                    }
                }
            }
        }
    }
    
    func enqueueScheduledTasks(in container: Container) -> Future<Void> {
        let keys = self.keys
        
        return container.withPooledConnection(to: .redis) { client in
            return client.zrangebyscore(keys.scheduled, min: "-inf", max: Date().unixTime.description).flatMap { data in
                guard !data.isEmpty else {
                    return client.future()
                }
                
                return client.rpoplpush(source: keys.scheduled, destination: keys.work).transform(to: ())
            }
        }
    }
}
