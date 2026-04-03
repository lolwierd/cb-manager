import Foundation

enum ClipboardSearch {
    static let keywordMinimumChars = 3
    static let semanticMinimumChars = 5
    private static let cancellationCheckInterval = 64

    static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func shouldRunKeywordQMD(normalizedQuery: String) -> Bool {
        normalizedQuery.count >= keywordMinimumChars
    }

    static func shouldRunSemanticQMD(normalizedQuery: String) -> Bool {
        normalizedQuery.count >= semanticMinimumChars
    }

    static func rank(
        entries: [ClipboardEntry],
        query: String,
        filter: ClipboardEntry.Kind,
        qmdResultQuery: String,
        qmdKeywordIDs: Set<String>?,
        qmdSemanticIDs: Set<String>?
    ) -> [ClipboardEntry] {
        let normalizedQuery = normalize(query)
        let base = filter == .all ? entries : entries.filter { $0.kind == filter }
        guard !normalizedQuery.isEmpty else { return base }
        let queryTokens = normalizedQuery.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !queryTokens.isEmpty else { return [] }

        var fuzzyRanked: [(ClipboardEntry, Int)] = []
        fuzzyRanked.reserveCapacity(min(base.count, 256))

        for (index, entry) in base.enumerated() {
            if index.isMultiple(of: cancellationCheckInterval), Task.isCancelled {
                return []
            }

            guard let score = fuzzyScore(for: entry, queryTokens: queryTokens) else { continue }
            fuzzyRanked.append((entry, score))
        }

        guard !Task.isCancelled else { return [] }

        fuzzyRanked.sort {
            if $0.1 == $1.1 { return $0.0.date > $1.0.date }
            return $0.1 > $1.1
        }
        guard !Task.isCancelled else { return [] }

        var merged: [ClipboardEntry] = fuzzyRanked.map(\.0)
        var seen = Set(merged.map(\.id))

        if qmdResultQuery == normalizedQuery {
            let qmdIDs = (qmdKeywordIDs ?? []).union(qmdSemanticIDs ?? [])
            var qmdOnly: [ClipboardEntry] = []
            qmdOnly.reserveCapacity(min(qmdIDs.count, base.count))

            for (index, entry) in base.enumerated() {
                if index.isMultiple(of: cancellationCheckInterval), Task.isCancelled {
                    return []
                }

                guard qmdIDs.contains(entry.id), !seen.contains(entry.id) else { continue }
                qmdOnly.append(entry)
            }

            qmdOnly.sort { $0.date > $1.date }
            guard !Task.isCancelled else { return [] }

            merged.append(contentsOf: qmdOnly)
            qmdOnly.forEach { seen.insert($0.id) }
        }

        return merged
    }

    static func fuzzyScore(for entry: ClipboardEntry, query: String) -> Int? {
        let tokens = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return fuzzyScore(for: entry, queryTokens: tokens)
    }

    private static func fuzzyScore(for entry: ClipboardEntry, queryTokens: [String]) -> Int? {
        let target = entry.searchableText
        guard !queryTokens.isEmpty else { return nil }

        var total = 0
        for token in queryTokens {
            if Task.isCancelled { return nil }

            if let exact = target.range(of: token) {
                let startDistance = target.distance(from: target.startIndex, to: exact.lowerBound)
                total += 250 + max(0, 120 - startDistance)
                continue
            }

            guard let subsequence = subsequenceScore(token, in: target) else {
                return nil
            }
            total += subsequence
        }

        if entry.kind == .image {
            total += 15
        }

        return total
    }

    private static func subsequenceScore(_ token: String, in target: String) -> Int? {
        guard !token.isEmpty else { return nil }
        // Optimization: if token is longer than target, fail immediately
        if token.count > target.count { return nil }

        var tokenIndex = token.startIndex
        var targetIndex = target.startIndex
        var gapPenalty = 0

        while tokenIndex < token.endIndex {
            if Task.isCancelled { return nil }

            var found = false
            while targetIndex < target.endIndex {
                if target[targetIndex] == token[tokenIndex] {
                    found = true
                    target.formIndex(after: &targetIndex)
                    token.formIndex(after: &tokenIndex)
                    break
                }
                gapPenalty += 1
                target.formIndex(after: &targetIndex)
            }

            if !found {
                return nil
            }
        }

        // Stricter penalty: 2 points per skipped character.
        // Base score: 150.
        // Threshold: 60.
        let score = 150 - (gapPenalty * 2)
        return score > 60 ? score : nil
    }
}
