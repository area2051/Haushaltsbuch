import SwiftUI
import HaushaltsbuchCore

/// Kategorie-Raster: Tipp auf eine Kategorie speichert. Gedimmt und gesperrt, solange `enabled` falsch ist.
struct CategoryGridView: View {
    let categories: [CategoryValue]
    let enabled: Bool
    let onSelect: (CategoryValue) -> Void

    private let columns = [GridItem(.adaptive(minimum: 72), spacing: 12, alignment: .top)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 14) {
            ForEach(categories, id: \.id) { category in
                Button {
                    onSelect(category)
                } label: {
                    VStack(spacing: 6) {
                        Image(systemName: category.icon)
                            .font(.title3)
                            .foregroundStyle(.white)
                            .frame(width: 48, height: 48)
                            .background(Circle().fill(Color(hex: category.color)))
                        Text(category.name)
                            .font(.caption)
                            .lineLimit(2)
                            .multilineTextAlignment(.center)
                            .foregroundStyle(.primary)
                    }
                    .frame(maxWidth: .infinity)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(category.name)
                .accessibilityIdentifier("quickEntry.category.\(category.name)")
            }
        }
        .disabled(!enabled)
        .opacity(enabled ? 1 : 0.4)
        .animation(.default, value: enabled)
    }
}

extension Color {
    /// „#RRGGBB“; ungültige Werte → Grau.
    init(hex: String) {
        var s = hex.trimmingCharacters(in: .whitespaces)
        if s.hasPrefix("#") { s.removeFirst() }
        guard s.count == 6, let v = UInt32(s, radix: 16) else {
            self = .gray
            return
        }
        self.init(red: Double((v >> 16) & 0xFF) / 255,
                  green: Double((v >> 8) & 0xFF) / 255,
                  blue: Double(v & 0xFF) / 255)
    }
}
