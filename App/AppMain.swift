import SwiftUI
import ReplayKit
import AVKit
import QuartzCore

// MARK: - App 入口

@main
struct TTPoolAssistApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}

// MARK: - 主界面

struct ContentView: View {
    @StateObject private var engine = AssistEngine()

    var body: some View {
        VStack(spacing: 14) {
            Text("TT 桌球辅助")
                .font(.title2).bold()

            // 收到的实时画面（CV 将来在这里做识别）
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Color.black)
                if let img = engine.preview {
                    Image(uiImage: img)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                } else {
                    Text(engine.status)
                        .foregroundColor(.gray)
                        .font(.footnote)
                }
            }
            .frame(height: 200)

            // 画中画宿主（PiP 内容的来源）
            PiPHostView(controller: engine.pip)
                .frame(height: 120)
                .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 12) {
                Button("开始录屏") { engine.showBroadcastPicker = true }
                    .buttonStyle(.borderedProminent)

                Button("起画中画") { engine.startPiP() }
                    .buttonStyle(.bordered)
            }

            Text(engine.status)
                .font(.caption2)
                .foregroundColor(.secondary)

            Text(engine.detectText)
                .font(.caption2)
                .foregroundColor(.orange)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text(engine.hint)
                .font(.caption2)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Spacer()
        }
        .padding()
        .sheet(isPresented: $engine.showBroadcastPicker) {
            BroadcastPickerView()
        }
        .onAppear { engine.onAppear() }
    }
}

// MARK: - 引擎：读帧 + 送 PiP

final class AssistEngine: ObservableObject {
    @Published var preview: UIImage?
    @Published var status = "等待画面…"
    @Published var detectText = "识别结果待出…"
    @Published var hint = "控制中心 → 录屏 → 选择「TT 桌球辅助」开始广播"
    @Published var showBroadcastPicker = false

    let pip = PiPController()
    private var timer: Timer?
    private var lastSeq: UInt64 = 0

    func onAppear() {
        startPolling()
    }

    private func startPolling() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.poll()
        }
    }

    private func poll() {
        guard let (data, meta) = FramePipe.readLatest(lastSeq: lastSeq) else { return }
        lastSeq = meta.seq
        guard let image = UIImage(data: data) else { return }
        preview = image
        status = "接收中 \(meta.width)×\(meta.height)  #\(meta.seq)"
        pip.enqueue(image)
        analyze(image)
    }

    /// 每 500ms 跑一次识别（Step 2 起点：台面 + 球位）
    private var lastAnalyze: CFTimeInterval = 0
    private func analyze(_ image: UIImage) {
        let now = CACurrentMediaTime()
        if now - lastAnalyze < 0.5 { return }
        lastAnalyze = now
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let table = TableDetector.detect(in: image) else {
                DispatchQueue.main.async { self?.detectText = "未识别到台面" }
                return
            }
            let balls = BallDetector.detect(in: image, table: table)
            let whites = balls.filter { $0.isWhite }
            let text: String
            if let w = whites.first {
                text = "台面 \(Int(table.rect.width))×\(Int(table.rect.height))  球 \(balls.count)  白球 (\(Int(w.center.x)),\(Int(w.center.y)))"
            } else {
                text = "台面 \(Int(table.rect.width))×\(Int(table.rect.height))  球 \(balls.count)  未找到白球"
            }
            DispatchQueue.main.async { self?.detectText = text }
        }
    }

    func startPiP() {
        pip.start()
        hint = "画中画已请求：切到 TT，窗口会自动浮起"
    }
}

// MARK: - 画中画宿主视图

struct PiPHostView: UIViewRepresentable {
    let controller: PiPController
    func makeUIView(context: Context) -> UIView { controller.makeHostView() }
    func updateUIView(_ uiView: UIView, context: Context) {}
}

// MARK: - 系统广播选择器（ReplayKit）

struct BroadcastPickerView: UIViewControllerRepresentable {
    func makeUIViewController(context: Context) -> UIViewController {
        let vc = UIViewController()
        vc.view.backgroundColor = .systemBackground

        let picker = RPSystemBroadcastPickerView(
            frame: CGRect(x: 20, y: 80, width: 240, height: 80))
        picker.preferredExtension = "com.yg.ttpoolassist.broadcast"
        picker.showsMicrophoneButton = false
        vc.view.addSubview(picker)

        let label = UILabel(frame: CGRect(x: 20, y: 180, width: 320, height: 60))
        label.numberOfLines = 0
        label.font = .systemFont(ofSize: 13)
        label.text = "点上面的按钮开始/停止广播。若列表里没有「TT 桌球辅助」，请先到 设置 → 控制中心 添加「屏幕录制」。"
        label.textColor = .secondaryLabel
        vc.view.addSubview(label)
        return vc
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
