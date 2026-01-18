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
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Connection") {
                    NotificationCenter.default.post(name: .openNewConnection, object: nil)
                }
                .keyboardShortcut("t", modifiers: .command)
            }
            
            CommandGroup(replacing: .toolbar) {
                Button("Close Tab") {
                    NotificationCenter.default.post(name: .closeCurrentTab, object: nil)
                }
                .keyboardShortcut("w", modifiers: .command)
                
                Divider()
                
                Button("Select Previous Tab") {
                    NotificationCenter.default.post(name: .selectPreviousTab, object: nil)
                }
                .keyboardShortcut("[", modifiers: [.command, .shift])
                
                Button("Select Next Tab") {
                    NotificationCenter.default.post(name: .selectNextTab, object: nil)
                }
                .keyboardShortcut("]", modifiers: [.command, .shift])
                
                Divider()
                
                ForEach(1...9, id: \.self) { index in
                    Button("Select Tab \(index)") {
                        NotificationCenter.default.post(name: .selectTabByIndex, object: index)
                    }
                    .keyboardShortcut(KeyEquivalent(Character(String(index))), modifiers: .command)
                }
            }
        }
    }
}

extension Notification.Name {
    static let closeCurrentTab = Notification.Name("closeCurrentTab")
    static let selectTabByIndex = Notification.Name("selectTabByIndex")
    static let selectPreviousTab = Notification.Name("selectPreviousTab")
    static let selectNextTab = Notification.Name("selectNextTab")
    static let openNewConnection = Notification.Name("openNewConnection")
}
