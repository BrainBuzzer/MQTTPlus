//
//  MockBrokerMetricsProvider.swift
//  MQTT Plus
//
//  Mock data provider for testing broker inspector views
//  Simulates real-time metric updates with realistic spikes
//

import Foundation
import Combine
import SwiftUI

// MARK: - Mock Broker Metrics Provider

/// Observable provider that simulates real-time broker metrics
/// Updates at 1Hz with occasional spikes in lag/memory
@MainActor
public final class MockBrokerMetricsProvider: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public var selectedBrokerType: BrokerType = .nats
    @Published public var natsMetrics: NatsMetrics
    @Published public var redisMetrics: RedisMetrics
    @Published public var kafkaMetrics: KafkaMetrics
    @Published public var rabbitmqMetrics: RabbitMQMetrics
    
    // History for sparklines
    @Published public var natsLagHistory: MetricHistory
    @Published public var natsMsgHistory: MetricHistory
    @Published public var redisOpsHistory: MetricHistory
    @Published public var redisMemoryHistory: MetricHistory
    @Published public var kafkaLagHistory: MetricHistory
    @Published public var kafkaUrpHistory: MetricHistory
    @Published public var rabbitmqPublishHistory: MetricHistory
    @Published public var rabbitmqDeliverHistory: MetricHistory
    
    // MARK: - Private Properties
    
    private var updateTimer: Timer?
    private var spikeTimer: Timer?
    private var tickCount: Int = 0
    
    // Base values for simulation
    private var baseNatsMsgCount: UInt64 = 1_000_000
    private var baseNatsLag: UInt64 = 50
    private var baseRedisOps: Int = 15000
    private var baseRedisMemory: UInt64 = 512_000_000
    private var baseKafkaLag: Int64 = 500
    
    // Spike state
    private var isInLagSpike = false
    private var isInMemorySpike = false
    
    // MARK: - Initialization
    
    public init() {
        // Initialize metrics with default values
        self.natsMetrics = NatsMetrics(
            streamName: "ORDERS",
            storageType: .file,
            msgCount: 1_000_000,
            byteCount: 256_000_000,
            consumerLag: 50,
            slowConsumerCount: 0
        )
        
        self.redisMetrics = RedisMetrics(
            usedMemoryHuman: "512.00M",
            usedMemoryBytes: 512_000_000,
            instantaneousOpsPerSec: 15000,
            connectedClients: 42,
            memFragmentationRatio: 1.12,
            totalNetInputBytes: 1_500_000_000
        )
        
        self.kafkaMetrics = KafkaMetrics(
            partitionCount: 12,
            underReplicatedPartitions: 0,
            consumerGroupLag: 500,
            isrShrinkRate: 0.0,
            logEndOffset: 5_000_000
        )
        
        self.rabbitmqMetrics = RabbitMQMetrics(
            messagesPublished: 1_000_000,
            messagesDelivered: 995_000,
            bytesPublished: 256_000_000,
            bytesDelivered: 254_720_000,
            channelCount: 8,
            consumerCount: 12
        )
        
        // Initialize history containers
        self.natsLagHistory = MetricHistory(maxPoints: 60)
        self.natsMsgHistory = MetricHistory(maxPoints: 60)
        self.redisOpsHistory = MetricHistory(maxPoints: 60)
        self.redisMemoryHistory = MetricHistory(maxPoints: 60)
        self.kafkaLagHistory = MetricHistory(maxPoints: 60)
        self.kafkaUrpHistory = MetricHistory(maxPoints: 60)
        self.rabbitmqPublishHistory = MetricHistory(maxPoints: 60)
        self.rabbitmqDeliverHistory = MetricHistory(maxPoints: 60)
        
        // Pre-populate history with initial values
        for _ in 0..<30 {
            natsLagHistory.append(Double(baseNatsLag) + Double.random(in: -10...10))
            natsMsgHistory.append(Double(baseNatsMsgCount))
            redisOpsHistory.append(Double(baseRedisOps) + Double.random(in: -500...500))
            redisMemoryHistory.append(Double(baseRedisMemory))
            kafkaLagHistory.append(Double(baseKafkaLag) + Double.random(in: -50...50))
            kafkaUrpHistory.append(0)
            rabbitmqPublishHistory.append(250.0 + Double.random(in: -20...20))
            rabbitmqDeliverHistory.append(245.0 + Double.random(in: -20...20))
        }
        
        // Start update timers
        startTimers()
    }
    
    deinit {
        // Timer invalidation is safe from any thread
        updateTimer?.invalidate()
        spikeTimer?.invalidate()
    }
    
    // MARK: - Timer Management
    
    private func startTimers() {
        // Main update timer - 1Hz
        updateTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.updateMetrics()
            }
        }
        
        // Spike timer - random spikes every 5-15 seconds
        scheduleNextSpike()
    }
    
    private func stopTimers() {
        updateTimer?.invalidate()
        updateTimer = nil
        spikeTimer?.invalidate()
        spikeTimer = nil
    }
    
    private func scheduleNextSpike() {
        let delay = Double.random(in: 5...15)
        spikeTimer = Timer.scheduledTimer(withTimeInterval: delay, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.triggerSpike()
                self?.scheduleNextSpike()
            }
        }
    }
    
    // MARK: - Metric Updates
    
    private func updateMetrics() {
        tickCount += 1
        
        updateNatsMetrics()
        updateRedisMetrics()
        updateKafkaMetrics()
    }
    
    private func updateNatsMetrics() {
        // Gradual message count increase
        baseNatsMsgCount += UInt64.random(in: 10...100)
        
        // Lag with noise (higher during spikes)
        var currentLag = baseNatsLag
        if isInLagSpike {
            currentLag = UInt64.random(in: 5000...15000)
        } else {
            currentLag = baseNatsLag + UInt64.random(in: 0...100)
        }
        
        // Slow consumers during high lag
        let slowConsumers = currentLag > 5000 ? Int.random(in: 1...3) : 0
        
        natsMetrics = NatsMetrics(
            streamName: "ORDERS",
            storageType: .file,
            msgCount: baseNatsMsgCount,
            byteCount: baseNatsMsgCount * 256,
            consumerLag: currentLag,
            slowConsumerCount: slowConsumers
        )
        
        // Update history
        natsLagHistory.append(Double(currentLag))
        natsMsgHistory.append(Double(baseNatsMsgCount))
    }
    
    private func updateRedisMetrics() {
        // Ops with variance
        let currentOps = baseRedisOps + Int.random(in: -1000...1000)
        
        // Memory with slight growth during spikes
        var currentMemory = baseRedisMemory
        var fragRatio = 1.12 + Double.random(in: -0.05...0.05)
        
        if isInMemorySpike {
            currentMemory = baseRedisMemory + UInt64.random(in: 100_000_000...300_000_000)
            fragRatio = Double.random(in: 1.8...2.5)
        }
        
        redisMetrics = RedisMetrics(
            usedMemoryHuman: ByteCountFormatter.string(fromByteCount: Int64(currentMemory), countStyle: .binary),
            usedMemoryBytes: currentMemory,
            instantaneousOpsPerSec: max(0, currentOps),
            connectedClients: 42 + Int.random(in: -5...5),
            memFragmentationRatio: fragRatio,
            totalNetInputBytes: 1_500_000_000 + UInt64(tickCount) * 10000
        )
        
        // Update history
        redisOpsHistory.append(Double(currentOps))
        redisMemoryHistory.append(Double(currentMemory) / 1_000_000) // MB for chart
    }
    
    private func updateKafkaMetrics() {
        // Gradual offset increase
        let currentOffset = 5_000_000 + Int64(tickCount * 100)
        
        // Lag with variance
        var currentLag = baseKafkaLag + Int64.random(in: -100...100)
        var urps = 0
        var shrinkRate = 0.0
        
        if isInLagSpike {
            currentLag = Int64.random(in: 10000...50000)
            urps = Int.random(in: 1...3)
            shrinkRate = Double.random(in: 0.05...0.15)
        }
        
        kafkaMetrics = KafkaMetrics(
            partitionCount: 12,
            underReplicatedPartitions: urps,
            consumerGroupLag: currentLag,
            isrShrinkRate: shrinkRate,
            logEndOffset: currentOffset
        )
        
        // Update history
        kafkaLagHistory.append(Double(currentLag))
        kafkaUrpHistory.append(Double(urps))
    }
    
    // MARK: - Spike Simulation
    
    private func triggerSpike() {
        // Randomly choose which type of spike
        let spikeType = Int.random(in: 0...2)
        
        switch spikeType {
        case 0:
            // Lag spike (affects NATS and Kafka)
            isInLagSpike = true
            Task {
                try? await Task.sleep(for: .seconds(Double.random(in: 3...8)))
                await MainActor.run {
                    self.isInLagSpike = false
                }
            }
        case 1:
            // Memory spike (affects Redis)
            isInMemorySpike = true
            Task {
                try? await Task.sleep(for: .seconds(Double.random(in: 2...5)))
                await MainActor.run {
                    self.isInMemorySpike = false
                }
            }
        default:
            // Both spikes
            isInLagSpike = true
            isInMemorySpike = true
            Task {
                try? await Task.sleep(for: .seconds(Double.random(in: 4...10)))
                await MainActor.run {
                    self.isInLagSpike = false
                    self.isInMemorySpike = false
                }
            }
        }
    }
    
    // MARK: - Public API
    
    /// Get unified broker metrics for the selected type
    public var currentMetrics: BrokerMetrics {
        switch selectedBrokerType {
        case .nats:
            return .nats(natsMetrics)
        case .redis:
            return .redis(redisMetrics)
        case .kafka:
            return .kafka(kafkaMetrics)
        case .rabbitmq:
            return .rabbitmq(rabbitmqMetrics)
        }
    }
    
    /// Reset metrics to baseline values
    public func reset() {
        baseNatsMsgCount = 1_000_000
        baseNatsLag = 50
        baseRedisOps = 15000
        baseRedisMemory = 512_000_000
        baseKafkaLag = 500
        isInLagSpike = false
        isInMemorySpike = false
        tickCount = 0
    }
}
