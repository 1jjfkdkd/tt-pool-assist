import UIKit
import CoreGraphics

/// 台面几何（像素坐标，原点左上）
struct TableGeometry {
    let rect: CGRect          // 绿色台面区域
    let ballRadius: CGFloat   // 估计球半径（像素）
}

struct DetectedBall {
    let center: CGPoint
    let radius: CGFloat
    let isWhite: Bool
}

/// 台面检测：绿色阈值 + 行列投影找主体矩形。
/// 阈值来自真实截图标定（1080×2340，台面 x 258..821、y 733..1826，球径约 30px）。
enum TableDetector {

    // 标定参考（占屏比例，仅用于合理性校验/回退）
    static let refFeltX0: CGFloat = 0.239
    static let refFeltX1: CGFloat = 0.760
    static let refFeltY0: CGFloat = 0.313
    static let refFeltY1: CGFloat = 0.780
    static let refBallDiameterOverFeltWidth: CGFloat = 0.0533

    /// 把 CGImage 解成 RGBA8888 缓冲
    static func pixelBuffer(from cg: CGImage) -> (data: [UInt8], w: Int, h: Int)? {
        let w = cg.width, h = cg.height
        guard w > 0, h > 0 else { return nil }
        var buf = [UInt8](repeating: 0, count: w * h * 4)
        let ok: Bool = buf.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress,
                  let ctx = CGContext(data: base,
                                      width: w,
                                      height: h,
                                      bitsPerComponent: 8,
                                      bytesPerRow: w * 4,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            ctx.draw(cg, in: CGRect(x: 0, y: 0, width: w, height: h))
            return true
        }
        guard ok else { return nil }
        return (buf, w, h)
    }

    @inline(__always)
    static func isFelt(_ r: Int, _ g: Int, _ b: Int) -> Bool {
        g > 90 && g < 200 && g > r + 25 && g > b + 15
    }

    static func detect(in image: UIImage) -> TableGeometry? {
        guard let cg = image.cgImage, let (buf, w, h) = pixelBuffer(from: cg) else { return nil }

        var colCount = [Int](repeating: 0, count: w)
        var rowCount = [Int](repeating: 0, count: h)
        var minX = w, maxX = -1, minY = h, maxY = -1

        for y in 0..<h {
            let row = y * w * 4
            for x in 0..<w {
                let i = row + x * 4
                if isFelt(Int(buf[i]), Int(buf[i + 1]), Int(buf[i + 2])) {
                    colCount[x] += 1
                    rowCount[y] += 1
                    if x < minX { minX = x }
                    if x > maxX { maxX = x }
                    if y < minY { minY = y }
                    if y > maxY { maxY = y }
                }
            }
        }
        guard maxX > minX, maxY > minY else { return nil }

        // 用 50% 峰值做投影裁剪，滤掉零散绿色 UI 元素
        let colMax = colCount.max() ?? 0
        let rowMax = rowCount.max() ?? 0
        guard colMax > 0, rowMax > 0 else { return nil }
        var x0 = 0, x1 = w - 1, y0 = 0, y1 = h - 1
        for x in 0..<w where colCount[x] > colMax / 2 { x0 = x; break }
        for x in stride(from: w - 1, through: 0, by: -1) where colCount[x] > colMax / 2 { x1 = x; break }
        for y in 0..<h where rowCount[y] > rowMax / 2 { y0 = y; break }
        for y in stride(from: h - 1, through: 0, by: -1) where rowCount[y] > rowMax / 2 { y1 = y; break }

        let rect = CGRect(x: x0, y: y0, width: x1 - x0 + 1, height: y1 - y0 + 1)
        guard rect.width > 80, rect.height > 80 else { return nil }

        let r = rect.width * refBallDiameterOverFeltWidth / 2.0
        return TableGeometry(rect: rect, ballRadius: max(3, r))
    }
}

/// 球检测：台面内「非绿色 + 够亮或够饱和」的圆状斑点，取面积接近期望值者。
enum BallDetector {

    static func detect(in image: UIImage, table: TableGeometry) -> [DetectedBall] {
        guard let cg = image.cgImage, let (buf, w, _) = TableDetector.pixelBuffer(from: cg) else { return [] }

        let rect = table.rect.integral
        let x0 = max(0, Int(rect.minX)), x1 = min(w - 1, Int(rect.maxX))
        let y0 = max(0, Int(rect.minY)), y1 = min(Int(cg.height) - 1, Int(rect.maxY))
        guard x1 > x0, y1 > y0 else { return [] }

        let rw = x1 - x0 + 1, rh = y1 - y0 + 1
        var mask = [Bool](repeating: false, count: rw * rh)

        for y in 0..<rh {
            for x in 0..<rw {
                let i = ((y + y0) * w + (x + x0)) * 4
                let r = Int(buf[i]), g = Int(buf[i + 1]), b = Int(buf[i + 2])
                let mx = max(r, max(g, b)), mn = min(r, min(g, b))
                let bright = mx > 150
                let saturated = (mx - mn) > 60
                mask[y * rw + x] = !TableDetector.isFelt(r, g, b) && (bright || saturated)
            }
        }

        let expected = CGFloat.pi * table.ballRadius * table.ballRadius
        var balls: [DetectedBall] = []
        var visited = [Bool](repeating: false, count: rw * rh)

        for sy in 0..<rh {
            for sx in 0..<rw {
                let start = sy * rw + sx
                if !mask[start] || visited[start] { continue }

                var stack = [start]
                visited[start] = true
                var count = 0
                var sumX = 0, sumY = 0
                var minBX = sx, maxBX = sx, minBY = sy, maxBY = sy

                while let cur = stack.popLast() {
                    let cy = cur / rw, cx = cur % rw
                    count += 1
                    sumX += cx; sumY += cy
                    if cx < minBX { minBX = cx }
                    if cx > maxBX { maxBX = cx }
                    if cy < minBY { minBY = cy }
                    if cy > maxBY { maxBY = cy }
                    if cx > 0 { let n = cur - 1; if mask[n] && !visited[n] { visited[n] = true; stack.append(n) } }
                    if cx < rw - 1 { let n = cur + 1; if mask[n] && !visited[n] { visited[n] = true; stack.append(n) } }
                    if cy > 0 { let n = cur - rw; if mask[n] && !visited[n] { visited[n] = true; stack.append(n) } }
                    if cy < rh - 1 { let n = cur + rw; if mask[n] && !visited[n] { visited[n] = true; stack.append(n) } }
                }

                let area = CGFloat(count)
                guard area > expected * 0.35, area < expected * 2.6 else { continue }
                let bw = maxBX - minBX + 1, bh = maxBY - minBY + 1
                guard Double(min(bw, bh)) / Double(max(bw, bh)) > 0.55 else { continue }

                let cxF = CGFloat(sumX) / CGFloat(count) + CGFloat(x0)
                let cyF = CGFloat(sumY) / CGFloat(count) + CGFloat(y0)
                let radius = sqrt(area / CGFloat.pi)

                // 白球：极亮且低饱和
                let i = (Int(cyF) * w + Int(cxF)) * 4
                let r = Int(buf[i]), g = Int(buf[i + 1]), b = Int(buf[i + 2])
                let mx = max(r, max(g, b)), mn = min(r, min(g, b))
                let isWhite = mx > 200 && (mx - mn) < 30

                balls.append(DetectedBall(center: CGPoint(x: cxF, y: cyF), radius: radius, isWhite: isWhite))
            }
        }
        return balls
    }
}
