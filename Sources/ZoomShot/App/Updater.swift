import AppKit

/// Minimal GitHub-Releases-backed update checker. No background scheduling,
/// no auto-install — just a "Check for Updates…" menu action that hits the
/// API, compares semver, and either tells the user they're current or offers
/// to open the new release in the browser.
enum Updater {
    private static let repoOwner = "auspy"
    private static let repoName = "zoomshot"
    private static let apiURL = URL(string:
        "https://api.github.com/repos/\(repoOwner)/\(repoName)/releases/latest")!

    @MainActor
    static func checkForUpdates(presentingFrom presenter: NSWindow? = nil) {
        let current = currentVersion()
        Task {
            do {
                let release = try await fetchLatest()
                await MainActor.run {
                    handleResult(current: current, release: release)
                }
            } catch {
                await MainActor.run {
                    showAlert(
                        style: .warning,
                        title: "Couldn't check for updates",
                        body: "\(error.localizedDescription)\n\nTry again later, or visit the releases page manually.",
                        primaryButton: "Open Releases Page",
                        secondaryButton: "OK",
                        primaryAction: openReleasesPage
                    )
                }
            }
        }
    }

    // MARK: - Internal

    private struct Release: Decodable {
        let tagName: String
        let htmlURL: URL
        let name: String?
        let body: String?

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
            case name
            case body
        }
    }

    private static func currentVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }

    private static func fetchLatest() async throws -> Release {
        var req = URLRequest(url: apiURL)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("ZoomShot/\(currentVersion())", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        if let http = response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            throw NSError(domain: "ZoomShot.Updater", code: http.statusCode,
                          userInfo: [NSLocalizedDescriptionKey: "GitHub returned HTTP \(http.statusCode)."])
        }
        return try JSONDecoder().decode(Release.self, from: data)
    }

    @MainActor
    private static func handleResult(current: String, release: Release) {
        let latest = stripLeadingV(release.tagName)
        switch compareSemver(current, latest) {
        case .orderedAscending:
            let title = "Update available — \(release.name ?? release.tagName)"
            let body = """
            You're on \(current). The latest release is \(latest).

            \((release.body?.trimmingCharacters(in: .whitespacesAndNewlines)).map { trim($0, 600) } ?? "")
            """
            showAlert(
                style: .informational,
                title: title,
                body: body,
                primaryButton: "Download",
                secondaryButton: "Later",
                primaryAction: { NSWorkspace.shared.open(release.htmlURL) }
            )
        case .orderedSame, .orderedDescending:
            showAlert(
                style: .informational,
                title: "You're up to date",
                body: "ZoomShot \(current) is the latest version.",
                primaryButton: "OK",
                secondaryButton: nil,
                primaryAction: nil
            )
        }
    }

    private static func stripLeadingV(_ s: String) -> String {
        s.hasPrefix("v") ? String(s.dropFirst()) : s
    }

    private static func trim(_ s: String, _ max: Int) -> String {
        s.count > max ? String(s.prefix(max)) + "…" : s
    }

    /// Tolerant semver compare: splits on ".", treats missing components as 0,
    /// drops anything after a "-" so pre-releases compare on their core only.
    private static func compareSemver(_ a: String, _ b: String) -> ComparisonResult {
        let parse: (String) -> [Int] = { v in
            let core = v.split(separator: "-", maxSplits: 1).first.map(String.init) ?? v
            return core.split(separator: ".").map { Int($0) ?? 0 }
        }
        let lhs = parse(a)
        let rhs = parse(b)
        let n = max(lhs.count, rhs.count)
        for i in 0..<n {
            let li = i < lhs.count ? lhs[i] : 0
            let ri = i < rhs.count ? rhs[i] : 0
            if li < ri { return .orderedAscending }
            if li > ri { return .orderedDescending }
        }
        return .orderedSame
    }

    private static func openReleasesPage() {
        if let url = URL(string: "https://github.com/\(repoOwner)/\(repoName)/releases") {
            NSWorkspace.shared.open(url)
        }
    }

    @MainActor
    private static func showAlert(style: NSAlert.Style,
                                  title: String,
                                  body: String,
                                  primaryButton: String,
                                  secondaryButton: String?,
                                  primaryAction: (() -> Void)?) {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = style
        alert.messageText = title
        alert.informativeText = body
        alert.addButton(withTitle: primaryButton)
        if let secondaryButton { alert.addButton(withTitle: secondaryButton) }
        if alert.runModal() == .alertFirstButtonReturn {
            primaryAction?()
        }
    }
}
