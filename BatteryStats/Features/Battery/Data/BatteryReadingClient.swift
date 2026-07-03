import Foundation

actor BatteryReadingWorker {
    private let service: BatteryReadingService

    init(service: BatteryReadingService = BatteryReadingService()) {
        self.service = service
    }

    func read(at date: Date = .now, options: BatteryReadOptions = .standard) -> BatteryReadResult {
        service.read(at: date, options: options)
    }
}

struct BatteryReadingClient: Sendable {
    let read: @Sendable (_ date: Date, _ options: BatteryReadOptions) async -> BatteryReadResult
    let makeNotificationToken: @MainActor @Sendable (_ handler: @escaping @Sendable () -> Void) -> PowerSourceReader.NotificationToken?

    static func live(service: BatteryReadingService = BatteryReadingService()) -> BatteryReadingClient {
        let worker = BatteryReadingWorker(service: service)

        return BatteryReadingClient(
            read: { date, options in
                await worker.read(at: date, options: options)
            },
            makeNotificationToken: { handler in
                service.makeNotificationToken(handler: handler)
            }
        )
    }
}
