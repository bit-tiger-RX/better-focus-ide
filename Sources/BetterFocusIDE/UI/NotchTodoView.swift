// SPDX-License-Identifier: GPL-3.0-or-later
// Copyright (C) 2026 BetterFocusIDE

import SwiftUI

/// 任务进度卡片：横向分段液柱 + 当前任务 + 下一步。
///
/// ## 为什么是分段条，而不是环形 / 时间轴
///
/// 刘海的可用高度是硬约束。环形与竖向时间轴都是「用高度换叙事」，而用户扫一眼刘海
/// 时真正想知道的是**总量还剩多少**。分段条把 N 个任务映射成 N 段胶囊：一行像素就
/// 表达了总量与分布，并且与灵动岛自身的胶囊语言同构。
///
/// ## 布局
///
/// ```
/// [Q] Qoder · 任务进度                     3 / 6  [pin]
/// ▬▬▬▬▬▬  ▬▬▬▬▬▬  ▬▬▬▬▬▬  ≈≈≈≈≈≈  ──────  ──────
/// ◌  补充 hooks 模板 matcher                     2m 14s
///    下一步  验证事件回传与断线重连
/// ```
///
/// 实心段是已完成，流动高光的一段是正在进行，空段是未开始。
/// 当前任务行左侧的弧线持续旋转，和这段高光是同一件事。
///
/// 所有纵向度量来自 `TodoCardLayout`，`NotchService` 用同一个函数算窗口高度，
/// 两侧不许各写一份魔数。
struct NotchTodoView: View {
    @ObservedObject var controller: TodoController
    var pinned = false
    var onTogglePin: () -> Void = {}

    /// 观察 Settings，使内边距等设置改动即时生效。
    @ObservedObject private var settings = Settings.shared
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    /// 状态标记列宽。转圈与「下一步」箭头共用，两行正文才能对齐。
    private static let markColumn: CGFloat = 11

    private var progress: TodoProgress { controller.progress }
    private var tint: Color { controller.provider.tint }
    private var inset: CGFloat { CGFloat(Settings.shared.cardInset) }

    /// 系统「减少动态效果」或应用内「减弱动态效果」任一开启，就停掉扫光和转圈。
    /// 进行中的段仍保留半透明填色，静止时也能和空段、实心段分开。
    private var calmMotion: Bool {
        reduceMotion || settings.reduceMotionResolved
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .frame(height: TodoCardLayout.headerHeight)

            segmentBar
                .padding(.top, TodoCardLayout.headerGap)

            if progress.isFinished {
                finishedRow
                    .padding(.top, TodoCardLayout.barGap)
            } else {
                currentRow
                    .padding(.top, TodoCardLayout.barGap)
                if progress.next != nil {
                    nextRow
                        .padding(.top, TodoCardLayout.rowGap)
                }
            }
        }
        .padding(.horizontal, inset)
        .padding(.vertical, TodoCardLayout.verticalPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        // 段填充用弹簧；当前项切换用短 easeOut（换行不该有回弹感）。
        .animation(reduceMotion ? nil : .spring(response: 0.34, dampingFraction: 0.82),
                   value: progress.segmentFills)
        .animation(.easeOut(duration: 0.22), value: progress.current?.id)
        .animation(.easeOut(duration: 0.22), value: progress.isFinished)
    }

    // MARK: - 头部

    /// 徽章 + 「来源 · 任务进度」+ 计数 + 钉住开关。
    private var header: some View {
        HStack(spacing: 8) {
            let name = controller.providerName.isEmpty
                ? controller.provider.displayName
                : controller.providerName
            let iconID = AgentProvider.iconIdentity(provider: controller.provider,
                                                    hostName: name,
                                                    bundleID: nil)
            IDEIconProvider.badgeView(hostName: iconID.name,
                                      bundleID: iconID.bundle,
                                      fallbackText: String(name.prefix(1)).uppercased(),
                                      tint: tint,
                                      size: IDEIconProvider.badgeSize)
                .layoutPriority(1)

            Text(name.isEmpty ? "任务进度" : "\(name) · 任务进度")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            // 计数是整张卡唯一的「精确量」：段条给分布感，数字给确定感。
            Text(progress.countText)
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(progress.isFinished ? AnyShapeStyle(tint)
                                 : AnyShapeStyle(.white.opacity(0.6)))
                .monospacedDigit()
                .contentTransition(.numericText())
                .animation(.easeOut(duration: 0.2), value: progress.completed)
                .layoutPriority(1)

            PinButton(pinned: pinned, action: onTogglePin)
                .layoutPriority(2)
        }
    }

    // MARK: - 分段条

    /// 分段液柱。
    ///
    /// 段数恒定不超过 8：任务更多时按桶均分（见 `TodoProgress.segmentFills`），
    /// 保证进度连续可读，也保证卡片高度不随任务数变化。
    private var segmentBar: some View {
        let fills = progress.segmentFills
        let count = max(1, fills.count)
        let gap: CGFloat = 4
        return GeometryReader { geo in
            let width = max(0, (geo.size.width - gap * CGFloat(count - 1)) / CGFloat(count))
            HStack(spacing: gap) {
                ForEach(0..<count, id: \.self) { index in
                    let fill = index < fills.count ? fills[index] : 0
                    segment(fill: fill, width: width, isActive: progress.activeSegment == index)
                }
            }
        }
        .frame(height: TodoCardLayout.barHeight)
        .accessibilityElement()
        .accessibilityLabel("任务进度")
        .accessibilityValue(progress.current.map {
            "\(progress.completed) / \(progress.total)，正在进行 \($0.content)"
        } ?? "\(progress.completed) / \(progress.total)")
    }

    /// 单段：底轨 + 按比例填充的胶囊。
    ///
    /// 填充用真实宽度而非 `scaleEffect`——缩放会把胶囊两端压扁，6pt 高度上尤其明显。
    /// 宽度不足一个圆头时按最小可见宽度画，避免「完成了但看不见」。
    ///
    /// 进行中的段不靠整段变淡（那会和空段混在一起）。它铺一层半透明主题色，
    /// 再让一条高光从左扫到右。实心段是已完成，空段是未开始。
    private func segment(fill: Double, width: CGFloat, isActive: Bool) -> some View {
        let clamped = min(1, max(0, fill))
        let filledWidth = clamped >= 1
            ? width
            : (clamped > 0 ? max(TodoCardLayout.barHeight, width * clamped) : 0)
        let running = isActive && progress.current != nil && clamped < 0.999
        return ZStack(alignment: .leading) {
            Color.clear
                .liquidGlass(.capsule, fallback: Color.white.opacity(0.12))
            if filledWidth > 0 {
                Capsule()
                    .fill(tint.opacity(clamped >= 1 ? 1 : 0.85))
                    .frame(width: filledWidth)
            }
            if running && filledWidth == 0 {
                Capsule()
                    .fill(tint.opacity(0.42))
            }
            if running && !calmMotion {
                RunningSweep(width: width)
            }
        }
        .frame(width: width, height: TodoCardLayout.barHeight)
    }

    // MARK: - 当前 / 下一步

    private var currentRow: some View {
        HStack(spacing: 7) {
            statusMark

            Text(progress.current?.content ?? progress.next?.content ?? "准备中")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.95))
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            elapsedText
                .font(.system(size: 10, weight: .regular, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .monospacedDigit()
                .layoutPriority(1)
        }
        .frame(height: TodoCardLayout.currentRowHeight)
        // 换行时整行轻微上浮淡入，替代「原地跳字」。
        .id(progress.current?.id ?? "none")
        .transition(.opacity.combined(with: .offset(y: 4)))
    }

    /// 进行中画旋转弧线；还没有进行中的项时，退成空心圆点，表示未开始。
    private var statusMark: some View {
        Group {
            if progress.current != nil {
                RunningMark(tint: tint, animate: !calmMotion)
            } else {
                Circle()
                    .strokeBorder(.white.opacity(0.35), lineWidth: 1)
                    .frame(width: 5, height: 5)
            }
        }
        .frame(width: Self.markColumn, height: Self.markColumn)
        .accessibilityHidden(true)
    }

    private var nextRow: some View {
        HStack(spacing: 7) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(.white.opacity(0.28))
                .frame(width: Self.markColumn)
            Text("下一步")
                .font(.system(size: 10))
                .foregroundStyle(.white.opacity(0.35))
            Text(progress.next?.content ?? "")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .truncationMode(.tail)
        }
        .frame(height: TodoCardLayout.nextRowHeight)
    }

    // MARK: - 全部完成

    private var finishedRow: some View {
        HStack(spacing: 7) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(tint)
                .symbolEffect(.bounce, value: progress.isFinished)
                .frame(width: Self.markColumn)
            Text(progress.total == 1 ? "任务已完成" : "全部 \(progress.total) 项已完成")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
            Spacer(minLength: 0)
        }
        .frame(height: TodoCardLayout.currentRowHeight)
    }

    // MARK: - 已用时长

    /// 「已用 2m 14s」——每秒重算，但不持有 Timer：`TimelineView` 只在可见时推进。
    private var elapsedText: some View {
        TimelineView(.periodic(from: controller.startedAt, by: 1)) { context in
            Text(Self.elapsedText(from: controller.startedAt,
                                  to: controller.finishedAt ?? context.date))
        }
    }

    static func elapsedText(from start: Date, to end: Date) -> String {
        let seconds = max(0, Int(end.timeIntervalSince(start)))
        if seconds < 60 { return "\(seconds)s" }
        let minutes = seconds / 60
        let rest = seconds % 60
        if minutes < 60 { return String(format: "%dm %02ds", minutes, rest) }
        return String(format: "%dh %02dm", minutes / 60, minutes % 60)
    }
}

// MARK: - 进行中指示

/// 当前任务行左侧的旋转弧线。
///
/// 用时间相位而不是 `repeatForever`：卡片被收起再展开时，动画从当前时刻接上，
/// 不会每次出现都从 0° 重播一遍。减弱动态效果时停在固定角度。
private struct RunningMark: View {
    var tint: Color
    var animate: Bool

    var body: some View {
        Group {
            if animate {
                TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
                    mark(angle: Self.angle(at: context.date))
                }
            } else {
                mark(angle: -90)
            }
        }
        .frame(width: 11, height: 11)
    }

    private func mark(angle: Double) -> some View {
        ZStack {
            Circle()
                .stroke(tint.opacity(0.28), lineWidth: 1.4)
            Circle()
                .trim(from: 0.12, to: 0.42)
                .stroke(tint, style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
                .rotationEffect(.degrees(angle))
        }
    }

    /// 0.9 秒转一圈。减去 90° 让开口从正上方开始。
    static func angle(at date: Date) -> Double {
        let period = 0.9
        let phase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / period
        return phase * 360 - 90
    }
}

/// 进行中那一段上的扫光。
///
/// 高光两端透明，扫出胶囊之后再从左侧进入，接缝处看不见跳跃。
/// 只裁扫光本身，不裁父层的液态玻璃棱边。
private struct RunningSweep: View {
    var width: CGFloat

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = Self.phase(at: context.date)
            let band = Self.bandWidth(segment: width)
            Capsule()
                .fill(LinearGradient(
                    colors: [
                        Color.white.opacity(0),
                        Color.white.opacity(0.92),
                        Color.white.opacity(0),
                    ],
                    startPoint: .leading,
                    endPoint: .trailing))
                .frame(width: band, height: TodoCardLayout.barHeight)
                .offset(x: -band + (width + band) * phase)
                .frame(width: width, height: TodoCardLayout.barHeight, alignment: .leading)
        }
        .clipShape(Capsule())
        .allowsHitTesting(false)
    }

    /// 1.1 秒从左扫到右，低于 3Hz。
    static func phase(at date: Date) -> Double {
        let period = 1.1
        return date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: period) / period
    }

    /// 高光宽度跟着段宽走，但不超过段宽的七成，窄段上仍能看出它在移动。
    static func bandWidth(segment width: CGFloat) -> CGFloat {
        let preferred = max(TodoCardLayout.barHeight * 2.2, width * 0.42)
        return min(width * 0.72, preferred)
    }
}

#if DEBUG
/// Xcode Canvas 预览：构造一个含进行中项的控制器。
struct NotchTodoView_Previews: PreviewProvider {
    static var previews: some View {
        let ctrl = TodoController()
        ctrl.apply(snapshot: [
            TodoItem(id: "1", content: "检查 Qoder hook 模板", status: .completed),
            TodoItem(id: "2", content: "补充 hooks 模板 matcher", status: .completed),
            TodoItem(id: "3", content: "验证事件回传与断线重连", status: .inProgress),
            TodoItem(id: "4", content: "归一化 Task* 增量写入", status: .pending),
            TodoItem(id: "5", content: "补齐卡片收起态进度线", status: .pending),
        ],
            sessionID: "preview", provider: .qoder,
            providerName: "Qoder", project: "better-focus-ide")
        return NotchTodoView(controller: ctrl)
            .frame(width: 380)
            .padding(.vertical, 20)
            .background(.black)
            .preferredColorScheme(.dark)
    }
}
#endif
