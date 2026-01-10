//
//  ServerConfigMigrator.swift
//  MQTT Plus
//
//  Lightweight CoreData backfills for ServerConfig.
//

import CoreData
import Foundation

@MainActor
enum ServerConfigMigrator {
    private static var didBackfill = false

    static func backfillProviderIdsIfNeeded(viewContext: NSManagedObjectContext) async {
        guard !didBackfill else { return }
        didBackfill = true

        let request = NSFetchRequest<NSManagedObject>(entityName: "ServerConfig")

        do {
            let servers = try viewContext.fetch(request)
            guard !servers.isEmpty else { return }

            var didChange = false

            for server in servers {
                let existingProviderId = (server.value(forKey: "providerId") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                let urlString = (server.value(forKey: "urlString") as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
                guard let urlString, !urlString.isEmpty else { continue }

                let serverId: UUID = {
                    if let id = server.value(forKey: "id") as? UUID { return id }
                    let newId = UUID()
                    server.setValue(newId, forKey: "id")
                    didChange = true
                    return newId
                }()

                let url = URL(string: urlString)

                // ProviderId backfill
                if existingProviderId == nil || existingProviderId?.isEmpty == true {
                    if let inferred = inferProviderId(from: urlString) {
                        server.setValue(inferred, forKey: "providerId")
                        didChange = true
                    }
                }

                // Extract host/port/useTLS/username/password from the URL for structured storage.
                if let url, let host = url.host, !host.isEmpty {
                    var shouldStripUserInfo = true

                    if (server.value(forKey: "host") as? String)?.isEmpty != false {
                        server.setValue(host, forKey: "host")
                        didChange = true
                    }

                    if server.value(forKey: "port") == nil, let port = url.port {
                        server.setValue(Int32(port), forKey: "port")
                        didChange = true
                    }

                    if server.value(forKey: "useTLS") == nil {
                        let scheme = url.scheme?.lowercased()
                        let tls = (scheme == "tls") || (scheme == "rediss") || (scheme == "kafkas")
                        server.setValue(tls, forKey: "useTLS")
                        didChange = true
                    }

                    if (server.value(forKey: "username") as? String)?.isEmpty != false,
                       let username = url.user,
                       !username.isEmpty {
                        server.setValue(username, forKey: "username")
                        didChange = true
                    }

                    if let password = url.password, !password.isEmpty {
                        let key = KeychainService.key(for: serverId, kind: .password)
                        do {
                            try KeychainService.storeString(password, key: key)
                            server.setValue(key, forKey: "passwordKeychainId")
                            didChange = true
                        } catch {
                            shouldStripUserInfo = false
                            print("[ServerConfigMigrator] Failed to move password into Keychain: \(error)")
                        }
                    }

                    // Sanitize stored URL by removing userinfo and normalizing TLS schemes for Redis/Kafka.
                    if var components = URLComponents(url: url, resolvingAgainstBaseURL: false) {
                        let originalScheme = components.scheme?.lowercased()
                        if shouldStripUserInfo {
                            components.user = nil
                            components.password = nil
                        }
                        if originalScheme == "rediss" {
                            components.scheme = "redis"
                        } else if originalScheme == "kafkas" {
                            components.scheme = "kafka"
                        }

                        if let sanitized = components.string, sanitized != urlString {
                            server.setValue(sanitized, forKey: "urlString")
                            didChange = true
                        }
                    }
                }

            }

            if didChange {
                try viewContext.save()
            }
        } catch {
            print("[ServerConfigMigrator] ProviderId backfill failed: \(error)")
        }
    }

    private static func inferProviderId(from urlString: String) -> String? {
        guard let url = URL(string: urlString), let scheme = url.scheme?.lowercased() else {
            return nil
        }

        switch scheme {
        case "nats", "tls":
            return "nats"
        case "redis", "rediss":
            return "redis"
        case "kafka", "kafkas":
            return "kafka"
        default:
            return nil
        }
    }
}
