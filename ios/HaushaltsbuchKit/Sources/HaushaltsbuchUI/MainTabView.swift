import SwiftUI

/// iPhone (kompakt): Tab-Leiste mit „+“ in der Mitte. „+“ öffnet die Erfassung und kehrt zum
/// vorherigen Tab zurück.
struct MainTabView: View {
    enum TabID: Hashable {
        case section(AppSection)
        case add
    }

    @State private var selection: TabID = .section(.overview)
    @State private var showEntry = false

    var body: some View {
        TabView(selection: tabSelection) {
            tab(.overview)
            tab(.transactions)
            Tab("Neu", systemImage: "plus.circle.fill", value: TabID.add) {
                Color.clear
            }
            .accessibilityIdentifier("tab.add")
            tab(.budgets)
            tab(.more)
        }
        .sheet(isPresented: $showEntry) {
            QuickEntryView()
        }
    }

    /// Fängt die Auswahl von „+“ ab, bevor sie den Tab wechselt.
    private var tabSelection: Binding<TabID> {
        Binding(
            get: { selection },
            set: { new in
                if new == .add {
                    showEntry = true
                } else {
                    selection = new
                }
            })
    }

    private func tab(_ section: AppSection) -> some TabContent<TabID> {
        Tab(section.title, systemImage: section.systemImage, value: TabID.section(section)) {
            NavigationStack {
                SectionScreen(section: section)
            }
        }
    }
}
