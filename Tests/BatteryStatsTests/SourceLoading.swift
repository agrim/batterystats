import Foundation
import XCTest

final class InMemoryUserDefaultsBacking: @unchecked Sendable {
    private final class WeakDefaults {
        weak var value: UserDefaults?

        init(_ value: UserDefaults) {
            self.value = value
        }
    }

    private let lock = NSLock()
    private var values: [String: Any] = [:]
    private var defaultsInstances: [WeakDefaults] = []

    func register(_ defaults: UserDefaults) {
        lock.withLock {
            defaultsInstances.removeAll { $0.value == nil }
            defaultsInstances.append(WeakDefaults(defaults))
        }
    }

    func object(forKey key: String) -> Any? {
        lock.withLock { values[key] }
    }

    func set(_ value: Any?, forKey key: String) {
        let recipients = lock.withLock { () -> [UserDefaults] in
            values[key] = value
            defaultsInstances.removeAll { $0.value == nil }
            return defaultsInstances.compactMap(\.value)
        }
        recipients.forEach {
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: $0)
        }
    }

    func replaceValues(with values: [String: Any]) {
        let recipients = lock.withLock { () -> [UserDefaults] in
            self.values = values
            defaultsInstances.removeAll { $0.value == nil }
            return defaultsInstances.compactMap(\.value)
        }
        recipients.forEach {
            NotificationCenter.default.post(name: UserDefaults.didChangeNotification, object: $0)
        }
    }

    func dictionaryRepresentation() -> [String: Any] {
        lock.withLock { values }
    }
}

class InMemoryUserDefaults: UserDefaults {
    private let suiteNameForTesting: String
    private let backing: InMemoryUserDefaultsBacking
    private(set) var setCallCount = 0
    private(set) var removeObjectCallCount = 0
    private(set) var synchronizeCallCount = 0

    init?(
        suiteName: String,
        backing: InMemoryUserDefaultsBacking
    ) {
        suiteNameForTesting = suiteName
        self.backing = backing
        super.init(suiteName: suiteName)
        backing.register(self)
    }

    override func object(forKey defaultName: String) -> Any? {
        backing.object(forKey: defaultName)
    }

    override func string(forKey defaultName: String) -> String? {
        object(forKey: defaultName) as? String
    }

    override func bool(forKey defaultName: String) -> Bool {
        switch object(forKey: defaultName) {
        case let value as Bool:
            return value
        case let value as NSNumber:
            return value.boolValue
        case let value as String:
            return NSString(string: value).boolValue
        default:
            return false
        }
    }

    override func set(_ value: Any?, forKey defaultName: String) {
        setCallCount += 1
        backing.set(value, forKey: defaultName)
    }

    override func removeObject(forKey defaultName: String) {
        removeObjectCallCount += 1
        backing.set(nil, forKey: defaultName)
    }

    override func dictionaryRepresentation() -> [String: Any] {
        backing.dictionaryRepresentation()
    }

    override func persistentDomain(forName domainName: String) -> [String: Any]? {
        domainName == suiteNameForTesting ? dictionaryRepresentation() : nil
    }

    override func setPersistentDomain(_ domain: [String: Any], forName domainName: String) {
        guard domainName == suiteNameForTesting else {
            return
        }

        backing.replaceValues(with: domain)
    }

    override func removePersistentDomain(forName domainName: String) {
        guard domainName == suiteNameForTesting else {
            return
        }

        backing.replaceValues(with: [:])
    }

    override func synchronize() -> Bool {
        synchronizeCallCount += 1
        return true
    }

    func resetTracking() {
        setCallCount = 0
        removeObjectCallCount = 0
        synchronizeCallCount = 0
    }
}

final class IsolatedUserDefaultsFixture<Defaults: UserDefaults>: @unchecked Sendable {
    let suiteName: String
    let defaults: Defaults
    let preferencesFileURL: URL
    private let backing: InMemoryUserDefaultsBacking

    init(
        suiteName: String,
        defaults: Defaults,
        backing: InMemoryUserDefaultsBacking
    ) {
        self.suiteName = suiteName
        self.defaults = defaults
        self.backing = backing
        preferencesFileURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Preferences", isDirectory: true)
            .appendingPathComponent("\(suiteName).plist", isDirectory: false)
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
        _ = defaults.synchronize()
        try? FileManager.default.removeItem(at: preferencesFileURL)
    }

    func makeSiblingDefaults() -> InMemoryUserDefaults {
        guard let defaults = InMemoryUserDefaults(suiteName: suiteName, backing: backing) else {
            preconditionFailure("Unable to create isolated UserDefaults suite \(suiteName)")
        }

        return defaults
    }
}

extension XCTestCase {
    static func sourceURL(relativePath: String) -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        let root = testFile
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return root.appendingPathComponent(relativePath)
    }

    static func loadSource(relativePath: String) throws -> String {
        try String(contentsOf: sourceURL(relativePath: relativePath), encoding: .utf8)
    }

    func makeIsolatedUserDefaults(
        prefix: String? = nil
    ) -> IsolatedUserDefaultsFixture<InMemoryUserDefaults> {
        makeIsolatedUserDefaults(prefix: prefix) { suiteName, backing in
            InMemoryUserDefaults(suiteName: suiteName, backing: backing)
        }
    }

    func makeIsolatedUserDefaults<Defaults: UserDefaults>(
        prefix: String? = nil,
        factory: (String, InMemoryUserDefaultsBacking) -> Defaults?
    ) -> IsolatedUserDefaultsFixture<Defaults> {
        let prefix = prefix ?? String(describing: type(of: self))
        let suiteName = "io.github.agrim.batterystats.tests.\(prefix).\(UUID().uuidString)"
        let backing = InMemoryUserDefaultsBacking()
        guard let defaults = factory(suiteName, backing) else {
            preconditionFailure("Unable to create isolated UserDefaults suite \(suiteName)")
        }

        let fixture = IsolatedUserDefaultsFixture(
            suiteName: suiteName,
            defaults: defaults,
            backing: backing
        )
        fixture.cleanUp()
        addTeardownBlock {
            fixture.cleanUp()
        }
        return fixture
    }
}
