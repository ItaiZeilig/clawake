import SwiftUI

/// A larger, brand-colored switch. Custom-drawn so it renders in previews and
/// reads as designed rather than a stock control (native Toggle renders as a
/// placeholder box under ImageRenderer).
struct BrandSwitch: View {
    let isOn: Bool
    let onColor: Color
    var size: CGFloat = 1.0

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            Capsule().fill(isOn ? onColor : Color.secondary.opacity(0.35))
            Circle()
                .fill(Color.white)
                .padding(3 * size)
                .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
        }
        .frame(width: 50 * size, height: 30 * size)
        .animation(.easeInOut(duration: 0.15), value: isOn)
    }
}

/// A small custom segmented control (pills). Custom-drawn so it renders in
/// previews and stays on-brand next to BrandSwitch.
struct SegmentedPills: View {
    let options: [String]
    let selected: Int
    let onSelect: (Int) -> Void
    let tint: Color

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, label in
                Button(action: { onSelect(i) }) {
                    Text(label)
                        .font(.system(size: 12, weight: i == selected ? .semibold : .regular))
                        .foregroundColor(i == selected ? .white : .secondary)
                        .padding(.horizontal, 12).padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(i == selected ? tint : Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}
