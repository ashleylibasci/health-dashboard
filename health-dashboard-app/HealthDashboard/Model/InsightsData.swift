import Foundation

/// What the insights features save (the At a glance tiles, the morning
/// note), kept in one
/// field of `AppData` so it stays on the phone with everything else.
/// Decoding is forgiving, like `AppData`'s.
struct InsightsData: Codable, Hashable {
    /// The At a glance tiles she pinned, in her order (`GlanceTile` raw
    /// values). Nil: the automatic four that follow the time of day.
    var glanceTiles: [String]?
    /// One note about 45 minutes after she wakes (D-N1). On by default:
    /// the one notification the app sends unless she turns others on.
    var morningNote = true

    init() {}

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = InsightsData()
        func get<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T { (try? c.decodeIfPresent(T.self, forKey: key)) ?? fallback }
        glanceTiles = get(.glanceTiles, d.glanceTiles)
        morningNote = get(.morningNote, d.morningNote)
    }
}
