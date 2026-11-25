import CoreGraphics
import XCTest
@testable import IPhoneAgent

@MainActor final class PhoneLandscapeTests: XCTestCase {
    private let portrait = 390.0 / 844.0

    private func geometry(_ side: FrameSide, aspect: Double = 720.0 / 334.0) -> FrameMapping {
        .phone(PhoneFrameGeometry(side: side, portraitAspect: portrait, frameAspect: aspect))
    }

    private func assertPoint(_ actual: CGPoint, _ expected: CGPoint, accuracy: Double = 1e-9,
                             file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.x, expected.x, accuracy: accuracy, file: file, line: line)
        XCTAssertEqual(actual.y, expected.y, accuracy: accuracy, file: file, line: line)
    }

    private func assertPoints(_ actual: [CGPoint], _ expected: [CGPoint], accuracy: Double = 1e-9,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(actual.count, expected.count, file: file, line: line)
        guard actual.count == expected.count else { return }
        for (a, b) in zip(actual, expected) { assertPoint(a, b, accuracy: accuracy, file: file, line: line) }
    }

    func testPortraitKeepsEveryCoordinateUnchanged() throws {
        let screen = FakeScreen()
        screen.aspect = portrait
        XCTAssertNil(FrameMapping.current(screen: screen))
        let action: JObject = ["action": .str("tap"), "x": .int(321), "y": .int(654)]
        XCTAssertEqual(try FrameMapping.toScreen(action, nil), action)
    }

    func testLandscapeLeftUsesThePhysicalLeftTransform() {
        let g = geometry(.left)
        assertPoint(g.screenPoint(fromFrame: CGPoint(x: 0.2, y: 0.3)), CGPoint(x: 0.7, y: 0.2))
        assertPoint(g.screenPoint(fromFrame: CGPoint(x: 0, y: 0)), CGPoint(x: 1, y: 0))
        assertPoint(g.screenPoint(fromFrame: CGPoint(x: 1, y: 1)), CGPoint(x: 0, y: 1))
    }

    func testLandscapeRightUsesThePhysicalRightTransform() {
        let g = geometry(.right)
        assertPoint(g.screenPoint(fromFrame: CGPoint(x: 0.2, y: 0.3)), CGPoint(x: 0.3, y: 0.8))
        assertPoint(g.screenPoint(fromFrame: CGPoint(x: 0, y: 0)), CGPoint(x: 0, y: 1))
        assertPoint(g.screenPoint(fromFrame: CGPoint(x: 1, y: 1)), CGPoint(x: 1, y: 0))
    }

    func testCenterCornersAndEdgesRoundTripInBothDirections() {
        let points = [CGPoint(x: 0, y: 0), CGPoint(x: 0.5, y: 0.5), CGPoint(x: 1, y: 1),
                      CGPoint(x: 0.02, y: 0.98), CGPoint(x: 0.98, y: 0.02), CGPoint(x: 0.5, y: 1)]
        for side in [FrameSide.left, .right] {
            let g = geometry(side)
            for point in points {
                let back = g.framePoint(fromScreen: g.screenPoint(fromFrame: point))
                assertPoint(back, point)
            }
        }
    }

    func testDifferentLandscapeResolutionsUseTheCurrentFrameAspect() {
        for aspect in [720.0 / 334.0, 1560.0 / 718.0, 1024.0 / 768.0] {
            let g = geometry(.left, aspect: aspect)
            let point = CGPoint(x: 0.4, y: 0.6)
            let back = g.framePoint(fromScreen: g.screenPoint(fromFrame: point))
            assertPoint(back, point)
        }
        let boxed = geometry(.left, aspect: 1024.0 / 768.0)
        XCTAssertLessThan(boxed.contentRect.height, 1)
        XCTAssertEqual(boxed.contentRect.width, 1, accuracy: 1e-9)
    }

    func testTapSwipePathAndCircleMapOnce() throws {
        let action: JObject = [
            "action": .str("swipe"),
            "x1": .int(513), "y1": .int(658), "x2": .int(200), "y2": .int(300),
            "points": .arr([.arr([.int(513), .int(658)]), .arr([.int(200), .int(300)])]),
            "r": .int(100)
        ]
        let left = try FrameMapping.toScreen(action, geometry(.left))
        XCTAssertEqual(left["x1"]?.double ?? 0, 342, accuracy: 1e-6)
        XCTAssertEqual(left["y1"]?.double ?? 0, 513, accuracy: 1e-6)
        assertPoints(points(left), [CGPoint(x: 342, y: 513), CGPoint(x: 700, y: 200)], accuracy: 1e-6)
        let right = try FrameMapping.toScreen(action, geometry(.right))
        XCTAssertEqual(right["x1"]?.double ?? 0, 658, accuracy: 1e-6)
        XCTAssertEqual(right["y1"]?.double ?? 0, 487, accuracy: 1e-6)
        let circle: JObject = ["action": .str("circle"), "x": .int(513), "y": .int(658), "r": .int(100)]
        let boxedMapping = geometry(.left, aspect: 1024.0 / 768.0)
        let boxed = try FrameMapping.toScreen(circle, boxedMapping)
        let scale = boxedMapping.screenAspect * boxedMapping.contentRect.height
        XCTAssertEqual(boxed["r"]?.double ?? 0, 100 / scale, accuracy: 1e-6)
    }

    func testPointerPathMovesHomeAndBackIntoFrameCoordinates() {
        let left = geometry(.left).phoneGeometry!
        assertPoints(pointerPath(["action": .str("home")], phone: left),
                     [CGPoint(x: 0.995, y: 0.5), CGPoint(x: 0.6, y: 0.5)])
        let right = geometry(.right).phoneGeometry!
        assertPoints(pointerPath(["action": .str("home")], phone: right),
                     [CGPoint(x: 0.005, y: 0.5), CGPoint(x: 0.4, y: 0.5)])
    }

    func testHistoricalTracePointMapsToPortraitPointerCoordinates() throws {
        let tap: JObject = ["action": .str("tap"), "x": .int(513), "y": .int(658)]
        let left = try FrameMapping.toScreen(tap, geometry(.left))
        let right = try FrameMapping.toScreen(tap, geometry(.right))
        XCTAssertEqual(left["x"]?.double ?? 0, 342, accuracy: 1e-6)
        XCTAssertEqual(left["y"]?.double ?? 0, 513, accuracy: 1e-6)
        XCTAssertEqual(right["x"]?.double ?? 0, 658, accuracy: 1e-6)
        XCTAssertEqual(right["y"]?.double ?? 0, 487, accuracy: 1e-6)
    }

    func testAgentUsesTheSelectedLandscapeOrientation() async throws {
        let provider = FrameMapping.sideProvider
        let wasPad = DeviceKind.isPad
        FrameMapping.sideProvider = { .left }
        DeviceKind.isPad = false
        defer { FrameMapping.sideProvider = provider; DeviceKind.isPad = wasPad }
        let phone = FakeGestures(), screen = FakeScreen()
        screen.aspect = 720.0 / 334.0
        let actor = FakeModel { _ in "THINK: target\nDO: tap 513 658" }
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: nil, trace: nil)
        _ = try await agent.step()
        XCTAssertEqual(phone.taps.count, 1)
        XCTAssertEqual(phone.taps.first?.x ?? 0, 0.342, accuracy: 1e-9)
        XCTAssertEqual(phone.taps.first?.y ?? 0, 0.513, accuracy: 1e-9)
    }

    func testUnknownLandscapeBlocksCoordinateActions() async throws {
        let provider = FrameMapping.sideProvider
        let wasPad = DeviceKind.isPad
        FrameMapping.sideProvider = { nil }
        DeviceKind.isPad = false
        defer { FrameMapping.sideProvider = provider; DeviceKind.isPad = wasPad }
        let phone = FakeGestures(), screen = FakeScreen()
        screen.aspect = 720.0 / 334.0
        let actor = FakeModel { _ in "THINK: unknown\nDO: tap 513 658" }
        let agent = AgentLoop(phone: phone, screen: screen, actor: actor, planner: nil, trace: nil)
        do {
            _ = try await agent.step()
            XCTFail("an unknown landscape side must not tap")
        } catch {}
        XCTAssertTrue(phone.taps.isEmpty)
    }

    func testIPadWithoutGeometryNeverUsesPhoneLandscapeMapping() {
        let provider = FrameMapping.sideProvider
        let wasPad = DeviceKind.isPad
        FrameMapping.sideProvider = { .left }
        DeviceKind.isPad = true
        defer { FrameMapping.sideProvider = provider; DeviceKind.isPad = wasPad }
        let screen = FakeScreen()
        screen.aspect = 720.0 / 334.0
        screen.geometry = nil
        XCTAssertNil(FrameMapping.current(screen: screen))
    }
}
