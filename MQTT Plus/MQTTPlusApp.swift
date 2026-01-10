//
//  MQTTPlusApp.swift
//  MQTT Plus
//
//  Created by Aditya on 10/01/26.
//

import SwiftUI
import CoreData

@main
struct MQTTPlusApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
