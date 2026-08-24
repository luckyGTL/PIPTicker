import SwiftUI

/// Mac 跨桌面置顶独立悬浮看板视图 (自适应 1~8 股、可拉伸缩放、毛玻璃半透明、贴边 3 秒自动收起、悬停即刻展开)
public struct MacFloatingStockView: View {
    @StateObject private var stockData = StockDataManager.shared
    @StateObject private var macWindowManager = MacFloatingWindowManager.shared
    
    var onClose: (() -> Void)? = nil
    
    @State private var isHovering: Bool = false
    @State private var showSettings: Bool = false
    @AppStorage("MacFloatingStockView_displayCount") private var displayCount: Int = 4
    @AppStorage("MacFloatingStockView_isRedUpGreenDown") private var isRedUpGreenDown: Bool = true
    
    public init(onClose: (() -> Void)? = nil) {
        self.onClose = onClose
    }
    
    public var body: some View {
        GeometryReader { geometry in
            let w = geometry.size.width
            let h = geometry.size.height
            let count = max(1, min(displayCount, stockData.watchlist.count))
            let displayList = Array(stockData.watchlist.prefix(count))
            let rowCounts = getRowDistribution(for: displayList.count)
            let isCompact = h < 140 || w < 260
            let isMicro = h < 65
            
            ZStack(alignment: .topTrailing) {
                // 1. 高级暗黑半透明毛玻璃背景
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.black.opacity(macWindowManager.windowOpacity))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(
                                macWindowManager.isDocked ? Color.blue.opacity(0.8) : Color.white.opacity(isHovering ? 0.35 : 0.12),
                                lineWidth: macWindowManager.isDocked ? 2 : 1
                            )
                    )
                
                // 2. 主体行情内容
                VStack(spacing: isMicro ? 1 : (isCompact ? 2 : 4)) {
                    // 顶部状态栏 (微型模式自动隐藏)
                    if !isMicro && !isCompact {
                        HStack {
                            Circle()
                                .fill(stockData.marketStatusText.contains("交易中") ? Color.green : Color.orange)
                                .frame(width: 6, height: 6)
                            
                            Text("● A股 \(stockData.marketStatusText)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(Color(red: 0.95, green: 0.75, blue: 0.25))
                            
                            Spacer()
                            
                            Text(formattedUpdateTime)
                                .font(.system(size: 9, design: .monospaced))
                                .foregroundColor(Color(white: 0.6))
                        }
                        .padding(.horizontal, 8)
                        .padding(.top, 4)
                    }
                    
                    // 1~8 股自适应多行满铺网格 (严格 100% 平分宽高，即时响应顺序变动)
                    VStack(spacing: isMicro ? 2 : (isCompact ? 3 : 4)) {
                        ForEach(0..<rowCounts.count, id: \.self) { rowIndex in
                            let itemsInThisRow = rowCounts[rowIndex]
                            let startIndex = (0..<rowIndex).reduce(0) { $0 + rowCounts[$1] }
                            let endIndex = min(startIndex + itemsInThisRow, displayList.count)
                            let rowItems = (startIndex < displayList.count) ? Array(displayList[startIndex..<endIndex]) : []
                            
                            HStack(spacing: isMicro ? 2 : (isCompact ? 3 : 4)) {
                                ForEach(rowItems, id: \.fullCode) { symbol in
                                    macStockCell(
                                        symbol: symbol,
                                        cellWidth: (w - CGFloat(itemsInThisRow - 1) * 4 - 12) / CGFloat(itemsInThisRow),
                                        cellHeight: (h - CGFloat(rowCounts.count - 1) * 4 - (isMicro || isCompact ? 8 : 26)) / CGFloat(rowCounts.count),
                                        totalCount: count
                                    )
                                }
                            }
                            .frame(maxHeight: .infinity)
                        }
                    }
                    .padding(isMicro ? 2 : (isCompact ? 4 : 6))
                    .frame(maxHeight: .infinity)
                }
                
                // 3. 悬浮窗处于收起状态时显现的吸附提示把手 (提示用户鼠标移入即可展开)
                if macWindowManager.isDocked {
                    dockedEdgeHandle(edge: macWindowManager.dockedEdge)
                }
                
                // 4. 悬浮窗右上角快捷控制栏 (鼠标悬停浮现)
                if isHovering && !macWindowManager.isDocked {
                    HStack(spacing: 6) {
                        // 设置浮层开关
                        Button(action: {
                            showSettings.toggle()
                        }) {
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.white.opacity(0.85))
                                .padding(4)
                                .background(Color.white.opacity(0.18))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                        
                        // 关闭按钮
                        Button(action: {
                            onClose?()
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 10, weight: .heavy))
                                .foregroundColor(.white.opacity(0.9))
                                .padding(4)
                                .background(Color.red.opacity(0.8))
                                .clipShape(Circle())
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                    .padding(5)
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                }
                
                // 5. 设置半透明覆盖抽屉
                if showSettings {
                    macSettingsOverlay
                }
            }
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.black.opacity(macWindowManager.isDocked ? 0.8 : 0.5), radius: 10, x: 0, y: 5)
            #if os(macOS) || targetEnvironment(macCatalyst)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.18)) {
                    self.isHovering = hovering
                }
                macWindowManager.setMouseHovering(hovering)
            }
            #endif
        }
    }
    
    // MARK: - 靠边收起后的边缘发光指示把手
    @ViewBuilder
    private func dockedEdgeHandle(edge: DockEdge) -> some View {
        HStack {
            if edge == .left {
                Spacer()
                VStack(spacing: 4) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.blue)
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: 3, height: 28)
                        .cornerRadius(1.5)
                }
                .padding(.trailing, 2)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .black))
                        .foregroundColor(.blue)
                    Rectangle()
                        .fill(Color.blue)
                        .frame(width: 3, height: 28)
                        .cornerRadius(1.5)
                }
                .padding(.leading, 2)
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color.blue.opacity(0.15))
        .allowsHitTesting(false)
    }
    
    // MARK: - 单张股票自适应卡片
    private func macStockCell(symbol: StockSymbol, cellWidth: CGFloat, cellHeight: CGFloat, totalCount: Int) -> some View {
        let quote = stockData.quotes[symbol.fullCode] ?? StockQuote(symbol: symbol)
        let red = Color(red: 0.92, green: 0.26, blue: 0.21)
        let green = Color(red: 0.18, green: 0.80, blue: 0.44)
        let activeColor = quote.isFlat ? Color.secondary : (isRedUpGreenDown ? (quote.isPositive ? red : green) : (quote.isPositive ? green : red))
        
        let isMicro = cellHeight < 52 || (totalCount >= 7 && cellHeight < 62)
        let isCompact = cellHeight < 75
        
        return VStack(alignment: isMicro ? .center : .leading, spacing: isMicro ? 0 : 2) {
            // 第 1 行：股票名称（最高优先级）与代码（空间不足隐藏）
            HStack(spacing: 2) {
                Text(symbol.name)
                    .font(.system(size: isMicro ? max(9.5, min(12.0, cellHeight * 0.30)) : (isCompact ? 12 : 14), weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .layoutPriority(1)
                
                // 空间充裕时才展示股票代码，否则彻底隐藏，绝不出现截断代码
                if !isMicro && cellWidth > 95 {
                    Spacer(minLength: 2)
                    Text(symbol.code)
                        .font(.system(size: isCompact ? 9 : 10, weight: .medium, design: .monospaced))
                        .foregroundColor(Color(white: 0.6))
                        .lineLimit(1)
                }
            }
            
            // 第 2 行：当前现价 (大号等宽数字)
            Text(quote.price)
                .font(.system(size: isMicro ? max(11.0, min(15.0, cellHeight * 0.42)) : (isCompact ? 16 : 22), weight: .heavy, design: .rounded))
                .foregroundColor(activeColor)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
            
            // 第 3 行：涨跌幅与跌额微标（极小时自动隐藏，垂直空间 100% 留给名称与价格）
            if !isMicro {
                HStack(spacing: 3) {
                    Text(quote.priceChangePercent)
                        .font(.system(size: isCompact ? 9 : 10, weight: .heavy))
                        .foregroundColor(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(activeColor)
                        .cornerRadius(3)
                    
                    if cellWidth > 90 {
                        Text(quote.priceChange)
                            .font(.system(size: isCompact ? 8.5 : 9.5, weight: .semibold))
                            .foregroundColor(activeColor)
                    }
                }
            }
        }
        .padding(isMicro ? 2 : (isCompact ? 4 : 6))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: isMicro ? .center : .leading)
        .background(Color(white: 0.12))
        .cornerRadius(6)
    }
    
    // MARK: - 悬浮看板设置面板
    private var macSettingsOverlay: some View {
        VStack(spacing: 8) {
            HStack {
                Text("悬浮窗偏好设置")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                Spacer()
                Button(action: { showSettings = false }) {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.white.opacity(0.7))
                }
                .buttonStyle(PlainButtonStyle())
            }
            
            Divider().background(Color.white.opacity(0.2))
            
            // 靠边自动收起开关与延迟时间配置
            Toggle(isOn: $macWindowManager.autoHideEnabled) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("靠边自动隐藏")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.white)
                    Text("小窗靠边后自动漂出，鼠标移入即时展开")
                        .font(.system(size: 9))
                        .foregroundColor(.white.opacity(0.6))
                }
            }
            .toggleStyle(SwitchToggleStyle())
            
            if macWindowManager.autoHideEnabled {
                HStack {
                    Text("收起等待:")
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.8))
                    Spacer()
                    ForEach([0.5, 1.0, 2.0, 3.0], id: \.self) { sec in
                        Button(action: { macWindowManager.autoHideDelay = sec }) {
                            Text(sec == 0.5 ? "0.5s" : "\(Int(sec))s")
                                .font(.system(size: 10, weight: macWindowManager.autoHideDelay == sec ? .bold : .medium))
                                .foregroundColor(macWindowManager.autoHideDelay == sec ? .white : .white.opacity(0.7))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(macWindowManager.autoHideDelay == sec ? Color.blue : Color.white.opacity(0.12))
                                .cornerRadius(4)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
            }
            
            // 股票数量快速切换 (1~8)
            HStack(spacing: 4) {
                Text("数量:")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
                ForEach(1...8, id: \.self) { c in
                    Button(action: { displayCount = c }) {
                        Text("\(c)")
                            .font(.system(size: 10, weight: displayCount == c ? .bold : .medium))
                            .foregroundColor(displayCount == c ? .white : .white.opacity(0.7))
                            .frame(width: 18, height: 18)
                            .background(displayCount == c ? Color.blue : Color.white.opacity(0.12))
                            .cornerRadius(4)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            
            // 透明度调节
            HStack {
                Text("透明度:")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
                Slider(value: $macWindowManager.windowOpacity, in: 0.4...1.0)
                    .onChange(of: macWindowManager.windowOpacity) { val in
                        macWindowManager.updateOpacity(val)
                    }
            }
            
            // 配色切换
            Toggle(isOn: $isRedUpGreenDown) {
                Text("红涨绿跌配色")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.8))
            }
            .toggleStyle(SwitchToggleStyle())
        }
        .padding(10)
        .background(Color.black.opacity(0.92))
        .cornerRadius(10)
        .padding(6)
        .transition(.opacity)
    }
    
    private func getRowDistribution(for count: Int) -> [Int] {
        switch max(1, count) {
        case 1: return [1]
        case 2: return [2]
        case 3: return [3]
        case 4: return [2, 2]
        case 5: return [3, 2]
        case 6: return [3, 3]
        case 7: return [4, 3]
        case 8: return [4, 4]
        default: return [2, 2]
        }
    }
    
    private var formattedUpdateTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: stockData.lastUpdated) + " 更新"
    }
}
