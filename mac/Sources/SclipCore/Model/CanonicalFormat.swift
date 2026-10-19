/// Platformlardan bağımsız kanonik pano biçim anahtarları.
public enum CanonicalFormat: String, Sendable, CaseIterable {
    case plainText = "text/plain"
    case html = "text/html"
    case rtf = "text/rtf"
    case png = "image/png"
    case jpeg = "image/jpeg"
    case gif = "image/gif"
    case webp = "image/webp"
    case svg = "image/svg+xml"
    case pdf = "application/pdf"
}
