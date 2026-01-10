//
//  PubSub_ViewerApp.swift
//  PubSub Viewer
//
//  Created by Aditya on 10/01/26.
//

import SwiftUI
import CoreData

@main
struct PubSub_ViewerApp: App {
    let persistenceController = PersistenceController.shared

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.managedObjectContext, persistenceController.container.viewContext)
        }
    }
}
