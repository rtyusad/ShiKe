import Network
import Foundation
import OSLog
/// 网络状态监控
/// 用于弱网提示、蜂窝网络用量确认、自适应超时
@Observable
final class NetworkMonitor {
    static let shared = NetworkMonitor()

    enum ConnectionType: String {
        case wifi
        case cellular
        case wired
        case unknown
    }

    private let monitor = NWPathMonitor()
    private let queue = DispatchQueue(label: "com.shike.network-monitor")

    private(set) var connectionType: ConnectionType = .unknown

    /// 是否为蜂窝网络（按流量计费）
    var isExpensive: Bool {
        connectionType == .cellular
    }

    /// 是否为低数据模式
    private(set) var isConstrained: Bool = false

    /// 是否有网络连接
    private(set) var isConnected: Bool = false

    /// 确认网络是否可用（MVP: 蜂窝网络不阻断，仅记录日志）
    func confirmIfExpensive() -> Bool {
        guard isConnected else { return false }
        if isExpensive {
            Logger.lifecycle.info("当前使用蜂窝网络，数据用量可能较大")
        }
        return true
    }

    // MARK: - 生命周期

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            self?.update(path: path)
        }
        monitor.start(queue: queue)
    }

    func stop() {
        monitor.cancel()
    }

    // MARK: - 私有

    private func update(path: NWPath) {
        let connected = path.status == .satisfied
        let constrained = path.isConstrained
        let connection: ConnectionType = {
            if path.usesInterfaceType(.wifi) { return .wifi }
            if path.usesInterfaceType(.cellular) { return .cellular }
            if path.usesInterfaceType(.wiredEthernet) { return .wired }
            return .unknown
        }()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.isConnected = connected
            self.isConstrained = constrained
            self.connectionType = connection
            Logger.lifecycle.debug("网络状态: \(self.connectionType.rawValue) (connected: \(self.isConnected))")
        }
    }
}
