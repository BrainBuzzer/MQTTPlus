//
//  StreamCreatorSheet.swift
//  PubSub Viewer
//
//  Created by Antigravity on 10/01/26.
//

import SwiftUI

struct StreamCreatorSheet: View {
    @ObservedObject var jetStreamManager: JetStreamManager
    @Binding var isPresented: Bool
    
    @State private var name = ""
    @State private var subjects = ""
    @State private var retention: RetentionPolicy = .limits
    @State private var storage: StorageType = .file
    @State private var maxAge: String = ""
    @State private var maxBytes: String = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Create Stream")
                    .font(.headline)
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Form
            Form {
                Section("Basic Information") {
                    TextField("Stream Name", text: $name)
                    TextField("Subjects (comma-separated, e.g. orders.*, events.>)", text: $subjects)
                }
                
                Section("Configuration") {
                Picker("Retention Policy", selection: $retention) {
                    ForEach([RetentionPolicy.limits, .interest, .workQueue], id: \.self) { policy in
                        Text(policy.rawValue).tag(policy)
                    }
                }
                
                Picker("Storage Type", selection: $storage) {
                    ForEach([StorageType.file, .memory], id: \.self) { type in
                        Text(type.rawValue).tag(type)
                    }
                }
                }
                
                Section("Limits (Optional)") {
                    TextField("Max Age (seconds)", text: $maxAge)
                        .help("Maximum age of messages in seconds")
                    TextField("Max Bytes", text: $maxBytes)
                        .help("Maximum size of the stream in bytes")
                }
                
                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button("Create") {
                    createStream()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || subjects.isEmpty || isCreating)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 500, height: 450)
    }
    
    private func createStream() {
        errorMessage = nil
        isCreating = true
        
        let subjectList = subjects
            .components(separatedBy: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        
        let config = StreamConfig(
            name: name,
            subjects: subjectList,
            retention: retention,
            storage: storage,
            maxAge: Double(maxAge).map { $0 },
            maxBytes: Int64(maxBytes)
        )
        
        Task {
            do {
                try await jetStreamManager.createStream(config: config)
                await MainActor.run {
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}

struct ConsumerCreatorSheet: View {
    @ObservedObject var jetStreamManager: JetStreamManager
    let streamName: String
    @Binding var isPresented: Bool
    
    @State private var name = ""
    @State private var durable = true
    @State private var deliverPolicy: DeliverPolicy = .all
    @State private var ackPolicy: AckPolicy = .explicit
    @State private var ackWait: String = "30"
    @State private var filterSubject = ""
    @State private var isCreating = false
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Create Consumer")
                        .font(.headline)
                    Text("Stream: \(streamName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") {
                    isPresented = false
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Form
            Form {
                Section("Basic Information") {
                    TextField("Consumer Name", text: $name)
                    Toggle("Durable", isOn: $durable)
                        .help("Durable consumers survive server restarts")
                }
                
                Section("Delivery Configuration") {
                    Picker("Deliver Policy", selection: $deliverPolicy) {
                        ForEach([DeliverPolicy.all, .last, .new], id: \.self) { policy in
                            Text(policy.rawValue).tag(policy)
                        }
                    }
                    .help("All: from beginning, Last: last message, New: new messages only")
                    
                    Picker("Ack Policy", selection: $ackPolicy) {
                        ForEach([AckPolicy.explicit, .all, .none], id: \.self) { policy in
                            Text(policy.rawValue).tag(policy)
                        }
                    }
                    .help("Explicit: manual ack per message, All: ack all up to this, None: no ack needed")
                    
                    TextField("Ack Wait (seconds)", text: $ackWait)
                        .help("Time to wait for acknowledgment before redelivery")
                }
                
                Section("Filtering (Optional)") {
                    TextField("Filter Subject", text: $filterSubject)
                        .help("Only receive messages matching this subject")
                }
                
                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button("Create") {
                    createConsumer()
                }
                .buttonStyle(.borderedProminent)
                .disabled(name.isEmpty || isCreating)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 500, height: 450)
    }
    
    private func createConsumer() {
        errorMessage = nil
        isCreating = true
        
        let config = ConsumerConfig(
            name: name,
            durable: durable,
            deliverPolicy: deliverPolicy,
            ackPolicy: ackPolicy,
            ackWait: Double(ackWait) ?? 30,
            filterSubject: filterSubject.isEmpty ? nil : filterSubject
        )
        
        Task {
            do {
                try await jetStreamManager.createConsumer(streamName: streamName, config: config)
                await MainActor.run {
                    isPresented = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isCreating = false
                }
            }
        }
    }
}

struct JetStreamPublishSheet: View {
    @ObservedObject var jetStreamManager: JetStreamManager
    let streamName: String
    @Binding var isPresented: Bool
    
    @State private var subject = ""
    @State private var payload = ""
    @State private var isPublishing = false
    @State private var publishResult: PublishAck?
    @State private var errorMessage: String?
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                VStack(alignment: .leading) {
                    Text("Publish to JetStream")
                        .font(.headline)
                    Text("Stream: \(streamName)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("Done") {
                    isPresented = false
                }
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Form
            Form {
                Section("Message") {
                    TextField("Subject", text: $subject)
                    TextEditor(text: $payload)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 150)
                        .border(Color.secondary.opacity(0.2))
                }
                
                if let result = publishResult {
                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Label("Published Successfully", systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                            Text("Stream: \(result.stream), Sequence: \(result.sequence)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            if result.duplicate {
                                Text("(Duplicate detected)")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                }
                
                if let error = errorMessage {
                    Section {
                        Label(error, systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .scrollContentBackground(.hidden)
            
            Divider()
            
            // Footer
            HStack {
                Spacer()
                Button("Publish") {
                    publishMessage()
                }
                .buttonStyle(.borderedProminent)
                .disabled(subject.isEmpty || payload.isEmpty || isPublishing)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
        }
        .frame(width: 500, height: 400)
    }
    
    private func publishMessage() {
        errorMessage = nil
        publishResult = nil
        isPublishing = true
        
        Task {
            do {
                let ack = try await jetStreamManager.publish(subject: subject, payload: payload)
                await MainActor.run {
                    publishResult = ack
                    isPublishing = false
                    // Clear form
                    subject = ""
                    payload = ""
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isPublishing = false
                }
            }
        }
    }
}
