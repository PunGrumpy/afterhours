import SwiftUI

/// Grouped rows like System Settings. Unlike `Form(.grouped)` it has an intrinsic height, so each
/// Settings tab can size the window to fit, the way Safari's Settings do.
struct SettingsSection<Rows: View, Footer: View>: View {
    let title: String?
    @ViewBuilder let rows: Rows
    @ViewBuilder let footer: Footer

    init(_ title: String? = nil, @ViewBuilder rows: () -> Rows, @ViewBuilder footer: () -> Footer = { EmptyView() }) {
        self.title = title
        self.rows = rows()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let title {
                Text(title).font(.headline).padding(.horizontal, 2)
            }
            // Rows paint themselves opaque, so the 1pt gaps between them show the separator behind.
            VStack(spacing: 1) { rows }
                .background(Color(nsColor: .separatorColor))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(Color(nsColor: .separatorColor), lineWidth: 1))
            footer
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 2)
        }
    }
}

/// A label on the left and a control on the right, at the height of a System Settings row.
struct SettingsRow<Label: View, Control: View>: View {
    @ViewBuilder let label: Label
    @ViewBuilder let control: Control

    init(@ViewBuilder label: () -> Label, @ViewBuilder control: () -> Control) {
        self.label = label()
        self.control = control()
    }

    init(_ title: String, @ViewBuilder control: () -> Control) where Label == Text {
        self.init(label: { Text(title) }, control: control)
    }

    var body: some View {
        HStack(spacing: 12) {
            label.frame(maxWidth: .infinity, alignment: .leading)
            control
        }
        .settingsRow()
    }
}

extension View {
    /// Row padding and an opaque fill, for content inside a `SettingsSection`.
    func settingsRow() -> some View {
        frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
            .padding(.horizontal, 14)
            .background(.background)
            .background(.quaternary.opacity(0.5))
    }
}

/// A switch that says on or off with its knob, not only its color.
struct SettingsToggle: View {
    let title: String
    @Binding var isOn: Bool

    var body: some View {
        SettingsRow(title) {
            Toggle(title, isOn: $isOn).toggleStyle(.switch).labelsHidden().controlSize(.small)
        }
    }
}
