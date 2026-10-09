import Foundation
import OSLog

/// What the spike measures inside the real host, written to the unified log (subsystem
/// `com.countdowncula.saver`) so `scripts/saver-spike.sh logs` can collect it: where the sandbox
/// puts the screensaver, whether it can read the snapshot the Mac app mirrors in, whether it can
/// read the App Group directly, and whether it can reach the server.
enum SaverSpike {
    private static var probed = false

    static func probe(instance: Int) {
        guard !probed else { return }
        probed = true
        let log = CountdownculaSaverView.log
        let home = NSHomeDirectory()
        log.notice("spike host=\(Bundle.main.bundleIdentifier ?? "?", privacy: .public) home=\(home, privacy: .public)")

        let snapshot = SaverSnapshot.readDirectory.appending(path: "countdowns.json")
        let mirrored = (try? Data(contentsOf: snapshot)).map { "\($0.count) bytes" } ?? "unreadable"
        log.notice("spike mirrored snapshot \(snapshot.path, privacy: .public): \(mirrored, privacy: .public)")

        let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: SharedConfig.appGroup)
        let realHome = URL(fileURLWithPath: NSHomeDirectoryForUser(NSUserName()) ?? home)
        let groupFile = realHome.appending(path: "Library/Group Containers/\(SharedConfig.appGroup)/WidgetSnapshot/countdowns.json")
        let direct = (try? Data(contentsOf: groupFile)).map { "\($0.count) bytes" } ?? "unreadable"
        log.notice("spike app group url=\(group?.path ?? "nil", privacy: .public) direct read: \(direct, privacy: .public)")

        var request = URLRequest(url: URL(string: "https://go.countdowncula.com/api/crypt")!)
        request.timeoutInterval = 10
        URLSession.shared.dataTask(with: request) { data, response, error in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            log.notice("spike network status=\(status) bytes=\(data?.count ?? 0) error=\(error?.localizedDescription ?? "none", privacy: .public)")
        }.resume()
    }
}
