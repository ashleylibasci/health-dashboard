import SwiftUI
import UIKit
import HealthCore

/// Quick log from anywhere (D-S2): long-press the Log tab for a small menu
/// (her latte, +1 bottle, period or bleeding flow, stress). Each one logs
/// straight away with the usual Undo toast; the Log tab stays the full form.
///
/// SwiftUI's tab items take no gestures, so this finds the tab bar UIKit
/// draws and adds a context-menu interaction that only answers over Log.
struct QuickLogMenu: UIViewRepresentable {
    var model: AppModel
    var store: DataStore
    @Binding var toast: UndoToast?

    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeUIView(context: Context) -> Finder {
        let view = Finder()
        view.coordinator = context.coordinator
        view.isUserInteractionEnabled = false
        return view
    }

    func updateUIView(_ view: Finder, context: Context) {
        context.coordinator.menu = { [model, store, $toast] in
            QuickLog(model: model, store: store, toast: $toast).menu
        }
    }

    /// An invisible view that, once in a window, installs the interaction
    /// on the tab bar (once).
    final class Finder: UIView {
        weak var coordinator: Coordinator?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            guard window != nil else { return }
            DispatchQueue.main.async { [weak self] in self?.install() }
        }

        private func install() {
            guard let coordinator, let root = window?.rootViewController,
                  let bar = Self.tabBar(in: root),
                  !bar.interactions.contains(where: { $0 is UIContextMenuInteraction }) else { return }
            coordinator.bar = bar
            bar.addInteraction(UIContextMenuInteraction(delegate: coordinator))
        }

        private static func tabBar(in vc: UIViewController) -> UITabBar? {
            if let tabs = vc as? UITabBarController { return tabs.tabBar }
            for child in vc.children + [vc.presentedViewController].compactMap({ $0 }) {
                if let bar = tabBar(in: child) { return bar }
            }
            return nil
        }
    }

    @MainActor
    final class Coordinator: NSObject, UIContextMenuInteractionDelegate {
        var menu: (@MainActor () -> UIMenu)?
        weak var bar: UITabBar?

        /// The Log item's frame in the bar: the view labelled "Log", or the
        /// last quarter of the bar if iOS draws it some other way.
        private func logFrame(in bar: UITabBar) -> CGRect {
            var found: CGRect?
            func walk(_ view: UIView) {
                if found == nil, view !== bar, view.accessibilityLabel == "Log", view.bounds.width < bar.bounds.width / 2 {
                    found = view.convert(view.bounds, to: bar)
                }
                view.subviews.forEach(walk)
            }
            walk(bar)
            if let found { return found }
            return CGRect(x: bar.bounds.width * 0.75, y: 0, width: bar.bounds.width * 0.25, height: bar.bounds.height)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    configurationForMenuAtLocation location: CGPoint) -> UIContextMenuConfiguration? {
            guard let bar, let menu, logFrame(in: bar).insetBy(dx: -8, dy: -8).contains(location) else { return nil }
            return UIContextMenuConfiguration(identifier: nil, previewProvider: nil) { _ in menu() }
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    configuration: UIContextMenuConfiguration,
                                    highlightPreviewForItemWithIdentifier identifier: any NSCopying) -> UITargetedPreview? {
            preview(interaction)
        }

        func contextMenuInteraction(_ interaction: UIContextMenuInteraction,
                                    previewForHighlightingMenuWithConfiguration configuration: UIContextMenuConfiguration) -> UITargetedPreview? {
            preview(interaction)
        }

        /// Lifts just the Log item, not the whole bar.
        private func preview(_ interaction: UIContextMenuInteraction) -> UITargetedPreview? {
            guard let bar else { return nil }
            let frame = logFrame(in: bar)
            let params = UIPreviewParameters()
            params.visiblePath = UIBezierPath(roundedRect: CGRect(origin: .zero, size: frame.size), cornerRadius: frame.height / 2)
            params.backgroundColor = .clear
            let snapshot = bar.resizableSnapshotView(from: frame, afterScreenUpdates: false, withCapInsets: .zero) ?? UIView()
            return UITargetedPreview(view: snapshot, parameters: params,
                                     target: UIPreviewTarget(container: bar, center: CGPoint(x: frame.midX, y: frame.midY)))
        }
    }
}

/// The four quick logs, each with the same message and Undo as on the Log tab.
@MainActor
private struct QuickLog {
    var model: AppModel
    var store: DataStore
    var toast: Binding<UndoToast?>

    private var cal: Calendar { Calendar.current }

    /// Her latte (the drink the widget's button logs), or her first saved drink.
    private var drink: Drink? {
        store.data.savedDrinks.first { $0.name.localizedCaseInsensitiveContains("latte") } ?? store.data.savedDrinks.first
    }

    var menu: UIMenu {
        var items: [UIMenuElement] = []
        if let drink {
            items.append(UIAction(title: drink.name, subtitle: "\(drink.caffeineMg) mg",
                                  image: UIImage(systemName: "cup.and.saucer.fill")) { _ in logDrink(drink) })
        }
        items.append(UIAction(title: "+1 bottle", subtitle: LogFormat.oz(store.data.bottleSizeML),
                              image: UIImage(systemName: "drop.fill")) { _ in addBottle() })
        if store.data.cycleSetup != .notTracking {
            let word = model.usesBleedingWording || model.usesPackWording ? "Bleeding" : "Period"
            let flows: [AppData.Flow] = [.spotting, .light, .medium, .heavy]
            items.append(UIMenu(title: word, image: UIImage(systemName: "drop.halffull"),
                                children: flows.map { f in UIAction(title: f.rawValue) { _ in setFlow(f) } }))
        }
        items.append(UIMenu(title: "Stress", image: UIImage(systemName: "waveform.path"),
                            children: (1...5).map { level in
                                UIAction(title: "\(level), \(LogView.stressWord(level))") { _ in logStress(level) }
                            }))
        return UIMenu(title: "Quick log", children: items)
    }

    private func show(_ message: String, undo: @escaping () -> Void) {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        toast.wrappedValue = UndoToast(message, undo: undo)
    }

    private func logDrink(_ drink: Drink) {
        let id = UUID()
        withMotion(.log) {
            model.logDrink(id: id, drinkID: drink.id, name: drink.name, mg: drink.caffeineMg, at: .now, saveToHealth: true)
        }
        show(LogFormat.loggedLine(LogFormat.midSentence(drink), at: .now)) {
            withMotion(.undo) { model.deleteDrink(id) }
        }
    }

    private func addBottle() {
        let id = UUID()
        let ml = store.data.bottleSizeML
        withMotion(.log) { model.addWater(ml: ml, id: id) }
        show("Added \(LogFormat.oz(ml)) at \(Clock.format(model.now)).") {
            withMotion(.undo) { model.deleteWater(id) }
        }
    }

    /// Today's flow, replacing what was there, as the Log tab's chips do.
    private func setFlow(_ flow: AppData.Flow) {
        let before = store.data.flowLog
        var data = store.data
        data.flowLog.removeAll { cal.isDateInToday($0.date) }
        data.flowLog.append(.init(date: .now, flow: flow))
        data.flowLog.sort { $0.date < $1.date }
        withMotion(.select) { store.data = data }
        show("Saved \(flow.rawValue.lowercased()) flow for today.") {
            withMotion(.undo) { store.data.flowLog = before }
        }
    }

    private func logStress(_ level: Int) {
        let entry = AppData.MoodEntry(date: .now, stress: level)
        withMotion(.select) { store.data.moodLog.append(entry) }
        show("Logged stress \(level), \(LogView.stressWord(level)).") {
            withMotion(.undo) { store.data.moodLog.removeAll { $0.id == entry.id } }
        }
    }
}
