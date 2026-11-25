import CoreGraphics
import Foundation

enum FrameSide: String, Codable, Equatable {
    case left
    case right
}

struct PhoneFrameGeometry: Equatable {
    var side: FrameSide
    var portraitAspect: Double
    var frameAspect: Double

    var contentAspect: Double { portraitAspect > 0 ? 1 / portraitAspect : 0 }

    var contentRect: CGRect {
        guard contentAspect.isFinite, frameAspect.isFinite, contentAspect > 0, frameAspect > 0 else { return .zero }
        if abs(frameAspect - contentAspect) / contentAspect < Letterbox.tolerance { return CGRect(x: 0, y: 0, width: 1, height: 1) }
        if frameAspect > contentAspect {
            let width = contentAspect / frameAspect
            return CGRect(x: (1 - width) / 2, y: 0, width: width, height: 1)
        }
        let height = frameAspect / contentAspect
        return CGRect(x: 0, y: (1 - height) / 2, width: 1, height: height)
    }

    func screenPoint(fromFrame point: CGPoint) -> CGPoint {
        let rect = contentRect
        let x = min(max((point.x - rect.minX) / max(rect.width, .leastNormalMagnitude), 0), 1)
        let y = min(max((point.y - rect.minY) / max(rect.height, .leastNormalMagnitude), 0), 1)
        switch side {
        case .left: return CGPoint(x: 1 - y, y: x)
        case .right: return CGPoint(x: y, y: 1 - x)
        }
    }

    func framePoint(fromScreen point: CGPoint) -> CGPoint {
        let rect = contentRect
        let x = min(max(point.x, 0), 1)
        let y = min(max(point.y, 0), 1)
        let fx: Double
        let fy: Double
        switch side {
        case .left: (fx, fy) = (y, 1 - x)
        case .right: (fx, fy) = (1 - y, x)
        }
        return CGPoint(x: rect.minX + fx * rect.width, y: rect.minY + fy * rect.height)
    }

    func contains(framePoint point: CGPoint) -> Bool {
        let rect = contentRect.insetBy(dx: -0.001, dy: -0.001)
        return point.x >= rect.minX && point.x <= rect.maxX && point.y >= rect.minY && point.y <= rect.maxY
    }
}

enum FrameMapping: Equatable {
    case pad(ScreenGeometry)
    case phone(PhoneFrameGeometry)

    static var sideProvider: () -> FrameSide? = { PhoneLandscapeConfig.resolvedSide() }

    static func portraitAspect(frameAspect: Double?) -> Double {
        guard let a = frameAspect, a.isFinite, a > 0 else { return 9 / 19.5 }
        return a < 1 ? a : 1 / a
    }

    static func isLandscape(_ aspect: Double?) -> Bool {
        guard let a = aspect, a.isFinite else { return false }
        return a > 1
    }

    @MainActor static func current(screen: ScreenSource?) -> FrameMapping? {
        if let pad = screen?.geometry { return .pad(pad) }
        if DeviceKind.isPad { return nil }
        guard let aspect = screen?.aspect, isLandscape(aspect), let side = sideProvider() else { return nil }
        return .phone(PhoneFrameGeometry(side: side,
                                         portraitAspect: portraitAspect(frameAspect: aspect),
                                         frameAspect: aspect))
    }

    @MainActor static func isPhoneLandscape(screen: ScreenSource?) -> Bool {
        !DeviceKind.isPad && isLandscape(screen?.aspect)
    }

    static func hasCoordinates(_ action: JObject) -> Bool {
        ["tap", "swipe", "path", "circle"].contains(action["action"]?.str ?? "")
    }

    var padGeometry: ScreenGeometry? {
        guard case .pad(let geometry) = self else { return nil }
        return geometry
    }

    var phoneGeometry: PhoneFrameGeometry? {
        guard case .phone(let geometry) = self else { return nil }
        return geometry
    }

    var screenAspect: Double {
        switch self {
        case .pad(let geometry): return geometry.screenAspect
        case .phone(let geometry): return geometry.portraitAspect
        }
    }

    var contentRect: CGRect {
        switch self {
        case .pad(let geometry): return geometry.contentRect
        case .phone(let geometry): return geometry.contentRect
        }
    }

    func contains(framePoint point: CGPoint) -> Bool {
        switch self {
        case .pad(let geometry): return geometry.contains(framePoint: point)
        case .phone(let geometry): return geometry.contains(framePoint: point)
        }
    }

    func screenPoint(fromFrame point: CGPoint) -> CGPoint {
        switch self {
        case .pad(let geometry): return geometry.screenPoint(fromFrame: point)
        case .phone(let geometry): return geometry.screenPoint(fromFrame: point)
        }
    }

    func framePoint(fromScreen point: CGPoint) -> CGPoint {
        switch self {
        case .pad(let geometry): return geometry.framePoint(fromScreen: point)
        case .phone(let geometry): return geometry.framePoint(fromScreen: point)
        }
    }

    static func toScreen(_ action: JObject, _ mapping: FrameMapping?) throws -> JObject {
        guard let mapping else { return action }
        var out = action
        func map(_ x: Double, _ y: Double) throws -> CGPoint {
            let point = CGPoint(x: x / 1000, y: y / 1000)
            guard mapping.contains(framePoint: point) else {
                throw Actions.ParseError(message: "that point is on a black bar around the mirrored screen, not on it")
            }
            let p = mapping.screenPoint(fromFrame: point)
            return CGPoint(x: min(max(p.x, 0), 1) * 1000, y: min(max(p.y, 0), 1) * 1000)
        }
        func move(_ kx: String, _ ky: String) throws {
            guard let x = action[kx]?.double, let y = action[ky]?.double else { return }
            let p = try map(x, y)
            (out[kx], out[ky]) = (.num(p.x), .num(p.y))
        }
        switch action["action"]?.str {
        case "tap": try move("x", "y")
        case "swipe":
            try move("x1", "y1"); try move("x2", "y2")
            if !points(action).isEmpty {
                out["points"] = .arr(try points(action).map { p in
                    let s = try map(Double(p.x), Double(p.y))
                    return .arr([.num(s.x), .num(s.y)])
                })
            }
        case "path":
            out["points"] = .arr(try points(action).map { p in
                let s = try map(Double(p.x), Double(p.y))
                return .arr([.num(s.x), .num(s.y)])
            })
        case "circle":
            try move("x", "y")
            if let r = action["r"]?.double { out["r"] = .num(r / max(radiusScale(mapping), 0.01)) }
        default: break
        }
        return out
    }

    private static func radiusScale(_ mapping: FrameMapping) -> Double {
        switch mapping {
        case .pad(let geometry): return geometry.contentRect.width
        case .phone(let geometry): return geometry.portraitAspect * geometry.contentRect.height
        }
    }
}
