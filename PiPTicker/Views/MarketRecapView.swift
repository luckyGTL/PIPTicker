import SwiftUI

/// A股全景复盘看板视图（板块资金流向/流入流出切换、个股资金流入流出榜、资金增速爆发榜、板块成分股钻取、涨跌停封板池）
public struct MarketRecapView: View {
    @StateObject private var recapManager = MarketRecapManager.shared
    
    // 大类主导航：0: 板块资金流向, 1: 个股主力资金榜, 2: ⚡️ 资金增速爆发榜, 3: 涨跌停与短线情绪
    @State private var selectedMajorTab: Int = 0
    
    // 子类分类（板块）：0: 行业板块, 1: 概念题材
    @State private var selectedSectorType: Int = 0
    
    // 板块资金流向方向切换：0: 🔥 主力净流入榜, 1: ❄️ 主力净流出榜
    @State private var sectorFlowDirection: Int = 0
    
    // 子类分类（个股）：0: 主力净流入前50, 1: 主力净流出前50
    @State private var stockFlowDirection: Int = 0
    
    // ⚡️ 资金增速榜专属二级分类：0: 📌 个股增速, 1: 🏢 行业增速, 2: 💡 概念增速
    @State private var speedDimension: Int = 0
    
    // ⚡️ 资金增速榜方向：0: 🔥 流入增速/抢筹爆发, 1: ❄️ 流出增速/抛压加速
    @State private var speedDirection: Int = 0
    
    // 子类分类（涨跌停）：0: 涨停封板池, 1: 跌停地板池
    @State private var limitPoolTab: Int = 0
    
    // 资金统计周期：今日、近3日、近5日、近7日、近10日、近20日
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
            
            // 3. 🌟 大类主导航栏 (第一排，4大类：板块资金、个股资金、资金增速榜、短线情绪)
            majorCategoryTabBar
                .padding(.horizontal, 16)
                .padding(.bottom, 8)
            
            // 4. 🌟 子类分类与统计周期工具栏 (第二排，独立整行)
            subCategoryAndFilterBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            
            Divider().opacity(0.4)
            
            // 5. 内容主体区域
            if selectedMajorTab == 0 {
                sectorFlowSection
            } else if selectedMajorTab == 1 {
                stockFlowRankSection
            } else if selectedMajorTab == 2 {
                speedRankingSection
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
                
                Text("板块资金 · 个股资金榜 · 资金增速榜 · 成分股钻取 · 情绪周期")
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
    
    // MARK: - 🌟 1. 大类主导航栏 (第一排，4大类切换)
    private var majorCategoryTabBar: some View {
        HStack(spacing: 6) {
            majorTabButton(title: "🏢 板块资金流向", index: 0)
            majorTabButton(title: "🏆 个股资金榜", index: 1)
            majorTabButton(title: "⚡️ 资金增速榜", index: 2)
            majorTabButton(title: "🚦 涨跌停与情绪", index: 3)
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
    
    // MARK: - 🌟 2. 子类分类与统计周期工具栏 (优化为两行优雅布局，彻底解决挤在一起的问题)
    private var subCategoryAndFilterBar: some View {
        VStack(spacing: 8) {
            // 第一行：分类维度与流入/流出方向切换
            HStack(spacing: 8) {
                if selectedMajorTab == 0 {
                    // 板块分类：行业 / 概念
                    HStack(spacing: 6) {
                        subFilterPill(title: "🏢 行业板块", isSelected: selectedSectorType == 0) {
                            withAnimation(.easeInOut(duration: 0.15)) { selectedSectorType = 0 }
                        }
                        subFilterPill(title: "💡 概念题材", isSelected: selectedSectorType == 1) {
                            withAnimation(.easeInOut(duration: 0.15)) { selectedSectorType = 1 }
                        }
                    }
                    
                    Spacer()
                    
                    // 资金流向方向：净流入 / 净流出
                    HStack(spacing: 6) {
                        subDirectionPill(title: "🔥 主力净流入", isPositive: true, isSelected: sectorFlowDirection == 0) {
                            withAnimation(.easeInOut(duration: 0.15)) { sectorFlowDirection = 0 }
                        }
                        subDirectionPill(title: "❄️ 主力净流出", isPositive: false, isSelected: sectorFlowDirection == 1) {
                            withAnimation(.easeInOut(duration: 0.15)) { sectorFlowDirection = 1 }
                        }
                    }
                } else if selectedMajorTab == 1 {
                    // 个股资金榜
                    HStack(spacing: 4) {
                        Image(systemName: "crown.fill")
                            .font(.system(size: 11))
                            .foregroundColor(.yellow)
                        Text("个股资金榜")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    HStack(spacing: 6) {
                        subDirectionPill(title: "🔥 净流入前 50", isPositive: true, isSelected: stockFlowDirection == 0) {
                            withAnimation(.easeInOut(duration: 0.15)) { stockFlowDirection = 0 }
                        }
                        subDirectionPill(title: "❄️ 净流出前 50", isPositive: false, isSelected: stockFlowDirection == 1) {
                            withAnimation(.easeInOut(duration: 0.15)) { stockFlowDirection = 1 }
                        }
                    }
                } else if selectedMajorTab == 2 {
                    // 资金增速榜维度：个股 / 行业 / 概念
                    HStack(spacing: 6) {
                        subFilterPill(title: "📌 个股增速", isSelected: speedDimension == 0) {
                            withAnimation(.easeInOut(duration: 0.15)) { speedDimension = 0 }
                        }
                        subFilterPill(title: "🏢 行业增速", isSelected: speedDimension == 1) {
                            withAnimation(.easeInOut(duration: 0.15)) { speedDimension = 1 }
                        }
                        subFilterPill(title: "💡 概念增速", isSelected: speedDimension == 2) {
                            withAnimation(.easeInOut(duration: 0.15)) { speedDimension = 2 }
                        }
                    }
                    
                    Spacer()
                    
                    // 增速榜方向
                    HStack(spacing: 6) {
                        subDirectionPill(title: "🔥 抢筹 / 流入增速", isPositive: true, isSelected: speedDirection == 0) {
                            withAnimation(.easeInOut(duration: 0.15)) { speedDirection = 0 }
                        }
                        subDirectionPill(title: "❄️ 抛压 / 流出增速", isPositive: false, isSelected: speedDirection == 1) {
                            withAnimation(.easeInOut(duration: 0.15)) { speedDirection = 1 }
                        }
                    }
                } else {
                    // 涨跌停与情绪池
                    HStack(spacing: 6) {
                        subFilterPill(title: "🔴 涨停封板池 (\(recapManager.limitUpStocks.count))", isSelected: limitPoolTab == 0) {
                            withAnimation(.easeInOut(duration: 0.15)) { limitPoolTab = 0 }
                        }
                        subFilterPill(title: "🟢 跌停地板池 (\(recapManager.limitDownStocks.count))", isSelected: limitPoolTab == 1) {
                            withAnimation(.easeInOut(duration: 0.15)) { limitPoolTab = 1 }
                        }
                    }
                    
                    Spacer()
                    
                    Text("最高连板: \(max(1, recapManager.sentimentSummary.maxConsecutiveLadder)) 板")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.orange)
                }
            }
            
            // 第二行：统计时间周期选择栏（仅在板块和个股资金榜展示）
            if selectedMajorTab == 0 || selectedMajorTab == 1 {
                HStack(spacing: 8) {
                    HStack(spacing: 4) {
                        Image(systemName: "calendar")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        Text("统计周期:")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(.secondary)
                    }
                    
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
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 4)
                                        .background(isSelected ? Color.blue : Color.appTertiaryBackground)
                                        .cornerRadius(6)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                    
                    Spacer()
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.appSecondaryBackground.opacity(0.55))
        .cornerRadius(10)
    }
    
    private func subFilterPill(title: String, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : .primary)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(isSelected ? Color.blue : Color.appTertiaryBackground)
                .cornerRadius(7)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    private func subDirectionPill(title: String, isPositive: Bool, isSelected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 12, weight: isSelected ? .bold : .medium))
                .foregroundColor(isSelected ? .white : (isPositive ? .red : .green))
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(
                    isSelected ? (isPositive ? Color.red : Color.green) : (isPositive ? Color.red.opacity(0.12) : Color.green.opacity(0.12))
                )
                .cornerRadius(7)
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - 1. 板块资金流向列表视图 (支持点击钻取成分股，流入/流出独立切换)
    private var sectorFlowSection: some View {
        let items = selectedSectorType == 0 ? recapManager.industrySectorFlows : recapManager.conceptSectorFlows
        let isInflow = (sectorFlowDirection == 0)
        
        let sortedItems = items.sorted {
            if isInflow {
                return $0.netInflow(for: selectedTimeRange) > $1.netInflow(for: selectedTimeRange)
            } else {
                return $0.netInflow(for: selectedTimeRange) < $1.netInflow(for: selectedTimeRange)
            }
        }
        let displayList = Array(sortedItems.prefix(30))
        
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
                                    sectorCardRow(index: index + 1, for: item, isPositive: isInflow)
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
    
    private func sectorCardRow(index: Int, for item: SectorFlowItem, isPositive: Bool) -> some View {
        let currentFlow = item.netInflow(for: selectedTimeRange)
        let currentPct = item.changePercent(for: selectedTimeRange)
        
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
                    if !item.leadingStockName.isEmpty {
                        Text("领涨: \(item.leadingStockName)")
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                    }
                    
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
                    
                    if item.ratioAmount != 0 {
                        Text("强度 \(item.formattedRatio)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.orange)
                    }
                }
            }
            
            Spacer()
            
            // 真实周期涨跌幅
            Text(String(format: "%+.2f%%", currentPct))
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(currentPct >= 0 ? .red : .green)
                .frame(width: 80, alignment: .trailing)
            
            // 真实净流入资金金额
            Text(item.formattedNetInflow(for: selectedTimeRange))
                .font(.system(size: 13, weight: .bold, design: .monospaced))
                .foregroundColor(currentFlow >= 0 ? .red : .green)
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.appTertiaryBackground)
        .cornerRadius(8)
    }
    
    // MARK: - 2. 个股主力资金流入 / 流出排行榜
    private var stockFlowRankSection: some View {
        let rawList = (stockFlowDirection == 0) ? recapManager.topStockInflows : recapManager.topStockOutflows
        let isInflow = (stockFlowDirection == 0)
        
        let sortedList = rawList.sorted {
            if isInflow {
                return $0.netInflow(for: selectedTimeRange) > $1.netInflow(for: selectedTimeRange)
            } else {
                return $0.netInflow(for: selectedTimeRange) < $1.netInflow(for: selectedTimeRange)
            }
        }
        let displayList = Array(sortedList.prefix(50))
        
        let headerTitle = "\(selectedTimeRange.rawValue)个股主力资金\(isInflow ? "净流入" : "净流出")前 50 强"
        let headerIcon = isInflow ? "arrow.up.right.circle.fill" : "arrow.down.right.circle.fill"
        let headerColor: Color = isInflow ? .red : .green
        
        return ScrollView {
            VStack(spacing: 12) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: headerIcon)
                            .foregroundColor(headerColor)
                        Text(headerTitle)
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
    
    // MARK: - 3. ⚡️ 资金增速/爆发排行榜视图 (三维：个股/行业/概念 × 流入/流出)
    private var speedRankingSection: some View {
        let isPositive = (speedDirection == 0)
        let headerIcon = isPositive ? "bolt.fill" : "arrow.down.right.and.arrow.up.left"
        let headerColor: Color = isPositive ? .red : .green
        let directionName = isPositive ? "抢筹流入增速" : "抛压流出加速"
        
        return ScrollView {
            VStack(spacing: 12) {
                if speedDimension == 0 {
                    // 个股资金增速榜
                    let list = isPositive ? recapManager.stockInflowSpeedRank : recapManager.stockOutflowSpeedRank
                    let displayList = Array(list.prefix(50))
                    
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: headerIcon)
                                .foregroundColor(headerColor)
                            Text("个股主力\(directionName)前 50 强")
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
                            Text("正在拉取个股资金增速与抢筹爆发数据...")
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
                } else if speedDimension == 1 {
                    // 行业板块资金增速榜
                    let list = isPositive ? recapManager.industryInflowSpeedRank : recapManager.industryOutflowSpeedRank
                    let displayList = Array(list.prefix(30))
                    
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: headerIcon)
                                .foregroundColor(headerColor)
                            Text("行业板块主力\(directionName)前 30 强")
                                .font(.system(size: 14, weight: .bold))
                        }
                        Spacer()
                        Text("共 \(displayList.count) 个行业")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                    
                    if displayList.isEmpty {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("正在拉取行业板块资金增速数据...")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 40)
                    } else {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(displayList.enumerated()), id: \.element.id) { index, item in
                                Button(action: {
                                    selectedSectorForDetail = item
                                }) {
                                    sectorCardRow(index: index + 1, for: item, isPositive: isPositive)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
                        }
                    }
                } else {
                    // 概念题材资金增速榜
                    let list = isPositive ? recapManager.conceptInflowSpeedRank : recapManager.conceptOutflowSpeedRank
                    let displayList = Array(list.prefix(30))
                    
                    HStack {
                        HStack(spacing: 4) {
                            Image(systemName: headerIcon)
                                .foregroundColor(headerColor)
                            Text("概念题材主力\(directionName)前 30 强")
                                .font(.system(size: 14, weight: .bold))
                        }
                        Spacer()
                        Text("共 \(displayList.count) 个概念")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                    
                    if displayList.isEmpty {
                        VStack(spacing: 8) {
                            ProgressView()
                            Text("正在拉取概念题材资金增速数据...")
                                .font(.system(size: 12))
                                .foregroundColor(.secondary)
                        }
                        .padding(.vertical, 40)
                    } else {
                        LazyVStack(spacing: 6) {
                            ForEach(Array(displayList.enumerated()), id: \.element.id) { index, item in
                                Button(action: {
                                    selectedSectorForDetail = item
                                }) {
                                    sectorCardRow(index: index + 1, for: item, isPositive: isPositive)
                                }
                                .buttonStyle(PlainButtonStyle())
                            }
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
        let currentFlow = item.netInflow(for: selectedTimeRange)
        let currentPct = item.changePercent(for: selectedTimeRange)
        
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
                    
                    if item.ratioAmount != 0 {
                        Text("净占比 \(item.formattedRatio)")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.orange)
                    } else {
                        Text("成交 \(item.formattedTurnover)")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(width: 120, alignment: .leading)
            
            Spacer()
            
            // 最新价格
            Text(String(format: "%.2f", item.currentPrice))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(currentPct >= 0 ? .red : .green)
                .frame(width: 70, alignment: .trailing)
            
            // 涨跌幅
            Text(String(format: "%+.2f%%", currentPct))
                .font(.system(size: 13, weight: .heavy, design: .rounded))
                .foregroundColor(currentPct >= 0 ? .red : .green)
                .frame(width: 75, alignment: .trailing)
            
            // 主力净流入金额 / 抢筹强度
            VStack(alignment: .trailing, spacing: 1) {
                Text(item.formattedNetInflow(for: selectedTimeRange))
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(currentFlow >= 0 ? .red : .green)
                
                if item.ratioAmount != 0 {
                    Text("强度 \(item.formattedRatio)")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundColor(currentFlow >= 0 ? .red.opacity(0.8) : .green.opacity(0.8))
                }
            }
            .frame(width: 90, alignment: .trailing)
            
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
    
    // MARK: - 4. 涨跌停池与短线情绪列表
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
                    Text("\(timeRange.rawValue)涨跌幅")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(String(format: "%+.2f%%", sector.changePercent(for: timeRange)))
                        .font(.system(size: 15, weight: .heavy, design: .rounded))
                        .foregroundColor(sector.changePercent(for: timeRange) >= 0 ? .red : .green)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(timeRange.rawValue)主力净流入")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(sector.formattedNetInflow(for: timeRange))
                        .font(.system(size: 15, weight: .bold, design: .monospaced))
                        .foregroundColor(sector.netInflow(for: timeRange) >= 0 ? .red : .green)
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
            HStack(spacing: 10) {
                Text("成分股排序:")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.secondary)
                
                Picker("", selection: $sortMode) {
                    Text("按涨跌幅").tag(0)
                    Text("按主力流入").tag(1)
                    Text("按成交额").tag(2)
                }
                .pickerStyle(SegmentedPickerStyle())
                .frame(width: 250)
                
                Spacer()
                
                Text("共 \(constituentStocks.count) 只成分股")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            
            Divider().opacity(0.3)
            
            // 表头栏（明确标注各列数据：最新价、涨跌幅、主力净流入、成交总额）
            HStack(spacing: 8) {
                Text("股票 / 代码")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 125, alignment: .leading)
                
                Spacer()
                
                Text("最新价")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 65, alignment: .trailing)
                
                Text("涨跌幅")
                    .font(.system(size: 11, weight: sortMode == 0 ? .bold : .semibold))
                    .foregroundColor(sortMode == 0 ? .blue : .secondary)
                    .frame(width: 70, alignment: .trailing)
                
                Text("主力净额")
                    .font(.system(size: 11, weight: sortMode == 1 ? .bold : .semibold))
                    .foregroundColor(sortMode == 1 ? .blue : .secondary)
                    .frame(width: 75, alignment: .trailing)
                
                Text("成交总额")
                    .font(.system(size: 11, weight: sortMode == 2 ? .bold : .semibold))
                    .foregroundColor(sortMode == 2 ? .orange : .secondary)
                    .frame(width: 75, alignment: .trailing)
                
                Text("操作")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.secondary)
                    .frame(width: 48, alignment: .center)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
            .background(Color.appSecondaryBackground.opacity(0.4))
            
            Divider().opacity(0.2)
            
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
        .frame(minWidth: 640, minHeight: 560)
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
                .font(.system(size: 10, weight: .bold, design: .rounded))
                .foregroundColor(index <= 3 ? .white : .secondary)
                .frame(width: 18, height: 18)
                .background(index == 1 ? Color.yellow : (index == 2 ? Color.gray : (index == 3 ? Color.orange : Color.clear)))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 2) {
                Text(item.name)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundColor(.primary)
                
                Text(codeOnly)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            .frame(width: 100, alignment: .leading)
            
            Spacer()
            
            // 最新价
            Text(String(format: "%.2f", item.currentPrice))
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundColor(item.changePercent >= 0 ? .red : .green)
                .frame(width: 65, alignment: .trailing)
            
            // 涨跌幅
            Text(String(format: "%+.2f%%", item.changePercent))
                .font(.system(size: 13, weight: sortMode == 0 ? .heavy : .bold, design: .rounded))
                .foregroundColor(item.changePercent >= 0 ? .red : .green)
                .frame(width: 70, alignment: .trailing)
            
            // 主力净流入
            Text(item.formattedNetInflow)
                .font(.system(size: 12, weight: sortMode == 1 ? .heavy : .semibold, design: .monospaced))
                .foregroundColor(item.netInflow >= 0 ? .red : .green)
                .frame(width: 75, alignment: .trailing)
            
            // 成交总额（明确显示各股票成交额，按成交额排序时高亮）
            Text(item.formattedTurnover)
                .font(.system(size: 12, weight: sortMode == 2 ? .heavy : .medium, design: .monospaced))
                .foregroundColor(sortMode == 2 ? .orange : .primary)
                .frame(width: 75, alignment: .trailing)
            
            // 操作：一键加自选
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
            .frame(width: 48, alignment: .center)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color.appSecondaryBackground)
        .cornerRadius(8)
    }
}
