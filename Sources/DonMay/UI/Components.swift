import SwiftUI

/// Một màu nhấn (xanh của logo) cho nút và thanh; ba màu ngữ nghĩa đã giảm độ bão hoà, chỉ dùng cho
/// icon nhỏ, chú giải và phần biểu đồ — để màn hình không bị đỏ/cam/xanh lá giành nhau sự chú ý.
enum Palette {
    static let accent = Color(red: 0.24, green: 0.58, blue: 0.93)
    static let safe = Color(red: 0.33, green: 0.68, blue: 0.58)
    static let warn = Color(red: 0.84, green: 0.63, blue: 0.29)
    static let alert = Color(red: 0.88, green: 0.40, blue: 0.37)
    static let neutral = Color.secondary
    static let track = Color.primary.opacity(0.08)
    static let other = Color.primary.opacity(0.22)

    static func color(_ risk: Risk) -> Color {
        switch risk {
        case .safe: safe
        case .warn: warn
        case .keep: neutral
        }
    }

    static func color(_ level: GrowthLevel) -> Color {
        switch level {
        case .spike: alert
        case .up: warn
        case .flat: neutral
        }
    }
}

struct AppLogo: View {
    let app: AppKind
    var size: CGFloat = 36
    var level: GrowthLevel = .flat

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if let icon = AppIcons.icon(for: app) {
                    Image(nsImage: icon).resizable().interpolation(.high)
                } else {
                    RoundedRectangle(cornerRadius: size * 0.22).fill(Color(red: 0.72, green: 0.25, blue: 0.18))
                        .overlay(Text("npm").font(.system(size: size * 0.3, weight: .bold)).foregroundStyle(.white))
                }
            }
            .frame(width: size, height: size)

            if level != .flat {
                GrowthBadge(level: level, size: max(size * 0.46, 14))
                    .offset(x: 4, y: 4)
            }
        }
    }
}

struct GrowthBadge: View {
    let level: GrowthLevel
    var size: CGFloat = 18

    var body: some View {
        Image(systemName: level.symbol)
            .font(.system(size: size * 0.5, weight: .heavy))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(Circle().fill(Palette.color(level)))
            .overlay(Circle().stroke(Color(nsColor: .windowBackgroundColor), lineWidth: 2))
            .help(level.title)
    }
}

extension GrowthLevel {
    /// ^^ tăng bất thường, ^ đang tăng.
    var symbol: String { self == .spike ? "chevron.up.2" : "chevron.up" }
}

/// Mũi tên chồng thay cho chữ "Tăng bất thường" / "Đang tăng"; chữ vẫn có khi rê chuột và cho VoiceOver.
struct GrowthIcon: View {
    let level: GrowthLevel
    var size: CGFloat = 12

    var body: some View {
        if level != .flat {
            Image(systemName: level.symbol)
                .font(.system(size: size, weight: .heavy))
                .foregroundStyle(Palette.color(level))
                .help(level.title)
                .accessibilityLabel(level.title)
        }
    }
}

struct Chip: View {
    let text: String
    let color: Color
    var systemImage: String?

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage).font(.system(size: 10, weight: .bold)) }
            Text(text)
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(Capsule().fill(color.opacity(0.14)))
    }
}

struct RiskChip: View {
    let risk: Risk
    var body: some View { Chip(text: risk.title, color: Palette.color(risk)) }
}

struct MeterBar: View {
    struct Segment: Identifiable {
        let id = UUID()
        let value: Double
        let color: Color
    }

    let segments: [Segment]
    var height: CGFloat = 12

    var body: some View {
        GeometryReader { geo in
            HStack(spacing: 0) {
                ForEach(segments) { segment in
                    segment.color.frame(width: max(0, geo.size.width * min(segment.value, 1)))
                }
                Spacer(minLength: 0)
            }
        }
        .frame(height: height)
        .background(Color.primary.opacity(0.08))
        .clipShape(Capsule())
    }
}

struct LegendDot: View {
    let color: Color
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 9, height: 9)
            Text(text).foregroundStyle(.secondary)
        }
        .font(.callout)
    }
}

struct Card<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 12).fill(Color(nsColor: .controlBackgroundColor)))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
    }
}

struct SectionTitle: View {
    let title: String
    var hint: String?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(title).font(.title3.weight(.semibold))
            if let hint { Text(hint).font(.callout).foregroundStyle(.secondary) }
        }
    }
}

extension View {
    func rowSurface() -> some View {
        padding(.horizontal, 16).padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(nsColor: .controlBackgroundColor))
    }
}

struct RowsContainer<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) { content }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.primary.opacity(0.08)))
    }
}
