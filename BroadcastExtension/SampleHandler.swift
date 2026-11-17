import ReplayKit
import CoreImage
import QuartzCore
import UIKit

/// 广播上传扩展：把整屏画面降采样成 480x270 的 JPEG，写进 App Group 给主 App。
/// 只读画面、不接触被录的 App，任何反作弊都感知不到。
class SampleHandler: RPBroadcastSampleHandler {

    private let ciContext = CIContext(options: [.useSoftwareRenderer: false])
    private var lastWrite: CFTimeInterval = 0
    private let minInterval: CFTimeInterval = 1.0 / Double(AssistConst.maxFramesPerSecond)

    override func broadcastStarted(withSetupInfo setupInfo: [String: NSObject]?) {
        FramePipe.clear()
    }

    override func broadcastFinished() {
        FramePipe.clear()
    }

    override func processSampleBuffer(_ sampleBuffer: CMSampleBuffer, with sampleBufferType: RPSampleBufferType) {
        guard sampleBufferType == .video else { return }

        let now = CACurrentMediaTime()
        if now - lastWrite < minInterval { return }
        lastWrite = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let srcWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let srcHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        guard srcWidth > 0, srcHeight > 0 else { return }

        // 保持比例，长边缩到 maxLongSide
        let longSide = max(srcWidth, srcHeight)
        let scale = min(1.0, AssistConst.maxLongSide / longSide)
        let targetW = (srcWidth * scale).rounded()
        let targetH = (srcHeight * scale).rounded()

        var image = CIImage(cvPixelBuffer: pixelBuffer)
        image = image.transformed(by: CGAffineTransform(scaleX: targetW / srcWidth,
                                                        y: targetH / srcHeight))

        guard let cg = ciContext.createCGImage(image,
                                               from: CGRect(x: 0, y: 0, width: targetW, height: targetH))
        else { return }

        let ui = UIImage(cgImage: cg)
        guard let jpeg = ui.jpegData(compressionQuality: 0.6) else { return }

        _ = FramePipe.write(jpeg: jpeg, width: Int(targetW), height: Int(targetH))    }
}
