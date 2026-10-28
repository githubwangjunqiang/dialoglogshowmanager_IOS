import Foundation
#if canImport(UIKit)
import UIKit

/// 主中枢 Tab 与内容面板的一体化联合轮廓背景视图（1:1 复刻 Android `ShowLogHubTabPanelBackground.java`）。
/// 为什么这样做：
/// 1. 选中 Tab 若使用独立背景，底边与内容面板顶边会形成生硬的直角接缝；
/// 2. 使用同一条 `UIBezierPath` + `CAShapeLayer` 绘制“选中页签 + 内容面板”的联合闭合轮廓，
///    并在页签底部两侧使用二次贝塞尔曲线（`addQuadCurve`）绘制 6pt 内凹圆角，使边框自然过渡；
/// 3. 填充色固定 `#1A1A1E`（`bgSurface`），描边固定 `#33333D`（`bgCardStroke`，线宽 `1pt`）。
@objcMembers
public final class ShowLogHubTabPanelBackgroundView: UIView {

    private static let jointEpsilonPt: CGFloat = 0.5

    public let panelTop: CGFloat = 36.0
    public let tabCorner: CGFloat = 10.0
    public let jointCorner: CGFloat = 6.0
    public let bottomCorner: CGFloat = 12.0
    public let strokeWidth: CGFloat = 1.0

    private let shapeLayer = CAShapeLayer()
    private var selectedTabLeft: CGFloat = 0
    private var selectedTabRight: CGFloat = 110

    public override init(frame: CGRect) {
        super.init(frame: frame)
        commonInit()
    }

    public required init?(coder: NSCoder) {
        super.init(coder: coder)
        commonInit()
    }

    private func commonInit() {
        backgroundColor = .clear
        isUserInteractionEnabled = false

        shapeLayer.fillColor = ShowLogTheme.bgSurface.cgColor
        shapeLayer.strokeColor = ShowLogTheme.bgCardStroke.cgColor
        shapeLayer.lineWidth = strokeWidth
        shapeLayer.lineCap = .round
        shapeLayer.lineJoin = .round
        layer.addSublayer(shapeLayer)
    }

    /// 更新滚动视口内选中页签的可视左右边界。
    public func setSelectedTab(tabLeft: CGFloat, tabRight: CGFloat) {
        let width = bounds.width
        let safeLeft = width > 0 ? max(0, min(tabLeft, width)) : max(0, tabLeft)
        let safeRight = width > 0 ? max(safeLeft, min(tabRight, width)) : max(safeLeft, tabRight)
        if abs(selectedTabLeft - safeLeft) < 0.1 && abs(selectedTabRight - safeRight) < 0.1 {
            return
        }
        selectedTabLeft = safeLeft
        selectedTabRight = safeRight
        rebuildPath()
    }

    public override func layoutSubviews() {
        super.layoutSubviews()
        shapeLayer.frame = bounds
        rebuildPath()
    }

    private func rebuildPath() {
        let width = bounds.width
        let height = bounds.height
        guard width > 0, height > panelTop else { return }

        let strokeInset = strokeWidth / 2.0
        let left = strokeInset
        let right = width - strokeInset
        let bottom = height - strokeInset
        let tabTop = strokeInset

        let tabLeft = max(left, min(selectedTabLeft, right))
        let tabRight = max(tabLeft, min(selectedTabRight, right))

        let path = UIBezierPath()
        path.move(to: CGPoint(x: left, y: panelTop))

        let hasLeftJoint = tabLeft > left + Self.jointEpsilonPt
        if hasLeftJoint {
            let jointStart = max(left, tabLeft - jointCorner)
            path.addLine(to: CGPoint(x: jointStart, y: panelTop))
            if tabLeft > jointStart + Self.jointEpsilonPt {
                // 从内容面板顶边向上弯入 Tab 左边框，形成二次贝塞尔内凹圆角
                path.addQuadCurve(
                    to: CGPoint(x: tabLeft, y: panelTop - jointCorner),
                    controlPoint: CGPoint(x: tabLeft, y: panelTop)
                )
            } else {
                path.addLine(to: CGPoint(x: tabLeft, y: panelTop - jointCorner))
            }
            path.addLine(to: CGPoint(x: tabLeft, y: tabTop + tabCorner))
        } else {
            // 选中第一个 Tab 时，左边缘与内容面板左边框直接连成一条直线
            path.addLine(to: CGPoint(x: left, y: tabTop + tabCorner))
        }

        // Tab 顶部左右外圆角
        path.addQuadCurve(
            to: CGPoint(x: tabLeft + tabCorner, y: tabTop),
            controlPoint: CGPoint(x: tabLeft, y: tabTop)
        )
        path.addLine(to: CGPoint(x: max(tabLeft + tabCorner, tabRight - tabCorner), y: tabTop))
        path.addQuadCurve(
            to: CGPoint(x: tabRight, y: tabTop + tabCorner),
            controlPoint: CGPoint(x: tabRight, y: tabTop)
        )

        let hasRightJoint = tabRight < right - Self.jointEpsilonPt
        if hasRightJoint {
            path.addLine(to: CGPoint(x: tabRight, y: panelTop - jointCorner))
            let jointEnd = min(right, tabRight + jointCorner)
            if jointEnd > tabRight + Self.jointEpsilonPt {
                // 从 Tab 右边框向下弯入内容面板顶边，形成二次贝塞尔内凹圆角
                path.addQuadCurve(
                    to: CGPoint(x: jointEnd, y: panelTop),
                    controlPoint: CGPoint(x: tabRight, y: panelTop)
                )
            } else {
                path.addLine(to: CGPoint(x: jointEnd, y: panelTop))
            }
            path.addLine(to: CGPoint(x: right, y: panelTop))
        } else {
            // 选中最右侧贴边 Tab 时，右边缘与内容面板右边框直接连成一条直线
            path.addLine(to: CGPoint(x: right, y: panelTop))
        }

        // 内容面板底部圆角与闭合
        path.addLine(to: CGPoint(x: right, y: bottom - bottomCorner))
        path.addQuadCurve(
            to: CGPoint(x: right - bottomCorner, y: bottom),
            controlPoint: CGPoint(x: right, y: bottom)
        )
        path.addLine(to: CGPoint(x: left + bottomCorner, y: bottom))
        path.addQuadCurve(
            to: CGPoint(x: left, y: bottom - bottomCorner),
            controlPoint: CGPoint(x: left, y: bottom)
        )
        path.close()

        shapeLayer.path = path.cgPath
    }
}
#endif
