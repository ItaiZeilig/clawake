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

/// A wrapping row of selectable pills, for choices with more options than fit on
/// one line (the auto-off timer durations). Same look as `SegmentedPills`, but it
/// flows onto a second line instead of overflowing.
struct WrapPills: View {
    let options: [String]
    let selected: Int
    let onSelect: (Int) -> Void
    let tint: Color

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(Array(options.enumerated()), id: \.offset) { i, label in
                Button(action: { onSelect(i) }) {
                    Text(label)
                        .font(.system(size: 12, weight: i == selected ? .semibold : .regular))
                        .foregroundColor(i == selected ? .white : .secondary)
                        .padding(.horizontal, 11).padding(.vertical, 5)
                        .background(
                            RoundedRectangle(cornerRadius: 7)
                                .fill(i == selected ? tint : Color.secondary.opacity(0.12)))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A minimal left-to-right wrapping layout. Places each child on the current line
/// and drops to the next line when the next child would overflow the width.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var rowHeight: CGFloat = 0
        var totalHeight: CGFloat = 0
        var lineWidth: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > 0, x + s.width > maxWidth {
                totalHeight += rowHeight + spacing
                lineWidth = max(lineWidth, x - spacing)
                x = 0
                rowHeight = 0
            }
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
        totalHeight += rowHeight
        lineWidth = max(lineWidth, x - spacing)
        let width = maxWidth.isFinite ? maxWidth : max(0, lineWidth)
        return CGSize(width: width, height: totalHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0
        for v in subviews {
            let s = v.sizeThatFits(.unspecified)
            if x > bounds.minX, x + s.width > bounds.maxX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            v.place(at: CGPoint(x: x, y: y), anchor: .topLeading, proposal: ProposedViewSize(s))
            x += s.width + spacing
            rowHeight = max(rowHeight, s.height)
        }
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
