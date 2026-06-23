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

    /// 在蜂窝网络下提示用户确认是否继续大数据量操作
    func confirmIfExpensive() async -> Bool {
        guard isExpensive else { return true }
        // 由调用方使用 UI 确认，这里仅返回状态
        return !isExpensive
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
        isConnected = path.status == .satisfied
        isConstrained = path.isConstrained

        if path.usesInterfaceType(.wifi) {
            connectionType = .wifi
        } else if path.usesInterfaceType(.cellular) {
            connectionType = .cellular
        } else if path.usesInterfaceType(.wiredEthernet) {
            connectionType = .wired
        } else {
            connectionType = .unknown
        }

        Logger.lifecycle.debug("网络状态: \(self.connectionType.rawValue) (connected: \(self.isConnected))")
    }
}
