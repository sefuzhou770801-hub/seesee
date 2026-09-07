import AppKit
import SwiftUI

/// 在主窗口存活时捕获 `openWindow`，关窗后由 AppDelegate 重建主窗口（进程不退出）。
@MainActor
enum MainWindowOpener {
    static let sceneID = "main"
    static var open: (() -> Void)?
}

/// 把 SwiftUI `openWindow` 挂到 AppDelegate 可调用的入口上。
private struct MainWindowOpenBridge: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                MainWindowOpener.open = {
                    openWindow(id: MainWindowOpener.sceneID)
                }
            }
    }
}

@main
struct ReplayApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var store = QueueStore()

    var body: some Scene {
        // 保留 WindowGroup：关最后一窗后进程仍存活（基线行为）。
        // matching 为空：外部 URL 不由 scene 新开窗；URL 入队走 AppDelegate。
        // 无窗重建走 MainWindowOpener（捕获的 openWindow），避免叠窗。
        WindowGroup(id: MainWindowOpener.sceneID) {
            ContentView()
                .environmentObject(store)
                .environmentObject(appDelegate.inbox)
                .preferredColorScheme(.dark)
                .tint(OpenMyChrome.ink)
                .background(MainWindowOpenBridge())
                .onReceive(NotificationCenter.default.publisher(for: NSApplication.willTerminateNotification)) { _ in
                    store.flushPendingSaves()
                }
        }
        .handlesExternalEvents(matching: [])
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1320, height: 820)
        .commands {
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .sidebar) {
                Button("显示或隐藏左侧栏") {
                    NotificationCenter.default.post(name: .replaySidebarToggle, object: nil)
                }
                .keyboardShortcut("s", modifiers: [.command, .control])
            }
            CommandGroup(after: .appInfo) {
                Button("打开下载文件夹") { store.revealMediaFolder() }
                Button("检查订阅更新") { store.channelWatch.pollAll() }
            }
        }

        // 应用菜单「设置…」（⌘,）：AI 密钥在这里填，侧栏无密钥提示也从这里打开。
        Settings {
            DigestSettingsView(mediaFolder: store.mediaFolder)
                .preferredColorScheme(.dark)
                .tint(OpenMyChrome.ink)
        }
        .windowResizability(.contentSize)
    }
}
