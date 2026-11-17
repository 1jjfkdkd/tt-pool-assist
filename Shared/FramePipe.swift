import Foundation

/// 共享容器里的「最新一帧」读写。
/// 写入用临时文件 + replaceItem，避免主 App 读到半截 JPEG。
public enum FramePipe {

    private static var writeSeq: UInt64 = 0

    /// 扩展侧调用：把一帧 JPEG 写进 App Group
    public static func write(jpeg: Data, width: Int, height: Int) -> Bool {
        guard let dir = AssistConst.containerURL() else { return false }
        let frameURL = dir.appendingPathComponent(AssistConst.frameFileName)
        let metaURL = dir.appendingPathComponent(AssistConst.metaFileName)
        let tmpURL = dir.appendingPathComponent("frame.tmp")

        do {
            try jpeg.write(to: tmpURL, options: .atomic)
            if FileManager.default.fileExists(atPath: frameURL.path) {
                _ = try FileManager.default.replaceItemAt(frameURL, withItemAt: tmpURL)
            } else {
                try FileManager.default.moveItem(at: tmpURL, to: frameURL)
            }

            writeSeq &+= 1
            let meta = FrameMeta(seq: writeSeq,
                                 width: width,
                                 height: height,
                                 timestamp: Date().timeIntervalSince1970)
            let data = try JSONEncoder().encode(meta)
            try data.write(to: metaURL, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    /// 主 App 侧调用：读取最新帧（seq 与上次相同则返回 nil，避免重复渲染）
    public static func readLatest(lastSeq: UInt64) -> (image: Data, meta: FrameMeta)? {
        guard let metaURL = AssistConst.metaURL(),
              let frameURL = AssistConst.frameURL() else { return nil }
        guard let metaData = try? Data(contentsOf: metaURL),
              let meta = try? JSONDecoder().decode(FrameMeta.self, from: metaData) else { return nil }
        if meta.seq == lastSeq { return nil }
        guard let jpeg = try? Data(contentsOf: frameURL) else { return nil }
        return (jpeg, meta)
    }

    /// 清空共享帧（停止广播时调用）
    public static func clear() {
        guard let dir = AssistConst.containerURL() else { return }
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(AssistConst.frameFileName))
        try? FileManager.default.removeItem(at: dir.appendingPathComponent(AssistConst.metaFileName))
    }
}
