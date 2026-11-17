import Foundation

/// 两个进程（广播扩展 / 主 App）共用的常量与共享容器定位
public enum AssistConst {
    /// 必须在两个 target 的 entitlements 里都是同一个值
    public static let appGroupID = "group.com.yg.ttpoolassist"

    /// 扩展写、主 App 读的最新一帧
    public static let frameFileName = "latest.jpg"
    /// 帧元信息（宽高、时间戳、序号）
    public static let metaFileName = "latest.json"

    /// 降采样目标：保持屏幕比例，长边缩到 900px（球径仍有 ~15px，识别够用）
    public static let maxLongSide: CGFloat = 900

    /// 兼容旧字段（竖屏时实际以 maxLongSide 计算为准）
    public static let frameWidth = 480
    public static let frameHeight = 270

    /// 扩展最多每秒写多少帧（保护扩展内存与 I/O）
    public static let maxFramesPerSecond = 8

    public static func containerURL() -> URL? {
        FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupID)
    }

    public static func frameURL() -> URL? {
        containerURL()?.appendingPathComponent(frameFileName)
    }

    public static func metaURL() -> URL? {
        containerURL()?.appendingPathComponent(metaFileName)
    }
}

/// 帧元信息，主 App 靠 seq 判断有没有新帧
public struct FrameMeta: Codable {
    public var seq: UInt64
    public var width: Int
    public var height: Int
    public var timestamp: Double

    public init(seq: UInt64, width: Int, height: Int, timestamp: Double) {
        self.seq = seq
        self.width = width
        self.height = height
        self.timestamp = timestamp
    }
}
