import Foundation
import Combine

/// Live microphone and system-audio levels, kept apart from the rest of the
/// app's state on purpose.
///
/// Audio callbacks arrive dozens of times a second. Publishing them on the
/// main model would re-render the whole window at that rate (measured: the
/// UI alone burning more CPU than the capture). Here they are throttled to
/// a rate the eye reads as continuous, and only the meters observe them.
@MainActor
final class AudioLevels: ObservableObject {
    @Published private(set) var microphone: Double = 0
    @Published private(set) var system: Double = 0

    /// 12 updates a second look smooth and cost nothing.
    private static let interval: TimeInterval = 1.0 / 12
    /// Below this, a change is not visible in a 40-pixel meter.
    private static let step = 0.02

    private var lastMicrophonePublish = Date.distantPast
    private var lastSystemPublish = Date.distantPast

    func report(microphone value: Double) {
        if shouldPublish(value, current: microphone, last: &lastMicrophonePublish) {
            microphone = value
        }
    }

    func report(system value: Double) {
        if shouldPublish(value, current: system, last: &lastSystemPublish) {
            system = value
        }
    }

    /// Silence is published immediately: a meter that keeps showing sound
    /// after the microphone was muted would be a lie.
    private func shouldPublish(_ value: Double, current: Double, last: inout Date) -> Bool {
        if value == 0, current != 0 { last = Date(); return true }
        let now = Date()
        guard now.timeIntervalSince(last) >= Self.interval else { return false }
        guard abs(value - current) >= Self.step else { return false }
        last = now
        return true
    }

    func reset() {
        microphone = 0
        system = 0
    }
}
