import Foundation
import Testing
@testable import HaushaltsbuchCore

private let home = UUID(), power = UUID(), rent = UUID(), water = UUID(), old = UUID(), oldChild = UUID()

private func cat(_ id: UUID, _ name: String, parent: UUID? = nil, sort: Int = 0, archived: Bool = false) -> CategoryValue {
    CategoryValue(id: id, name: name, icon: "tag", color: "#000000", kind: .expense, sortOrder: sort,
                  archived: archived, parentId: parent)
}

private let tree = CategoryTree([
    cat(home, "Wohnen", sort: 1),
    cat(power, "Strom", parent: home, sort: 2),
    cat(rent, "Miete", parent: home, sort: 2),
    cat(water, "Wasser", parent: home, sort: 1),
    cat(old, "Alt", archived: true),
    cat(oldChild, "Kind", parent: old),
])

@Test func rootOfMapsChildrenToTheirParentMainAndUnknownToThemselves() {
    let gone = UUID()
    #expect(tree.rootOf(power) == home)
    #expect(tree.rootOf(home) == home)
    #expect(tree.rootOf(gone) == gone)
}

@Test func childrenOfIsOrderedBySortOrderThenName() {
    #expect(tree.childrenOf(home).map(\.id) == [water, rent, power])
    #expect(tree.childrenOf(power).isEmpty)
}

@Test func labelFor() {
    #expect(tree.label(power) == "Wohnen · Strom")
    #expect(tree.label(home) == "Wohnen")
    #expect(tree.label(UUID()) == "Unbekannt")
}

@Test func isSelectableIsFalseForArchivedAndChildrenOfAnArchivedParent() {
    #expect(tree.isSelectable(tree.byId[home]!))
    #expect(tree.isSelectable(tree.byId[power]!))
    #expect(!tree.isSelectable(tree.byId[old]!))
    #expect(!tree.isSelectable(tree.byId[oldChild]!))
}
