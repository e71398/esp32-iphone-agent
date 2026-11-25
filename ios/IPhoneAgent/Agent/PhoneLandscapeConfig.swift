import Foundation
import UIKit

enum PhoneLandscapeMode: String {
    case auto
    case left
    case right
    case off
}

enum PhoneLandscapeConfig {
    static let key = "IA.phoneLandscapeMode"

    private static let started: Void = {
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
    }()

    static var mode: PhoneLandscapeMode {
        get { PhoneLandscapeMode(rawValue: UserDefaults.standard.string(forKey: key) ?? "") ?? .auto }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: key) }
    }

    static func prepare() {
        _ = started
    }

    static func resolvedSide() -> FrameSide? {
        prepare()
        switch mode {
        case .left: return .left
        case .right: return .right
        case .off: return nil
        case .auto:
            switch UIDevice.current.orientation {
            case .landscapeLeft: return .left
            case .landscapeRight: return .right
            default: return nil
            }
        }
    }
}
