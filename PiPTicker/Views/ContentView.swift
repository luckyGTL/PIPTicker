import SwiftUI
import AVKit

#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

extension Color {
    static var appBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.systemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.windowBackgroundColor)
        #else
        return Color.black
        #endif
    }
    
    static var appSecondaryBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.secondarySystemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.controlBackgroundColor)
        #else
        return Color(white: 0.15)
        #endif
    }
    
    static var appTertiaryBackground: Color {
        #if canImport(UIKit)
        return Color(UIColor.tertiarySystemGroupedBackground)
        #elseif canImport(AppKit)
        return Color(NSColor.underPageBackgroundColor)
        #else
        return Color(white: 0.2)
        #endif
    }
}

/// Mac 视图模式
public enum MacViewMode: String, CaseIterable, Identifiable {
    case quotes = "行情看板"
    case news = "7x24快讯"
    case recap = "A股复盘"
    case global = "全球市场"
    case dashboard = "全景分栏"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .quotes: return "chart.xyaxis.line"
        case .news: return "bolt.fill"
        case .recap: return "chart.pie.fill"
        case .global: return "globe.americas.fill"
        case .dashboard: return "rectangle.split.3x1"
        }
    }
}

struct ContentView: View {
    @StateObject private var stockData = StockDataManager.shared
    @StateObject private var pipManager = PiPManager.shared
    @StateObject private var newsManager = FinancialNewsManager.shared
    @StateObject private var searchService = StockSearchService.shared
    @ObservedObject private var macWindowManager = MacFloatingWindowManager.shared
    
    @State private var macViewMode: MacViewMode = .quotes
    @State private var selectedIOSTab: Int = 0
    
    @State private var isRedUpGreenDown: Bool = true
    @State private var autoPiP: Bool = true
    @State private var pipStockCount: Int = 4 // 支持 1 ~ 8 只自适应铺满
    @State private var showingAddStockSheet: Bool = false
    @State private var inputStockCode: String = ""
    @State private var addStockErrorMessage: String? = nil
    @State private var isAddingStock: Bool = false
    
    // 手势交互状态控制
    @State private var draggingStock: StockSymbol? = nil
    @State private var activeSwipedStockId: String? = nil
    
    var body: some View {
        #if os(macOS)
        ZStack {
            Color.appBackground
                .ignoresSafeArea()
            
            VStack(spacing: 0) {
                // Mac 顶部导航栏（包含模式切换、实时状态与刷新按钮）
                macHeaderBar
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 12)
                
                Divider()
                
                // 主体区域：根据模式展示
                Group {
                    switch macViewMode {
                    case .quotes:
                        macQuotesLayout
                    case .news:
                        FinancialNewsView()
                    case .recap:
                        MarketRecapView()
                    case .global:
                        GlobalMarketView()
                    case .dashboard:
                        macDashboardSplitLayout
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // 自选股要闻突发提醒弹窗 (Mac 全局浮层，绑定独立ID与平滑透明度缩放转场，防止多条未读时文字翻转)
            if newsManager.showInAppAlertModal, let alertItem = newsManager.latestWatchlistAlert {
                watchlistAlertModalView(for: alertItem)
                    .id(newsManager.currentAlertItem?.id ?? alertItem.id)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)),
                        removal: .opacity
                    ))
                    .zIndex(100)
            }
        }
        .onAppear {
            stockData.start()
            newsManager.start()
            MarketRecapManager.shared.start()
            GlobalMarketManager.shared.start()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToNewsTabNotification"))) { _ in
            macViewMode = .news
        }
        .sheet(isPresented: $showingAddStockSheet) {
            addStockSheetView
        }
        .sheet(item: $newsManager.selectedNewsForDetail) { item in
            NewsDetailSheetView(item: item)
        }
        #else
        ZStack {
            TabView(selection: $selectedIOSTab) {
                // Tab 1: 行情看板与画中画
                NavigationView {
                    ZStack {
                        Color.appBackground
                            .ignoresSafeArea()
                            .contentShape(Rectangle())
                            .onTapGesture {
                                dismissSwipedCard()
                            }
                        
                        ScrollView {
                            VStack(spacing: 16) {
                                marketStatusBar
                                pipPreviewGridCard
                                pipControlButton
                                watchlistSection
                                settingsSection
                                instructionSection
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 14)
                        }
                        .simultaneousGesture(
                            TapGesture().onEnded {
                                if activeSwipedStockId != nil {
                                    dismissSwipedCard()
                                }
                            }
                        )
                    }
                    .navigationTitle("A股行情 · 画中画")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .automatic) {
                            Button(action: {
                                stockData.fetchQuotes()
                            }) {
                                Image(systemName: "arrow.clockwise")
                                    .font(.system(size: 15, weight: .bold))
                                    .rotationEffect(.degrees(stockData.isUpdating ? 360 : 0))
                                    .animation(stockData.isUpdating ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: stockData.isUpdating)
                            }
                        }
                    }
                    .sheet(isPresented: $showingAddStockSheet) {
                        addStockSheetView
                    }
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Label("行情看板", systemImage: "chart.xyaxis.line")
                }
                .tag(0)
                
                // Tab 2: 7x24 全网实时财经资讯
                NavigationView {
                    FinancialNewsView()
                        .navigationTitle("7x24 实时快讯")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Label("7x24快讯", systemImage: "bolt.fill")
                }
                .tag(1)
                
                // Tab 3: A股全景复盘 (板块资金/涨跌停)
                NavigationView {
                    MarketRecapView()
                        .navigationTitle("A股全景复盘")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Label("A股复盘", systemImage: "chart.pie.fill")
                }
                .tag(2)
                
                // Tab 4: 全球核心市场 (美股盘前盘后/板块 + 韩国股市)
                NavigationView {
                    GlobalMarketView()
                        .navigationTitle("全球核心市场")
                        .navigationBarTitleDisplayMode(.inline)
                }
                .navigationViewStyle(StackNavigationViewStyle())
                .tabItem {
                    Label("全球市场", systemImage: "globe.americas.fill")
                }
                .tag(3)
            }
            
            // 自选股要闻突发提醒弹窗 (iOS 全局浮层，绑定独立ID与平滑透明度缩放转场，防止多条未读时文字翻转)
            if newsManager.showInAppAlertModal, let alertItem = newsManager.latestWatchlistAlert {
                watchlistAlertModalView(for: alertItem)
                    .id(newsManager.currentAlertItem?.id ?? alertItem.id)
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.96)),
                        removal: .opacity
                    ))
                    .zIndex(100)
            }
        }
        .sheet(item: $newsManager.selectedNewsForDetail) { item in
            NewsDetailSheetView(item: item)
        }
        .onReceive(NotificationCenter.default.publisher(for: NSNotification.Name("SwitchToNewsTabNotification"))) { _ in
            selectedIOSTab = 1
        }
        .onAppear {
            stockData.start()
            newsManager.start()
            MarketRecapManager.shared.start()
            GlobalMarketManager.shared.start()
            #if canImport(UIKit)
            pipManager.tickerViewController.displayCount = pipStockCount
            #endif
        }
        #endif
    }
    
    private func dismissSwipedCard() {
        if activeSwipedStockId != nil {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                activeSwipedStockId = nil
            }
        }
    }
    
    // MARK: - Mac 顶部主控栏
    #if os(macOS)
    private var macHeaderBar: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text("PiPTicker · A股与7x24全球财经看板")
                    .font(.system(size: 18, weight: .bold))
                Text("全网快讯秒级抓取 · 跨桌面独立置顶悬浮 · 模糊搜索联想")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            // 模式切换胶囊
            HStack(spacing: 4) {
                ForEach(MacViewMode.allCases) { mode in
                    let isSelected = macViewMode == mode
                    Button(action: {
                        withAnimation(.easeInOut(duration: 0.15)) {
                            macViewMode = mode
                        }
                    }) {
                        HStack(spacing: 5) {
                            Image(systemName: mode.iconName)
                                .font(.system(size: 11, weight: .bold))
                            Text(mode.rawValue)
                                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                        }
                        .foregroundColor(isSelected ? .white : .primary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(isSelected ? Color.blue : Color.appSecondaryBackground)
                        .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(3)
            .background(Color.appTertiaryBackground)
            .cornerRadius(10)
            
            // 全局刷新按钮
            Button(action: {
                stockData.fetchQuotes()
                newsManager.fetchAllNewsChannels()
            }) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees((stockData.isUpdating || newsManager.isRefreshing) ? 360 : 0))
                        .animation((stockData.isUpdating || newsManager.isRefreshing) ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: stockData.isUpdating || newsManager.isRefreshing)
                    Text("刷新数据")
                        .font(.system(size: 12, weight: .semibold))
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.appSecondaryBackground)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - Mac 行情专属双栏布局
    private var macQuotesLayout: some View {
        ScrollView {
            HStack(alignment: .top, spacing: 20) {
                // 左侧栏：16:9 画中画预览、开启置顶悬浮窗按钮、偏好设置与贴士
                VStack(spacing: 16) {
                    marketStatusBar
                    pipPreviewGridCard
                    pipControlButton
                    settingsSection
                    instructionSection
                }
                .frame(minWidth: 420, idealWidth: 460, maxWidth: 520)
                
                // 右侧栏：全部自选股列表与管理
                VStack(spacing: 16) {
                    watchlistSection
                }
                .frame(maxWidth: .infinity)
            }
            .padding(20)
        }
    }
    
    // MARK: - Mac 综合分栏全景看板 (左侧行情看板 + 右侧实时快讯瀑布流)
    private var macDashboardSplitLayout: some View {
        HStack(spacing: 0) {
            // 左半屏：自选股与悬浮窗控制
            ScrollView {
                VStack(spacing: 16) {
                    marketStatusBar
                    pipPreviewGridCard
                    pipControlButton
                    watchlistSection
                }
                .padding(16)
            }
            .frame(minWidth: 400, idealWidth: 440, maxWidth: 500)
            
            Divider()
            
            // 右半屏：7x24 实时快讯时间轴
            FinancialNewsView()
                .frame(maxWidth: .infinity)
        }
    }
    #endif
    
    // MARK: - 市场状态栏
    private var marketStatusBar: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(marketDotColor)
                .frame(width: 8, height: 8)
            
            Text(stockData.isMockMode ? "模拟数据模式运行中" : "A股状态: \(stockData.marketStatusText)")
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(formattedUpdateTime)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Color.appSecondaryBackground)
        .cornerRadius(10)
    }
    
    // MARK: - 画中画 16:9 实时同款自适应全铺满预览网格卡片
    private var pipPreviewGridCard: some View {
        let displayList = Array(stockData.watchlist.prefix(pipStockCount))
        let rowCounts = getRowDistribution(for: displayList.count)
        
        return VStack(spacing: 8) {
            HStack {
                Text("16:9 宽屏悬浮窗效果预览 (\(displayList.count)只自适应全铺满)")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.secondary)
                
                Spacer()
                
                Text("极宽满屏 · 解锁全宽")
                    .font(.caption2)
                    .foregroundColor(.blue)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.blue.opacity(0.12))
                    .cornerRadius(4)
            }
            .padding(.horizontal, 4)
            
            // 16:9 纯黑高对比度容器
            VStack(spacing: 6) {
                // 顶部状态微标
                HStack {
                    Text("● A股 \(stockData.marketStatusText)")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundColor(Color(red: 0.95, green: 0.75, blue: 0.25))
                    Spacer()
                    Text(formattedUpdateTime)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(Color(white: 0.6))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Color(white: 0.08))
                .cornerRadius(5)
                
                // 自适应多行铺满网格
                VStack(spacing: 4) {
                    ForEach(0..<rowCounts.count, id: \.self) { rowIndex in
                        let itemsInThisRow = rowCounts[rowIndex]
                        let startIndex = (0..<rowIndex).reduce(0) { $0 + rowCounts[$1] }
                        let endIndex = min(startIndex + itemsInThisRow, displayList.count)
                        let rowItems = (startIndex < displayList.count) ? Array(displayList[startIndex..<endIndex]) : []
                        
                        HStack(spacing: 4) {
                            ForEach(rowItems, id: \.fullCode) { symbol in
                                pipStockPreviewCell(symbol: symbol, totalCount: displayList.count)
                            }
                        }
                        .frame(maxHeight: .infinity)
                    }
                }
                .frame(maxHeight: .infinity)
            }
            .padding(8)
            .background(Color.black)
            .cornerRadius(14)
            .aspectRatio(16.0 / 9.0, contentMode: .fit)
            .background(
                PiPSourceAnchorView()
            )
            .shadow(color: Color.black.opacity(0.25), radius: 8, x: 0, y: 3)
        }
        .padding(10)
        .background(Color.appSecondaryBackground)
        .cornerRadius(18)
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
    
    private func pipStockPreviewCell(symbol: StockSymbol, totalCount: Int) -> some View {
        let quote = stockData.quotes[symbol.fullCode] ?? StockQuote(symbol: symbol)
        let color = getStockColor(isPositive: quote.isPositive, isFlat: quote.isFlat)
        
        let isHero = totalCount == 1
        let isCompact = totalCount >= 5
        
        return VStack(alignment: .leading, spacing: isHero ? 3 : (isCompact ? 0 : 1)) {
            HStack(spacing: 2) {
                Text(symbol.name)
                    .font(.system(size: isHero ? 16 : (isCompact ? 10 : 12), weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(1)
                    .layoutPriority(1)
                
                Spacer(minLength: 2)
                
                if !isCompact || totalCount <= 4 {
                    Text(symbol.code)
                        .font(.system(size: isHero ? 10 : 8, weight: .semibold, design: .monospaced))
                        .foregroundColor(Color(white: 0.6))
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                }
            }
            
            Text(quote.price)
                .font(.system(size: isHero ? 28 : (isCompact ? 14 : 17), weight: .heavy, design: .rounded))
                .foregroundColor(color)
                .minimumScaleFactor(0.45)
                .lineLimit(1)
            
            HStack(spacing: 3) {
                Text(quote.priceChangePercent)
                    .font(.system(size: isHero ? 11 : (isCompact ? 8 : 9), weight: .heavy))
                    .foregroundColor(.white)
                    .padding(.horizontal, isCompact ? 2 : 3)
                    .padding(.vertical, 1)
                    .background(color)
                    .cornerRadius(3)
                
                Text(quote.priceChange)
                    .font(.system(size: isHero ? 10 : (isCompact ? 7 : 8), weight: .semibold))
                    .foregroundColor(color)
            }
        }
        .padding(isHero ? 8 : (isCompact ? 3 : 5))
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(Color(white: 0.12))
        .cornerRadius(6)
    }
    
    // MARK: - 画中画与 Mac 独立置顶悬浮窗控制按钮
    private var pipControlButton: some View {
        VStack(spacing: 8) {
            #if canImport(UIKit)
            Button(action: {
                if pipManager.isPiPActive {
                    pipManager.stopPiP()
                } else {
                    pipManager.startPiP()
                }
            }) {
                HStack(spacing: 10) {
                    Image(systemName: pipManager.isPiPActive ? "pip.exit" : "pip.enter")
                        .font(.system(size: 18, weight: .bold))
                    Text(pipManager.isPiPActive ? "关闭画中画" : "开启 16:9 极宽悬浮窗 (展示 \(min(pipStockCount, stockData.watchlist.count)) 只)")
                        .font(.system(size: 16, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(
                    LinearGradient(
                        colors: pipManager.isPiPActive ? [Color.red, Color.orange] : [Color.blue, Color.purple],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(14)
                .shadow(color: (pipManager.isPiPActive ? Color.red : Color.blue).opacity(0.3), radius: 8, x: 0, y: 4)
            }
            #endif
            
            #if canImport(AppKit)
            Button(action: {
                MacFloatingWindowManager.shared.toggleFloatingWindow()
            }) {
                HStack(spacing: 8) {
                    Image(systemName: "macwindow.on.rectangle")
                        .font(.system(size: 15, weight: .bold))
                    Text(MacFloatingWindowManager.shared.isFloatingWindowOpen ? "关闭 Mac 跨桌面置顶悬浮窗" : "开启 Mac 跨桌面置顶悬浮窗 (Always on Top)")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(
                    LinearGradient(
                        colors: MacFloatingWindowManager.shared.isFloatingWindowOpen ? [Color.red, Color.orange] : [Color.blue, Color.indigo],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(12)
                .shadow(color: Color.blue.opacity(0.3), radius: 6, x: 0, y: 3)
            }
            #endif
        }
    }
    
    // MARK: - 自选股列表
    private var watchlistSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("全部自选股 (\(stockData.watchlist.count)只)")
                    .font(.headline)
                
                Spacer()
                
                Button(action: {
                    inputStockCode = ""
                    addStockErrorMessage = nil
                    searchService.clear()
                    showingAddStockSheet = true
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                        Text("添加股票")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.blue)
                }
            }
            .padding(.horizontal, 4)
            
            VStack(spacing: 8) {
                ForEach(Array(stockData.watchlist.enumerated()), id: \.element.fullCode) { index, symbol in
                    let quote = stockData.quotes[symbol.fullCode] ?? StockQuote(symbol: symbol)
                    let isShownInPiP = index < pipStockCount
                    let color = getStockColor(isPositive: quote.isPositive, isFlat: quote.isFlat)
                    
                    SwipeableStockRow(
                        index: index,
                        symbol: symbol,
                        quote: quote,
                        isShownInPiP: isShownInPiP,
                        color: color,
                        isDragging: draggingStock == symbol,
                        activeSwipedId: $activeSwipedStockId,
                        onDelete: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                                stockData.removeStock(symbol)
                            }
                        }
                    )
                    .onDrag {
                        self.draggingStock = symbol
                        #if os(iOS)
                        let impact = UIImpactFeedbackGenerator(style: .medium)
                        impact.impactOccurred()
                        #endif
                        return NSItemProvider(object: symbol.fullCode as NSString)
                    }
                    .onDrop(of: [.text], delegate: StockDropDelegate(
                        targetItem: symbol,
                        watchlist: $stockData.watchlist,
                        draggingItem: $draggingStock
                    ))
                }
            }
        }
    }
    
    // MARK: - 股票模糊搜索与添加弹窗（支持名称、简拼、代码模糊匹配）
    private var addStockSheetView: some View {
        VStack(spacing: 16) {
            // 弹窗顶部栏
            HStack {
                Text("搜索并添加股票 / 指数 / ETF")
                    .font(.headline)
                Spacer()
                Button("完成") {
                    showingAddStockSheet = false
                }
                #if os(macOS)
                .keyboardShortcut(.cancelAction)
                #endif
            }
            
            // 搜索输入框（支持中文名、拼音简拼、代码即时联想）
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundColor(.secondary)
                    .font(.system(size: 15))
                
                TextField("输入股票名称、简拼或代码 (如 茅台 / byd / 600519)", text: $inputStockCode)
                    .font(.system(size: 15, weight: .medium))
                    .onChange(of: inputStockCode) { newText in
                        searchService.search(query: newText)
                    }
                
                if searchService.isSearching {
                    ProgressView()
                        .scaleEffect(0.8)
                } else if !inputStockCode.isEmpty {
                    Button(action: {
                        inputStockCode = ""
                        searchService.clear()
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(10)
            .background(Color.appSecondaryBackground)
            .cornerRadius(10)
            
            // 搜索结果列表 / 预设快捷推荐
            if !searchService.searchResults.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("搜索联想结果 (\(searchService.searchResults.count)个)：")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    ScrollView {
                        LazyVStack(spacing: 8) {
                            ForEach(searchService.searchResults) { item in
                                let isAlreadyAdded = stockData.watchlist.contains(where: { $0.fullCode == item.symbol.fullCode })
                                HStack(spacing: 10) {
                                    // 市场与类型微标
                                    Text(item.typeName)
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(marketBadgeColor(market: item.symbol.market, typeName: item.typeName))
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(marketBadgeColor(market: item.symbol.market, typeName: item.typeName).opacity(0.12))
                                        .cornerRadius(4)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        HStack(spacing: 4) {
                                            Text(item.symbol.name)
                                                .font(.system(size: 14, weight: .bold))
                                            if !item.pinyin.isEmpty {
                                                Text("(\(item.pinyin))")
                                                    .font(.system(size: 11))
                                                    .foregroundColor(.secondary)
                                            }
                                        }
                                        
                                        HStack(spacing: 4) {
                                            Text(item.symbol.code)
                                                .font(.system(size: 11, design: .monospaced))
                                                .foregroundColor(.secondary)
                                            Text("· \(item.symbol.marketDisplayName)")
                                                .font(.system(size: 10))
                                                .foregroundColor(.secondary)
                                        }
                                    }
                                    
                                    Spacer()
                                    
                                    if isAlreadyAdded {
                                        Text("已在自选")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundColor(.secondary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(Color.appTertiaryBackground)
                                            .cornerRadius(6)
                                    } else {
                                        Button(action: {
                                            stockData.addStock(input: item.symbol.fullCode) { result in
                                                if case .success = result {
                                                    // 成功添加
                                                }
                                            }
                                        }) {
                                            HStack(spacing: 3) {
                                                Image(systemName: "plus")
                                                    .font(.system(size: 11, weight: .bold))
                                                Text("添加")
                                                    .font(.system(size: 12, weight: .semibold))
                                            }
                                            .foregroundColor(.white)
                                            .padding(.horizontal, 10)
                                            .padding(.vertical, 5)
                                            .background(Color.blue)
                                            .cornerRadius(6)
                                        }
                                        .buttonStyle(PlainButtonStyle())
                                    }
                                }
                                .padding(10)
                                .background(Color.appSecondaryBackground)
                                .cornerRadius(10)
                            }
                        }
                    }
                    .frame(maxHeight: 220)
                }
            } else if !inputStockCode.isEmpty && !searchService.isSearching {
                VStack(spacing: 8) {
                    Text("未检索到包含「\(inputStockCode)」的股票，您可直接按代码添加：")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                    
                    Button(action: {
                        isAddingStock = true
                        stockData.addStock(input: inputStockCode) { result in
                            isAddingStock = false
                            if case .success = result {
                                showingAddStockSheet = false
                            }
                        }
                    }) {
                        Text("按「\(inputStockCode)」直接添加")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 7)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                .padding(.vertical, 8)
            }
            
            // 常用推荐指数与热门标的快捷芯片
            VStack(alignment: .leading, spacing: 8) {
                Text("💡 常用指数与热门标的快速添加：")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                let quickCodes = [
                    ("000001", "上证指数"),
                    ("399006", "创业板指"),
                    ("399001", "深证成指"),
                    ("600519", "贵州茅台"),
                    ("300750", "宁德时代"),
                    ("002594", "比亚迪"),
                    ("688981", "中芯国际"),
                    ("300059", "东方财富")
                ]
                
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                    ForEach(quickCodes, id: \.0) { item in
                        let isAdded = stockData.watchlist.contains(where: { $0.code == item.0 })
                        Button(action: {
                            if !isAdded {
                                stockData.addStock(input: item.0) { _ in }
                            }
                        }) {
                            HStack {
                                Text(item.1)
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.primary)
                                Spacer()
                                Text(isAdded ? "已添加" : item.0)
                                    .font(.caption2)
                                    .foregroundColor(isAdded ? .green : .secondary)
                            }
                            .padding(8)
                            .background(isAdded ? Color.green.opacity(0.1) : Color.appSecondaryBackground)
                            .cornerRadius(8)
                        }
                        .buttonStyle(PlainButtonStyle())
                        .disabled(isAdded)
                    }
                }
            }
            
            Spacer()
        }
        .padding(20)
        #if os(macOS)
        .frame(width: 480, height: 480)
        .background(Color.appBackground)
        #else
        .background(Color.appBackground)
        #endif
    }
    
    private func marketBadgeColor(market: String, typeName: String) -> Color {
        if typeName == "指数" {
            return .orange
        } else if typeName == "ETF" {
            return .purple
        } else if market == "sh" {
            return .red
        } else if market == "sz" {
            return .blue
        } else {
            return .teal
        }
    }
    
    // MARK: - 偏好设置
    private var settingsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("画中画与行情偏好")
                .font(.headline)
                .padding(.horizontal, 4)
            
            VStack(spacing: 0) {
                // 画中画股票数量 (1 ~ 8 只自适应铺满)
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("展示股票数量: \(pipStockCount) 只")
                            .font(.body)
                        Text("支持 1 ~ 8 只，16:9 宽屏自动等比铺满全宽画布")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    Spacer()
                    
                    Stepper("", value: $pipStockCount, in: 1...8)
                        .labelsHidden()
                        .onChange(of: pipStockCount) { val in
                            #if canImport(UIKit)
                            pipManager.tickerViewController.setDisplayCount(val)
                            #endif
                        }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                // 快捷数量选择
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(1...8, id: \.self) { count in
                            Button(action: {
                                pipStockCount = count
                                #if canImport(UIKit)
                                pipManager.tickerViewController.setDisplayCount(count)
                                #endif
                            }) {
                                Text("\(count)只")
                                    .font(.system(size: 13, weight: pipStockCount == count ? .bold : .medium))
                                    .foregroundColor(pipStockCount == count ? .white : .primary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 6)
                                    .background(pipStockCount == count ? Color.blue : Color.appTertiaryBackground)
                                    .cornerRadius(8)
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
                }
                
                Divider().padding(.leading, 16)
                
                Toggle(isOn: $autoPiP) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("回到桌面自动开启")
                            .font(.body)
                        Text("离开 App 时自动弹出 16:9 极宽行情画中画")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: autoPiP) { val in
                    pipManager.setAutoPiP(enabled: val)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                Divider().padding(.leading, 16)
                
                Toggle(isOn: $isRedUpGreenDown) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("红涨绿跌配色")
                            .font(.body)
                        Text(isRedUpGreenDown ? "当前：红涨绿跌（A股大陆标准）" : "当前：绿涨红跌（国际习惯）")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: isRedUpGreenDown) { val in
                    #if canImport(UIKit)
                    pipManager.tickerViewController.isRedUpGreenDown = val
                    #endif
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                Divider().padding(.leading, 16)
                
                Toggle(isOn: $stockData.isMockMode) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("模拟行情波动模式")
                            .font(.body)
                        Text("在周末或非交易时段生成动态跳动行情用于演示")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: stockData.isMockMode) { val in
                    if val {
                        stockData.enableMockMode()
                    } else {
                        stockData.disableMockMode()
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                #if os(macOS)
                Divider().padding(.leading, 16)
                
                // Mac 专属：悬浮窗贴边自动收起开关
                Toggle(isOn: $macWindowManager.autoHideEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Mac 悬浮窗靠边自动隐藏")
                            .font(.body)
                        Text("将小窗拖至屏幕边缘后自动向外收起，鼠标移入即刻滑出")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                if macWindowManager.autoHideEnabled {
                    Divider().padding(.leading, 16)
                    
                    // Mac 专属：收起延迟等待时间选择器 (默认 1.0 秒)
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("靠边收起等待时间")
                                .font(.body)
                            Text("当前：\(macWindowManager.autoHideDelay == 0.5 ? "0.5" : "\(Int(macWindowManager.autoHideDelay))") 秒后自动收起")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        Spacer()
                        
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach([0.5, 1.0, 2.0, 3.0, 5.0], id: \.self) { sec in
                                    Button(action: {
                                        macWindowManager.autoHideDelay = sec
                                    }) {
                                        Text(sec == 0.5 ? "0.5s" : "\(Int(sec))s")
                                            .font(.system(size: 12, weight: macWindowManager.autoHideDelay == sec ? .bold : .medium))
                                            .foregroundColor(macWindowManager.autoHideDelay == sec ? .white : .primary)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 5)
                                            .background(macWindowManager.autoHideDelay == sec ? Color.blue : Color.appTertiaryBackground)
                                            .cornerRadius(6)
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                }
                #endif
                
                Divider().padding(.leading, 16)
                
                // 7x24 实时快讯与自选股强提醒
                Toggle(isOn: $newsManager.isWatchlistAlertEnabled) {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(spacing: 4) {
                            Image(systemName: "bell.badge.fill")
                                .foregroundColor(.orange)
                                .font(.system(size: 13))
                            Text("自选股与概念题材推送提醒")
                                .font(.body)
                        }
                        Text("抓取到自选个股或所属概念的利好/利空/突发时，立即弹窗与系统推送")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .onChange(of: newsManager.isWatchlistAlertEnabled) { val in
                    newsManager.toggleWatchlistAlert(enabled: val)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                
                if !newsManager.isSystemNotificationAuthorized {
                    Button(action: {
                        newsManager.openSystemNotificationSettings()
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "gearshape.fill")
                                .foregroundColor(.yellow)
                            Text("系统通知权限未开启，点击前往系统设置允许推送")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.yellow)
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundColor(.yellow)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.yellow.opacity(0.12))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
                
                Divider().padding(.leading, 16)
                
                // 自动抓取轮询间隔
                VStack(alignment: .leading, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("快讯自动抓取轮询")
                            .font(.body)
                        Text("当前：\(Int(newsManager.autoRefreshInterval)) 秒自动抓取最新全网电报与推特")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach([10.0, 20.0, 30.0, 60.0, 180.0, 300.0], id: \.self) { sec in
                                let isSelected = newsManager.autoRefreshInterval == sec
                                let label = sec < 60 ? "\(Int(sec))秒" : "\(Int(sec / 60))分钟"
                                Button(action: {
                                    newsManager.setAutoRefreshInterval(sec)
                                }) {
                                    Text(label)
                                        .font(.system(size: 12, weight: isSelected ? .heavy : .medium))
                                        .foregroundColor(isSelected ? .white : .primary)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(isSelected ? Color.blue : Color.appTertiaryBackground)
                                        .cornerRadius(8)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(isSelected ? Color.blue : Color.white.opacity(0.1), lineWidth: 1)
                                        )
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .background(Color.appSecondaryBackground)
            .cornerRadius(14)
        }
    }
    
    // MARK: - 自选股要闻突发提醒弹窗 (全局 Modal，支持多条队列逐一确认)
    private func watchlistAlertModalView(for item: NewsItem) -> some View {
        let queueCount = newsManager.pendingAlertQueue.count
        return ZStack {
            Color.black.opacity(0.65)
                .ignoresSafeArea()
                .onTapGesture {
                    withAnimation { newsManager.dismissCurrentAlert() }
                }
            
            VStack(alignment: .leading, spacing: 14) {
                modalTopHeader(item: item, queueCount: queueCount)
                
                Divider().background(Color.white.opacity(0.2))
                
                modalMetaBar(item: item)
                
                if !item.title.isEmpty {
                    Text(item.title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.yellow)
                }
                
                Text(item.content)
                    .font(.system(size: 13))
                    .foregroundColor(.white.opacity(0.92))
                    .lineSpacing(4)
                    .textSelection(.enabled)
                
                modalActionButtons(item: item, queueCount: queueCount)
            }
            .id(item.id)
            .animation(.easeInOut(duration: 0.2), value: item.id)
            .padding(20)
            .frame(maxWidth: 500)
            .background(Color(white: 0.14))
            .cornerRadius(16)
            .overlay(
                RoundedRectangle(cornerRadius: 16)
                    .stroke(Color.red.opacity(0.8), lineWidth: 2)
            )
            .shadow(color: Color.red.opacity(0.3), radius: 20, x: 0, y: 8)
            .padding(24)
        }
    }
    
    private func modalTopHeader(item: NewsItem, queueCount: Int) -> some View {
        let alertCat = newsManager.currentAlertItem?.alertCategory ?? .watchlistStock
        let modalTitle: String = {
            switch alertCat {
            case .watchlistStock: return "🚨 自选个股重要提醒！"
            case .watchlistConcept: return "🚨 自选关联板块要闻！"
            case .globalBreaking: return "⚡️ 全网重大突发事件！"
            }
        }()
        let labelText: String = {
            switch alertCat {
            case .watchlistStock: return "命中自选:"
            case .watchlistConcept: return "关联自选:"
            case .globalBreaking: return "事件属性:"
            }
        }()
        
        return HStack(spacing: 8) {
            Image(systemName: "bell.badge.fill")
                .font(.system(size: 20, weight: .bold))
                .foregroundColor(.red)
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(modalTitle)
                        .font(.system(size: 16, weight: .heavy))
                        .foregroundColor(.white)
                    
                    if queueCount > 1 {
                        Text("(剩余 \(queueCount) 条)")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.yellow.opacity(0.2))
                            .cornerRadius(4)
                    }
                }
                HStack(spacing: 6) {
                    Text(labelText)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.white.opacity(0.8))
                    
                    modalStockBadges(alertCat: alertCat)
                }
                .padding(.top, 2)
            }
            
            Spacer()
            
            Button(action: {
                withAnimation { newsManager.dismissCurrentAlert() }
            }) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 20))
                    .foregroundColor(.white.opacity(0.6))
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    @ViewBuilder
    private func modalStockBadges(alertCat: AlertCategoryType) -> some View {
        if alertCat == .globalBreaking {
            HStack(spacing: 3) {
                Image(systemName: "bolt.fill")
                    .font(.system(size: 10))
                    .foregroundColor(.red)
                Text("全网重大突发")
                    .font(.system(size: 12, weight: .heavy))
                    .foregroundColor(.red)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.red.opacity(0.22))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.red.opacity(0.7), lineWidth: 1.2))
        } else {
            let matchedList = newsManager.currentAlertItem?.matchedStocks ?? []
            if !matchedList.isEmpty {
                ForEach(matchedList) { match in
                    HStack(spacing: 3) {
                        Image(systemName: match.matchType == "自选个股" ? "star.fill" : "tag.fill")
                            .font(.system(size: 10))
                            .foregroundColor(match.matchType == "自选个股" ? .yellow : .cyan)
                        Text(match.symbol.name)
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(match.matchType == "自选个股" ? .yellow : .cyan)
                    }
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background((match.matchType == "自选个股" ? Color.yellow : Color.cyan).opacity(0.22))
                    .cornerRadius(6)
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke((match.matchType == "自选个股" ? Color.yellow : Color.cyan).opacity(0.7), lineWidth: 1.2))
                }
            } else {
                HStack(spacing: 3) {
                    Image(systemName: "star.fill")
                        .font(.system(size: 10))
                        .foregroundColor(.yellow)
                    Text(newsManager.matchedAlertStockName)
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(.yellow)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Color.yellow.opacity(0.22))
                .cornerRadius(6)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.yellow.opacity(0.7), lineWidth: 1.2))
            }
        }
        
        if !newsManager.matchedAlertReason.isEmpty {
            HStack(spacing: 3) {
                Image(systemName: "tag.fill")
                    .font(.system(size: 9))
                    .foregroundColor(.cyan)
                Text(newsManager.matchedAlertReason.replacingOccurrences(of: "【", with: "").replacingOccurrences(of: "】", with: ""))
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundColor(.cyan)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(Color.cyan.opacity(0.2))
            .cornerRadius(6)
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color.cyan.opacity(0.6), lineWidth: 1.2))
        }
    }
    
    private func modalMetaBar(item: NewsItem) -> some View {
        HStack(spacing: 8) {
            Text(item.source.rawValue)
                .font(.system(size: 10, weight: .bold))
                .foregroundColor(Color.blue)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(Color.blue.opacity(0.2))
                .cornerRadius(4)
            
            if let summary = item.aiFactorSummary, !summary.isEmpty {
                HStack(spacing: 3) {
                    Text("AI: \(summary)")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(item.sentiment == .bullish ? .red : (item.sentiment == .bearish ? .green : .white.opacity(0.85)))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background((item.sentiment == .bullish ? Color.red : (item.sentiment == .bearish ? Color.green : Color.white)).opacity(0.16))
                .cornerRadius(4)
            } else {
                HStack(spacing: 2) {
                    Image(systemName: item.sentiment.iconName)
                        .font(.system(size: 9))
                    Text("AI: \(item.sentiment.rawValue)")
                        .font(.system(size: 10, weight: .bold))
                }
                .foregroundColor(item.sentiment == .bullish ? .red : (item.sentiment == .bearish ? .green : .white.opacity(0.7)))
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.white.opacity(0.12))
                .cornerRadius(4)
            }
            
            Spacer()
            
            Text("\(item.formattedClockTime) (\(item.timeAgoText))")
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
    }
    
    private func modalActionButtons(item: NewsItem, queueCount: Int) -> some View {
        HStack(spacing: 10) {
            Button(action: {
                #if os(macOS)
                macViewMode = .news
                #else
                selectedIOSTab = 1
                #endif
                withAnimation { newsManager.dismissCurrentAlert() }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                    newsManager.selectedNewsForDetail = item
                    newsManager.targetScrollNewsId = item.id
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 12, weight: .bold))
                    Text("查看详情")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
                .background(Color.blue)
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            
            Button(action: {
                withAnimation { newsManager.dismissCurrentAlert() }
            }) {
                Text(queueCount > 1 ? "下一条 (\(queueCount - 1))" : "知道了")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white.opacity(0.9))
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Color.white.opacity(0.18))
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            
            if queueCount > 1 {
                Button(action: {
                    withAnimation { newsManager.dismissAllAlerts() }
                }) {
                    Text("全部已读")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.white.opacity(0.7))
                        .frame(width: 75)
                        .frame(height: 38)
                        .background(Color.white.opacity(0.1))
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
        }
        .padding(.top, 6)
    }
    
    // MARK: - 使用说明
    private var instructionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("💡 16:9 极宽画中画与 7x24 快讯使用贴士")
                .font(.subheadline)
                .fontWeight(.bold)
                .foregroundColor(.secondary)
            
            VStack(alignment: .leading, spacing: 5) {
                Text("1. 支持搜索股票中文名（如“茅台”）、简拼（如“gzmt”）或 6 位代码，实时联想秒级添加。")
                Text("2. 7x24 实时快讯汇聚财联社、华尔街见闻、新浪全球、东方财富、彭博/路透/推特官方编译。")
                Text("3. 快讯中提及的股票代码支持一键直接添加到自选股。")
                Text("4. 长按任意自选股票上下拖拽可快速调整画中画展示席位，向左滑动可删除。")
            }
            .font(.footnote)
            .foregroundColor(.secondary)
            .lineSpacing(3)
        }
        .padding(14)
        .background(Color.appTertiaryBackground)
        .cornerRadius(12)
    }
    
    // MARK: - 辅助计算
    private func getStockColor(isPositive: Bool, isFlat: Bool) -> Color {
        if isFlat {
            return Color.secondary
        }
        let red = Color(red: 0.92, green: 0.26, blue: 0.21)
        let green = Color(red: 0.18, green: 0.80, blue: 0.44)
        
        if isRedUpGreenDown {
            return isPositive ? red : green
        } else {
            return isPositive ? green : red
        }
    }
    
    private var marketDotColor: Color {
        if stockData.isMockMode {
            return .purple
        }
        if stockData.marketStatusText.contains("交易中") {
            return .green
        } else {
            return .orange
        }
    }
    
    private var formattedUpdateTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: stockData.lastUpdated) + " 更新"
    }
}

// MARK: - 长按拖拽排序 Drop 代理
struct StockDropDelegate: DropDelegate {
    let targetItem: StockSymbol
    @Binding var watchlist: [StockSymbol]
    @Binding var draggingItem: StockSymbol?
    
    func dropEntered(info: DropInfo) {
        guard let dragging = draggingItem,
              dragging != targetItem,
              let from = watchlist.firstIndex(of: dragging),
              let to = watchlist.firstIndex(of: targetItem) else { return }
        
        if watchlist[to] != dragging {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                watchlist.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
            }
        }
    }
    
    func performDrop(info: DropInfo) -> Bool {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
            draggingItem = nil
        }
        StockDataManager.shared.saveState()
        return true
    }
    
    func dropUpdated(info: DropInfo) -> DropProposal? {
        return DropProposal(operation: .move)
    }
}

// MARK: - 自选股单行组件
struct SwipeableStockRow: View {
    let index: Int
    let symbol: StockSymbol
    let quote: StockQuote
    let isShownInPiP: Bool
    let color: Color
    var isDragging: Bool = false
    @Binding var activeSwipedId: String?
    let onDelete: () -> Void
    
    @State private var dragOffset: CGFloat = 0
    @State private var isHovered: Bool = false
    
    private var isCurrentSwiped: Bool {
        activeSwipedId == symbol.fullCode
    }
    
    var body: some View {
        ZStack(alignment: .trailing) {
            #if os(iOS)
            if dragOffset < -5 || isCurrentSwiped {
                HStack {
                    Spacer()
                    Button(role: .destructive, action: {
                        let generator = UINotificationFeedbackGenerator()
                        generator.notificationOccurred(.success)
                        onDelete()
                    }) {
                        VStack(spacing: 3) {
                            Image(systemName: "trash.fill")
                                .font(.system(size: 18, weight: .bold))
                            Text("删除")
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(.white)
                        .frame(width: 74, height: 60)
                        .background(Color.red)
                        .cornerRadius(12)
                    }
                }
                .transition(.opacity)
            }
            #endif
            
            stockCardContent
                .offset(x: isCurrentSwiped ? -78 : dragOffset)
                .scaleEffect(isDragging ? 1.03 : 1.0)
                .shadow(color: isDragging ? Color.black.opacity(0.2) : Color.clear, radius: 8, x: 0, y: 4)
                .opacity(isDragging ? 0.85 : 1.0)
                #if os(iOS)
                .gesture(
                    DragGesture(minimumDistance: 15, coordinateSpace: .local)
                        .onChanged { value in
                            if value.translation.width < 0 {
                                dragOffset = value.translation.width
                            } else if isCurrentSwiped {
                                dragOffset = -78 + value.translation.width
                            }
                        }
                        .onEnded { value in
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.76)) {
                                if value.translation.width < -120 {
                                    let generator = UINotificationFeedbackGenerator()
                                    generator.notificationOccurred(.success)
                                    onDelete()
                                    activeSwipedId = nil
                                    dragOffset = 0
                                } else if value.translation.width < -40 {
                                    activeSwipedId = symbol.fullCode
                                    dragOffset = -78
                                } else {
                                    activeSwipedId = nil
                                    dragOffset = 0
                                }
                            }
                        }
                )
                #endif
                #if os(macOS)
                .onHover { hovering in
                    withAnimation(.easeInOut(duration: 0.15)) {
                        self.isHovered = hovering
                    }
                }
                #endif
        }
    }
    
    private var stockCardContent: some View {
        HStack(spacing: 12) {
            if isDragging {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Color.secondary.opacity(0.8))
                    .padding(.leading, 2)
                    .transition(.scale.combined(with: .opacity))
            }
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(symbol.name)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(.primary)
                    
                    if isShownInPiP {
                        Text("PiP 席位 \(index + 1)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.blue)
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 4) {
                    Text(symbol.code)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Text(symbol.marketDisplayName)
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            Text(quote.price)
                .font(.system(size: 17, weight: .bold, design: .rounded))
                .foregroundColor(color)
                .frame(minWidth: 80, alignment: .trailing)
            
            Text(quote.priceChangePercent)
                .font(.system(size: 13, weight: .bold))
                .foregroundColor(.white)
                .frame(width: 76, height: 32)
                .background(color)
                .cornerRadius(6)
            
            #if os(macOS)
            if isHovered {
                Button(action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(.red)
                        .padding(6)
                        .background(Color.red.opacity(0.12))
                        .clipShape(Circle())
                }
                .buttonStyle(PlainButtonStyle())
                .transition(.opacity)
            }
            #endif
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(isShownInPiP ? Color.blue.opacity(0.06) : Color.appSecondaryBackground)
        .cornerRadius(12)
        .overlay(
            RoundedRectangle(cornerRadius: 12)
                .stroke(isShownInPiP ? Color.blue.opacity(0.4) : Color.clear, lineWidth: 1)
        )
    }
}

// MARK: - 用于向 AVPictureInPictureController 提供载体 SourceView 的精确 16:9 锚点
#if canImport(UIKit)
final class PiPAnchorUIView: UIView {
    private var hasInitializedPiP = false
    
    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 50, bounds.height > 20 else { return }
        if !hasInitializedPiP || PiPManager.shared.pipController == nil {
            hasInitializedPiP = true
            PiPManager.shared.setupPiP(with: self)
        }
    }
}

struct PiPSourceAnchorView: UIViewRepresentable {
    func makeUIView(context: Context) -> PiPAnchorUIView {
        let view = PiPAnchorUIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = false
        return view
    }
    
    func updateUIView(_ uiView: PiPAnchorUIView, context: Context) {}
}
#else
struct PiPSourceAnchorView: View {
    var body: some View {
        Color.clear
    }
}
#endif
