import Foundation

@MainActor
public final class GraphDataBuffer {
    private var buffer: [Double]
    private var index: Int = 0
    private let capacity: Int
    private var count: Int = 0

    public init(capacity: Int = 50) {
        self.capacity = capacity
        buffer = Array(repeating: 0, count: capacity)
    }

    // swiftlint:disable:next empty_count
    public var isEmpty: Bool { count == 0 }

    public func push(_ value: Double) {
        buffer[index] = value
        index = (index + 1) % capacity
        if count < capacity {
            count += 1
        }
    }

    public func values() -> [Double] {
        guard !isEmpty else {
            return []
        }
        if count < capacity {
            return Array(buffer[0 ..< count])
        }
        return Array(buffer[index ..< capacity]) + Array(buffer[0 ..< index])
    }
}
