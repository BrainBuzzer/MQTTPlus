//
//  PublishSheet.swift
//  MQTT Plus
//
//  Created by Aditya on 10/01/26.
//

import SwiftUI

struct PublishSheet: View {
    @ObservedObject var connectionManager: ConnectionManager
    @Binding var isPresented: Bool
    
    var initialSubject: String?
    var initialPayload: String?
    
    @State private var subject = ""
    @State private var payload = ""
    @State private var isValidJSON = false
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Publish Message")
                    .font(.headline)
                
                Spacer()
                
                Button(action: { isPresented = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()
            .background(Color(nsColor: .controlBackgroundColor))
            
            Divider()
            
            // Form
            VStack(alignment: .leading, spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Subject")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    TextField("e.g., my.topic", text: $subject)
                        .textFieldStyle(.roundedBorder)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text("Payload")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        Spacer()
                        
                        if isValidJSON {
                            Label("Valid JSON", systemImage: "checkmark.circle.fill")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        
                        Button("Format JSON") {
                            formatJSON()
                        }
                        .font(.caption)
                        .disabled(!isValidJSON)
                    }
                    
                    TextEditor(text: $payload)
                        .font(.system(.body, design: .monospaced))
                        .frame(minHeight: 150)
                        .border(Color.secondary.opacity(0.3))
                        .onChange(of: payload) {
                            validateJSON()
                        }
                }
            }
            .padding()
            
            Divider()
            
            // Actions
            HStack {
                Button("Cancel") {
                    isPresented = false
                }
                .keyboardShortcut(.escape)
                
                Spacer()
                
                Button("Publish") {
                    publishMessage()
                }
                .keyboardShortcut(.return)
                .buttonStyle(.borderedProminent)
                .disabled(subject.isEmpty || payload.isEmpty)
            }
            .padding()
    }
    .frame(width: 500, height: 400)
    .onAppear {
        if let initial = initialSubject, subject.isEmpty {
            subject = initial
        }
        if let initialPayload = initialPayload, payload.isEmpty {
            payload = initialPayload
            validateJSON()
        }
    }
}
    
    private func validateJSON() {
        guard let data = payload.data(using: .utf8) else {
            isValidJSON = false
            return
        }
        isValidJSON = (try? JSONSerialization.jsonObject(with: data)) != nil
    }
    
    private func formatJSON() {
        guard let data = payload.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data),
              let prettyData = try? JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys]),
              let prettyString = String(data: prettyData, encoding: .utf8) else {
            return
        }
        payload = prettyString
    }
    
    private func publishMessage() {
        connectionManager.publish(to: subject, payload: payload)
        isPresented = false
    }
}

#Preview {
    PublishSheet(connectionManager: ConnectionManager(), isPresented: .constant(true))
}
