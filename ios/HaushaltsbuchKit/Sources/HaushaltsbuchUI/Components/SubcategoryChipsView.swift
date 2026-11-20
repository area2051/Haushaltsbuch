import SwiftUI

/// Chip-Reihe unter einer Hauptkategorie: „Allgemein“ und ihre Unterkategorien (wie `SubcategoryChips` im Web).
struct SubcategoryChipsView: View {
    let options: [SubcategoryOption]
    let selectedId: UUID?
    var caption = "Unterkategorie"
    let onSelect: (UUID) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(caption).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(options) { option in
                        let selected = option.id == selectedId
                        Button { onSelect(option.id) } label: {
                            Text(option.name)
                                .font(.subheadline.weight(.medium))
                                .padding(.horizontal, 14)
                                .frame(height: 36)
                                .foregroundStyle(selected ? Color(.systemBackground) : Color.primary)
                                .background(Capsule().fill(selected ? Color.primary : Color(.secondarySystemFill)))
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                        .accessibilityIdentifier("subcategory.\(option.name)")
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Unterkategorie")
    }
}
