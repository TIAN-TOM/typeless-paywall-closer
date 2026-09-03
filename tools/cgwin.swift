import CoreGraphics
import Foundation
let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as! [[String: Any]]
for w in list where (w["kCGWindowOwnerName"] as? String) == "Typeless" {
    let b = w["kCGWindowBounds"] as? [String: Any] ?? [:]
    print("id=\(w["kCGWindowNumber"] ?? "?") layer=\(w["kCGWindowLayer"] ?? "?") onscreen=\(w["kCGWindowIsOnscreen"] ?? false) alpha=\(w["kCGWindowAlpha"] ?? "?") name=\(w["kCGWindowName"] ?? "") bounds=\(b)")
}
print("done")
