import AppKit
import BatteryCore
import Foundation
import Observation
import UserNotifications

@Observable
@MainActor
final class BatteryMonitor {
    private let provider: BatteryProvider
    private var timer: Timer?
    @ObservationIgnored private var isScrolling = false
    @ObservationIgnored private var deferredSnapshot: BatterySnapshot?
    @ObservationIgnored private var deferredRefreshDate: Date?
    @ObservationIgnored private var chargeLimitWasReached = false
    @ObservationIgnored private var thermalLimitWasReached = false
    @ObservationIgnored private var notificationPermissionRequested = false

    var snapshot: BatterySnapshot?
    var telemetry: BatteryTelemetry?
    var errorMessage: String?
    var lastRefresh: Date?
    var chargeLimitAlertActive = false
    var thermalLimitAlertActive = false
    var protectionStatusText = "监测中"
    var notificationStatusText = "通知权限未确认"

    init(provider: BatteryProvider) {
        self.provider = provider
    }

    func start() {
        requestNotificationPermission()
        refresh()

        guard timer == nil else {
            return
        }

        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refresh()
            }
        }
    }

    func setScrolling(_ scrolling: Bool) {
        guard isScrolling != scrolling else {
            return
        }

        isScrolling = scrolling

        if !scrolling, let deferredSnapshot, let deferredRefreshDate {
            self.deferredSnapshot = nil
            self.deferredRefreshDate = nil
            publish(snapshot: deferredSnapshot, refreshDate: deferredRefreshDate)
        }
    }

    func refresh() {
        do {
            let latestSnapshot = try provider.snapshot()
            let refreshDate = Date()

            if isScrolling {
                deferredSnapshot = latestSnapshot
                deferredRefreshDate = refreshDate
                return
            }

            publish(snapshot: latestSnapshot, refreshDate: refreshDate)
        } catch BatteryReadError.noBattery {
            snapshot = nil
            telemetry = nil
            deferredSnapshot = nil
            deferredRefreshDate = nil
            errorMessage = "未检测到内置电池"
            lastRefresh = Date()
        } catch {
            snapshot = nil
            telemetry = nil
            deferredSnapshot = nil
            deferredRefreshDate = nil
            errorMessage = "无法读取电池数据"
            lastRefresh = Date()
        }
    }

    private func publish(snapshot latestSnapshot: BatterySnapshot, refreshDate: Date) {
        telemetry = BatteryTelemetry(snapshot: latestSnapshot, timestamp: refreshDate)
        evaluateProtection(snapshot: latestSnapshot)

        if let snapshot, snapshot.hasSameDashboardReading(as: latestSnapshot) {
            lastRefresh = refreshDate
            errorMessage = nil
            return
        }

        snapshot = latestSnapshot
        errorMessage = nil
        lastRefresh = refreshDate
    }

    private func evaluateProtection(snapshot latestSnapshot: BatterySnapshot) {
        let settings = ProtectionSettings.current
        let currentPercent = latestSnapshot.trueChargePercent ?? latestSnapshot.systemChargePercent
        let temperature = latestSnapshot.batteryTemperatureCelsius

        let chargeLimitReached = settings.chargeLimitEnabled
            && latestSnapshot.externalConnected
            && currentPercent.map { $0 >= settings.chargeLimitPercent } == true

        let thermalLimitReached = settings.thermalProtectionEnabled
            && temperature.map { $0 >= settings.thermalLimitCelsius } == true

        chargeLimitAlertActive = chargeLimitReached
        thermalLimitAlertActive = thermalLimitReached
        protectionStatusText = protectionStatus(
            chargeLimitReached: chargeLimitReached,
            thermalLimitReached: thermalLimitReached
        )

        if chargeLimitReached, !chargeLimitWasReached {
            postNotification(
                identifier: "charge-limit",
                title: "已达到充电上限",
                body: "真实电量 \(BatteryFormatter.percent(currentPercent)) 已达到 \(Int(settings.chargeLimitPercent))%，可考虑拔掉电源。"
            )
        }

        if thermalLimitReached, !thermalLimitWasReached {
            postNotification(
                identifier: "thermal-limit",
                title: "电池温度达到热保护阈值",
                body: "电池温度 \(BatteryFormatter.temperature(temperature)) 已达到 \(BatteryFormatter.temperature(settings.thermalLimitCelsius))。"
            )
        }

        chargeLimitWasReached = chargeLimitReached
        thermalLimitWasReached = thermalLimitReached
    }

    private func protectionStatus(chargeLimitReached: Bool, thermalLimitReached: Bool) -> String {
        if chargeLimitReached && thermalLimitReached {
            return "充电上限和热保护已触发"
        }
        if chargeLimitReached {
            return "充电上限已触发"
        }
        if thermalLimitReached {
            return "热保护已触发"
        }
        return "监测中"
    }

    private func requestNotificationPermission() {
        guard !notificationPermissionRequested else {
            return
        }

        notificationPermissionRequested = true

        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let monitor = self else {
                return
            }

            if settings.authorizationStatus == .notDetermined {
                UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
                    let statusText = granted ? "通知已开启" : "通知未授权"
                    Task { @MainActor [monitor, statusText] in
                        monitor.notificationStatusText = statusText
                    }
                }
                return
            }

            let statusText = settings.authorizationStatus.statusText
            Task { @MainActor [monitor, statusText] in
                monitor.notificationStatusText = statusText
            }
        }
    }

    private func postNotification(identifier: String, title: String, body: String) {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            guard let monitor = self else {
                return
            }

            let authorizationStatus = settings.authorizationStatus
            guard authorizationStatus == .authorized || authorizationStatus == .provisional else {
                let statusText = authorizationStatus.statusText
                Task { @MainActor [monitor, statusText] in
                    monitor.notificationStatusText = statusText
                }
                return
            }

            let content = UNMutableNotificationContent()
            content.title = title
            content.body = body
            content.sound = .default

            let request = UNNotificationRequest(
                identifier: "BatteryTruth.\(identifier).\(UUID().uuidString)",
                content: content,
                trigger: nil
            )

            UNUserNotificationCenter.current().add(request)
        }
    }

    func postTestNotification() {
        postNotification(
            identifier: "test",
            title: "BatteryTruth 提醒测试",
            body: "本地通知可用。达到充电上限或热保护阈值时会自动提醒。"
        )
    }

    func copyDiagnostics() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()

        if let snapshot {
            let lastRefreshLine = "Last refresh: \(lastRefresh.map(BatteryFormatter.timestamp) ?? "Unavailable")"
            pasteboard.setString(snapshot.diagnosticText + "\n" + lastRefreshLine, forType: .string)
        } else {
            pasteboard.setString(errorMessage ?? "BatteryTruth: no battery snapshot", forType: .string)
        }
    }
}

private struct ProtectionSettings {
    let chargeLimitEnabled: Bool
    let chargeLimitPercent: Double
    let thermalProtectionEnabled: Bool
    let thermalLimitCelsius: Double

    static var current: ProtectionSettings {
        let defaults = UserDefaults.standard
        return ProtectionSettings(
            chargeLimitEnabled: defaults.object(forKey: "chargeLimitEnabled") as? Bool ?? true,
            chargeLimitPercent: defaults.object(forKey: "chargeLimitPercent") as? Double ?? 80.0,
            thermalProtectionEnabled: defaults.object(forKey: "thermalProtectionEnabled") as? Bool ?? true,
            thermalLimitCelsius: defaults.object(forKey: "thermalLimitCelsius") as? Double ?? 38.0
        )
    }
}

private extension UNAuthorizationStatus {
    var statusText: String {
        switch self {
        case .authorized:
            return "通知已开启"
        case .denied:
            return "通知未授权"
        case .notDetermined:
            return "通知权限未确认"
        case .provisional:
            return "临时通知已开启"
        case .ephemeral:
            return "临时通知已开启"
        @unknown default:
            return "通知状态未知"
        }
    }
}
