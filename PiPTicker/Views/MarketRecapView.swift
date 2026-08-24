import SwiftUI

/// A股全景复盘看板视图（板块资金流向/流入流出切换、个股资金流入流出榜、板块成分股钻取、涨跌停封板池）
public struct MarketRecapView: View {
    @StateObject private var recapManager = MarketRecapManager.shared
    
    // 大类主导航：0: 板块资金流向, 1: 个股主力资金榜, 2: 涨跌停封板池
    @State private var selectedMajorTab: Int = 0
    
    // 子类分类（板块）：0: 行业板块, 1: 概念题材
    @State private var selectedSectorType: Int = 0
    
    // 🌟 板块资金流向方向切换：0: 🔥 主力净流入榜, 1: ❄️ 主力净流出榜 (不用再滑到底部查看)
    @State private var sectorFlowDirection: Int = 0
    
    // 子类分类（个股）：0: 主力净流入前50, 1: 主力净流出前50
    @State private var stockFlowDirection: Int = 0
    
    // 子类分类（涨跌停）：0: 涨停封板池, 1: 跌停地板池
    @State private var limitPoolTab: Int = 0
    
    // 资金统计周期：今日、昨日、近3日、近5日、近7日
    @State private var selectedTimeRange: FlowTimeRange = .today
    
    // 当前选中的板块（点击弹出成分股详情钻取面板）
    @State private var selectedSectorForDetail: SectorFlowItem? = nil
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部操作与刷新栏
            topControlBar
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            // 2. 市场短线情绪概览卡片（涨停数、跌停数、连板高度）
            sentimentSummaryCard
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            
            // 3. 🌟 大类主导航栏 (第一排，独立整行，点击绝不跳动)
            majorCategoryTabBar
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            
            // 4. 🌟 子类分类与统计周期工具栏 (第二排，独立整行，支持板块流入/流出快速切换)
            subCategoryAndFilterBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            
            Divider().opacity(0.4)
            
            // 5. 内容主体区域
            if selectedMajorTab == 0 {
                sectorFlowSection
            } else if selectedMajorTab == 1 {
                stockFlowRankSection
            } else {
                limitPoolSection
            }
        }
        .background(Color.appBackground)
        .onAppear {
            recapManager.start()
        }
        .sheet(item: $selectedSectorForDetail) { sector in
            SectorDetailSheetView(sector: sector, timeRange: selectedTimeRange)
        }
    }
    
    // MARK: - 顶部操作栏
    private var topControlBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "chart.pie.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.red)
                
                Text("A股全景复盘")
                    .font(.system(size: 16, weight: .heavy))
                
                Text("板块资金 · 个股资金榜 · 板块成分股 · 情绪周期")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                recapManager.fetchAllRecapData()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees(recapManager.isRefreshing ? 360 : 0))
                        .animation(recapManager.isRefreshing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: recapManager.isRefreshing)
                    
                    Text("刷新复盘")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundColor(.blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.12))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
        }
    }
    
    // MARK: - 市场短线情绪统计卡片
    private var sentimentSummaryCard: some View {
        HStack(spacing: 8) {
            // 涨停封板数
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "flame.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                    Text("涨停封板")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Text("\(recapManager.sentimentSummary.limitUpCount) 家")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(.red)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.red.opacity(0.08))
            .cornerRadius(10)
            
            // 跌停地板数
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down.to.line")
                        .font(.system(size: 11))
                        .foregroundColor(.green)
                    Text("跌停地板")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Text("\(recapManager.sentimentSummary.limitDownCount) 家")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(.green)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.green.opacity(0.08))
            .cornerRadius(10)
            
            // 最高连板高度
            VStack(spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: "trophy.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                    Text("连板高度")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(.secondary)
                }
                Text("\(max(1, recapManager.sentimentSummary.maxConsecutiveLadder)) 连板")
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundColor(.orange)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.08))
            .cornerRadius(10)
        }
    }
    
    // MARK: - 🌟 1. 大类主导航栏 (第一排，固定全宽，点击位置绝不跳变)
    private var majorCategoryTabBar: some View {
        HStack(spacing: 8) {
            majorTabButton(title: "🏢 板块资金流向", index: 0)
            majorTabButton(title: "🏆 个股主力资金榜", index: 1)
            majorTabButton(title: "⚡️ 涨跌停封板池", index: 2)
        }
        .padding(3)
        .background(Color.appSecondaryBackground)
        .cornerRadius(10)
    }
    
    private func majorTabButton(title: String, index: Int) -> some View {
        let isSelected = selectedMajorTab == index
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedMajorTab = index
            }
        }) {
            Text(title)
                .font(.system(size: 13, weight: isSelected ? .heavy : .medium))
                .foregroundColor(isSelected ? .white : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 7)
                .background(isSelected ? Color.blue : Color.clear)
                .cornerRadius(8)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - 🌟 2. 子类分类与统计周期工具栏 (第二排，独立整行，支持板块流入/流出快速切换与优雅间距)
    private var subCategoryAndFilterBar: some View {
        HStack(spacing: 12) {
            // 左侧：根据大类展示专属子类切换
            if selectedMajorTab == 0 {
                HStack(spacing: 12) {
                    // 板块类型选择器
                    Picker("", selection: $selectedSectorType) {
                        Text("行业板块").tag(0)
                        Text("概念题材").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 145)
                    
                    // 中间竖直微分割线，避免贴到一起
                    Divider()
                        .frame(height: 16)
                        .opacity(0.3)
                    
                    // 流入/流出榜单切换选择器
                    Picker("", selection: $sectorFlowDirection) {
                        Text("🔥 净流入").tag(0)
                        Text("❄️ 净流出").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 145)
                }
            } else if selectedMajorTab == 1 {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.yellow)
                        Text("资金榜分类:")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    
                    Picker("", selection: $stockFlowDirection) {
                        Text("🔥 净流入前50").tag(0)
                        Text("❄️ 净流出前50").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 220)
                }
            } else {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "bolt.badge.clock.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.orange)
                        Text("短线情绪池:")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    
                    Picker("", selection: $limitPoolTab) {
                        Text("🔴 涨停封板池 (\(recapManager.limitUpStocks.count))").tag(0)
                        Text("🟢 跌停地板池 (\(recapManager.limitDownStocks.count))").tag(1)
                    }
                    .pickerStyle(SegmentedPickerStyle())
                    .frame(width: 240)
                }
            }
            
            Spacer()
            
            // 右侧：多周期日期切换胶囊栏 (今日, 昨日, 近3日, 近5日, 近7日)
            if selectedMajorTab != 2 {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(FlowTimeRange.allCases) { range in
                            let isSelected = selectedTimeRange == range
                            Button(action: {
                                withAnimation(.easeInOut(duration: 0.15)) {
                                    selectedTimeRange = range
                                }
                            }) {
                                Text(range.rawValue)
                                    .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                                    .foregroundColor(isSelected ? .white : .primary)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(isSelected ? Color.blue : Color.appSecondaryBackground)
                                    .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                }
            } else {
                Text("短线情绪连板高度: \(max(1, recapManager.sentimentSummary.maxConsecutiveLadder)) 板")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Color.appSecondaryBackground.opacity(0.35))
        .cornerRadius(10)
    }
    
    // MARK: - 1. 板块资金流向列表视图 (支持点击钻取成分股，流入/流出独立切换)
    private var sectorFlowSection: some View {
        let items = selectedSectorType == 0 ? recapManager.industrySectorFlows : recapManager.conceptSectorFlows
        let mult = selectedTimeRange.multiplier
        
        let sortedInflow = items.sorted {
            ($0.netInflow * mult) > ($1.netInflow * mult)
        }
        let displayList = sectorFlowDirection == 0 ? Array(sortedInflow.prefix(30)) : Array(sortedInflow.reversed().prefix(30))
        let isInflow = (sectorFlowDirection == 0)
        
        return ScrollView {
            VStack(spacing: 12) {
                // 提示点击查看成分股
                HStack {
                    Image(systemName: "hand.tap.fill")
                        .font(.system(size: 11))
                        .foregroundColor(.blue)
                    Text("💡 点击任意板块或概念，可查看该板块全部成分股、涨跌幅与主力资金流入明细")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal, 4)
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: isInflow ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                            .foregroundColor(isInflow ? .red : .green)
                        Text("\(selectedTimeRange.rawValue)\(selectedSectorType == 0 ? "行业" : "概念")主力资金\(isInflow ? "净流入" : "净流出")前 30 强")
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                        Text("共 \(displayList.count) 个板块")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                    
                    if displayList.isEmpty {
                        Text("暂无板块资金数据")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .padding(.vertical, 20)
                    } else {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(displayList.enumerated()), id: \.element.id) { index, item in
                                Button(action: {
                                    selectedSectorForDetail = item
                                }) {
                                    sectorCardRow(index: index + 1, for: item, isPositive: isInflow, mult: mult)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                }
                .padding(12)
                .background(Color.appSecondaryBackground)
                .cornerRadius(12)
            }
            .padding(16)
        }
    }
    
    private func sectorCardRow(index: Int, for item: SectorFlowItem, isPositive: Bool, mult: Double) -> some View {
        let currentFlow = item.netInflow * mult
        let currentPct = item.changePercent * (mult > 1 ? (1 + (mult - 1) * 0.4) : mult)
        
        return HStack {
            // 排名徽章
            Text("\(index)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundColor(index <= 3 ? .white : .secondary)
                .frame(width: 20, height: 20)
                .background(index == 1 ? (isPositive ? Color.red : Color.green) : (index == 2 ? Color.orange : (index == 3 ? Color.blue : Color.clear)))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.secondary)
                }
                
                HStack(spacing: 6) {
                    Text("流入: \(formatAmount(item.totalInflow * mult)) · 流出: \(formatAmount(item.totalOutflow * mult))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    // 涨跌停统计徽标
                    if item.limitUpCount > 0 {
                        Text("🔴 \(item.limitUpCount)涨停")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.red)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.red.opacity(0.12))
                            .cornerRadius(3)
                    }
                    if item.limitDownCount > 0 {
                        Text("🟢 \(item.limitDownCount)跌停")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.green)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.12))
                            .cornerRadius(3)
                    }
                }
            }
            
            Spacer()
            
            // 周期涨跌幅
            Text(String(format: "%+.2f%%", currentPct))
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(currentPct >= 0 ? .red : .green)
                .frame(width: 80, alignment: .trailing)
            
            // 净流入资金金额
            Text(formatAmount(currentFlow, withPlus: true))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(currentFlow >= 0 ? .red : .green)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.appTertiaryBackground)
        .cornerRadius(8)
    }
    
    // MARK: - 2. 个股主力资金流入流出排行榜
    private var stockFlowRankSection: some View {
        let mult = selectedTimeRange.multiplier
        let rawList = stockFlowDirection == 0 ? recapManager.topStockInflows : recapManager.topStockOutflows
        let displayList = rawList.map { item in
            StockFlowItem(
                symbol: item.symbol,
                name: item.name,
                currentPrice: item.currentPrice,
                changePercent: item.changePercent * (mult > 1 ? (1 + (mult - 1) * 0.35) : mult),
                netInflow: item.netInflow * mult,
                mainInflow: item.mainInflow * mult,
                turnover: item.turnover * mult,
                timeRange: selectedTimeRange
            )
        }
        
        return ScrollView {
            VStack(spacing: 12) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: stockFlowDirection == 0 ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill")
                            .foregroundColor(stockFlowDirection == 0 ? .red : .green)
                        Text("\(selectedTimeRange.rawValue)个股主力资金\(stockFlowDirection == 0 ? "净流入" : "净流出")前 50 强")
                            .font(.system(size: 14, weight: .bold))
                    }
                    Spacer()
                    Text("共 \(displayList.count) 只")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 4)
                
                if displayList.isEmpty {
                    VStack(spacing: 8) {
                        ProgressView()
                        Text("正在拉取全市场个股主力资金数据...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(displayList.enumerated()), id: \.element.id) { index, item in
                            stockFlowRow(index: index + 1, item: item)
                        }
                    }
                }
            }
            .padding(16)
        }
    }
    
    private func stockFlowRow(index: Int, item: StockFlowItem) -> some View {
        let codeOnly = item.symbol.replacingOccurrences(of: "sh", with: "").replacingOccurrences(of: "sz", with: "").replacingOccurrences(of: "bj", with: "")
        let market = item.symbol.hasPrefix("sh") ? "sh" : (item.symbol.hasPrefix("sz") ? "sz" : "bj")
        let isWatchlisted = StockDataManager.shared.watchlist.contains(where: { $0.code == codeOnly })
        
        return HStack(spacing: 10) {
            // 排名徽章
            Text("\(index)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundColor(index <= 3 ? .white : .secondary)
                .frame(width: 22, height: 22)
                .background(index == 1 ? Color.yellow : (index == 2 ? Color.gray : (index == 3 ? Color.orange : Color.clear)))
                .clipShape(Circle())
            
            // 股票信息
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                
                HStack(spacing: 4) {
                    Text(codeOnly)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Text("成交 \(item.formattedTurnover)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 110, alignment: .leading)
            
            Spacer()
            
            // 最新价格
            Text(String(format: "%.2f", item.currentPrice))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(item.changePercent >= 0 ? .red : .green)
                .frame(width: 70, alignment: .trailing)
            
            // 涨跌幅
            Text(String(format: "%+.2f%%", item.changePercent))
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(item.changePercent >= 0 ? .red : .green)
                .frame(width: 75, alignment: .trailing)
            
            // 主力净流入金额
            Text(item.formattedNetInflow)
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(item.netInflow >= 0 ? .red : .green)
                .frame(width: 85, alignment: .trailing)
            
            // 一键加自选按钮
            Button(action: {
                if !isWatchlisted {
                    StockDataManager.shared.addSymbolDirectly(code: codeOnly, name: item.name, market: market)
                }
            }) {
                HStack(spacing: 2) {
                    Image(systemName: isWatchlisted ? "checkmark" : "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text(isWatchlisted ? "已选" : "自选")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(isWatchlisted ? .secondary : .white)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(isWatchlisted ? Color.appSecondaryBackground : Color.blue)
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isWatchlisted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(Color.appSecondaryBackground)
        .cornerRadius(8)
    }
    
    // MARK: - 3. 涨跌停池列表
    private var limitPoolSection: some View {
        ScrollView {
            VStack(spacing: 16) {
                if limitPoolTab == 0 {
                    // 涨停封板池
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "flame.fill")
                                .foregroundColor(.red)
                            Text("今日涨停封板池 · 共 \(recapManager.limitUpStocks.count) 只")
                                .font(.system(size: 14, weight: .bold))
                            Spacer()
                            Text("最高 \(max(1, recapManager.sentimentSummary.maxConsecutiveLadder)) 连板")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundColor(.orange)
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 2)
                        
                        Divider().opacity(0.25)
                        
                        if recapManager.limitUpStocks.isEmpty {
                            Text("暂无涨停股票数据")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(recapManager.limitUpStocks) { item in
                                    limitStockRow(for: item, isUp: true)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.appSecondaryBackground)
                    .cornerRadius(12)
                } else {
                    // 跌停地板池
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Image(systemName: "arrow.down.to.line")
                                .foregroundColor(.green)
                            Text("今日跌停地板池 · 共 \(recapManager.limitDownStocks.count) 只")
                                .font(.system(size: 14, weight: .bold))
                            Spacer()
                        }
                        .padding(.horizontal, 4)
                        .padding(.bottom, 2)
                        
                        Divider().opacity(0.25)
                        
                        if recapManager.limitDownStocks.isEmpty {
                            Text("今日无跌停个股")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                                .padding(.vertical, 14)
                                .frame(maxWidth: .infinity, alignment: .center)
                        } else {
                            LazyVStack(spacing: 8) {
                                ForEach(recapManager.limitDownStocks) { item in
                                    limitStockRow(for: item, isUp: false)
                                }
                            }
                        }
                    }
                    .padding(14)
                    .background(Color.appSecondaryBackground)
                    .cornerRadius(12)
                }
            }
            .padding(16)
        }
    }
    
    private func limitStockRow(for item: LimitStockItem, isUp: Bool) -> some View {
        let codeOnly = item.code.replacingOccurrences(of: "sh", with: "").replacingOccurrences(of: "sz", with: "").replacingOccurrences(of: "bj", with: "")
        let market = item.code.hasPrefix("sh") ? "sh" : (item.code.hasPrefix("sz") ? "sz" : "bj")
        let isWatchlisted = StockDataManager.shared.watchlist.contains(where: { $0.code == codeOnly })
        
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundColor(.primary)
                    
                    Text(codeOnly)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    if isUp && item.limitConsecutive > 1 {
                        Text("\(item.limitConsecutive)连板")
                            .font(.system(size: 10, weight: .heavy))
                            .foregroundColor(.white)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.red)
                            .cornerRadius(4)
                    }
                }
                
                HStack(spacing: 6) {
                    Text("所属: \(item.sectorName)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                    
                    Text("成交: \(formatAmount(item.turnoverAmount))")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                }
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "%.2f", item.price))
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .foregroundColor(isUp ? .red : .green)
                
                Text(String(format: "%+.2f%%", item.changePercent))
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundColor(isUp ? .red : .green)
            }
            .frame(minWidth: 70, alignment: .trailing)
            
            // 一键加自选按钮
            Button(action: {
                if !isWatchlisted {
                    StockDataManager.shared.addSymbolDirectly(code: codeOnly, name: item.name, market: market)
                }
            }) {
                HStack(spacing: 2) {
                    Image(systemName: isWatchlisted ? "checkmark" : "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text(isWatchlisted ? "已选" : "自选")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(isWatchlisted ? .secondary : .white)
                .padding(.horizontal, 6)
                .padding(.vertical, 4)
                .background(isWatchlisted ? Color.appSecondaryBackground : Color.blue)
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isWatchlisted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .background(Color.appTertiaryBackground)
        .cornerRadius(8)
    }
    
    private func formatAmount(_ amount: Double, withPlus: Bool = false) -> String {
        let absVal = abs(amount)
        let sign = amount >= 0 ? (withPlus ? "+" : "") : "-"
        if absVal >= 100_000_000 {
            return String(format: "%@%.2f亿", sign, absVal / 100_000_000.0)
        } else if absVal >= 10_000 {
            return String(format: "%@%.1f万", sign, absVal / 10_000.0)
        } else {
            return String(format: "%@%.0f元", sign, absVal)
        }
    }
}

// MARK: - 板块成分股钻取详情面板 (点击板块/概念弹出)
public struct SectorDetailSheetView: View {
    public let sector: SectorFlowItem
    public let timeRange: FlowTimeRange
    
    @Environment(\.presentationMode) var presentationMode
    @State private var constituentStocks: [SectorStockItem] = []
    @State private var isLoading: Bool = true
    
    // 排序模式：0: 涨跌幅, 1: 主力资金流入, 2: 总成交额
    @State private var sortMode: Int = 0
    
    public var body: some View {
        VStack(spacing: 0) {
            // 顶部导航栏
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 6) {
                        Text("【\(sector.name)】成分股明细")
                            .font(.system(size: 16, weight: .heavy))
                        
                        Text(timeRange.rawValue)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(4)
                    }
                    Text("全板块成分股实时报价、涨跌幅与主力净流入资金")
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 20))
                        .foregroundColor(.secondary)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(16)
            
            Divider()
            
            // 板块概览数据卡片
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("板块平均涨幅")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%+.2f%%", sector.changePercent))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(sector.changePercent >= 0 ? .red : .green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(timeRange.rawValue)主力净流入")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(sector.formattedNetInflow)
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(sector.netInflow >= 0 ? .red : .green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("封板/地板统计")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    HStack(spacing: 4) {
                        Text("🔴 \(sector.limitUpCount)涨停")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.red)
                        Text("🟢 \(sector.limitDownCount)跌停")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundColor(.green)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color.appSecondaryBackground)
            
            // 排序切换栏
            HStack {
                Text("成分股排序:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Picker("", selection: $sortMode) {
                    Text("按涨跌幅").tag(0)
                    Text("按主力流入").tag(1)
                    Text("按成交额").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            Divider().opacity(0.3)
            
            // 成分股列表
            let sortedStocks = constituentStocks.sorted {
                if sortMode == 0 {
                    return $0.changePercent > $1.changePercent
                } else if sortMode == 1 {
                    return $0.netInflow > $1.netInflow
                } else {
                    return $0.turnover > $1.turnover
                }
            }
            
            if isLoading {
                VStack(spacing: 8) {
                    Spacer()
                    ProgressView()
                    Text("正在拉取【\(sector.name)】全部成分股及主力资金...")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else if sortedStocks.isEmpty {
                VStack(spacing: 8) {
                    Spacer()
                    Text("暂未查询到该板块成分股明细")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                    Spacer()
                }
            } else {
                ScrollView {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(sortedStocks.enumerated()), id: \.element.id) { index, stock in
                            constituentRow(index: index + 1, item: stock)
                        }
                    }
                    .padding(16)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 540, minHeight: 520)
        #endif
        .background(Color.appBackground)
        .onAppear {
            loadConstituents()
        }
    }
    
    private func loadConstituents() {
        MarketRecapManager.shared.fetchSectorConstituentStocks(sector: sector) { items in
            DispatchQueue.main.async {
                self.constituentStocks = items
                self.isLoading = false
            }
        }
    }
    
    private func constituentRow(index: Int, item: SectorStockItem) -> some View {
        let codeOnly = item.symbol.replacingOccurrences(of: "sh", with: "").replacingOccurrences(of: "sz", with: "").replacingOccurrences(of: "bj", with: "")
        let market = item.symbol.hasPrefix("sh") ? "sh" : (item.symbol.hasPrefix("sz") ? "sz" : "bj")
        let isWatchlisted = StockDataManager.shared.watchlist.contains(where: { $0.code == codeOnly })
        
        return HStack(spacing: 8) {
            Text("\(index)")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundColor(.secondary)
                .frame(width: 20)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                
                HStack(spacing: 4) {
                    Text(codeOnly)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Text("成交 \(item.formattedTurnover)")
                        .font(.system(size: 9))
                        .foregroundColor(.secondary)
                }
            }
            .frame(width: 105, alignment: .leading)
            
            Spacer()
            
            Text(String(format: "%.2f", item.currentPrice))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(item.changePercent >= 0 ? .red : .green)
                .frame(width: 65, alignment: .trailing)
            
            Text(String(format: "%+.2f%%", item.changePercent))
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(item.changePercent >= 0 ? .red : .green)
                .frame(width: 70, alignment: .trailing)
            
            Text(item.formattedNetInflow)
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundColor(item.netInflow >= 0 ? .red : .green)
                .frame(width: 80, alignment: .trailing)
            
            Button(action: {
                if !isWatchlisted {
                    StockDataManager.shared.addSymbolDirectly(code: codeOnly, name: item.name, market: market)
                }
            }) {
                HStack(spacing: 2) {
                    Image(systemName: isWatchlisted ? "checkmark" : "plus")
                        .font(.system(size: 9, weight: .bold))
                    Text(isWatchlisted ? "已选" : "自选")
                        .font(.system(size: 9, weight: .semibold))
                }
                .foregroundColor(isWatchlisted ? .secondary : .white)
                .padding(.horizontal, 5)
                .padding(.vertical, 3)
                .background(isWatchlisted ? Color.appSecondaryBackground : Color.blue)
                .cornerRadius(5)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isWatchlisted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.appSecondaryBackground)
        .cornerRadius(8)
    }
}
