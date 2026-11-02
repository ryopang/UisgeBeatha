import CloudKit
import SwiftUI
import Foundation
import Observation

/// What Settings tells the person about iCloud sync, in plain terms.
nonisolated enum SyncStatus: Equatable, Sendable {
    /// Still asking iCloud about the account.
    case checking
    /// Mirroring to the person's private iCloud database.
    case on
    /// Sync can't run for this build, with the reason. The collection is
    /// still fully usable on this device.
    case off(SyncMode.LocalOnlyReason)
    /// Sync is set up, but the person's iCloud account can't be used right now.
    case accountUnavailable(AccountProblem)

    enum AccountProblem: Equatable, Sendable {
        case signedOut
        case restricted
        case temporarilyUnavailable
        case unknown
    }

    /// Pure, so the matrix of states is unit tested.
    static func resolve(mode: SyncMode, account: CKAccountStatus?) -> SyncStatus {
        switch mode {
        case .localOnly(let reason):
            return .off(reason)
        case .cloud:
            guard let account else { return .checking }
            switch account {
            case .available: return .on
            case .noAccount: return .accountUnavailable(.signedOut)
            case .restricted: return .accountUnavailable(.restricted)
            case .temporarilyUnavailable: return .accountUnavailable(.temporarilyUnavailable)
            case .couldNotDetermine: return .accountUnavailable(.unknown)
            @unknown default: return .accountUnavailable(.unknown)
            }
        }
    }
}

/// Watches the iCloud account so Settings can explain sync honestly.
///
/// The app never blocks on this: with no account, a restricted one or no
/// network, everything keeps working locally and syncs when it can.
@MainActor @Observable
final class CloudSyncMonitor {
    let mode: SyncMode
    private(set) var account: CKAccountStatus?

    init(mode: SyncMode) {
        self.mode = mode
    }

    var status: SyncStatus {
        SyncStatus.resolve(mode: mode, account: account)
    }

    /// Reads the account status once.
    func refresh() async {
        // Only ask CloudKit when the store was actually created with it;
        // touching a container the app isn't entitled to is an error.
        guard case .cloud = mode else { return }
        do {
            account = try await CKContainer(identifier: AppContainer.cloudKitContainerID).accountStatus()
        } catch {
            account = .couldNotDetermine
        }
    }

    /// Refreshes now and again whenever the iCloud account changes
    /// (signed in or out, restricted, and so on). Runs until cancelled.
    func run() async {
        await refresh()
        guard case .cloud = mode else { return }
        for await _ in NotificationSignal.stream(for: .CKAccountChanged) {
            await refresh()
        }
    }
}

extension EnvironmentValues {
    /// nil in previews and tests, where there is no sync to report on.
    @Entry var syncMonitor: CloudSyncMonitor?
}
