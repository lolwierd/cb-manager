import Foundation

enum ClipboardSearch {
    static let keywordMinimumChars = 3
    static let semanticMinimumChars = 5

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
        let base = entries.filter { filter == .all || $0.kind == filter }
        let normalizedQuery = normalize(query)
        guard !normalizedQuery.isEmpty else { return base }

        let fuzzyRanked = base.compactMap { entry -> (ClipboardEntry, Int)? in
            guard let score = fuzzyScore(for: entry, query: normalizedQuery) else { return nil }
            return (entry, score)
        }
        .sorted {
            if $0.1 == $1.1 { return $0.0.date > $1.0.date }
            return $0.1 > $1.1
        }

        var merged: [ClipboardEntry] = fuzzyRanked.map(\.0)
        var seen = Set(merged.map(\.id))

        if qmdResultQuery == normalizedQuery {
            let qmdIDs = (qmdKeywordIDs ?? []).union(qmdSemanticIDs ?? [])
            let qmdOnly = base
                .filter { qmdIDs.contains($0.id) && !seen.contains($0.id) }
                .sorted { $0.date > $1.date }

            merged.append(contentsOf: qmdOnly)
            qmdOnly.forEach { seen.insert($0.id) }
        }

        return merged
    }

    static func fuzzyScore(for entry: ClipboardEntry, query: String) -> Int? {
        let target = entry.searchableText
        let tokens = query.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        guard !tokens.isEmpty else { return nil }

        var total = 0
        for token in tokens {
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

        var tokenIndex = token.startIndex
        var targetIndex = target.startIndex
        var gapPenalty = 0

        while tokenIndex < token.endIndex {
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

        return max(1, 140 - min(gapPenalty, 120))
    }
}
