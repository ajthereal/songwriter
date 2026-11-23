import SwiftUI
import UIKit

/// Holds the latest scroll offset and viewport size without triggering view updates.
final class ScrollTracker {
    /// Negative of the scroll offset (so the content origin relative to the viewport).
    var offset: CGPoint = .zero
    /// Full size of the Scroll2D view (including the fixed left column and top strip).
    var size: CGSize = .zero
    /// Called when the user (not code) moves the content horizontally or vertically.
    var onUserScroll: (() -> Void)?
}

struct ScrollRequest: Equatable {
    var token: Int
    var x: CGFloat?
    var y: CGFloat?
}

/// A two axis scroll view with a fixed left column, a fixed top strip and an optional fixed bottom strip.
/// One UIScrollView is the single source of truth: the strips are repositioned directly from its
/// offset in scrollViewDidScroll, so they can never drift from the content.
struct Scroll2D<Content: View, Left: View, Top: View, Corner: View, Bottom: View>: UIViewControllerRepresentable {
    let contentSize: CGSize
    let leftWidth: CGFloat
    let topHeight: CGFloat
    let bottomHeight: CGFloat
    let request: ScrollRequest?
    let tracker: ScrollTracker?
    let onPinch: ((CGFloat, Bool) -> Void)?
    let content: () -> Content
    let left: () -> Left
    let top: () -> Top
    let corner: () -> Corner
    let bottom: () -> Bottom

    init(contentSize: CGSize, leftWidth: CGFloat, topHeight: CGFloat, bottomHeight: CGFloat = 0,
         request: ScrollRequest? = nil, tracker: ScrollTracker? = nil,
         onPinch: ((CGFloat, Bool) -> Void)? = nil,
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
        self.onPinch = onPinch
        self.content = content
        self.left = left
        self.top = top
        self.corner = corner
        self.bottom = bottom
    }

    func makeUIViewController(context: Context) -> Scroll2DController {
        let c = Scroll2DController()
        apply(to: c)
        return c
    }

    func updateUIViewController(_ c: Scroll2DController, context: Context) {
        apply(to: c)
    }

    private func apply(to c: Scroll2DController) {
        c.tracker = tracker
        c.onPinch = onPinch
        c.contentHost.rootView = AnyView(content())
        c.topHost.rootView = AnyView(top().background(Theme.paper))
        c.leftHost.rootView = AnyView(left().background(Theme.paper))
        c.cornerHost.rootView = AnyView(corner())
        c.bottomHost.rootView = AnyView(bottom().background(Theme.paper))
        c.configure(contentSize: contentSize, leftWidth: leftWidth, topHeight: topHeight, bottomHeight: bottomHeight)
        c.handle(request: request)
    }
}

extension Scroll2D where Bottom == EmptyView {
    init(contentSize: CGSize, leftWidth: CGFloat, topHeight: CGFloat, request: ScrollRequest? = nil, tracker: ScrollTracker? = nil,
         onPinch: ((CGFloat, Bool) -> Void)? = nil,
         @ViewBuilder content: @escaping () -> Content,
         @ViewBuilder left: @escaping () -> Left,
         @ViewBuilder top: @escaping () -> Top,
         @ViewBuilder corner: @escaping () -> Corner) {
        self.init(contentSize: contentSize, leftWidth: leftWidth, topHeight: topHeight, bottomHeight: 0,
                  request: request, tracker: tracker, onPinch: onPinch,
                  content: content, left: left, top: top, corner: corner, bottom: { EmptyView() })
    }
}

final class Scroll2DController: UIViewController, UIScrollViewDelegate, UIGestureRecognizerDelegate {
    let scroll = UIScrollView()
    let topClip = UIView()
    let leftClip = UIView()
    let bottomClip = UIView()
    let contentHost = UIHostingController(rootView: AnyView(EmptyView()))
    let topHost = UIHostingController(rootView: AnyView(EmptyView()))
    let leftHost = UIHostingController(rootView: AnyView(EmptyView()))
    let cornerHost = UIHostingController(rootView: AnyView(EmptyView()))
    let bottomHost = UIHostingController(rootView: AnyView(EmptyView()))

    var tracker: ScrollTracker?
    var onPinch: ((CGFloat, Bool) -> Void)?

    private var contentSize = CGSize.zero
    private var leftWidth: CGFloat = 0
    private var topHeight: CGFloat = 0
    private var bottomHeight: CGFloat = 0
    private var lastToken: Int?
    private var pending: ScrollRequest?
    private var lastOffsetX: CGFloat = 0

    override func viewDidLoad() {
        super.viewDidLoad()
        view.clipsToBounds = true
        view.backgroundColor = .clear

        scroll.delegate = self
        scroll.contentInsetAdjustmentBehavior = .never
        scroll.showsHorizontalScrollIndicator = true
        scroll.showsVerticalScrollIndicator = true
        scroll.isDirectionalLockEnabled = true
        scroll.delaysContentTouches = false
        scroll.bounces = true
        scroll.backgroundColor = .clear
        view.addSubview(scroll)

        for clip in [topClip, leftClip, bottomClip] {
            clip.clipsToBounds = true
            clip.backgroundColor = .clear
            view.addSubview(clip)
        }

        install(contentHost, in: scroll)
        install(topHost, in: topClip)
        install(leftHost, in: leftClip)
        install(bottomHost, in: bottomClip)
        install(cornerHost, in: view)

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)
    }

    private func install(_ host: UIHostingController<AnyView>, in container: UIView) {
        addChild(host)
        host.view.backgroundColor = .clear
        host.safeAreaRegions = []
        container.addSubview(host.view)
        host.didMove(toParent: self)
    }

    func configure(contentSize: CGSize, leftWidth: CGFloat, topHeight: CGFloat, bottomHeight: CGFloat) {
        self.contentSize = contentSize
        self.leftWidth = leftWidth
        self.topHeight = topHeight
        self.bottomHeight = bottomHeight
        if isViewLoaded { layoutAll() }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        layoutAll()
    }

    private func layoutAll() {
        let w = view.bounds.width
        let h = view.bounds.height
        tracker?.size = view.bounds.size
        let viewportW = max(0, w - leftWidth)
        let viewportH = max(0, h - topHeight - bottomHeight)
        scroll.frame = CGRect(x: leftWidth, y: topHeight, width: viewportW, height: viewportH)
        if scroll.contentSize != contentSize { scroll.contentSize = contentSize }
        contentHost.view.frame = CGRect(origin: .zero, size: contentSize)
        topClip.frame = CGRect(x: leftWidth, y: 0, width: viewportW, height: topHeight)
        leftClip.frame = CGRect(x: 0, y: topHeight, width: leftWidth, height: viewportH)
        bottomClip.frame = CGRect(x: leftWidth, y: max(0, h - bottomHeight), width: viewportW, height: bottomHeight)
        bottomClip.isHidden = bottomHeight <= 0
        cornerHost.view.frame = CGRect(x: 0, y: 0, width: leftWidth, height: topHeight)
        syncStrips()
        if let r = pending, scroll.bounds.width > 0, scroll.bounds.height > 0 {
            pending = nil
            handle(request: r)
        }
    }

    private func syncStrips() {
        let ox = scroll.contentOffset.x
        let oy = scroll.contentOffset.y
        topHost.view.frame = CGRect(x: -ox, y: 0, width: contentSize.width, height: topHeight)
        leftHost.view.frame = CGRect(x: 0, y: -oy, width: leftWidth, height: contentSize.height)
        bottomHost.view.frame = CGRect(x: -ox, y: 0, width: contentSize.width, height: bottomHeight)
        tracker?.offset = CGPoint(x: -ox, y: -oy)
    }

    func scrollViewDidScroll(_ scrollView: UIScrollView) {
        syncStrips()
        let x = scrollView.contentOffset.x
        defer { lastOffsetX = x }
        if abs(x - lastOffsetX) > 0.5, scrollView.isDragging || scrollView.isDecelerating || scrollView.isTracking {
            tracker?.onUserScroll?()
        }
    }

    func handle(request: ScrollRequest?) {
        guard let r = request else { return }
        if lastToken == r.token { return }
        if scroll.bounds.width <= 0 || scroll.bounds.height <= 0 {
            pending = r   // not laid out yet; applied after the first layout
            return
        }
        lastToken = r.token
        let maxX = max(0, contentSize.width - scroll.bounds.width)
        let maxY = max(0, contentSize.height - scroll.bounds.height)
        var target = scroll.contentOffset
        if let x = r.x { target.x = min(maxX, max(0, x)) }
        if let y = r.y { target.y = min(maxY, max(0, y)) }
        if target == scroll.contentOffset { return }
        // Layout may not have run yet on the first request, so animate only once the view is on screen.
        scroll.setContentOffset(target, animated: view.window != nil)
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        switch g.state {
        case .began, .changed:
            onPinch?(g.scale, false)
        case .ended, .cancelled, .failed:
            onPinch?(g.scale, true)
        default:
            break
        }
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        true
    }
}
