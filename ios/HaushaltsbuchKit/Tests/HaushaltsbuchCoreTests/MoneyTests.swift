import Testing
@testable import HaushaltsbuchCore

@Test func moneyFormatsGerman() {
    #expect(Money.format(cents: 123456).normalizedSpaces == "1.234,56 €")
    #expect(Money.format(cents: 1250).normalizedSpaces == "12,50 €")
    #expect(Money.format(cents: 5).normalizedSpaces == "0,05 €")
    #expect(Money.format(cents: 0).normalizedSpaces == "0,00 €")
    #expect(Money.format(cents: 99_999_999_900).normalizedSpaces == "999.999.999,00 €")
}

@Test func moneyFormatSignedByKind() {
    #expect(Money.formatSigned(cents: 1250, kind: .income).normalizedSpaces == "+12,50 €")
    #expect(Money.formatSigned(cents: 1250, kind: .expense).normalizedSpaces == "−12,50 €")
}

@Test func kindAndFrequencyRawValues() {
    #expect(Kind.allCases == [.income, .expense])
    #expect(Frequency.allCases.map(\.rawValue) == ["weekly", "monthly", "yearly"])
}
