import Foundation

// MARK: - Core AI Curated Playlist Models

/// Represents a user-created subfolder within a language (e.g. "Spiritual", "Rabindra Sangeet", "Party").
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
        icon: String = "folder.fill",
        description: String = "",
        trackIds: [String] = [],
        isCustom: Bool = true,
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
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "folder.fill"
        description = try container.decodeIfPresent(String.self, forKey: .description) ?? ""
        trackIds = try container.decodeIfPresent([String].self, forKey: .trackIds) ?? []
        isCustom = try container.decodeIfPresent(Bool.self, forKey: .isCustom) ?? false
        aliases = try container.decodeIfPresent([String].self, forKey: .aliases) ?? []
    }
}

/// Represents a top-level language folder (e.g. Bengali, Hindi, English, Punjabi).
/// Songs by default lay directly in `directTrackIds`. If user adds subfolders, matching songs live in `genres`.
public struct AILanguageCategory: Codable, Identifiable, Hashable, Sendable {
    public let id: String
    public var language: String
    public var icon: String
    public var genres: [AIGenreGroup] // user-created subfolders
    public var directTrackIds: [String] // songs laying directly in the language folder

    public var totalTrackCount: Int {
        Set(directTrackIds + genres.flatMap { $0.trackIds }).count
    }

    /// User-friendly alias
    public var subfolders: [AIGenreGroup] {
        get { genres }
        set { genres = newValue }
    }

    public init(
        id: String = UUID().uuidString,
        language: String,
        icon: String = "folder.fill",
        genres: [AIGenreGroup] = [],
        directTrackIds: [String] = []
    ) {
        self.id = id
        self.language = language
        self.icon = icon
        self.genres = genres
        self.directTrackIds = directTrackIds
    }

    enum CodingKeys: String, CodingKey {
        case id, language, icon, genres, directTrackIds
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        language = try container.decode(String.self, forKey: .language)
        icon = try container.decodeIfPresent(String.self, forKey: .icon) ?? "folder.fill"
        let decodedGenres = try container.decodeIfPresent([AIGenreGroup].self, forKey: .genres) ?? []
        var direct = try container.decodeIfPresent([String].self, forKey: .directTrackIds) ?? []

        // Migration: If decoded genres contain non-custom auto-generated folders,
        // flatten their tracks directly into directTrackIds so songs lay cleanly in the language folder!
        var retainedSubfolders: [AIGenreGroup] = []
        for g in decodedGenres {
            if g.isCustom {
                retainedSubfolders.append(g)
            } else {
                for tid in g.trackIds where !direct.contains(tid) {
                    direct.append(tid)
                }
            }
        }
        self.genres = retainedSubfolders
        self.directTrackIds = direct
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(language, forKey: .language)
        try container.encode(icon, forKey: .icon)
        try container.encode(genres, forKey: .genres)
        try container.encode(directTrackIds, forKey: .directTrackIds)
    }
}

/// Root container persisted on disk at `AICuratedPlaylists.json`.
public struct AICuratedLibrary: Codable, Sendable {
    public var lastUpdated: Date
    public var categories: [AILanguageCategory]

    public var totalTrackCount: Int {
        Set(categories.flatMap { $0.directTrackIds + $0.genres.flatMap { $0.trackIds } }).count
    }

    public init(lastUpdated: Date = Date(), categories: [AILanguageCategory] = []) {
        self.lastUpdated = lastUpdated
        self.categories = categories
    }

    /// Safely adds a track to a specific language.
    /// AI NEVER creates subfolders. Tracks ONLY go into user-created subfolders if they match.
    /// Otherwise, tracks lay directly in the language folder (`directTrackIds`).
    public mutating func insert(
        trackId: String,
        language: String,
        genreName: String = "",
        genreIcon: String = "folder.fill",
        genreDescription: String = "",
        isCustom: Bool = false
    ) {
        let cleanLang = language.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        let cleanGenre = genreName.trimmingCharacters(in: .whitespacesAndNewlines)
        let isUnfiled = cleanGenre.isEmpty || cleanGenre.caseInsensitiveCompare("none") == .orderedSame || cleanGenre.caseInsensitiveCompare("other") == .orderedSame

        if let lIdx = categories.firstIndex(where: { $0.language.caseInsensitiveCompare(cleanLang) == .orderedSame }) {
            // 1. If cleanGenre matches an existing user-created subfolder:
            if !isUnfiled, let genreIdx = categories[lIdx].genres.firstIndex(where: { 
                $0.name.caseInsensitiveCompare(cleanGenre) == .orderedSame ||
                $0.aliases.contains(where: { $0.caseInsensitiveCompare(cleanGenre) == .orderedSame }) ||
                ($0.name.localizedCaseInsensitiveContains("spiritual") && (
                    cleanGenre.localizedCaseInsensitiveContains("spirit") ||
                    cleanGenre.localizedCaseInsensitiveContains("devot") ||
                    cleanGenre.localizedCaseInsensitiveContains("bhajan") ||
                    cleanGenre.localizedCaseInsensitiveContains("sacred") ||
                    cleanGenre.localizedCaseInsensitiveContains("prayer")
                )) ||
                ($0.name.localizedCaseInsensitiveContains("rabindra") && (
                    cleanGenre.localizedCaseInsensitiveContains("rabindra") ||
                    cleanGenre.localizedCaseInsensitiveContains("tagore")
                ))
            }) {
                categories[lIdx].directTrackIds.removeAll(where: { $0 == trackId })
                if !categories[lIdx].genres[genreIdx].trackIds.contains(trackId) {
                    categories[lIdx].genres[genreIdx].trackIds.append(trackId)
                }
            } else if isCustom && !isUnfiled {
                // User explicitly created this subfolder:
                categories[lIdx].directTrackIds.removeAll(where: { $0 == trackId })
                let newGroup = AIGenreGroup(
                    id: "\(cleanLang.lowercased())_\(categories[lIdx].genres.count + 1)_\(UUID().uuidString.prefix(4))",
                    name: cleanGenre,
                    icon: genreIcon,
                    description: genreDescription,
                    trackIds: [trackId],
                    isCustom: true
                )
                categories[lIdx].genres.append(newGroup)
            } else {
                // Song does not match any user subfolder, or is unidentifiable:
                // Lay directly in the language folder below the subfolders!
                for gIdx in categories[lIdx].genres.indices {
                    categories[lIdx].genres[gIdx].trackIds.removeAll(where: { $0 == trackId })
                }
                if !categories[lIdx].directTrackIds.contains(trackId) {
                    categories[lIdx].directTrackIds.append(trackId)
                }
            }
        } else {
            // New language category:
            if isCustom && !isUnfiled {
                let newGroup = AIGenreGroup(
                    id: "\(cleanLang.lowercased())_1",
                    name: cleanGenre,
                    icon: genreIcon,
                    description: genreDescription,
                    trackIds: [trackId],
                    isCustom: true
                )
                let newCat = AILanguageCategory(
                    id: cleanLang.lowercased(),
                    language: cleanLang,
                    icon: Self.defaultIcon(for: cleanLang),
                    genres: [newGroup],
                    directTrackIds: []
                )
                categories.append(newCat)
            } else {
                // AI classification creates the language folder ONLY, with all songs laying in directTrackIds!
                let newCat = AILanguageCategory(
                    id: cleanLang.lowercased(),
                    language: cleanLang,
                    icon: Self.defaultIcon(for: cleanLang),
                    genres: [],
                    directTrackIds: [trackId]
                )
                categories.append(newCat)
            }
        }

        self.lastUpdated = Date()
    }

    /// Renames an existing subfolder within a language, migrates tracks, and flags as custom.
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

    /// Adds a new user subfolder inside a language.
    public mutating func addCustomGenre(
        in language: String,
        name: String,
        icon: String = "folder.fill",
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
                genres: [newGroup],
                directTrackIds: []
            )
            categories.append(newCat)
        }
        self.lastUpdated = Date()
    }

    /// Deletes a subfolder inside a language.
    /// Tracks are automatically returned to laying directly in the language folder (`directTrackIds`) so nothing is ever lost.
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
            for t in tracks where !categories[lIdx].genres[targetIdx].trackIds.contains(t) {
                categories[lIdx].genres[targetIdx].trackIds.append(t)
            }
        } else {
            // Return tracks directly to laying in the language folder!
            for t in tracks where !categories[lIdx].directTrackIds.contains(t) {
                categories[lIdx].directTrackIds.append(t)
            }
        }
        self.lastUpdated = Date()
    }

    /// Moves a track between subfolders, or to/from the language folder root.
    public mutating func moveTrack(
        trackId: String,
        in language: String,
        fromGenre: String,
        toGenre: String
    ) {
        let cleanLang = language.trimmingCharacters(in: .whitespacesAndNewlines).capitalized
        guard let lIdx = categories.firstIndex(where: { $0.language.caseInsensitiveCompare(cleanLang) == .orderedSame }) else {
            return
        }

        // 1. Remove from source
        if fromGenre.isEmpty || fromGenre.caseInsensitiveCompare("root") == .orderedSame || fromGenre.caseInsensitiveCompare("main") == .orderedSame {
            categories[lIdx].directTrackIds.removeAll(where: { $0 == trackId })
        } else if let fromIdx = categories[lIdx].genres.firstIndex(where: { $0.name.caseInsensitiveCompare(fromGenre) == .orderedSame }) {
            categories[lIdx].genres[fromIdx].trackIds.removeAll(where: { $0 == trackId })
        }

        // 2. Add to destination
        if toGenre.isEmpty || toGenre.caseInsensitiveCompare("root") == .orderedSame || toGenre.caseInsensitiveCompare("main") == .orderedSame {
            if !categories[lIdx].directTrackIds.contains(trackId) {
                categories[lIdx].directTrackIds.append(trackId)
            }
        } else if let toIdx = categories[lIdx].genres.firstIndex(where: { $0.name.caseInsensitiveCompare(toGenre) == .orderedSame }) {
            if !categories[lIdx].genres[toIdx].trackIds.contains(trackId) {
                categories[lIdx].genres[toIdx].trackIds.append(trackId)
            }
        }
        self.lastUpdated = Date()
    }

    /// Removes a track across all curated categories (e.g. when un-downloaded).
    /// Custom subfolders (`isCustom == true`) are permanently preserved even if empty.
    public mutating func remove(trackId: String) {
        for lIdx in categories.indices {
            categories[lIdx].directTrackIds.removeAll(where: { $0 == trackId })
            for gIdx in categories[lIdx].genres.indices {
                categories[lIdx].genres[gIdx].trackIds.removeAll(where: { $0 == trackId })
            }
            // Remove empty subfolders ONLY if NOT custom
            categories[lIdx].genres.removeAll(where: { !$0.isCustom && $0.trackIds.isEmpty })
        }
        // Remove empty language folders ONLY if all direct tracks and subfolders are empty and non-custom
        categories.removeAll(where: { cat in
            cat.directTrackIds.isEmpty && (
                cat.genres.isEmpty || cat.genres.allSatisfy { $0.trackIds.isEmpty && !$0.isCustom }
            )
        })
        self.lastUpdated = Date()
    }

    /// Returns the language category containing this track, if any.
    public func category(for trackId: String) -> AILanguageCategory? {
        categories.first { cat in
            cat.directTrackIds.contains(trackId) || cat.genres.contains(where: { $0.trackIds.contains(trackId) })
        }
    }

    /// Returns the user subfolder containing this track, if any.
    public func subfolder(for trackId: String) -> AIGenreGroup? {
        for cat in categories {
            if let sub = cat.genres.first(where: { $0.trackIds.contains(trackId) }) {
                return sub
            }
        }
        return nil
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
