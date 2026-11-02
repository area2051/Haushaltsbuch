import SwiftUI

/// iPad (regulär): Seitenleiste mit den Bereichen, „+“ in der Toolbar und ⌘N.
struct MainSplitView: View {
    @State private var selection: AppSection? = .overview
    @State private var showEntry = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            List(AppSection.allCases, selection: $selection) { section in
                Label(section.title, systemImage: section.systemImage)
                    .tag(section)
            }
            .navigationTitle("Haushaltsbuch")
        } detail: {
            NavigationStack {
                SectionScreen(section: selection ?? .overview)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) { addButton }
                    }
            }
        }
        .navigationSplitViewStyle(.balanced)
        .sheet(isPresented: $showEntry) {
            QuickEntryView()
        }
    }

    private var addButton: some View {
        Button {
            showEntry = true
        } label: {
            Label("Neue Buchung", systemImage: "plus")
        }
        .keyboardShortcut("n")
        .accessibilityIdentifier("toolbar.add")
    }
}
