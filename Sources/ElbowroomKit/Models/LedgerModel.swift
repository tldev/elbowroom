import Foundation
import Observation

public struct LedgerQuery: Hashable, Sendable {
    public var revision: Int
    public var tier: Tier?
    public var search: String
    public var sort: LedgerSort
    public var ascending: Bool
    public var language: String

    public init(revision: Int, tier: Tier? = nil, search: String = "", sort: LedgerSort = .size,
                ascending: Bool = false, language: String = Loc.lang) {
        self.revision = revision
        self.tier = tier
        self.search = search
        self.sort = sort
        self.ascending = ascending
        self.language = language
    }
}

/// One retained projection per visible table, invalidated by its actual inputs.
@MainActor
@Observable
public final class LedgerModel {
    public private(set) var rows: [LedgerRow] = []
    public private(set) var completedQuery: LedgerQuery?
    @ObservationIgnored private var generation = 0

    public init() {}

    public func update(items: [AtlasItem], insights: [SystemInsight], query: LedgerQuery) async {
        generation += 1
        let request = generation
        guard completedQuery != query else { return }
        let work = Task.detached(priority: .userInitiated) {
            let rows = LedgerProjection.rows(items: items, insights: insights, tier: query.tier,
                                  search: query.search, sort: query.sort, ascending: query.ascending)
            return rows
        }
        let projected = await withTaskCancellationHandler {
            await work.value
        } onCancel: {
            work.cancel()
        }
        guard !Task.isCancelled, generation == request else { return }
        rows = projected
        completedQuery = query
    }
}
