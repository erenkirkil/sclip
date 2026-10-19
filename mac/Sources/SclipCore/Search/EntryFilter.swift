import Foundation

/// Arama filtresi (`behavior.md` B-6.5.4, B-6.5.6): salt türetilmiştir, depoyu değiştirmez.
public enum EntryFilter {
    public static func filter(_ entries: [Entry], query: String) -> [Entry] {
        let needle = SearchNormalizer.normalize(query)
        if needle.isEmpty { return entries }
        let pattern = Array(needle.utf8)
        return entries.filter { entry in
            Array(SearchIndex.text(for: entry).utf8).firstRange(of: pattern) != nil
        }
    }
}
