import Foundation
import os

/// Unified-logging namespace (matches the L-K-M family convention). Never log
/// file contents or the API key.
enum Log {
    private static let subsystem = "ch.lkmc.Sortomat"
    static let app = Logger(subsystem: subsystem, category: "app")
    static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    static let watch = Logger(subsystem: subsystem, category: "watch")
    static let updates = Logger(subsystem: subsystem, category: "updates")
}
