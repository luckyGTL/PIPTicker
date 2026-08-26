import SwiftUI

/// 全球核心市场看板视图（美股三大指数、科技七巨头与核心芯片龙头、美股板块、韩国股市指数与龙头股）
public struct GlobalMarketView: View {
    @StateObject private var globalManager = GlobalMarketManager.shared
    
    // 分市场切换：0: 美股市场 (包含板块与龙头股及盘前盘后), 1: 韩国股市 (大盘指数与龙头)
    @State private var selectedMarketTab: Int = 0
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            // 1. 顶部操作与刷新栏
            topControlBar
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            // 2. 市场主分类切换栏 (美股核心市场 vs 韩国股市)
            marketTabBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            
            Divider().opacity(0.4)
            
            // 3. 市场专属内容视图
            if selectedMarketTab == 0 {
                usMarketSection
            } else {
                koreaMarketSection
            }
        }
        .background(Color.appBackground)
        .onAppear {
            globalManager.start()
        }
    }
    
    // MARK: - 顶部操作栏
    private var topControlBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "globe.americas.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.blue)
                
                Text("全球核心市场")
                    .font(.system(size: 16, weight: .heavy))
                
                Text("美股盘前盘后 · 芯片与存储龙头 · 韩国股市")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                globalManager.fetchAllGlobalQuotes()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees(globalManager.isRefreshing ? 360 : 0))
                        .animation(globalManager.isRefreshing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: globalManager.isRefreshing)
                    
                    Text("刷新行情")
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
    
    // MARK: - 市场主分类切换栏
    private var marketTabBar: some View {
        HStack(spacing: 8) {
            marketTabButton(title: "🇺🇸 美股核心市场 (含盘前盘后与芯片存储)", index: 0)
            marketTabButton(title: "🇰🇷 韩国股市 (KOSPI & KRX龙头)", index: 1)
        }
        .padding(3)
        .background(Color.appSecondaryBackground)
        .cornerRadius(10)
    }
    
    private func marketTabButton(title: String, index: Int) -> some View {
        let isSelected = selectedMarketTab == index
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedMarketTab = index
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
    
    // MARK: - 美股市场视图
    private var usMarketSection: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1. 美股三大指数卡片 (道琼斯、纳斯达克、标普500) - 红涨绿跌
                let usIndices = globalManager.globalIndices.filter { $0.region == "美股" }
                if !usIndices.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(usIndices) { idx in
                            indexCard(for: idx)
                        }
                    }
                }
                
                // 2. 美股主要行业板块表现 (含盘前/盘后)
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "square.grid.2x2.fill")
                            .foregroundColor(.orange)
                        Text("美股核心行业板块表现（含常规与盘前盘后涨势）")
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(globalManager.usSectors) { sector in
                            usSectorCard(for: sector)
                        }
                    }
                }
                .padding(12)
                .background(Color.appSecondaryBackground)
                .cornerRadius(12)
                
                // 3. 美股科技与存储龙头个股列表（美光、闪迪/西数、英伟达、特斯拉、海力士等）
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "crown.fill")
                            .foregroundColor(.yellow)
                        Text("美股核心龙头股票（常规价 & 盘前盘后实时撮合）")
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                        Text("共 \(globalManager.usLeaderStocks.count) 只")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                    }
                    .padding(.horizontal, 4)
                    
                    LazyVStack(spacing: 8) {
                        ForEach(globalManager.usLeaderStocks) { stock in
                            usStockRow(for: stock)
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
    
    // MARK: - 韩国股市视图
    private var koreaMarketSection: some View {
        ScrollView {
            VStack(spacing: 16) {
                // 1. 韩国大盘指数卡片 (KOSPI, KOSDAQ) - 红涨绿跌
                let koreaIndices = globalManager.globalIndices.filter { $0.region == "韩股" }
                if !koreaIndices.isEmpty {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                        ForEach(koreaIndices) { idx in
                            indexCard(for: idx)
                        }
                    }
                }
                
                // 2. 韩国股市核心龙头股票 (含三星、SK海力士) - 红涨绿跌
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Image(systemName: "sparkles")
                            .foregroundColor(.blue)
                        Text("韩国股市核心龙头股 (KRX Leaders · 含三星与SK海力士)")
                            .font(.system(size: 14, weight: .bold))
                        Spacer()
                    }
                    .padding(.horizontal, 4)
                    
                    LazyVStack(spacing: 8) {
                        ForEach(globalManager.koreaLeaderStocks) { stock in
                            koreaStockRow(for: stock)
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
    
    // MARK: - 指数卡片（红涨绿跌）
    private func indexCard(for idx: GlobalIndexQuote) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(idx.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            Text(String(format: "%.2f", idx.currentPrice))
                .font(.system(size: 16, weight: .heavy, design: .monospaced))
                .foregroundColor(idx.changePercent >= 0 ? .red : .green)
            
            HStack(spacing: 4) {
                Text(String(format: "%+.2f", idx.changeAmount))
                Text(String(format: "(%+.2f%%)", idx.changePercent))
            }
            .font(.system(size: 11, weight: .bold))
            .foregroundColor(idx.changePercent >= 0 ? .red : .green)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.appSecondaryBackground)
        .cornerRadius(10)
    }
    
    // MARK: - 美股十大核心板块卡片（红涨绿跌，含盘前盘后实时行情）
    private func usSectorCard(for sector: USSectorQuote) -> some View {
        let isPrePostActive = sector.prePostChangePercent != nil
        let primaryPct = isPrePostActive ? (sector.prePostChangePercent ?? sector.changePercent) : sector.changePercent
        
        return HStack(spacing: 8) {
            Image(systemName: sector.iconName)
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(.blue)
                .frame(width: 22)
            
            VStack(alignment: .leading, spacing: 2) {
                Text(sector.name)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.primary)
                Text("领涨: \(sector.leadingStock)")
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                // 主大字展示当前有效时段的实时涨跌幅 (盘前盘后优先)
                HStack(spacing: 3) {
                    if isPrePostActive {
                        Text("盘前")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundColor(.purple)
                            .padding(.horizontal, 3)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.15))
                            .cornerRadius(3)
                    }
                    Text(String(format: "%+.2f%%", primaryPct))
                        .font(.system(size: 13, weight: .heavy, design: .rounded))
                        .foregroundColor(primaryPct >= 0 ? .red : .green)
                }
                
                if isPrePostActive {
                    HStack(spacing: 2) {
                        Text("常规")
                            .font(.system(size: 9))
                            .foregroundColor(.secondary)
                        Text(String(format: "%+.2f%%", sector.changePercent))
                            .font(.system(size: 9, weight: .semibold, design: .monospaced))
                            .foregroundColor(sector.changePercent >= 0 ? .red : .green)
                    }
                }
            }
        }
        .padding(9)
        .background(Color.appTertiaryBackground)
        .cornerRadius(8)
    }
    
    // MARK: - 美股个股卡片（含盘前/盘后实时数据高亮展示，红涨绿跌）
    private func usStockRow(for stock: USStockQuote) -> some View {
        VStack(spacing: 6) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(stock.nameCn)
                            .font(.system(size: 14, weight: .bold))
                        Text(stock.symbol)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundColor(.blue)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.blue.opacity(0.12))
                            .cornerRadius(3)
                        
                        if stock.isPrePostActive {
                            HStack(spacing: 2) {
                                Image(systemName: "bolt.fill")
                                    .font(.system(size: 8))
                                Text("盘前/盘后实时")
                                    .font(.system(size: 9, weight: .bold))
                            }
                            .foregroundColor(.purple)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.purple.opacity(0.15))
                            .cornerRadius(3)
                        }
                    }
                    
                    HStack(spacing: 6) {
                        Text(stock.sectorCategory)
                            .font(.system(size: 10))
                            .foregroundColor(.secondary)
                        
                        if !stock.marketCapFormatted.isEmpty {
                            Text("· 市值: \(stock.marketCapFormatted)")
                                .font(.system(size: 10))
                                .foregroundColor(.secondary)
                        }
                    }
                }
                
                Spacer()
                
                // 实时价格与涨跌幅展示区（如果盘前盘后有效，醒目展示盘前盘后价格；否则展示常规价）
                VStack(alignment: .trailing, spacing: 2) {
                    if let prePostPrice = stock.prePostPrice, let prePostChange = stock.prePostChangePercent {
                        HStack(spacing: 4) {
                            Text(String(format: "$%.2f", prePostPrice))
                                .font(.system(size: 15, weight: .heavy, design: .monospaced))
                            Text(String(format: "%+.2f%%", prePostChange))
                                .font(.system(size: 13, weight: .heavy, design: .rounded))
                        }
                        .foregroundColor(prePostChange >= 0 ? .red : .green)
                        
                        Text(String(format: "常规收盘: $%.2f (%+.2f%%)", stock.regularPrice, stock.regularChangePercent))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundColor(.secondary)
                    } else {
                        Text(String(format: "$%.2f", stock.regularPrice))
                            .font(.system(size: 15, weight: .heavy, design: .monospaced))
                        
                        HStack(spacing: 4) {
                            Text(String(format: "%+.2f", stock.regularChange))
                            Text(String(format: "(%+.2f%%)", stock.regularChangePercent))
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(stock.regularChangePercent >= 0 ? .red : .green)
                    }
                }
            }
            
            // 底部盘前盘后详细时段状态
            if let prePostPrice = stock.prePostPrice, let prePostChange = stock.prePostChangePercent {
                Divider().opacity(0.2)
                
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: "moon.stars.fill")
                            .font(.system(size: 9))
                            .foregroundColor(.purple)
                        Text("盘前/盘后实时撮合")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(.purple)
                    }
                    
                    Text("当前报价: $\(String(format: "%.2f", prePostPrice))")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundColor(prePostChange >= 0 ? .red : .green)
                    
                    Spacer()
                    
                    Text(stock.volumeFormatted)
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.purple.opacity(0.06))
                .cornerRadius(5)
            }
        }
        .padding(10)
        .background(Color.appTertiaryBackground)
        .cornerRadius(10)
    }
    
    // MARK: - 韩国个股卡片（红涨绿跌）
    private func koreaStockRow(for stock: KoreaStockQuote) -> some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(stock.nameCn)
                        .font(.system(size: 14, weight: .bold))
                    Text(stock.nameKr)
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                    
                    Text(stock.industry)
                        .font(.system(size: 10))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(3)
                }
                
                Text(stock.symbol)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "₩%.0f", stock.currentPrice))
                    .font(.system(size: 14, weight: .bold, design: .monospaced))
                
                HStack(spacing: 4) {
                    Text(String(format: "%+.0f", stock.changeAmount))
                    Text(String(format: "(%+.2f%%)", stock.changePercent))
                }
                .font(.system(size: 11, weight: .bold))
                .foregroundColor(stock.changePercent >= 0 ? .red : .green)
            }
        }
        .padding(10)
        .background(Color.appTertiaryBackground)
        .cornerRadius(10)
    }
}
