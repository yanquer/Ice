// 隔离真实鼠标和事件投递，验证生产移动方法在超时、取消及回退失败时恢复光标。
import Cocoa

/// 提供可识别的菜单栏项目，不查询真实窗口。
struct MenuBarItem {
    let isMovable: Bool = true
    let ownerPID: pid_t = 0
    let logString: String = "test-item"
}

/// 保留生产方法的错误分类，避免失败被当作正常返回。
struct EventError: Error {
    enum Code { case invalidCursorLocation, invalidEventSource, invalidItem, eventCreationFailure, notMovable, couldNotComplete, invalidAppState }
    let code: Code
    let item: MenuBarItem
}

/// 标记模拟链路中互不相同的原始错误。
enum TestFailure: Error { case confirmation, event, fallback, wake }

/// 模拟事件来源位置，不连接系统事件监听器。
enum EventTap {
    enum Location { case pid(pid_t), sessionEventTap }
}

/// 用于创建测试事件的类型，不投递到系统。
enum MenuBarItemEventType {
    enum State { case leftMouseDown, leftMouseUp }
    case move(State)
}

extension CGEvent {
    /// 只构造内存中的事件，所有实际投递由测试桩接管。
    static func menuBarItemEvent(type: MenuBarItemEventType, location: CGPoint, item: MenuBarItem, pid: pid_t, source: CGEventSource) -> CGEvent? {
        CGEvent(source: source)
    }
}

/// 用计数与位置替代系统光标，检测提前显示、隐藏泄漏和过期位置恢复。
@MainActor
enum MouseCursor {
    static var locationCoreGraphics: CGPoint? = CGPoint(x: 100, y: 200)
    static var hideCount: Int = 0
    static var hides: Int = 0
    /// 记录隐藏次数并拒绝嵌套隐藏。
    static func hide() { precondition(hideCount == 0); hideCount += 1; hides += 1 }
    /// 检查显示与隐藏严格配对。
    static func show() { precondition(hideCount == 1); hideCount -= 1 }
    /// 模拟将光标移回本次操作开始时的位置。
    static func warp(to point: CGPoint) { locationCoreGraphics = point }
}

/// 收集生产日志以验证原始回退错误没有丢失。
@MainActor
struct Logger {
    static let itemManager: Logger = Logger()
    static var messages: [String] = []
    /// 收集正常阶段日志。
    func info(_ message: String) { Self.messages.append(message) }
    /// 收集调试阶段日志。
    func debug(_ message: String) { Self.messages.append(message) }
    /// 收集失败诊断日志。
    func error(_ message: String) { Self.messages.append(message) }
    /// 收集重试原因日志。
    func warning(_ message: String) { Self.messages.append(message) }
}

/// 检查事件监听停止后，无论成功失败都能恢复。
@MainActor
final class AppState {
    let eventManager: EventManager = EventManager()
    final class EventManager {
        var stopped: Bool = false
        /// 模拟暂停应用事件监听。
        func stopAll() { stopped = true }
        /// 模拟恢复应用事件监听。
        func startAll() { stopped = false }
    }
}

/// 为生产移动方法提供可控超时和取消，不修改用户菜单栏或偏好。
@MainActor
final class MenuBarItemManager {
    enum Scenario: CaseIterable { case success, retry, exhausted, cancelEvent, cancelWait, eventAndFallbackFailure, wakeFailure }
    enum MoveDestination {
        case leftOfItem(MenuBarItem)
        var logString: String { "test-destination" }
    }
    let scenario: Scenario
    var appState: AppState? = AppState()
    var itemMoveCount: Int = 0
    var lastItemMoveStartDate: Date?
    var attempts: Int = 0
    var positioned: Bool = false
    var wakeEvents: Int = 0
    /// 选择当前测试的单一故障条件。
    init(scenario: Scenario) { self.scenario = scenario }
    /// 为移动准备阶段提供固定窗口坐标。
    func getCurrentFrame(for item: MenuBarItem) -> CGRect? { CGRect(x: 10, y: 0, width: 20, height: 30) }
    /// 提供模拟拖动落点。
    func getEndPoint(for destination: MoveDestination) throws -> CGPoint { .zero }
    /// 提供模拟回退落点。
    func getFallbackPoint(for item: MenuBarItem) throws -> CGPoint { .zero }
    /// 返回模拟目标项目。
    func getTargetItem(for destination: MoveDestination) -> MenuBarItem { MenuBarItem() }
    /// 不修改系统事件抑制配置。
    func permitAllEvents(for stateID: CGEventSourceStateID, during states: [CGEventSuppressionState], suppressionInterval: TimeInterval, item: MenuBarItem) throws { }
    /// 确认准备等待期间光标可见。
    func waitForNoModifiersPressed() async throws { precondition(MouseCursor.hideCount == 0) }
    /// 确认等待鼠标静止期间光标可见。
    func waitForMouseToStopMoving() async throws { precondition(MouseCursor.hideCount == 0) }
    /// 在模拟拖动期间注入取消或事件错误。
    func scrombleEvent(_ event: CGEvent, from first: EventTap.Location, to second: EventTap.Location, waitingForFrameChangeOf item: MenuBarItem) async throws {
        precondition(MouseCursor.hideCount == 1)
        if scenario == .cancelEvent { throw CancellationError() }
        if scenario == .eventAndFallbackFailure { throw TestFailure.event }
    }
    /// 在唤醒期间检查隐藏范围，并按场景注入失败。
    func scrombleEvent(_ event: CGEvent, from first: EventTap.Location, to second: EventTap.Location, item: MenuBarItem) async throws {
        precondition(MouseCursor.hideCount == 1)
        wakeEvents += 1
        if scenario == .wakeFailure { throw TestFailure.wake }
    }
    /// 验证回退仍处于本次拖动的隐藏范围，独立保留回退错误。
    func postEventAndWaitToReceive(_ event: CGEvent, to location: EventTap.Location, item: MenuBarItem) async throws {
        precondition(MouseCursor.hideCount == 1)
        if scenario == .eventAndFallbackFailure { throw TestFailure.fallback }
    }
    /// 确认位置检查与重试决策期间光标已显示。
    func itemHasCorrectPosition(item: MenuBarItem, for destination: MoveDestination) throws -> Bool {
        precondition(MouseCursor.hideCount == 0)
        return positioned
    }
    /// 模拟原故障的确认超时，等待期间检查光标可见并模拟用户移动鼠标。
    func waitForCorrectPosition(item: MenuBarItem, to destination: MoveDestination, timeout: Duration) async throws {
        precondition(MouseCursor.hideCount == 0)
        attempts += 1
        let expected: CGPoint = CGPoint(x: 100 + (attempts - 1) * 10, y: 200)
        precondition(MouseCursor.locationCoreGraphics == expected)
        MouseCursor.locationCoreGraphics = CGPoint(x: expected.x + 10, y: expected.y)
        try await Task.sleep(for: .milliseconds(30))
        precondition(MouseCursor.hideCount == 0)
        if scenario == .cancelWait { throw CancellationError() }
        if scenario == .exhausted || scenario == .wakeFailure || (scenario == .retry && attempts == 1) { throw TestFailure.confirmation }
        positioned = true
    }
}

/// 对成功、超时、重试、取消和回退失败执行同一套生命周期检查。
@main
@MainActor
private enum ItemCursorRegressionTests {
    /// 运行生产方法，确保失败按原始原因传递且没有光标隐藏或监听暂停泄漏。
    static func main() async throws {
        for scenario: MenuBarItemManager.Scenario in MenuBarItemManager.Scenario.allCases {
            MouseCursor.locationCoreGraphics = CGPoint(x: 100, y: 200)
            MouseCursor.hides = 0
            Logger.messages = []
            let manager: MenuBarItemManager = MenuBarItemManager(scenario: scenario)
            var failure: Error?
            do {
                try await manager.move(item: MenuBarItem(), to: .leftOfItem(MenuBarItem()))
            } catch { failure = error }
            switch scenario {
            case .success: precondition(failure == nil && manager.attempts == 1 && MouseCursor.hides == 1)
            case .retry: precondition(failure == nil && manager.attempts == 2 && manager.wakeEvents == 2 && MouseCursor.hides == 3)
            case .exhausted: precondition(failure as? TestFailure == .confirmation && manager.attempts == 5 && manager.wakeEvents == 8)
            case .cancelEvent, .cancelWait: precondition(failure is CancellationError && manager.wakeEvents == 0)
            case .eventAndFallbackFailure:
                precondition(failure as? TestFailure == .event)
                precondition(Logger.messages.contains { $0.contains("fallback") && $0.contains("error: fallback") })
            case .wakeFailure: precondition(failure as? TestFailure == .wake && manager.wakeEvents == 1)
            }
            precondition(MouseCursor.hideCount == 0 && manager.itemMoveCount == 0 && manager.appState?.eventManager.stopped == false)
            precondition(Logger.messages.contains { $0.contains("hide scope duration:") })
            print("PASS: cursor lifecycle: \(scenario)")
        }
        print("All item cursor regression cases passed.")
    }
}
