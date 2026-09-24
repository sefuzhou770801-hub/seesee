import SwiftUI

/// 设置窗观察 QueueStore，把片库路径、未连接和搬移进度同步进设置页模型。
struct DigestSettingsLiveView: View {
    @ObservedObject var store: QueueStore
    @StateObject private var model: DigestSettingsModel

    init(store: QueueStore) {
        self.store = store
        _model = StateObject(wrappedValue: DigestSettingsModel(mediaFolder: store.mediaFolder))
    }

    var body: some View {
        DigestSettingsView(model: model)
            .onAppear(perform: syncFromStore)
            .onReceive(store.objectWillChange) { _ in
                syncFromStore()
            }
    }

    private func syncFromStore() {
        model.mediaFolder = store.mediaFolder
        model.isMediaFolderDisconnected = store.isMediaFolderDisconnected
        model.mediaFolderMoveProgress = store.mediaFolderMoveProgress
        model.mediaFolderMoveFailure = store.mediaFolderMoveMessage
        model.onChangeMediaFolder = { [store] in
            store.presentMediaFolderPicker()
        }
    }
}
