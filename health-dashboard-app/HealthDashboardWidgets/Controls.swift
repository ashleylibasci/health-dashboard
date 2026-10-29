import AppIntents
import SwiftUI
import WidgetKit

/// Controls for Control Center, the Lock Screen corners and the Action
/// button (iOS 18): log her usual latte, log a bottle of water, and switch
/// the smart alarm. They work like the widget buttons, without opening the app.

@available(iOS 18.0, *)
struct LogLatteControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LogLatteControl", provider: QuickDrinkName()) { name in
            ControlWidgetButton(action: LogLatteIntent()) {
                Label("Log \(name.lowercased())", systemImage: "mug.fill")
            }
        }
        .displayName("Log latte")
        .description("Logs your usual latte and saves the caffeine to Apple Health.")
    }

    /// Her saved latte's name ("Latte", or her first saved drink).
    struct QuickDrinkName: ControlValueProvider {
        var previewValue: String { "Latte" }
        func currentValue() async throws -> String { WidgetSnapshot.load()?.quickDrink?.name ?? "Latte" }
    }
}

@available(iOS 18.0, *)
struct LogBottleControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "LogBottleControl") {
            ControlWidgetButton(action: LogBottleIntent()) {
                Label("+1 bottle", systemImage: "waterbottle.fill")
            }
        }
        .displayName("+1 bottle")
        .description("Logs a bottle of water and saves it to Apple Health.")
    }
}

@available(iOS 18.0, *)
struct SmartAlarmControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "SmartAlarmControl", provider: SmartAlarmState()) { isOn in
            ControlWidgetToggle("Smart alarm", isOn: isOn, action: SetSmartAlarmIntent()) { on in
                Label(on ? "On" : "Off", systemImage: on ? "alarm.fill" : "alarm")
            }
            .tint(.orange)
        }
        .displayName("Smart alarm")
        .description("Turns the smart alarm on your Watch on or off. Open the app on your Watch before bed to finish turning it on.")
    }

    struct SmartAlarmState: ControlValueProvider {
        var previewValue: Bool { true }
        func currentValue() async throws -> Bool { WidgetSnapshot.load()?.smartAlarmOn ?? false }
    }
}
