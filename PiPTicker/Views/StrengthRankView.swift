import SwiftUI

/// A股短线强度排名（主力净流入 Top20 / 涨速 Top20）
public struct StrengthRankView: View {
    @StateObject private var rankManager = StrengthRankManager.shared
    @ObservedObject private var stockData = StockDataManager.shared
    
    // 0: 净流入资金排名  1: 涨速排名
    @State private var selectedTab: Int = 0
    
    public init() {}
    
    public var body: some View {
        VStack(spacing: 0) {
            topControlBar
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 8)
            
            statusBanner
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            
            rankTabBar
                .padding(.horizontal, 16)
                .padding(.bottom, 10)
            
            Divider().opacity(0.4)
            
            rankListSection
        }
        .background(Color.appBackground)
        .onAppear {
            rankManager.start()
        }
    }
    
    // MARK: - 顶部操作栏
    
    private var topControlBar: some View {
        HStack {
            HStack(spacing: 6) {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.orange)
                
                Text("强度排名")
                    .font(.system(size: 16, weight: .heavy))
                
                Text("净流入 · 涨速 · 盘中10秒刷新")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            Button(action: {
                rankManager.fetchRankings()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees(rankManager.isRefreshing ? 360 : 0))
                        .animation(rankManager.isRefreshing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: rankManager.isRefreshing)
                    
                    Text("刷新")
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
    
    // MARK: - 盘中 / 盘后状态条
    
    private var statusBanner: some View {
        let isTrading = stockData.isMarketTradingHours
        return HStack(spacing: 8) {
            Circle()
                .fill(isTrading ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            
            Text(isTrading ? "盘中实时 · 每 10 秒自动刷新" : "\(stockData.marketStatusText) · 已停止自动刷新")
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(formattedUpdateTime)
                .font(.system(size: 11, design: .monospaced))
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.appSecondaryBackground)
        .cornerRadius(10)
    }
    
    // MARK: - Tab 切换
    
    private var rankTabBar: some View {
        HStack(spacing: 8) {
            rankTabButton(title: "净流入资金排名", index: 0)
            rankTabButton(title: "涨速排名", index: 1)
        }
        .padding(3)
        .background(Color.appSecondaryBackground)
        .cornerRadius(10)
    }
    
    private func rankTabButton(title: String, index: Int) -> some View {
        let isSelected = selectedTab == index
        return Button(action: {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedTab = index
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
    
    // MARK: - 榜单列表
    
    private var displayList: [StrengthRankItem] {
        selectedTab == 0 ? rankManager.netInflowRanks : rankManager.speedRanks
    }
    
    private var rankListSection: some View {
        ScrollView {
            VStack(spacing: 12) {
                HStack {
                    HStack(spacing: 4) {
                        Image(systemName: selectedTab == 0 ? "arrow.down.left.and.arrow.up.right" : "bolt.fill")
                            .foregroundColor(selectedTab == 0 ? .red : .orange)
                        Text(selectedTab == 0 ? "主力净流入资金前 20 强" : "全市场涨速前 20 强")
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
                        Text(selectedTab == 0 ? "正在拉取净流入资金排名..." : "正在拉取涨速排名...")
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                    }
                    .padding(.vertical, 40)
                    .frame(maxWidth: .infinity)
                } else {
                    LazyVStack(spacing: 6) {
                        ForEach(Array(displayList.enumerated()), id: \.element.id) { index, item in
                            rankRow(index: index + 1, item: item)
                        }
                    }
                }
            }
            .padding(16)
        }
    }
    
    private func rankRow(index: Int, item: StrengthRankItem) -> some View {
        let isWatchlisted = stockData.watchlist.contains(where: { $0.code == item.code })
        let changeColor: Color = item.changePercent >= 0 ? .red : .green
        let metricValue = selectedTab == 0 ? item.netInflow : item.speedPercent
        let metricColor: Color = metricValue >= 0 ? .red : .green
        
        return HStack(spacing: 10) {
            Text("\(index)")
                .font(.system(size: 11, weight: .heavy, design: .rounded))
                .foregroundColor(index <= 3 ? .white : .secondary)
                .frame(width: 22, height: 22)
                .background(index == 1 ? Color.yellow : (index == 2 ? Color.gray : (index == 3 ? Color.orange : Color.clear)))
                .clipShape(Circle())
            
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.name)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.primary)
                        .lineLimit(1)
                    
                    Text(item.code)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                    
                    Text("成交 \(item.formattedTurnover)")
                        .font(.system(size: 10))
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                
                HStack(spacing: 10) {
                    Text(String(format: "%.2f", item.currentPrice))
                        .font(.system(size: 13, weight: .semibold, design: .monospaced))
                        .foregroundColor(changeColor)
                    
                    Text(String(format: "%+.2f%%", item.changePercent))
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(changeColor)
                    
                    HStack(spacing: 3) {
                        Text(selectedTab == 0 ? "净流入" : "涨速")
                            .font(.system(size: 10, weight: .medium))
                            .foregroundColor(.secondary)
                        Text(selectedTab == 0 ? item.formattedNetInflow : item.formattedSpeed)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .foregroundColor(metricColor)
                    }
                }
            }
            
            Spacer(minLength: 6)
            
            Button(action: {
                if !isWatchlisted {
                    stockData.addSymbolDirectly(code: item.code, name: item.name, market: item.market)
                }
            }) {
                HStack(spacing: 2) {
                    Image(systemName: isWatchlisted ? "checkmark" : "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text(isWatchlisted ? "已选" : "自选")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(isWatchlisted ? .secondary : .white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(isWatchlisted ? Color.appTertiaryBackground : Color.blue)
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isWatchlisted)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(Color.appSecondaryBackground)
        .cornerRadius(8)
    }
    
    private var formattedUpdateTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: rankManager.lastUpdated) + " 更新"
    }
}
