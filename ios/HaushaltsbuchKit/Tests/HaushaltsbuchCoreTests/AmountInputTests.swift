import Testing
@testable import HaushaltsbuchCore

@Test func amountInputFromRight() {
    var a = AmountInput()
    [1, 2, 5, 0].forEach { a.append(digit: $0) }
    #expect(a.cents == 1250)
    #expect(a.display.normalizedSpaces == "12,50 €")
    #expect(a.isValid)
}

@Test func amountInputIgnoresTenthDigit() {
    var a = AmountInput()
    for _ in 0..<9 { a.append(digit: 9) }
    #expect(a.cents == 999_999_999)
    a.append(digit: 9)
    #expect(a.cents == 999_999_999)
    a.append(digit: 0)
    #expect(a.cents == 999_999_999)
}

@Test func amountInputIgnoresLeadingZero() {
    var a = AmountInput()
    a.append(digit: 0)
    #expect(a.cents == 0)
    #expect(!a.isValid)
    a.append(digit: 0)
    #expect(a.cents == 0)
    a.append(digit: 5)
    #expect(a.cents == 5)
    #expect(a.isValid)
}

@Test func amountInputIgnoresInvalidDigit() {
    var a = AmountInput()
    a.append(digit: 10)
    a.append(digit: -1)
    #expect(a.cents == 0)
}

@Test func deleteLastRemovesRightmostDigit() {
    var a = AmountInput()
    [1, 2, 5, 0].forEach { a.append(digit: $0) }
    a.deleteLast()
    #expect(a.cents == 125)
    a.deleteLast(); a.deleteLast(); a.deleteLast()
    #expect(a.cents == 0)
    a.deleteLast()
    #expect(a.cents == 0)
}

@Test func clearResets() {
    var a = AmountInput()
    a.append(digit: 7)
    a.clear()
    #expect(a == AmountInput())
    #expect(a.display.normalizedSpaces == "0,00 €")
}
