import UIKit

/// App 生命周期委托（处理后台进入时的清理逻辑）
final class AppDelegate: NSObject, UIApplicationDelegate {

    func applicationDidEnterBackground(_ application: UIApplication) {
        // 进入后台时清理残留临时文件
        FileCleanup().cleanupOrphanedFiles()
        Logger.lifecycle.info("App 进入后台，已清理临时文件")
    }

    func applicationWillTerminate(_ application: UIApplication) {
        // 终止前清理
        FileCleanup().cleanupOrphanedFiles()
        Logger.lifecycle.info("App 即将终止，已清理临时文件")
    }
}
