# PubSub Viewer

**The ultimate high-performance macOS client for your message queues.**

![PubSub Viewer](/Users/aditya/.gemini/antigravity/brain/c52e9e96-2015-4585-9fc2-bcedb444b303/pubsub_viewer_hero_banner_1768029328557.png)

## Overview

PubSub Viewer is a native macOS application designed for developers who need a fast, reliable, and beautiful tool to interact with their messaging infrastructure. Built with SwiftUI and powered by direct C FFI bindings, it offers zero-latency performance for high-throughput environments.

![PubSub Dashboard](/Users/aditya/.gemini/antigravity/brain/c52e9e96-2015-4585-9fc2-bcedb444b303/pubsub_dashboard_mockup_1768029074854.png)

## Key Features

### 🚀 High Performance Engine

Unlike Electron-based wrappers, PubSub Viewer is a native Swift application. It utilizes direct FFI bindings to the official C client libraries (e.g., `cnats`), ensuring that even the most demanding message streams are handled with ease.

### 🔌 Multi-Protocol Support

Unified interface for all your messaging needs:

* **NATS Core**: Real-time pub/sub with wildcard support.
* **NATS JetStream**: Advanced stream management, consumer inspection, and message replay.
* **Redis Pub/Sub**: Seamless integration with your Redis channels (Glob pattern matching supported).

### 🛠 Powerful JetStream Tools

Manage your NATS JetStream infrastructure directly from the UI.

* **Stream Management**: Create, edit, and delete streams.
* **Consumer Insights**: View consumer lag, active status, and configuration.
* **Message Inspection**: Browse persistent messages with full header and payload details.

![JetStream Management](/Users/aditya/.gemini/antigravity/brain/c52e9e96-2015-4585-9fc2-bcedb444b303/jetstream_view_mockup_1768029092065.png)

### 🎨 Native macOS Experience

* **Dark Mode**: Optimized for late-night coding sessions.
* **Fast Filtering**: Real-time subject/channel filtering.
* **JSON Highlighting**: Built-in syntax highlighting for message payloads.

### 🗂 Multi-Tab Workspace

* **Simultaneous Connections**: Connect to multiple servers (NATS, Redis, etc.) at once.
* **Isolated Sessions**: Each tab maintains its own independent state, message log, and subscriptions.
* **Smart Management**: Easily switch between environments without disconnecting.

## Getting Started

### Prerequisites

* macOS 14.0+
* Xcode 15.0+ (for building from source)

### Building

No external dependencies required! All C libraries are vendored and statically linked.

1. Clone the repository.
2. Open `PubSub Viewer.xcodeproj` in Xcode.
3. Build and Run (Cmd+R).

## Architecture

* **UI**: SwiftUI (Custom Tab Manager & Session Architecture)
* **State Management**: Per-tab `Session` models managed by `TabManager`
* **Networking**: Swift Concurrency (Async/Await)
* **NATS**: `cnats` (C library) via FFI
* **Redis**: Swift-native implementation

## License

MIT
