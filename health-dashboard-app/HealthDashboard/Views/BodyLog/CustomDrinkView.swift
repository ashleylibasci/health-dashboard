import SwiftUI
import HealthCore

/// Make a drink that isn't in the common list: name, size, caffeine and icon.
struct CustomDrinkView: View {
    @EnvironmentObject var model: AppModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var scheme

    @State private var name = ""
    @State private var size: DrinkSize? = .medium
    @State private var customSize = false
    @State private var ounces = ""
    @State private var mg = 150
    /// Shown when a typed amount was out of range and got changed.
    @State private var mgNote: String?
    @State private var icon: Drink.Icon = .latte
    @State private var saveToMine = true
    @State private var logIt = true
    @State private var logTime: LogTime = .now
    @FocusState private var focused: Field?

    private enum Field: Hashable { case name, ounces, mg }

    enum DrinkSize: String, CaseIterable, Identifiable {
        case small = "Small", medium = "Medium", large = "Large"
        var id: String { rawValue }
    }

    private let mgRange = 0...600

    var body: some View {
        Screen(title: "New drink", accent: .yellow) {
            HStack(spacing: 8) {
                Text("New")
                Text("drink").foregroundStyle(Accent.yellow.ink(scheme))
            }
            .font(.scaled(size: 34, weight: .bold))
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isHeader)

            nameAndSize
            caffeine
            iconAndSave
            if logIt { whenCard }
            buttons
        }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { focused = nil }
            }
        }
    }

    // MARK: Draft

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    private var ouncesValue: Double? {
        guard let v = Double(ounces.replacingOccurrences(of: ",", with: ".")), v > 0 else { return nil }
        return v
    }

    private var sizeLabel: String? {
        if customSize, let oz = ouncesValue {
            return oz == oz.rounded() ? "\(Int(oz)) oz" : String(format: "%.1f oz", oz)
        }
        return customSize ? nil : size?.rawValue
    }

    private var draft: Drink {
        Drink(name: trimmedName.isEmpty ? "New drink" : trimmedName, sizeLabel: sizeLabel,
              caffeineMg: mg, icon: icon, isCustom: true)
    }

    private var canSave: Bool { !trimmedName.isEmpty && mg > 0 && (saveToMine || logIt) }

    private var primaryTitle: String {
        if saveToMine && logIt { return "Save and log" }
        return saveToMine ? "Save drink" : "Log drink"
    }

    // MARK: Sections

    private var nameAndSize: some View {
        Card {
            fieldLabel("Drink name")
            TextField("Iced brown sugar oat shaken espresso", text: $name)
                .font(.scaled(size: 16, weight: .semibold))
                .textInputAutocapitalization(.sentences)
                .submitLabel(.done)
                .focused($focused, equals: .name)
                .padding(.horizontal, 14)
                .frame(minHeight: 52)
                .background(inputBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Accent.indigo.ink(scheme).opacity(focused == .name ? 0.8 : 0.4), lineWidth: 1.5))
                .accessibilityLabel("Drink name")

            fieldLabel("Size").padding(.top, 4)
            HStack(spacing: 8) {
                ForEach(DrinkSize.allCases) { option in
                    Chip(title: option.rawValue, selected: !customSize && size == option, accent: .yellow) {
                        size = option
                        customSize = false
                    }
                }
            }
            customSizeRow
        }
    }

    /// Said out loud instead of silently ignoring what she typed.
    private var ouncesNote: String? {
        guard customSize, !ounces.isEmpty else { return nil }
        guard let oz = ouncesValue else { return "Type the size as a number, like 12 or 16.9." }
        return oz > 64 ? "\(LogFormat.ozNumber(oz * LogFormat.mlPerOunce)) oz is a very big drink. Check the number." : nil
    }

    private var customSizeRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            customSizeField
            if let ouncesNote {
                Label(ouncesNote, systemImage: "exclamationmark.circle")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(Accent.orange.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var customSizeField: some View {
        let p = Palette(scheme: scheme)
        return HStack(spacing: 10) {
            Button {
                customSize.toggle()
                if customSize { focused = .ounces }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: customSize ? "largecircle.fill.circle" : "circle")
                        .font(.scaled(size: 20))
                        .foregroundStyle(customSize ? Accent.yellow.ink(scheme) : p.tertiary)
                    Text("Custom size").font(.scaled(size: 14, weight: .semibold))
                }
                .frame(minHeight: 44)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(customSize ? .isSelected : [])
            Spacer()
            Text("Ounces").font(.scaled(size: 13)).secondaryText()
            TextField("12", text: $ounces)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .font(.scaled(size: 15, weight: .semibold))
                .focused($focused, equals: .ounces)
                .padding(.horizontal, 10)
                // Grows with the text size.
                .frame(width: Font.scaledSize(72))
                .frame(minHeight: 44)
                .background(inputBackground, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(p.cardBorder))
                .accessibilityLabel("Custom size in ounces")
                .onChange(of: ounces) {
                    if !ounces.isEmpty { customSize = true }
                }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 4)
        .background(p.chip.opacity(0.6), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
            .strokeBorder(p.cardBorder, style: StrokeStyle(lineWidth: 1, dash: [4, 3])))
    }

    private var caffeine: some View {
        Card(accent: .yellow) {
            SectionLabel(text: "Caffeine", accent: .yellow)
            HStack(spacing: 12) {
                stepButton(systemImage: "minus", label: "Decrease caffeine by 5 mg") { setMg(mg - 5) }
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    TextField("0", value: $mg, format: .number)
                        .keyboardType(.numberPad)
                        .multilineTextAlignment(.trailing)
                        .font(.scaledNumber(30))
                        .focused($focused, equals: .mg)
                        .accessibilityLabel("Caffeine in milligrams")
                    Text("mg").font(.scaled(size: 15, weight: .semibold)).secondaryText()
                }
                .padding(.horizontal, 14)
                .frame(maxWidth: .infinity, minHeight: 56)
                .background(inputBackground, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Accent.yellow.fill(scheme).opacity(0.45), lineWidth: 1.5))
                stepButton(systemImage: "plus", label: "Increase caffeine by 5 mg") { setMg(mg + 5) }
            }
            .onChange(of: mg) {
                if !mgRange.contains(mg) { setMg(mg) }
            }
            if let mgNote {
                Label(mgNote, systemImage: "exclamationmark.circle")
                    .font(.scaled(size: 13, weight: .semibold))
                    .foregroundStyle(Accent.orange.ink(scheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            Text("Check the cafe\u{2019}s menu or the can. Your daily limit is 400 mg.")
                .font(.scaled(size: 13))
                .secondaryText()
        }
    }

    private func setMg(_ value: Int) {
        let clamped = min(max(value, mgRange.lowerBound), mgRange.upperBound)
        mgNote = value > mgRange.upperBound
            ? "\(value) mg is more than a single drink can hold here, so it\u{2019}s set to \(mgRange.upperBound) mg. Check the number."
            : nil
        mg = clamped
    }

    private func stepButton(systemImage: String, label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemImage)
                .font(.scaled(size: 18, weight: .bold))
                .foregroundStyle(Accent.yellow.ink(scheme))
                .frame(width: 48, height: 48)
                .background(Accent.yellow.fill(scheme).opacity(0.16), in: Circle())
                .overlay(Circle().strokeBorder(Accent.yellow.fill(scheme).opacity(0.3)))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }

    private var iconAndSave: some View {
        Card {
            HStack(spacing: 4) {
                fieldLabel("Icon")
                Text("(optional)").font(.scaled(size: 12)).secondaryText()
            }
            HStack(spacing: 10) {
                ForEach(Drink.Icon.allCases, id: \.self) { option in
                    iconButton(option)
                }
            }
            Divider().overlay(Palette(scheme: scheme).cardBorder)
            SettingToggleRow(title: "Save to My drinks", detail: "Shows up as a one-tap button", isOn: $saveToMine)
            Divider().overlay(Palette(scheme: scheme).cardBorder)
            SettingToggleRow(title: "Log it too", detail: "Adds it to today's caffeine at the time you pick", accent: .yellow, isOn: $logIt)

            fieldLabel("Preview in My drinks").padding(.top, 4)
            SavedDrinkRow(drink: draft, trailingSystemImage: nil)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Preview: \(draft.name), \(draft.sizeLabel ?? "no size"), \(draft.caffeineMg) mg, custom")
        }
    }

    private func iconButton(_ option: Drink.Icon) -> some View {
        let accent = BodyLogStyle.accent(for: option)
        let selected = option == icon
        return Button { icon = option } label: {
            Image(systemName: BodyLogStyle.symbol(for: option))
                .font(.scaled(size: 18, weight: .semibold))
                .foregroundStyle(accent.ink(scheme))
                .frame(width: 52, height: 52)
                .background(accent.fill(scheme).opacity(selected ? 0.28 : 0.16), in: Circle())
                .overlay(Circle().strokeBorder(selected ? accent.fill(scheme) : Color.clear, lineWidth: 2))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(BodyLogStyle.name(for: option))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var whenCard: some View {
        Card(accent: .yellow) {
            LogTimeSelector(time: $logTime, accent: .yellow, title: "When did you have it?")
        }
    }

    private func saveAndLog() {
        let drink = draft
        if saveToMine { model.save(customDrink: drink, logNow: false) }
        if logIt { model.log(drink, at: logTime.date) }
        dismiss()
    }

    private var buttons: some View {
        VStack(spacing: 10) {
            Button(action: saveAndLog) {
                Text(primaryTitle)
                    .font(.scaled(size: 17, weight: .bold))
                    .frame(maxWidth: .infinity, minHeight: 56)
                    .foregroundStyle(Color(hex: 0x1A1400))
                    .background(Accent.yellow.fill(scheme), in: Capsule())
                    .opacity(canSave ? 1 : 0.45)
            }
            .buttonStyle(.plain)
            .disabled(!canSave)
            .accessibilityHint(logIt ? "Logs it \(logTime.phrase)" : "")

            if !canSave {
                Text(hint)
                    .font(.scaled(size: 13))
                    .secondaryText()
            } else if logIt {
                Text("Logs \(logTime.phrase). You can change the time later in Caffeine today.")
                    .font(.scaled(size: 13))
                    .secondaryText()
            }
        }
        .padding(.top, 4)
    }

    private var hint: String {
        if trimmedName.isEmpty { return "Add a name to save this drink." }
        if mg <= 0 { return "Add the caffeine amount to save this drink." }
        return "Turn on Save to My drinks or Log it too."
    }

    // MARK: Helpers

    private var inputBackground: Color {
        scheme == .dark ? Color.black.opacity(0.35) : Color(hex: 0xF6F6FA)
    }

    private func fieldLabel(_ text: String) -> some View {
        Text(text.uppercased())
            .font(.scaled(size: 12, weight: .bold))
            .tracking(0.3)
            .secondaryText()
    }
}
