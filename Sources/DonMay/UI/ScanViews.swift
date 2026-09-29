import SwiftUI

/// Màn quét lần đầu: logo quét qua lại, dòng "đang quét gì", và lưới nhóm sáng dần khi đo xong.
struct ScanningView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(spacing: 22) {
            ScanRadar(size: 120)
            VStack(spacing: 6) {
                Text(state.scanPlannedTotal == 0 ? "Đang tìm các vị trí cần quét" : "Đang đo dung lượng")
                    .font(.title2.weight(.semibold))
                Text(state.scanStep.isEmpty ? "Chuẩn bị…" : state.scanStep)
                    .foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle)
                    .frame(maxWidth: 460)
            }
            VStack(spacing: 6) {
                ProgressView(value: state.scanProgress).frame(width: 360)
                if state.scanPlannedTotal > 0 {
                    Text("\(state.scanDoneTotal) / \(state.scanPlannedTotal) vị trí").font(.caption).monospacedDigit().foregroundStyle(.secondary)
                }
            }
            ScanGroupGrid()
            Text("Nếu macOS hỏi quyền truy cập Desktop, Documents hoặc Downloads, hãy bấm Cho phép. Việc quét chờ tới khi Ngài trả lời.")
                .font(.callout).foregroundStyle(.secondary).multilineTextAlignment(.center).frame(maxWidth: 420)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.regularMaterial)
    }
}

/// Mỗi nhóm một ô: mờ khi chưa tới lượt, có vòng quay khi đang quét, dấu tích và dung lượng khi xong.
struct ScanGroupGrid: View {
    @Environment(AppState.self) private var state

    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.fixed(96), spacing: 10), count: 5), spacing: 10) {
            ForEach(AppKind.allCases) { app in
                let status = status(of: app)
                VStack(spacing: 5) {
                    ZStack(alignment: .bottomTrailing) {
                        AppLogo(app: app, size: 34)
                            .opacity(status == .waiting ? 0.35 : 1)
                            .scaleEffect(status == .active ? 1.08 : 1)
                            .animation(.spring(duration: 0.35), value: status)
                        switch status {
                        case .done:
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.white, Palette.safe).font(.system(size: 14))
                                .offset(x: 4, y: 4)
                        case .active:
                            ProgressView().controlSize(.mini).offset(x: 5, y: 5)
                        case .waiting:
                            EmptyView()
                        }
                    }
                    Text(app.title).font(.caption).lineLimit(1)
                    Text(status == .waiting ? " " : Format.bytes(state.scanFound[app] ?? 0))
                        .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
                }
                .frame(width: 96)
            }
        }
    }

    private enum Status { case waiting, active, done }

    private func status(of app: AppKind) -> Status {
        if state.scanPlannedTotal == 0 {
            guard let finding = state.scanFinding,
                  let current = AppKind.allCases.firstIndex(of: finding),
                  let index = AppKind.allCases.firstIndex(of: app) else { return .waiting }
            return index == current ? .active : .waiting
        }
        let planned = state.scanPlanned[app] ?? 0
        let done = state.scanDone[app] ?? 0
        if done >= planned { return .done }
        return done > 0 || state.scanStep.hasPrefix(app.title) ? .active : .waiting
    }
}

/// Logo với một vệt quét xoay quanh — cho biết ứng dụng đang làm việc chứ không treo.
struct ScanRadar: View {
    let size: CGFloat
    @State private var angle = 0.0
    @State private var pulse = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Circle().stroke(Palette.safe.opacity(0.15), lineWidth: 6)
            Circle()
                .trim(from: 0, to: 0.22)
                .stroke(AngularGradient(colors: [Palette.safe.opacity(0), Palette.safe], center: .center),
                        style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(angle))
            Circle().stroke(Palette.safe.opacity(pulse ? 0 : 0.35), lineWidth: 2)
                .scaleEffect(pulse ? 1.35 : 1)
            if let logo = Brand.logo {
                Image(nsImage: logo).resizable().padding(size * 0.14)
            }
        }
        .frame(width: size, height: size)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(.linear(duration: 1.4).repeatForever(autoreverses: false)) { angle = 360 }
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { pulse = true }
        }
    }
}

/// Quét lại khi đã có kết quả: một dải mảnh ở đầu màn, danh sách cũ vẫn xem được.
struct ScanBanner: View {
    @Environment(AppState.self) private var state

    var body: some View {
        HStack(spacing: 12) {
            ScanRadar(size: 26)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.scanStep.isEmpty ? "Đang quét lại…" : "Đang quét lại · \(state.scanStep)")
                    .lineLimit(1).truncationMode(.middle)
                ProgressView(value: state.scanProgress).frame(maxWidth: 420)
            }
            Spacer()
            if state.scanPlannedTotal > 0 {
                Text("\(state.scanDoneTotal) / \(state.scanPlannedTotal)").monospacedDigit().foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 28).padding(.vertical, 10)
        .background(Palette.safe.opacity(0.08))
    }
}
