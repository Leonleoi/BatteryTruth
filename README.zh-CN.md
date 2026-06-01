# BatteryTruth

[English](README.md) | [中文](README.zh-CN.md)

BatteryTruth 是一个原生 macOS SwiftUI 应用，用于从 Mac 电池控制器读取真实电池容量、真实电池健康度和实时功率数据。

项目面向 macOS 15+，使用 Swift Package Manager 构建和打包。

## 功能

- 真实电量百分比，精确到小数点后两位
- 真实电池健康度百分比，精确到小数点后两位
- 不使用固定机型设计容量表：`DesignCapacity` 从当前 Mac 的电池控制器读取
- 实时充电功率和掉电功率
- 电压、电流、电池温度、虚拟温度、循环次数、设计循环次数和适配器数据
- 优先读取 `AppleSmartBattery` raw 数据；raw 字段不可用时回退到 `IOPowerSources`
- 适配所有能暴露内置电池数据的 Mac；台式 Mac 或无内置电池设备会显示明确的无电池状态
- SwiftUI 桌面仪表盘，深色玻璃风格、全窗口布局、顺滑滚动、菜单栏显示
- 内置设置面板，可调整菜单栏显示样式、充电上限监测和热保护监测阈值
- 应用图标基于 MIT 许可的 Bootstrap Icons `battery-charging`

## 电池计算方式

BatteryTruth 在 raw 电池字段可用时，不使用系统 UI 四舍五入后的百分比。

真实电量：

```text
AppleRawCurrentCapacity / AppleRawMaxCapacity * 100
```

真实健康度：

```text
AppleRawMaxCapacity / DesignCapacity * 100
```

实时功率：

```text
Voltage(mV) * InstantAmperage(mA) / 1,000,000
```

健康度不会强制截断到 100%。新电池或刚校准过的电池，满充容量可能高于设计容量。

## 限制

BatteryTruth 不伪造充电控制。macOS 15 没有提供本 App 可直接调用的公开接口来切断充电。App 内的充电上限和热保护功能是基于真实电池数据的监测和提示功能。

## 免责声明

本软件按现状提供，使用风险由使用者自行承担。

安装、运行、构建、修改或依赖本软件过程中如出现意外、读数不准、数据丢失、设备问题、电池问题、系统异常、经济损失或其他直接/间接损失，作者不承担责任。

BatteryTruth 仅用于信息展示，不是 Apple 官方软件，不是维修工具，也不保证电池状态或设备安全。涉及关键电池或硬件判断时，请以 Apple 诊断、macOS 系统设置或合格维修服务商的结论为准。

English disclaimer: Use BatteryTruth at your own risk. This app is provided as-is without warranty. The author is not responsible for unexpected behavior, incorrect readings, data loss, device issues, battery issues, system instability, financial loss, or other direct or indirect damage caused by installing, running, building, modifying, or relying on this app.

## 系统要求

- macOS 15 或更新版本
- Xcode Command Line Tools
- Swift 6 工具链

## 构建

```bash
swift test
./script/build_and_run.sh --verify
```

App bundle 会生成到：

```text
dist/BatteryTruth.app
```

## 打包 Release 资产

```bash
./script/package_release.sh
```

Release zip 会生成到：

```text
dist/BatteryTruth-macOS.zip
```

## 图标许可

电池充电图标来源基于 Bootstrap Icons `battery-charging`，使用 MIT 许可证。

见：

- `Assets/AppIcon/bootstrap-battery-charging.svg`
- `Assets/AppIcon/BOOTSTRAP_ICONS_LICENSE.md`
- https://icons.getbootstrap.com/icons/battery-charging/
- https://github.com/twbs/icons

## 项目许可证

BatteryTruth 使用 MIT License。见 `LICENSE`。
