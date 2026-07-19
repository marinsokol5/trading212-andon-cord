import AppKit
import SwiftUI
import Trading212Core

/// The **Snapshots** screen: a read-only browser of the trading snapshots the
/// `t212` CLI writes into the variant workspace (`snapshot save` exports and
/// automatic pre-sale records).
///
/// The app intentionally does not link `Trading212Trading`, so this screen
/// never gains the ability to restore or trade from a snapshot. It reads just
/// the display fields with its own minimal decoder; anything it cannot parse
/// is listed as unrecognized rather than hidden.
struct SnapshotsView: View {
    @Bindable var model: AppModel

    @State private var snapshots: [SnapshotFileSummary] = []
    @State private var loadError: String?
    @State private var loaded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScreenHeader("Snapshots", subtitle: "Saved portfolio states from the t212 CLI — read-only here") {
                Button {
                    revealFolder()
                } label: {
                    Label("Show in Finder", systemImage: "folder")
                }
                .disabled(snapshots.isEmpty && loadError != nil)
                Button {
                    reload()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.borderless)

            if let loadError {
                ContentUnavailableView(
                    "Snapshots unavailable",
                    systemImage: "exclamationmark.triangle",
                    description: Text(loadError))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if snapshots.isEmpty {
                emptyState
            } else {
                list
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            reload()
        }
    }

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No snapshots yet", systemImage: "square.stack.3d.up")
        } description: {
            Text("Create one in Terminal with `t212 snapshot save`. A real `t212 sell-all` also writes a pre-sale snapshot automatically before placing any order.")
                .frame(maxWidth: 480)
        } actions: {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString("t212 snapshot save", forType: .string)
            } label: {
                Label("Copy Command", systemImage: "doc.on.doc")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            VStack(spacing: 8) {
                ForEach(snapshots) { snapshot in
                    SnapshotRow(snapshot: snapshot, model: model)
                }
            }
            .padding(.horizontal, 22)
            .padding(.bottom, 18)
            .padding(.top, 4)
        }
    }

    private func reload() {
        do {
            snapshots = try SnapshotLibrary.load()
            loadError = nil
        } catch {
            snapshots = []
            loadError = error.localizedDescription
        }
    }

    private func revealFolder() {
        guard let workspace = try? Workspace() else { return }
        NSWorkspace.shared.activateFileViewerSelecting([workspace.snapshotsDirectoryURL])
    }
}

private struct SnapshotRow: View {
    let snapshot: SnapshotFileSummary
    @Bindable var model: AppModel

    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(snapshot.kindDisplayName)
                        .font(.system(size: 13, weight: .semibold))
                    if let environment = snapshot.environment {
                        EnvironmentBadge(environment: environment)
                    }
                    if snapshot.problem != nil {
                        Label("Unrecognized format", systemImage: "questionmark.circle")
                            .font(.caption)
                            .foregroundStyle(Theme.warning)
                    }
                }
                Text(snapshot.fileName)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .textSelection(.enabled)
            }
            Spacer(minLength: 12)
            VStack(alignment: .trailing, spacing: 4) {
                if let value = snapshot.accountValue, let currency = snapshot.currency {
                    Text(model.privateAmount(value, currency: currency, style: .fullWithCents))
                        .font(.body.monospacedDigit())
                }
                HStack(spacing: 6) {
                    if let count = snapshot.positionCount {
                        Text(count == 1 ? "1 position" : "\(count) positions")
                    }
                    if let capturedAt = snapshot.capturedAt {
                        Text(capturedAt.formatted(date: .abbreviated, time: .shortened))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Button {
                NSWorkspace.shared.activateFileViewerSelecting([snapshot.url])
            } label: {
                Image(systemName: "magnifyingglass")
            }
            .buttonStyle(.borderless)
            .help("Show this file in Finder")
            .opacity(hovering ? 1 : 0.35)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .card(hovering: hovering)
        .onHover { hovering = $0 }
        .animation(.easeOut(duration: 0.12), value: hovering)
    }
}

/// One snapshot file's display summary. `problem` marks files in the snapshots
/// directory that this app-local decoder could not parse.
struct SnapshotFileSummary: Identifiable, Sendable {
    let url: URL
    let fileName: String
    let kind: String?
    let environment: Trading212Environment?
    let capturedAt: Date?
    let accountValue: Decimal?
    let currency: String?
    let positionCount: Int?
    let problem: String?

    var id: String { fileName }

    var kindDisplayName: String {
        switch kind {
        case "current": "Snapshot"
        case "preSale": "Pre-sale record"
        case let other?: other
        case nil: "Snapshot file"
        }
    }
}

/// Reads display summaries from the variant workspace's snapshots directory.
/// Strictly read-only: never creates directories or touches file contents.
@MainActor
enum SnapshotLibrary {
    /// The screenshot harness points this at a fixture directory; the app
    /// itself always reads the real workspace.
    static var directoryOverride: URL?

    static func load(fileManager: FileManager = .default) throws -> [SnapshotFileSummary] {
        let directory = try directoryOverride ?? Workspace().snapshotsDirectoryURL
        guard fileManager.fileExists(atPath: directory.path) else { return [] }

        let files = try fileManager.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles])

        return files
            .filter { $0.pathExtension.lowercased() == "json" }
            .map(summary(for:))
            .sorted { sortDate(of: $0) > sortDate(of: $1) }
    }

    private static func sortDate(of snapshot: SnapshotFileSummary) -> Date {
        snapshot.capturedAt
            ?? ((try? snapshot.url.resourceValues(forKeys: [.contentModificationDateKey]))?
                .contentModificationDate ?? .distantPast)
    }

    private static func summary(for url: URL) -> SnapshotFileSummary {
        do {
            let data = try Data(contentsOf: url)
            let document = try JSONDecoder().decode(DisplayDocument.self, from: data)
            return SnapshotFileSummary(
                url: url,
                fileName: url.lastPathComponent,
                kind: document.kind,
                environment: Trading212Environment(rawValue: document.environment),
                capturedAt: parseISO8601(document.capturedAt),
                accountValue: Decimal(string: document.totals.accountValue, locale: Locale(identifier: "en_US_POSIX")),
                currency: document.account.currency,
                positionCount: document.positions.count,
                problem: nil)
        } catch {
            return SnapshotFileSummary(
                url: url,
                fileName: url.lastPathComponent,
                kind: nil,
                environment: nil,
                capturedAt: nil,
                accountValue: nil,
                currency: nil,
                positionCount: nil,
                problem: "Not a readable snapshot: \(error.localizedDescription)")
        }
    }

    private static func parseISO8601(_ string: String) -> Date? {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = fractional.date(from: string) { return date }
        let plain = ISO8601DateFormatter()
        plain.formatOptions = [.withInternetDateTime]
        return plain.date(from: string)
    }

    /// Display fields only — mirrors the wire shape of
    /// `TradingSnapshotDocument` without importing the trading library.
    private struct DisplayDocument: Decodable {
        struct Account: Decodable { let currency: String }
        struct Totals: Decodable { let accountValue: String }
        struct Position: Decodable { let ticker: String }

        let kind: String
        let capturedAt: String
        let environment: String
        let account: Account
        let totals: Totals
        let positions: [Position]
    }
}
