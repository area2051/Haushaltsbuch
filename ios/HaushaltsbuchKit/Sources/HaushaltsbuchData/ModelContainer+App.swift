import Foundation
import SwiftData

public enum AppSchema {
    public static let models: [any PersistentModel.Type] = [
        CategoryEntity.self, TransactionEntity.self, BudgetEntity.self,
        RecurringRuleEntity.self, MemberEntity.self,
    ]
}

extension ModelContainer {
    /// Container für die App (`inMemory: true` für Tests/Previews).
    public static func makeAppContainer(inMemory: Bool = false) throws -> ModelContainer {
        let schema = Schema(AppSchema.models)
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: inMemory)
        return try ModelContainer(for: schema, configurations: [config])
    }
}
