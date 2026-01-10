//
//  AppBootstrapper.swift
//  MQTT Plus
//
//  One-time app bootstrap tasks (provider registration, data backfills).
//

import CoreData

@MainActor
enum AppBootstrapper {
    private static var didRun = false

    static func runIfNeeded(viewContext: NSManagedObjectContext) async {
        guard !didRun else { return }
        didRun = true

        registerAllProviders()
        await ServerConfigMigrator.backfillProviderIdsIfNeeded(viewContext: viewContext)
    }
}

