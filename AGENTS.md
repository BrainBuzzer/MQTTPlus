# AGENTS.md

This file provides guidance for AI coding agents working on the PubSub Viewer project.

## Project Overview

PubSub Viewer is a macOS application for viewing and managing messages across multiple message queue systems. It's built with SwiftUI and uses C FFI for native library integration.

## Architecture

### Core Components

- **MQCore/** - Multi-MQ abstraction layer
  - `Protocols/` - MessageQueueClient, StreamingClient, MessageQueueProvider
  - `Models/` - Unified data models (MQMessage, MQStreamInfo, etc.)
  - `Registry/` - Provider registration and discovery

- **Providers/** - MQ-specific implementations
  - `NATS/` - NATS provider using C FFI (cnats library)
  - `Kafka/` - Kafka provider using pure Swift (Kafka wire protocol)
  - `Redis/` - Redis provider using pure Swift (RESP protocol)

- **Views/** - SwiftUI views for the UI
  - `SessionTabView.swift` - Custom tab bar implementation
  - `AddServerView.swift` - Two-pane server creation UI

### Session Management

The application uses a multi-tab architecture:

- **TabManager** (`Managers/TabManager.swift`): Singleton-like owner of all open sessions. Handles opening, closing, and selecting tabs.
- **Session** (`Models/Session.swift`): Represents a single active connection tab. Owns its own `ConnectionManager` instance.
- **ConnectionManager**: Instance-based (not singleton) to allow multiple simultaneous connections to any provider.

### C FFI Integration

The project uses C libraries via Objective-C bridging headers:

1. Bridging header: `PubSub Viewer/PubSub_Viewer-Bridging-Header.h`
2. C library: cnats (vendored under `ThirdParty/cnats/` and linked statically)
3. Swift wrapper: `Providers/NATS/NatsCClient.swift`

## Build Requirements

- macOS 26.2+
- Xcode with Swift 5.0+
- No external (Homebrew) dependencies required for NATS: the cnats headers and static libs are vendored under `ThirdParty/`.

## Key Files

| File | Purpose |
|------|---------|
| `NatsManager.swift` | Instance-based manager for a single NATS connection |
| `TabManager.swift` | Manages list of active `Session` objects and selection state |
| `Session.swift` | Model holding state for one connection tab (config + manager) |
| `SessionTabView.swift` | Main UI container rendering the tab bar and active session |
| `NatsCClient.swift` | C FFI wrapper around nats.c library |
| `ContentView.swift` | Root view wiring up TabManager |
| `JetStreamManager.swift` | JetStream operations (placeholder) |

## Conventions

### Swift Style

- Use `@MainActor` for UI-related classes
- Use async/await for asynchronous operations
- Prefer `final class` for concrete implementations
- Use `@unchecked Sendable` for classes with internal locking

### C FFI Pattern

- Use `OpaquePointer` for C struct pointers
- Always cleanup C resources in `deinit`
- Use `withUnsafeBytes` for passing Data to C functions
- Check `natsStatus` return values

### Error Handling

- Use `MQError` enum for MQ-related errors
- Include descriptive error messages
- Log errors via `NatsManager.log()`

## Testing

To test NATS functionality:

```bash
# Start local NATS server
docker run -d --name nats -p 4222:4222 nats:latest

# Connect via app to nats://localhost:4222
```

## Common Tasks

### Adding a New MQ Provider

1. Create provider directory: `Providers/NewMQ/`
2. Vendor any required C library under `ThirdParty/` (or the provider folder)
3. Add includes to bridging header
4. Create `NewMQClient.swift` implementing `MessageQueueClient`
5. Create `NewMQProvider.swift` implementing `MessageQueueProvider`
6. Update Xcode build settings (header/library paths and linker flags)

### Modifying Build Settings

Build settings are in `project.pbxproj` under:

- `48B531582F1202E000706410` (Debug)
- `48B531592F1202E000706410` (Release)

Key settings: `HEADER_SEARCH_PATHS`, `LIBRARY_SEARCH_PATHS`, `OTHER_LDFLAGS`, `SWIFT_OBJC_BRIDGING_HEADER`
