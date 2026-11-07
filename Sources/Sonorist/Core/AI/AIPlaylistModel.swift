import Foundation

// MARK: - Core AI Curated Playlist Models

/// Represents a single curated genre cluster within a language (e.g. "Melodic & Romance", "Pop & Dance").
/// Max 5 genres per language to keep navigation clean and Apple HIG compliant.
public struct AIGenreGroup: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var icon: String
    public var description: String
    public var trackIds: [String]

    public init(
        id: String = UUID().uuidString,
        name: String,
        icon: String = "music.note",
        description: String = "",
        trackIds: [String] = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.description = description
        self.trackIds = trackIds
    }
}

/// Represents a top-level language folder (e.g. Hindi, English, Punjabi, Instrumental).
public struct AILanguageCategory: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var language: String
    public var icon: String
    public var genres: [AIGenreGroup]

    public var totalTrackCount: Int {
        // Unique count in case track appears across genres
        Set(genres.flatMap { $0.trackIds }).count
    }

    public init(
        id: String = UUID().uuidString,
        language: String,
        icon: String = "folder.fill",
        genres: [AIGenreGroup] = []
    ) {
        self.id = id
        self.language = language
        self.icon = icon
        self.genres = genres
    }
}

/// Root container persisted on disk at `AICuratedPlaylists.json`.
public struct AICuratedLibrary: Codable, Sendable {
    public var lastUpdated: Date
    public var categories: [AILanguageCategory]

    public var totalTrackCount: Int {
        Set(categories.flatMap { $0.genres.flatMap { $0.trackIds } }).count
    }

    public init(lastUpdated: Date = Date(), categories: [AILanguageCategory] = []) {
        self.lastUpdated = lastUpdated
        self.categories = categories
    }

    /// Safely adds a track to a specific language and genre group.
    /// Strictly caps genres per language to 5 to maintain clean, focused organization.
    public mutating func insert(
        trackId: String,
        language: String,
        genreName: String,
        genreIcon: String = "music.note",
        genreDescription: String = ""
    ) {
        let cleanLang = language.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        let cleanGenre = genreName.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Locate or create language category
        if let langIdx = categories.firstIndex(where: { $0.language.caseInsensitiveCompare(cleanLang) == .orderedSame }) {
            // Language exists: locate or create genre group
            if let genreIdx = categories[langIdx].genres.firstIndex(where: { $0.name.caseInsensitiveCompare(cleanGenre) == .orderedSame }) {
                if !categories[langIdx].genres[genreIdx].trackIds.contains(trackId) {
                    categories[langIdx].genres[genreIdx].trackIds.append(trackId)
                }
            } else {
                // If under the 5 genre cap, create new genre
                if categories[langIdx].genres.count < 5 {
                    let newGroup = AIGenreGroup(
                        id: "\(cleanLang.lowercased())_\(categories[langIdx].genres.count + 1)",
                        name: cleanGenre,
                        icon: genreIcon,
                        description: genreDescription,
                        trackIds: [trackId]
                    )
                    categories[langIdx].genres.append(newGroup)
                } else {
                    // Fall back to appending to the first/most general genre
                    if !categories[langIdx].genres[0].trackIds.contains(trackId) {
                        categories[langIdx].genres[0].trackIds.append(trackId)
                    }
                }
            }
        } else {
            // Create new language folder
            let newGroup = AIGenreGroup(
                id: "\(cleanLang.lowercased())_1",
                name: cleanGenre,
                icon: genreIcon,
                description: genreDescription,
                trackIds: [trackId]
            )
            let newCat = AILanguageCategory(
                id: cleanLang.lowercased(),
                language: cleanLang,
                icon: Self.defaultIcon(for: cleanLang),
                genres: [newGroup]
            )
            categories.append(newCat)
        }

        self.lastUpdated = Date()
    }

    /// Removes a track across all curated categories (e.g. when un-downloaded)
    public mutating func remove(trackId: String) {
        for lIdx in categories.indices {
            for gIdx in categories[lIdx].genres.indices {
                categories[lIdx].genres[gIdx].trackIds.removeAll(where: { $0 == trackId })
            }
            // Remove empty genres
            categories[lIdx].genres.removeAll(where: { $0.trackIds.isEmpty })
        }
        // Remove empty language folders
        categories.removeAll(where: { $0.genres.isEmpty })
        self.lastUpdated = Date()
    }

    public static func defaultIcon(for language: String) -> String {
        switch language.lowercased() {
        case "hindi", "bengali", "tamil", "telugu", "punjabi", "urdu":
            return "music.mic"
        case "english":
            return "globe"
        case "instrumental", "soundtrack", "ost", "lo-fi":
            return "guitars"
        case "japanese", "korean", "k-pop", "anime":
            return "sparkles"
        default:
            return "folder.fill"
        }
    }
}
