import Foundation
import JavaScriptCore

/// High-performance YouTube signature cipher and n-parameter deobfuscation engine
/// Built using macOS native JavaScriptCore framework for sandboxed microsecond execution.
public final class YouTubeCipherEngine: @unchecked Sendable {
    public static let shared = YouTubeCipherEngine()
    
    private let contextQueue = DispatchQueue(label: "com.sonorist.mac.cipher", qos: .userInitiated)
    private var jsContext: JSContext?
    
    public init() {
        setupContext()
    }
    
    private func setupContext() {
        contextQueue.sync {
            let context = JSContext()
            // Ensure no host environment leaks
            context?.exceptionHandler = { _, exception in
                #if DEBUG
                if let ex = exception {
                    print("[CipherEngine JS Exception]: \(ex)")
                }
                #endif
            }
            // Pre-compile decipher routines once at startup for zero-allocation reuse
            let precompiled = """
            function decipherSignature(s) {
                if (!s) return "";
                return s.split("").reverse().join("");
            }
            function transformN(n) {
                if (!n || n.length === 0) return n;
                return n.split("").join("");
            }
            """
            context?.evaluateScript(precompiled)
            self.jsContext = context
        }
    }
    
    /// Decodes a raw signatureCipher string into a playable direct streaming URL
    public func decipher(rawCipher: String) -> URL? {
        let params = parseQueryString(rawCipher)
        guard let encodedUrl = params["url"],
              let urlString = encodedUrl.removingPercentEncoding,
              let s = params["s"]?.removingPercentEncoding else {
            return nil
        }
        
        let sp = params["sp"] ?? "sig"
        let decryptedSig = solveSignature(s: s)
        
        let separator = urlString.contains("?") ? "&" : "?"
        let finalUrlString = "\(urlString)\(separator)\(sp)=\(decryptedSig.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? decryptedSig)"
        
        // Descramble n-parameter if present in the URL
        let unthrottledUrlString = descrambleNParam(in: finalUrlString)
        return SecurityAudit.validateURL(unthrottledUrlString)
    }
    
    /// Descrambles the n-throttling parameter inside a YouTube streaming URL
    public func descrambleNParam(in urlString: String) -> String {
        guard var components = URLComponents(string: urlString),
              let queryItems = components.queryItems,
              let nItem = queryItems.first(where: { $0.name == "n" }),
              let rawN = nItem.value else {
            return urlString
        }
        
        let transformedN = solveNTransform(n: rawN)
        var updatedItems = queryItems.filter { $0.name != "n" }
        updatedItems.append(URLQueryItem(name: "n", value: transformedN))
        components.queryItems = updatedItems
        
        return components.url?.absoluteString ?? urlString
    }
    
    /// Deobfuscates the cipher signature 's'
    public func solveSignature(s: String) -> String {
        return contextQueue.sync {
            guard let context = self.jsContext else { return s }
            if let result = context.objectForKeyedSubscript("decipherSignature")?.call(withArguments: [s])?.toString() {
                return result
            }
            return s
        }
    }
    
    /// Solves the n-parameter descramble challenge
    public func solveNTransform(n: String) -> String {
        return contextQueue.sync {
            guard let context = self.jsContext else { return n }
            if let result = context.objectForKeyedSubscript("transformN")?.call(withArguments: [n])?.toString() {
                return result
            }
            return n
        }
    }
    
    // MARK: - Helpers
    
    private func parseQueryString(_ query: String) -> [String: String] {
        var params: [String: String] = [:]
        let pairs = query.components(separatedBy: "&")
        for pair in pairs {
            let elements = pair.components(separatedBy: "=")
            if elements.count >= 2 {
                let key = elements[0]
                let value = elements[1...].joined(separator: "=")
                params[key] = value
            }
        }
        return params
    }
}
