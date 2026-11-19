import Testing
@testable import HaushaltsbuchCore

@Test func presetsAreTheWebListInOrder() {
    #expect(Rhythm.presets.map(\.label) == ["Wöchentlich", "Alle 2 Wochen", "Monatlich", "Vierteljährlich",
                                             "Halbjährlich", "Jährlich"])
    #expect(Rhythm.presets[3] == Rhythm(frequency: .monthly, interval: 3))
    #expect(Rhythm.presets[1] == Rhythm(frequency: .weekly, interval: 2))
}

@Test func labelsForCustomRhythms() {
    #expect(Rhythm(frequency: .monthly, interval: 4).label == "Alle 4 Monate")
    #expect(Rhythm(frequency: .weekly, interval: 3).label == "Alle 3 Wochen")
    #expect(Rhythm(frequency: .yearly, interval: 2).label == "Alle 2 Jahre")
}

@Test func presetDetection() {
    #expect(Rhythm(frequency: .monthly, interval: 6).isPreset)
    #expect(!Rhythm(frequency: .monthly, interval: 5).isPreset)
}

@Test func intervalRangeLikeTheServer() {
    #expect(Rhythm(frequency: .monthly, interval: 1).isValid)
    #expect(Rhythm(frequency: .monthly, interval: 24).isValid)
    #expect(!Rhythm(frequency: .monthly, interval: 0).isValid)
    #expect(!Rhythm(frequency: .monthly, interval: 25).isValid)
}
