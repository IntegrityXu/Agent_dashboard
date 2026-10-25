/// Failed attempts back off; a verified healthy session resets the next retry.
struct ReconnectBackoff {
    private var delay = 1.0

    mutating func nextDelay(afterHealthySession healthy: Bool) -> Double {
        if healthy { delay = 1 }
        defer { delay = min(delay * 2, 15) }
        return delay
    }
}
