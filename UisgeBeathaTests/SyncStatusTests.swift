import CloudKit
import Foundation
import SwiftData
import Testing
@testable import UisgeBeatha

/// Phase 3: what Settings says about sync, the price and last-tasted
/// accessors, and the new sort key.
@MainActor
struct SyncStatusTests {
    // MARK: - Status matrix

    @Test func localOnlyModesAreOffWhateverTheAccount() {
        for account in [CKAccountStatus.available, .noAccount, nil] {
            #expect(SyncStatus.resolve(mode: .localOnly(reason: .disabled), account: account) == .off(.disabled))
        }
        #expect(
            SyncStatus.resolve(mode: .localOnly(reason: .cloudKitUnavailable("x")), account: .available)
                == .off(.cloudKitUnavailable("x"))
        )
    }

    @Test func cloudModeFollowsTheAccount() {
        #expect(SyncStatus.resolve(mode: .cloud, account: nil) == .checking)
        #expect(SyncStatus.resolve(mode: .cloud, account: .available) == .on)
        #expect(SyncStatus.resolve(mode: .cloud, account: .noAccount) == .accountUnavailable(.signedOut))
        #expect(SyncStatus.resolve(mode: .cloud, account: .restricted) == .accountUnavailable(.restricted))
        #expect(
            SyncStatus.resolve(mode: .cloud, account: .temporarilyUnavailable)
                == .accountUnavailable(.temporarilyUnavailable)
        )
        #expect(SyncStatus.resolve(mode: .cloud, account: .couldNotDetermine) == .accountUnavailable(.unknown))
    }

    @Test func everyStatusHasPlainLanguageForSettings() {
        let statuses: [SyncStatus] = [
            .checking, .on, .off(.disabled), .off(.cloudKitUnavailable("x")),
            .accountUnavailable(.signedOut), .accountUnavailable(.restricted),
            .accountUnavailable(.temporarilyUnavailable), .accountUnavailable(.unknown),
        ]
        for status in statuses {
            #expect(!Strings.Settings.syncTitle(status).isEmpty)
            #expect(!Strings.Settings.syncExplanation(status).isEmpty)
            #expect(!Strings.Settings.syncExplanation(status).contains("—"), "No em dashes in UI copy")
        }
    }

    @Test func aLocalOnlyMonitorNeverTouchesCloudKit() async {
        let monitor = CloudSyncMonitor(mode: .localOnly(reason: .disabled))
        await monitor.refresh()
        #expect(monitor.account == nil)
        #expect(monitor.status == .off(.disabled))
    }

    // MARK: - Container

    @Test func disablingSyncByArgumentOpensALocalStore() throws {
        // `open` reads the real store location, so only the argument path is
        // exercised here; the in-memory path is covered by AppContainerTests.
        #expect(AppContainer.disableSyncArgument == "-disableCloudSync")
        #expect(AppContainer.cloudKitContainerID == "iCloud.com.ryo.UisgeBeatha")
    }

    // MARK: - Price

    @Test func priceRoundTripsThroughMinorUnits() {
        let bottle = Bottle()
        bottle.price = Decimal(string: "89.99")
        #expect(bottle.priceMinorUnits == 8999)
        #expect(bottle.price == Decimal(string: "89.99"))
    }

    @Test func minorUnitsRoundHalfAwayFromZero() {
        #expect(Bottle.minorUnits(from: Decimal(string: "19.995")!) == 2000)
        #expect(Bottle.minorUnits(from: Decimal(string: "0.004")!) == 0)
        #expect(Bottle.minorUnits(from: 100) == 10000)
    }

    @Test func aV1PriceWithoutMinorUnitsStillReads() {
        let bottle = Bottle(purchasePrice: Decimal(string: "54.5"))
        #expect(bottle.priceMinorUnits == nil)
        #expect(bottle.price == Decimal(string: "54.5"))
    }

    @Test func clearingThePriceClearsBothFields() {
        let bottle = Bottle()
        bottle.price = 40
        bottle.price = nil
        #expect(bottle.purchasePrice == nil)
        #expect(bottle.priceMinorUnits == nil)
    }

    @Test func theIntegerWinsIfTheDecimalDriftedInSync() {
        // CloudKit mirrors Decimal through a Double and can hand back noise.
        let bottle = Bottle(purchasePrice: Decimal(string: "89.98999999999999"), priceMinorUnits: 8999)
        #expect(bottle.price == Decimal(string: "89.99"))
    }

    // MARK: - Last tasted

    @Test func lastTastedFollowsTheNewestNote() throws {
        let container = try AppContainer.make(inMemory: true)
        let context = ModelContext(container)
        let bottle = Bottle(name: "Ardbeg 10")
        context.insert(bottle)
        for time in [1_000.0, 3_000.0, 2_000.0] {
            let note = TastingNote(date: Date(timeIntervalSince1970: time), nose: "x")
            context.insert(note)
            note.bottle = bottle
        }
        try context.save()

        bottle.refreshLastTasted()
        #expect(bottle.lastTastedDate == Date(timeIntervalSince1970: 3_000))

        let newest = try #require(bottle.notes?.first { $0.date == Date(timeIntervalSince1970: 3_000) })
        context.delete(newest)
        try context.save()
        bottle.refreshLastTasted()
        #expect(bottle.lastTastedDate == Date(timeIntervalSince1970: 2_000))
    }

    @Test func aBottleWithNoNotesHasNoLastTastedDate() {
        let bottle = Bottle(lastTastedDate: Date.now)
        bottle.refreshLastTasted()
        #expect(bottle.lastTastedDate == nil)
    }

    @Test func sortingByLastTastedPutsTheNewestFirstAndNeverTastedLast() {
        let recent = Bottle(name: "Recent", lastTastedDate: Date(timeIntervalSince1970: 9_000))
        let older = Bottle(name: "Older", lastTastedDate: Date(timeIntervalSince1970: 1_000))
        let neverB = Bottle(name: "B Never")
        let neverA = Bottle(name: "A Never")

        let sorted = CollectionSortKey.lastTasted.sorted([neverB, older, neverA, recent])

        #expect(sorted.map(\.name) == ["Recent", "Older", "A Never", "B Never"])
    }
}
