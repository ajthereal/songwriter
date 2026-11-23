import SwiftUI

struct ScrollOffsetKey: PreferenceKey {
    static var defaultValue: CGPoint = .zero
    static func reduce(value: inout CGPoint, nextValue: () -> CGPoint) { value = nextValue() }
}

/// Holds the latest scroll offset and viewport size without triggering view updates.
final class ScrollTracker {
    var offset: CGPoint = .zero
    var size: CGSize = .zero
    /// Offset changes before this time are treated as programmatic (not a user scroll).
    var ignoreUntil = Date.distantPast
    /// Called with the previous and new offset whenever the scroll offset changes.
    var onChange: ((CGPoint, CGPoint) -> Void)?
}

struct ScrollRequest: Equatable {
    var token: Int
    var x: CGFloat?
    var y: CGFloat?
}

/// A two axis scroll view with a fixed left column, a fixed top strip and an optional fixed bottom strip
/// that follow the scroll offset of the main content.
struct Scroll2D<Content: View, Left: View, Top: View, Corner: View, Bottom: View>: View {
    let contentSize: CGSize
    let leftWidth: CGFloat
    let topHeight: CGFloat
    let bottomHeight: CGFloat
    let request: ScrollRequest?
    let tracker: ScrollTracker?
    let content: () -> Content
    let left: () -> Left
    let top: () -> Top
    let corner: () -> Corner
    let bottom: () -> Bottom

    @State var offset: CGPoint = .zero
    let space = "scroll2d"
    let step: CGFloat = 25

    init(contentSize: CGSize, leftWidth: CGFloat, topHeight: CGFloat, bottomHeight: CGFloat = 0,
         request: ScrollRequest? = nil, tracker: ScrollTracker? = nil,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder left: @escaping () -> Left,
         @ViewBuilder top: @escaping () -> Top,
         @ViewBuilder corner: @escaping () -> Corner,
         @ViewBuilder bottom: @escaping () -> Bottom) {
        self.contentSize = contentSize
        self.leftWidth = leftWidth
        self.topHeight = topHeight
        self.bottomHeight = bottomHeight
        self.request = request
        self.tracker = tracker
        self.content = content
        self.left = left
        self.top = top
        self.corner = corner
        self.bottom = bottom
    }

    private var totalWidth: CGFloat { leftWidth + contentSize.width }
    private var totalHeight: CGFloat { topHeight + contentSize.height + bottomHeight }

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                scroller
                topStrip(geo: geo)
                leftStrip(geo: geo)
                bottomStrip(geo: geo)
                corner()
                    .frame(width: leftWidth, height: topHeight)
            }
            .clipped()
            .onAppear { tracker?.size = geo.size }
            .onChange(of: geo.size) { _, newSize in tracker?.size = newSize }
        }
    }

    private var scroller: some View {
        ScrollViewReader { proxy in
            ScrollView([.horizontal, .vertical], showsIndicators: true) {
                ZStack(alignment: .topLeading) {
                    GeometryReader { g in
                        Color.clear.preference(key: ScrollOffsetKey.self, value: g.frame(in: .named(space)).origin)
                    }
                    .frame(width: 1, height: 1)
                    markers
                    content()
                        .frame(width: contentSize.width, height: contentSize.height, alignment: .topLeading)
                        .offset(x: leftWidth, y: topHeight)
                }
                .frame(width: totalWidth, height: totalHeight, alignment: .topLeading)
            }
            .coordinateSpace(name: space)
            .onPreferenceChange(ScrollOffsetKey.self) { value in
                let old = tracker?.offset ?? .zero
                tracker?.offset = value
                if value != offset { offset = value }
                if value != old { tracker?.onChange?(old, value) }
            }
            .onChange(of: request) { _, newValue in
                guard let r = newValue else { return }
                if let x = r.x {
                    let k = max(0, Int(x / step))
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo("x\(k)", anchor: .leading) }
                }
                if let y = r.y {
                    let k = max(0, Int(y / step))
                    withAnimation(.easeOut(duration: 0.2)) { proxy.scrollTo("y\(k)", anchor: .top) }
                }
            }
        }
    }

    /// Invisible anchors every 25 points so the view can be scrolled programmatically.
    private var markers: some View {
        ZStack(alignment: .topLeading) {
            ForEach(0..<(Int(totalWidth / step) + 1), id: \.self) { i in
                Color.clear.frame(width: 1, height: 1).offset(x: CGFloat(i) * step, y: 0).id("x\(i)")
            }
            ForEach(0..<(Int(totalHeight / step) + 1), id: \.self) { i in
                Color.clear.frame(width: 1, height: 1).offset(x: 0, y: CGFloat(i) * step).id("y\(i)")
            }
        }
        .allowsHitTesting(false)
    }

    private func topStrip(geo: GeometryProxy) -> some View {
        ZStack(alignment: .topLeading) {
            top()
                .frame(width: contentSize.width, height: topHeight, alignment: .topLeading)
                .offset(x: offset.x)
        }
        .frame(width: max(0, geo.size.width - leftWidth), height: topHeight, alignment: .topLeading)
        .background(Theme.paper)
        .clipped()
        .offset(x: leftWidth, y: 0)
    }

    private func leftStrip(geo: GeometryProxy) -> some View {
        ZStack(alignment: .topLeading) {
            left()
                .frame(width: leftWidth, height: contentSize.height, alignment: .topLeading)
                .offset(y: offset.y)
        }
        .frame(width: leftWidth, height: max(0, geo.size.height - topHeight - bottomHeight), alignment: .topLeading)
        .background(Theme.paper)
        .clipped()
        .offset(x: 0, y: topHeight)
    }

    private func bottomStrip(geo: GeometryProxy) -> some View {
        ZStack(alignment: .topLeading) {
            if bottomHeight > 0 {
                bottom()
                    .frame(width: contentSize.width, height: bottomHeight, alignment: .topLeading)
                    .offset(x: offset.x)
            }
        }
        .frame(width: max(0, geo.size.width - leftWidth), height: bottomHeight, alignment: .topLeading)
        .background(Theme.paper)
        .clipped()
        .offset(x: leftWidth, y: max(0, geo.size.height - bottomHeight))
        .opacity(bottomHeight > 0 ? 1 : 0)
        .allowsHitTesting(bottomHeight > 0)
    }
}

extension Scroll2D where Bottom == EmptyView {
    init(contentSize: CGSize, leftWidth: CGFloat, topHeight: CGFloat, request: ScrollRequest? = nil, tracker: ScrollTracker? = nil,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder left: @escaping () -> Left,
         @ViewBuilder top: @escaping () -> Top,
         @ViewBuilder corner: @escaping () -> Corner) {
        self.init(contentSize: contentSize, leftWidth: leftWidth, topHeight: topHeight, bottomHeight: 0, request: request, tracker: tracker,
                  content: content, left: left, top: top, corner: corner, bottom: { EmptyView() })
    }
}
