//
//  RealBrokerMetricsProvider.swift
//  MQTT Plus
//
//  Real-time metrics provider that extracts data from actual broker connections
//  Uses ConnectionManager's client instances to fetch live server stats
//

import Foundation
import Combine
import SwiftUI

// MARK: - Real Broker Metrics Provider

/// Observable provider that fetches real metrics from connected brokers
@MainActor
public final class RealBrokerMetricsProvider: ObservableObject {
    
    // MARK: - Published Properties
    
    @Published public var brokerType: BrokerType = .nats
    @Published public var natsMetrics: NatsMetrics = NatsMetrics()
    @Published public var redisMetrics: RedisMetrics = RedisMetrics()
    @Published public var kafkaMetrics: KafkaMetrics = KafkaMetrics()
    @Published public var rabbitmqMetrics: RabbitMQMetrics = RabbitMQMetrics()
    
    // History for sparklines
    @Published public var natsLagHistory: MetricHistory = MetricHistory(maxPoints: 60)
    @Published public var natsMsgHistory: MetricHistory = MetricHistory(maxPoints: 60)
    @Published public var redisOpsHistory: MetricHistory = MetricHistory(maxPoints: 60)
    @Published public var redisMemoryHistory: MetricHistory = MetricHistory(maxPoints: 60)
    @Published public var kafkaLagHistory: MetricHistory = MetricHistory(maxPoints: 60)
    @Published public var kafkaUrpHistory: MetricHistory = MetricHistory(maxPoints: 60)
    @Published public var rabbitmqPublishHistory: MetricHistory = MetricHistory(maxPoints: 60)
    @Published public var rabbitmqDeliverHistory: MetricHistory = MetricHistory(maxPoints: 60)
    
    // MARK: - Private Properties
    
    private weak var connectionManager: ConnectionManager?
    private var updateTimer: Timer?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init(connectionManager: ConnectionManager) {
        self.connectionManager = connectionManager
        
        // Subscribe to stream/consumer updates (JetStream)
        connectionManager.$streams
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recomputeNatsMetrics()
            }
            .store(in: &cancellables)

        connectionManager.$consumers
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.recomputeNatsMetrics()
            }
            .store(in: &cancellables)
        
        // Subscribe to provider changes
        connectionManager.$currentProvider
            .receive(on: DispatchQueue.main)
            .sink { [weak self] provider in
                self?.updateBrokerType(from: provider)
            }
            .store(in: &cancellables)
        
        // Start periodic refresh
        startPeriodicRefresh()
    }
    
    deinit {
        updateTimer?.invalidate()
    }
    
    // MARK: - Timer Management
    
    private func startPeriodicRefresh() {
        updateTimer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in
                await self?.refreshMetrics()
            }
        }
    }
    
    // MARK: - Metric Updates
    
    private func updateBrokerType(from provider: MQProviderKind?) {
        guard let provider = provider else { return }
        switch provider {
        case .nats: brokerType = .nats
        case .redis: brokerType = .redis
        case .kafka: brokerType = .kafka
        case .rabbitmq: brokerType = .rabbitmq
        }
    }
    
    private func recomputeNatsMetrics() {
        guard brokerType == .nats, let manager = connectionManager else { return }

        guard manager.mode == .jetstream else {
            natsMetrics = NatsMetrics(streamName: "JetStream disabled")
            return
        }

        let streams = manager.streams
        guard !streams.isEmpty else {
            natsMetrics = NatsMetrics(streamName: "No streams")
            return
        }

        var totalMsgs: UInt64 = 0
        var totalBytes: UInt64 = 0
        for stream in streams {
            totalMsgs += stream.messageCount
            totalBytes += stream.byteCount
        }

        let totalPending: UInt64 = manager.consumers.values
            .flatMap { $0 }
            .reduce(0) { $0 + $1.pending }

        let slowConsumers = manager.consumers.values
            .flatMap { $0 }
            .filter { $0.pending > 1000 }
            .count

        let firstStream = streams.first!
        natsMetrics = NatsMetrics(
            streamName: streams.count == 1 ? firstStream.name : "\(streams.count) streams",
            storageType: firstStream.storage,
            msgCount: totalMsgs,
            byteCount: totalBytes,
            consumerLag: totalPending,
            slowConsumerCount: slowConsumers
        )

        natsMsgHistory.append(Double(totalMsgs))
        natsLagHistory.append(Double(totalPending))
    }
    
    private func refreshMetrics() async {
        guard let manager = connectionManager,
              manager.connectionState == .connected else { return }
        
        switch brokerType {
        case .nats:
            await refreshNatsMetrics()
        case .redis:
            await refreshRedisMetrics()
        case .kafka:
            await refreshKafkaMetrics()
        case .rabbitmq:
            await refreshRabbitMQMetrics()
        }
    }
    
    // MARK: - NATS Metrics
    
    private func refreshNatsMetrics() async {
        guard let manager = connectionManager else { return }
        
        // Refresh streams if in JetStream mode
        if manager.mode == .jetstream {
            await manager.refreshStreams()
        }
    }
    
    // MARK: - Redis Metrics
    
    private func refreshRedisMetrics() async {
        guard let manager = connectionManager else { return }
        guard let redisClient = manager.activeClient as? RedisClient else { return }

        do {
            let metrics = try await redisClient.fetchServerMetrics()
            redisMetrics = metrics
            redisOpsHistory.append(Double(metrics.instantaneousOpsPerSec))
            redisMemoryHistory.append(Double(metrics.usedMemoryBytes) / 1_000_000)
        } catch {
            redisMetrics = RedisMetrics(usedMemoryHuman: "—")
        }
    }
    
    // MARK: - Kafka Metrics
    
    private func refreshKafkaMetrics() async {
        guard let manager = connectionManager else { return }
        guard let kafkaClient = manager.activeClient as? KafkaClient else { return }

        do {
            let metrics = try await kafkaClient.fetchClusterMetrics()
            kafkaMetrics = metrics
            kafkaLagHistory.append(Double(metrics.consumerGroupLag))
            kafkaUrpHistory.append(Double(metrics.underReplicatedPartitions))
        } catch {
            kafkaMetrics = KafkaMetrics()
        }
    }
    
    // MARK: - RabbitMQ Metrics
    
    private func refreshRabbitMQMetrics() async {
        guard let manager = connectionManager else { return }
        guard let rabbitmqClient = manager.activeClient as? RabbitMQClient else { return }
        
        let metrics = rabbitmqClient.fetchMetrics()
        rabbitmqMetrics = metrics
        rabbitmqPublishHistory.append(Double(metrics.messagesPublished))
        rabbitmqDeliverHistory.append(Double(metrics.messagesDelivered))
    }
}
