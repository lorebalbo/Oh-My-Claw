import Foundation

/// Categories for error notification batching and cooldown.
/// Each category gets its own batching window and cooldown timer.
enum ErrorCategory: String, CaseIterable, Sendable {
    case audioConversion
    case audioMetadata
    case audioFileMove
    case pdfClassification
    case configReload
    case fileDisappeared
    case general

    /// Human-readable name for notification text (e.g., "audio conversion").
    var displayName: String {
        switch self {
        case .audioConversion: return "audio conversion"
        case .audioMetadata: return "audio metadata"
        case .audioFileMove: return "audio file move"
        case .pdfClassification: return "PDF classification"
        case .configReload: return "config reload"
        case .fileDisappeared: return "file disappeared"
        case .general: return "processing"
        }
    }

    /// Cooldown duration in seconds before the same category can fire again.
    /// Most categories use 5 minutes. Config reload uses 10 seconds since it's user-initiated.
    var cooldownInterval: TimeInterval {
        switch self {
        case .configReload: return 10.0
        default: return 300.0
        }
    }
}

/// A single error event captured for batching.
struct ErrorInfo: Sendable {
    let file: String
    let message: String
    let timestamp: Date
}

/// Collects processing errors, batches rapid ones within a 3-second window,
/// and enforces per-category cooldowns to prevent notification spam.
///
/// Usage:
/// ```
/// await errorCollector.report(category: .audioConversion, file: "song.mp3", message: "ffmpeg exit code 1")
/// ```
///
/// Batching behavior:
/// - First error in a category starts a 3-second timer
/// - Additional errors in the same category within the window are accumulated
/// - When the timer fires, a single notification is posted (with count if > 1)
/// - The category enters cooldown (5 minutes) — further errors are suppressed until cooldown expires
actor ErrorCollector {
    /// Errors buffered within the current batching window, grouped by category.
    private var pendingErrors: [ErrorCategory: [ErrorInfo]] = [:]

    /// Timestamp of last notification per category (for cooldown enforcement).
    private var lastNotified: [ErrorCategory: Date] = [:]

    /// Active batching timer tasks per category.
    private var batchTimers: [ErrorCategory: Task<Void, Never>] = [:]

    /// Duration to wait for additional errors before flushing (seconds).
    private let batchWindow: TimeInterval = 3.0

    /// Report an error. The error will be batched with others of the same category
    /// that arrive within the batch window, then flushed as a single notification.
    /// If the category is in cooldown, the error is silently suppressed (still logged).
    func report(category: ErrorCategory, file: String, message: String) {
        // Check cooldown — if category was recently notified, suppress
        if let lastTime = lastNotified[category],
           Date().timeIntervalSince(lastTime) < category.cooldownInterval {
            AppLogger.shared.debug("Error suppressed by cooldown",
                context: ["category": category.rawValue, "file": file])
            return
        }

        // Accumulate the error
        let info = ErrorInfo(file: file, message: message, timestamp: Date())
        pendingErrors[category, default: []].append(info)

        // Reset or start the batch timer for this category
        batchTimers[category]?.cancel()
        batchTimers[category] = Task { [weak self, batchWindow] in
            try? await Task.sleep(for: .seconds(batchWindow))
            guard !Task.isCancelled else { return }
            await self?.flushCategory(category)
        }
    }

    /// Flush all pending errors for a category into a single notification.
    private func flushCategory(_ category: ErrorCategory) {
        guard let errors = pendingErrors.removeValue(forKey: category),
              !errors.isEmpty else { return }
        batchTimers.removeValue(forKey: category)
        lastNotified[category] = Date()

        // Build and post notification
        let identifier = "error-\(category.rawValue)"

        if errors.count == 1 {
            let e = errors[0]
            NotificationManager.shared.notify(
                title: "Oh My Claw — Error",
                body: "\(e.file): \(e.message)",
                identifier: identifier
            )
        } else {
            NotificationManager.shared.notify(
                title: "Oh My Claw — \(errors.count) Errors",
                body: "\(errors.count) \(category.displayName) errors occurred",
                identifier: identifier
            )
        }

        AppLogger.shared.info("Error notification posted",
            context: [
                "category": category.rawValue,
                "count": "\(errors.count)"
            ])
    }

    /// Cancel all pending batch timers. Called during teardown (e.g., sleep).
    func cancelPendingTimers() {
        for task in batchTimers.values {
            task.cancel()
        }
        batchTimers.removeAll()
    }

    /// Flush all pending errors immediately (e.g., before sleep teardown).
    /// Posts any accumulated errors without waiting for the batch window.
    func flushAll() {
        for category in pendingErrors.keys {
            flushCategory(category)
        }
    }

    /// Reset cooldowns. Called after wake so errors are reported fresh.
    func resetCooldowns() {
        lastNotified.removeAll()
    }
}
