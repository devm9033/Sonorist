import Foundation

/// Security and defensive validation layer conforming to ECC Security & Swift Security guidelines.
public enum SecurityAudit {
    
    /// Allowed YouTube, Google media, and verified lyrics domains for API requests and media streaming
    private static let allowedHosts: Set<String> = [
        "music.youtube.com",
        "www.youtube.com",
        "youtube.com",
        "googlevideo.com",
        "ytimg.com",
        "i.ytimg.com",
        "googleusercontent.com",
        "yt3.googleusercontent.com",
        "ggpht.com",
        "yt3.ggpht.com",
        "lrclib.net",
        "music.163.com",
        "163.com",
        "gvt1.com",
        "pollinations.ai",
        "googleapis.com"
    ]
    
    /// Validates an external URL for App Transport Security and trusted domain origin
    public static func validateURL(_ urlString: String) -> URL? {
        guard let url = URL(string: urlString) else {
            return nil
        }
        
        // 1. Allow local file scheme for offline cache and imported local tracks
        if url.isFileURL {
            return url
        }
        
        // 2. Enforce HTTPS (ATS requirement)
        guard url.scheme?.lowercased() == "https" else {
            return nil
        }
        
        // 3. Host validation: must belong to allowed YouTube / Google media / LRCLIB domains
        guard let host = url.host?.lowercased() else {
            return nil
        }
        
        let isAllowed = allowedHosts.contains(where: { host == $0 || host.hasSuffix("." + $0) })
        guard isAllowed else {
            return nil
        }
        
        return url
    }
    
    /// Sanitizes user search queries or ID strings against injection, path traversal and control characters
    public static func sanitizeSearchQuery(_ query: String) -> String {
        let sanitized = query
            .replacingOccurrences(of: "../", with: "")
            .replacingOccurrences(of: "..\\", with: "")
            .replacingOccurrences(of: "\0", with: "")
            .components(separatedBy: .controlCharacters)
            .joined()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return String(sanitized.prefix(250))
    }
    
    /// Validates YouTube Video ID (standard base64url 11-character string: [a-zA-Z0-9_-]{11})
    public static func validateVideoID(_ videoId: String) -> Bool {
        let pattern = "^[a-zA-Z0-9_-]{11}$"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return false }
        let range = NSRange(location: 0, length: videoId.utf16.count)
        return regex.firstMatch(in: videoId, options: [], range: range) != nil
    }
}
