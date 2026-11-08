import Foundation

// MARK: - Core AI Curated Playlist Models

/// Represents a single curated genre cluster within a language (e.g. "Melodic & Romance", "Spiritual", "Pop & Dance").
/// Max 5 standard genres per language to keep navigation clean and Apple HIG compliant, with user-customizable folders.
public struct AIGenreGroup: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public var icon: String
    public var description: String
    public var trackIds: [String]
    public var isCustom: Bool
    public var aliases: [String]

    public init(
        id: String = UUID().uuidString,
        name: String,
        icon: String = "music.note",
        description: String = "",
        trackIds: [String] = [],
        isCustom: Bool = false,
        aliases: [String] = []
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.description = description
        self.trackIds = trackIds
        self.isCustom = isCustom
        self.aliases = aliases
    }

    enum CodingKeys: String, CodingKey {
        case id, name, icon, description, trackIds, isCustom, aliases
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "music.note"
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        trackIds = try container.decodeIfPresent([String].self, forKey: .trackIds) ?? []
        isCustom = try container.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
    }
}

/// Represents a top-level language folder (e.g. Hindi, Bengali, English, Punjabi, Instrumental).
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
    /// Strictly caps automatic genres per language to 5, while honoring user-customized folders.
    public mutating func insert(
        trackId: String,
        language: String,
        genreName: String,
        genreIcon: String = "music.note",
        genreDescription: String = "",
        isCustom: Bool = false
    ) {
        let cleanLang = language.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        let cleanGenre = genreName.trimmingCharacters(in: .whitespacesAndNewlines)

        // 1. Locate or create language category
        if let langIdx = categories.firstIndex(where: { $0.language.caseInsensitiveCompare(cleanLang) == .orderedSame }) {
            // Check direct name match
            if let genreIdx = categories[langIdx].genres.firstIndex(where: { $0.name.caseInsensitiveCompare(cleanGenre) == .orderedSame }) {
                if !categories[langIdx].genres[genreIdx].trackIds.contains(trackId) {
                    categories[langIdx].genres[genreIdx].trackIds.append(trackId)
                }
            } else if let aliasIdx = categories[langIdx].genres.firstIndex(where: { g in
                g.aliases.contains(where: { $0.caseInsensitiveCompare(cleanGenre) == .orderedSame }) ||
                // Smart mapping for Spiritual / Devotional / Classics
                (g.name.localizedCaseInsensitiveContains("spiritual") && (
                    cleanGenre.localizedCaseInsensitiveContains("spirit") ||
                    cleanGenre.localizedCaseInsensitiveContains("devot") ||
                    cleanGenre.localizedCaseInsensitiveContains("classic") ||
                    cleanGenre.localizedCaseInsensitiveContains("heritage") ||
                    cleanGenre.localizedCaseInsensitiveContains("bhajan") ||
                    cleanGenre.localizedCaseInsensitiveContains("rabindra")
                ))
            }) {
                if !categories[langIdx].genres[aliasIdx].trackIds.contains(trackId) {
                    categories[langIdx].genres[aliasIdx].trackIds.append(trackId)
                }
            } else {
                // If under the 5 genre cap, create new genre
                if categories[langIdx].genres.count < 5 || isCustom {
                    let newGroup = AIGenreGroup(
                        id: "\(cleanLang.lowercased())_\(categories[langIdx].genres.count + 1)",
                        name: cleanGenre,
                        icon: genreIcon,
                        description: genreDescription,
                        trackIds: [trackId],
                        isCustom: isCustom
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
                trackIds: [trackId],
                isCustom: isCustom
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

    /// Renames an existing genre folder within a language, migrates tracks, and flags as custom.
    public mutating func renameGenre(
        in language: String,
        oldName: String,
        newName: String,
        newIcon: String? = nil,
        newDescription: String? = nil
    ) {
        let cleanLang = language.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        let cleanNewName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanNewName.isEmpty else { return }

        if let lIdx = categories.firstIndex(where: { $0.language.caseInsensitiveCompare(cleanLang) == .orderedSame }),
           let gIdx = categories[lIdx].genres.firstIndex(where: { $0.name.caseInsensitiveCompare(oldName) == .orderedSame }) {
            categories[lIdx].genres[gIdx].name = cleanNewName
            if let icon = newIcon, !icon.isEmpty {
                categories[lIdx].genres[gIdx].icon = icon
            }
            if let desc = newDescription {
                categories[lIdx].genres[gIdx].description = desc
            }
            if !categories[lIdx].genres[gIdx].aliases.contains(where: { $0.caseInsensitiveCompare(oldName) == .orderedSame }) {
                categories[lIdx].genres[gIdx].aliases.append(oldName)
            }
            categories[lIdx].genres[gIdx].isCustom = true
            self.lastUpdated = Date()
        }
    }

    /// Adds a new custom playlist folder inside a language.
    public mutating func addCustomGenre(
        in language: String,
        name: String,
        icon: String = "music.note",
        description: String = ""
    ) {
        let cleanLang = language.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        let cleanName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanName.isEmpty else { return }

        if let lIdx = categories.firstIndex(where: { $0.language.caseInsensitiveCompare(cleanLang) == .orderedSame }) {
            if let gIdx = categories[lIdx].genres.firstIndex(where: { $0.name.caseInsensitiveCompare(cleanName) == .orderedSame }) {
                categories[lIdx].genres[gIdx].isCustom = true
                if !icon.isEmpty { categories[lIdx].genres[gIdx].icon = icon }
                if !description.isEmpty { categories[lIdx].genres[gIdx].description = description }
            } else {
                let newGroup = AIGenreGroup(
                    id: "\(cleanLang.lowercased())_\(categories[lIdx].genres.count + 1)_\(UUID().uuidString.prefix(4))",
                    name: cleanName,
                    icon: icon,
                    description: description,
                    trackIds: [],
                    isCustom: true
                )
                categories[lIdx].genres.append(newGroup)
            }
        } else {
            let newGroup = AIGenreGroup(
                id: "\(cleanLang.lowercased())_1",
                name: cleanName,
                icon: icon,
                description: description,
                trackIds: [],
                isCustom: true
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

    /// Deletes a genre folder inside a language, optionally migrating its tracks to another folder.
    public mutating func deleteGenre(
        in language: String,
        name: String,
        migrateToGenre: String? = nil
    ) {
        let cleanLang = language.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        guard let lIdx = categories.firstIndex(where: { $0.language.caseInsensitiveCompare(cleanLang) == .orderedSame }),
              let gIdx = categories[lIdx].genres.firstIndex(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            return
        }

        let tracks = categories[lIdx].genres[gIdx].trackIds
        categories[lIdx].genres.remove(at: gIdx)

        if let target = migrateToGenre,
           let targetIdx = categories[lIdx].genres.firstIndex(where: { $0.name.caseInsensitiveCompare(target) == .orderedSame }) {
            for t in tracks {
                if !categories[lIdx].genres[targetIdx].trackIds.contains(t) {
                    categories[lIdx].genres[targetIdx].trackIds.append(t)
                }
            }
        }
        self.lastUpdated = Date()
    }

    /// Moves a track from one genre folder to another within the same language.
    public mutating func moveTrack(
        trackId: String,
        in language: String,
        fromGenre: String,
        toGenre: String
    ) {
        let cleanLang = language.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        guard let lIdx = categories.firstIndex(where: { $0.language.caseInsensitiveCompare(cleanLang) == .orderedSame }),
              let fromIdx = categories[lIdx].genres.firstIndex(where: { $0.name.caseInsensitiveCompare(fromGenre) == .orderedSame }),
              let toIdx = categories[lIdx].genres.firstIndex(where: { $0.name.caseInsensitiveCompare(toGenre) == .orderedSame }) else {
            return
        }

        categories[lIdx].genres[fromIdx].trackIds.removeAll(where: { $0 == trackId })
        if !categories[lIdx].genres[toIdx].trackIds.contains(trackId) {
            categories[lIdx].genres[toIdx].trackIds.append(trackId)
        }
        self.lastUpdated = Date()
    }

    /// Removes a track across all curated categories (e.g. when un-downloaded).
    /// Custom folders (`isCustom == true`) are permanently preserved even if empty.
    public mutating func remove(trackId: String) {
        for lIdx in categories.indices {
            for gIdx in categories[lIdx].genres.indices {
                categories[lIdx].genres[gIdx].trackIds.removeAll(where: { $0 == trackId })
            }
            // Remove empty genres ONLY if NOT marked as custom
            categories[lIdx].genres.removeAll(where: { !$0.isCustom && $0.trackIds.isEmpty })
        }
        // Remove empty language folders ONLY if all genres are empty and non-custom
        categories.removeAll(where: { cat in
            cat.genres.isEmpty || (cat.genres.allSatisfy { $0.trackIds.isEmpty && !$0.isCustom })
        })
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
