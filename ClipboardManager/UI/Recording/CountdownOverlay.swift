// ClipboardManager/UI/Recording/CountdownOverlay.swift
import AppKit
import SwiftUI

/// A full-screen, borderless, nonactivating overlay that shows a 3 → 2 → 1
/// countdown over a dim backdrop before recording begins, then calls `onDone`.
/// Esc cancels (`onCancel`). Built like `ScreenFreezeWindow` (the freeze
/// overlay) so it covers the whole target screen, sits at the shielding window
/// level, joins all spaces, and can become key to receive Esc — the behaviour
/// this menu-bar-only (LSUIElement) app relies on.
///
/// Exercised by the AppCoordinator orchestration (plan Task 6); here it just
/// needs to build, present, count down, and report completion/cancellation.
@MainActor
final class CountdownOverlay {
    private var panel: CountdownPanel?
    private var timer: Timer?

    /// Presents the countdown on `screen`, counting from `seconds` down to 1
    /// (one tick per second), then dismisses itself and calls `onDone`. Esc (or
    /// a programmatic `cancel()`) dismisses and calls `onCancel` instead.
    /// `onDone`/`onCancel` fire at most once, on the main actor.
    func show(on screen: NSScreen,
              from seconds: Int = 3,
              onDone: @escaping @MainActor () -> Void,
              onCancel: @escaping @MainActor () -> Void) {
        guard panel == nil else { return }

        var finished = false
        let value = CountdownValue(remaining: max(1, seconds))

        let p = CountdownPanel(screen: screen)
        let finishCancel: @MainActor () -> Void = { [weak self] in
            guard !finished else { return }
            finished = true
            self?.tearDown()
            onCancel()
        }
        p.onEscape = finishCancel
        p.contentView = NSHostingView(rootView: CountdownView(value: value))

        p.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
        panel = p
        Log.coordinator.info("recording countdown started from \(max(1, seconds), privacy: .public)")

        // 1s tick: decrement, and when it would pass 0, finish with onDone.
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !finished else { return }
                if value.remaining <= 1 {
                    finished = true
                    self.tearDown()
                    onDone()
                } else {
                    value.remaining -= 1
                }
            }
        }
    }

    /// Cancels an in-flight countdown without invoking either callback (used when
    /// the surrounding flow aborts for another reason).
    func cancel() {
        tearDown()
    }

    private func tearDown() {
        timer?.invalidate()
        timer = nil
        panel?.orderOut(nil)
        panel = nil
    }
}

/// Observable holder for the visible count so the SwiftUI view updates on tick.
@MainActor
private final class CountdownValue: ObservableObject {
    @Published var remaining: Int
    init(remaining: Int) { self.remaining = remaining }
}

/// Borderless, transparent, shielding-level panel covering one screen. Can
/// become key so Esc is delivered even if the SwiftUI monitor missed it.
private final class CountdownPanel: NSPanel {
    var onEscape: (() -> Void)?

    init(screen: NSScreen) {
        super.init(
            contentRect: screen.frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isFloatingPanel = true
        level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        animationBehavior = .none
        isReleasedWhenClosed = false
        setFrame(screen.frame, display: false)
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { onEscape?(); return }   // Esc
        super.keyDown(with: event)
    }
}

/// A big centered number over a dim backdrop.
private struct CountdownView: View {
    @ObservedObject var value: CountdownValue

    var body: some View {
        ZStack {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            Text("\(value.remaining)")
                .font(.system(size: 180, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.5), radius: 12, x: 0, y: 4)
                .transition(.scale.combined(with: .opacity))
                .id(value.remaining)
                .animation(.easeOut(duration: 0.25), value: value.remaining)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
