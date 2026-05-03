import Foundation

struct TestDefaultsHelper {
    let suiteName: String
    let defaults: UserDefaults

    init(prefix: String = "BillEasyTests") {
        self.suiteName = "\(prefix).\(UUID().uuidString)"
        self.defaults = UserDefaults(suiteName: suiteName) ?? .standard
        self.defaults.removePersistentDomain(forName: suiteName)
    }

    func cleanup() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults.synchronize()
    }
}
