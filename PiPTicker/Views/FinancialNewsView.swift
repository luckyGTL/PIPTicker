import SwiftUI

/// 7x24 权威全网财经快讯与自选股要闻雷达视图
public struct FinancialNewsView: View {
    @StateObject private var newsManager = FinancialNewsManager.shared
    @ObservedObject private var stockData = StockDataManager.shared
    
    // 自动抓取配置抽屉展开状态
    @State private var showSettingsPopover: Bool = false
    @State private var showingAddedStockToast: String? = nil
    
    public init() {}
    
    public var body: some View {
        ZStack {
            VStack(spacing: 0) {
                // 1. 顶部操作栏（搜索、手动刷新、自动轮询状态）
                newsTopBar
                    .padding(.horizontal, 16)
                    .padding(.top, 12)
                    .padding(.bottom, 8)
                
                // 2. 自动抓取与自选股提醒快捷配置条 (展开状态)
                if showSettingsPopover {
                    autoRefreshConfigBar
                        .padding(.horizontal, 16)
                        .padding(.bottom, 10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                // 3. 分类频道筛选胶囊栏
                categoryFilterBar
                    .padding(.bottom, 8)
                
                // 3.5 推特大V筛选胶囊栏 (当选中推特专栏时呈现)
                if newsManager.selectedCategory == .twitter {
                    twitterVFilterBar
                        .padding(.bottom, 8)
                }
                
                // 4. 媒体来源过滤栏 (财联社、新浪、华尔街、东方财富、推特/X等)
                if newsManager.selectedCategory != .twitter {
                    sourceFilterBar
                        .padding(.bottom, 10)
                }
                
                Divider()
                    .opacity(0.4)
                
                // 5. 实时快讯时间轴列表（支持触底加载更多、顶部新更新悬浮条与独立详情钻取）
                if newsManager.filteredNews.isEmpty {
                    emptyStateView
                } else {
                    newsListView
                }
            }
            .background(Color.appBackground)
        }
        .overlay(alignment: .bottom) {
            if let toast = showingAddedStockToast {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                    Text(toast)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(.white)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.black.opacity(0.85))
                .cornerRadius(20)
                .shadow(radius: 8)
                .padding(.bottom, 24)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .onAppear {
            newsManager.start()
        }
    }
    
    // MARK: - 顶部操作栏
    private var newsTopBar: some View {
        HStack(spacing: 10) {
            // 关键词搜索栏
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.secondary)
                
                TextField("搜索财经要闻、个股、英伟达、海力士、巴菲特、推特大V...", text: $newsManager.searchKeyword)
                    .font(.system(size: 13))
                
                if !newsManager.searchKeyword.isEmpty {
                    Button(action: {
                        newsManager.searchKeyword = ""
                    }) {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundColor(.secondary)
                            .font(.system(size: 13))
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(Color.appSecondaryBackground)
            .cornerRadius(8)
            
            // 自动刷新配置抽屉切换按钮
            Button(action: {
                withAnimation(.easeInOut(duration: 0.2)) {
                    showSettingsPopover.toggle()
                }
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 12, weight: .bold))
                    Text(newsManager.autoRefreshInterval < 60 ? "\(Int(newsManager.autoRefreshInterval))秒" : "\(Int(newsManager.autoRefreshInterval / 60))分")
                        .font(.system(size: 11, weight: .bold))
                }
                .foregroundColor(showSettingsPopover ? .white : .blue)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(showSettingsPopover ? Color.blue : Color.blue.opacity(0.12))
                .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            
            // 手动强制抓取按钮
            Button(action: {
                newsManager.fetchAllNewsChannels()
            }) {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .rotationEffect(.degrees(newsManager.isRefreshing ? 360 : 0))
                        .animation(newsManager.isRefreshing ? Animation.linear(duration: 1).repeatForever(autoreverses: false) : .default, value: newsManager.isRefreshing)
                    
                    Text("抓取")
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
    
    // MARK: - 自动抓取与自选股提醒快捷配置条
    private var autoRefreshConfigBar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text("抓取间隔:")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.secondary)
                
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach([10.0, 20.0, 30.0, 60.0, 180.0, 300.0], id: \.self) { interval in
                            let isSelected = newsManager.autoRefreshInterval == interval
                            let label = interval < 60 ? "\(Int(interval))秒" : "\(Int(interval / 60))分钟"
                            Button(action: {
                                newsManager.setAutoRefreshInterval(interval)
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
            
            Divider().opacity(0.3)
            
            HStack(spacing: 20) {
                // 自动抓取开关
                Toggle(isOn: $newsManager.isAutoRefreshEnabled) {
                    Text("自动实时抓取")
                        .font(.system(size: 12, weight: .semibold))
                }
                .onChange(of: newsManager.isAutoRefreshEnabled) { val in
                    newsManager.toggleAutoRefresh(enabled: val)
                }
                .toggleStyle(SwitchToggleStyle())
                
                // 自选股要闻弹窗强提醒开关（支持权限检测与跳转设置）
                Toggle(isOn: $newsManager.isWatchlistAlertEnabled) {
                    HStack(spacing: 4) {
                        Image(systemName: "bell.badge.fill")
                            .foregroundColor(.orange)
                            .font(.system(size: 12))
                        Text("自选与概念弹窗推送")
                            .font(.system(size: 12, weight: .semibold))
                    }
                }
                .onChange(of: newsManager.isWatchlistAlertEnabled) { val in
                    newsManager.toggleWatchlistAlert(enabled: val)
                }
                .toggleStyle(SwitchToggleStyle())
                
                Spacer()
                
                // 系统通知未授权时醒目跳转按钮
                if !newsManager.isSystemNotificationAuthorized {
                    Button(action: {
                        newsManager.openSystemNotificationSettings()
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 11))
                            Text("开启系统推送权限")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.yellow)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.yellow.opacity(0.18))
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
        }
        .padding(12)
        .background(Color.appSecondaryBackground)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color.orange.opacity(0.35), lineWidth: 1)
        )
    }
    
    // MARK: - 分类频道筛选栏
    private var categoryFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NewsCategory.allCases) { category in
                    let isSelected = newsManager.selectedCategory == category
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            newsManager.selectedCategory = category
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: category.iconName)
                                .font(.system(size: 11))
                            Text(category.rawValue)
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
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - 推特大V筛选栏
    private var twitterVFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Text("大V聚焦:")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(.secondary)
                    .padding(.leading, 2)
                
                ForEach(TwitterVCategory.allCases) { vCat in
                    let isSelected = newsManager.selectedTwitterVCategory == vCat
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            newsManager.selectedTwitterVCategory = vCat
                        }
                    }) {
                        Text(vCat.rawValue)
                            .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                            .foregroundColor(isSelected ? .white : .primary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(isSelected ? Color.cyan : Color.appTertiaryBackground)
                            .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - 媒体来源过滤栏
    private var sourceFilterBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(NewsSource.allCases) { source in
                    let isSelected = newsManager.selectedSource == source
                    Button(action: {
                        withAnimation(.spring(response: 0.25, dampingFraction: 0.8)) {
                            newsManager.selectedSource = source
                        }
                    }) {
                        HStack(spacing: 4) {
                            if source != .all {
                                Image(systemName: source.iconName)
                                    .font(.system(size: 10))
                            }
                            Text(source.rawValue)
                                .font(.system(size: 11, weight: isSelected ? .bold : .medium))
                        }
                        .foregroundColor(isSelected ? .white : .secondary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(isSelected ? sourceColor(for: source) : Color.appTertiaryBackground)
                        .cornerRadius(6)
                    }
                    .buttonStyle(PlainButtonStyle())
                }
            }
            .padding(.horizontal, 16)
        }
    }
    
    // MARK: - 快讯时间轴列表（支持精准滑动偏移监听、悬浮在屏幕顶部的“有N条新快讯”胶囊与右下角回顶部悬浮按钮）
    private var newsListView: some View {
        ScrollViewReader { proxy in
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(spacing: 0) {
                        // 顶部隐式锚点
                        Color.clear
                            .frame(height: 1)
                            .id("TOP_ANCHOR")
                            .onAppear {
                                newsManager.isUserViewingOlderNews = false
                            }
                            .onDisappear {
                                newsManager.isUserViewingOlderNews = true
                            }
                        
                        LazyVStack(spacing: 12) {
                            // 顶部状态小结
                            HStack {
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(Color.green)
                                        .frame(width: 7, height: 7)
                                    Text("全网 7x24 实时电报 · 已显示 \(newsManager.filteredNews.count) 条 (历史库已存 \(newsManager.allNews.count) 条)")
                                        .font(.system(size: 11, weight: .medium))
                                        .foregroundColor(.secondary)
                                }
                                
                                Spacer()
                                
                                Text("最近抓取: \(formattedUpdateTime)")
                                    .font(.system(size: 10, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 6)
                            
                            ForEach(newsManager.filteredNews, id: \.id) { item in
                                newsCardView(for: item)
                                    .id(item.id)
                                    .onAppear {
                                        // 当滚动到倒数第3条时自动触发加载更多
                                        if item.id == newsManager.filteredNews.suffix(3).first?.id {
                                            newsManager.loadMoreHistory()
                                        }
                                    }
                            }
                            
                            // 触底加载更多按钮与状态
                            Button(action: {
                                newsManager.loadMoreHistory()
                            }) {
                                HStack(spacing: 6) {
                                    if newsManager.isLoadingMore {
                                        ProgressView()
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "arrow.down.circle.fill")
                                    }
                                    Text(newsManager.isLoadingMore ? "正在加载更早历史快讯..." : (newsManager.hasMoreHistory ? "⬇️ 下滑 / 点击加载更多历史快讯" : "已加载全部近期资讯"))
                                        .font(.system(size: 12, weight: .semibold))
                                }
                                .foregroundColor(.blue)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 10)
                                .background(Color.appSecondaryBackground)
                                .cornerRadius(8)
                            }
                            .buttonStyle(PlainButtonStyle())
                            .disabled(newsManager.isLoadingMore || !newsManager.hasMoreHistory)
                            .padding(.top, 8)
                        }
                        .padding(.horizontal, 16)
                        .padding(.bottom, 24)
                        .background(
                            GeometryReader { geo in
                                Color.clear.preference(
                                    key: ScrollOffsetPreferenceKey.self,
                                    value: geo.frame(in: .named("NewsScrollCoordinateSpace")).minY
                                )
                            }
                        )
                    }
                }
                .coordinateSpace(name: "NewsScrollCoordinateSpace")
                .onPreferenceChange(ScrollOffsetPreferenceKey.self) { offset in
                    // 精准滚动偏移量防抖检测：仅在状态切换时赋值，杜绝 120FPS 持续重绘
                    if offset < -80 {
                        if !newsManager.isUserViewingOlderNews {
                            newsManager.isUserViewingOlderNews = true
                        }
                    } else if offset >= -20 {
                        if newsManager.isUserViewingOlderNews {
                            newsManager.isUserViewingOlderNews = false
                        }
                    }
                }
                
                // 🌟 顶部动态新快讯提醒胶囊：仅在后台有未加载新快讯时才提示，平时在顶部绝不遮挡！
                if !newsManager.pendingIncomingNews.isEmpty {
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            newsManager.applyPendingNews()
                            proxy.scrollTo("TOP_ANCHOR", anchor: .top)
                        }
                    }) {
                        HStack(spacing: 6) {
                            Image(systemName: "arrow.up.circle.fill")
                                .font(.system(size: 14, weight: .heavy))
                            Text("⬆️ 发现 \(newsManager.pendingIncomingNews.count) 条新快讯 · 点击立即加载并回顶部")
                                .font(.system(size: 12, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .background(
                            Capsule()
                                .fill(LinearGradient(gradient: Gradient(colors: [Color.blue, Color(red: 0.1, green: 0.5, blue: 1.0)]), startPoint: .leading, endPoint: .trailing))
                        )
                        .shadow(color: Color.blue.opacity(0.45), radius: 10, x: 0, y: 4)
                        .overlay(
                            Capsule()
                                .stroke(Color.white.opacity(0.25), lineWidth: 1)
                        )
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity).combined(with: .scale(scale: 0.9)))
                    .zIndex(100)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                // 🌟 核心 2：右下角常驻“回顶部”悬浮小火箭圆钮
                if newsManager.isUserViewingOlderNews {
                    Button(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                            newsManager.applyPendingNews()
                            proxy.scrollTo("TOP_ANCHOR", anchor: .top)
                        }
                    }) {
                        HStack(spacing: 4) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 13, weight: .heavy))
                            Text("回顶部")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Color.blue)
                        .clipShape(Capsule())
                        .shadow(color: Color.blue.opacity(0.4), radius: 8, x: 0, y: 3)
                    }
                    .buttonStyle(PlainButtonStyle())
                    .padding(.trailing, 20)
                    .padding(.bottom, 24)
                    .transition(.scale.combined(with: .opacity))
                    .zIndex(99)
                }
            }
            .onChange(of: newsManager.targetScrollNewsId) { targetId in
                if let id = targetId {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                        proxy.scrollTo(id, anchor: .top)
                    }
                    newsManager.targetScrollNewsId = nil
                }
            }
        }
    }
    
    // MARK: - 单条快讯卡片（点击卡片即可查看独立详情）
    private func newsCardView(for item: NewsItem) -> some View {
        Button(action: {
            newsManager.selectedNewsForDetail = item
        }) {
            VStack(alignment: .leading, spacing: 6) {
                // 顶部信息：推特作者或媒体来源 + 时间戳 + 重要等级徽标
                HStack(spacing: 6) {
                    if let handle = item.authorHandle, let name = item.authorName {
                        // 推特专属作者大V徽章
                        HStack(spacing: 4) {
                            Image(systemName: "bubble.left.and.bubble.right.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.cyan)
                            Text(name)
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundColor(.cyan)
                            Text(handle)
                                .font(.system(size: 10, design: .monospaced))
                                .foregroundColor(.secondary)
                            Image(systemName: "checkmark.seal.fill")
                                .font(.system(size: 9))
                                .foregroundColor(.blue)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.cyan.opacity(0.12))
                        .cornerRadius(4)
                    } else {
                        // 权威媒体来源药丸
                        HStack(spacing: 3) {
                            Image(systemName: item.source.iconName)
                                .font(.system(size: 9, weight: .bold))
                            Text(item.source.rawValue)
                                .font(.system(size: 10, weight: .bold))
                        }
                        .foregroundColor(sourceColor(for: item.source))
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(sourceColor(for: item.source).opacity(0.12))
                        .cornerRadius(4)
                    }
                    
                    // 重磅突发高亮微标
                    if item.importance == .breaking {
                        HStack(spacing: 2) {
                            Image(systemName: "flame.fill")
                                .font(.system(size: 9))
                            Text("重磅突发")
                                .font(.system(size: 10, weight: .heavy))
                        }
                        .foregroundColor(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(Color.red)
                        .cornerRadius(4)
                    }
                    
                    Spacer()
                    
                    // 相对时间与时分秒
                    Text("\(item.formattedClockTime) (\(item.timeAgoText))")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundColor(.secondary)
                }
                
                // 命中自选股票与板块概念提示横幅（支持多只自选股与 AI 研判因子展示）
                let matches = !item.matchedWatchlistStocks.isEmpty ? item.matchedWatchlistStocks : newsManager.getAllMatchedWatchlistAndConcepts(for: item, watchlist: stockData.watchlist)
                if !matches.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            ForEach(matches) { match in
                                HStack(spacing: 3) {
                                    Image(systemName: match.matchType == "自选个股" ? "star.fill" : "tag.fill")
                                        .font(.system(size: 9))
                                        .foregroundColor(match.matchType == "自选个股" ? .yellow : .cyan)
                                    Text(match.symbol.name)
                                        .font(.system(size: 11, weight: .heavy))
                                        .foregroundColor(match.matchType == "自选个股" ? .yellow : .cyan)
                                }
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background((match.matchType == "自选个股" ? Color.yellow : Color.cyan).opacity(0.18))
                                .cornerRadius(4)
                            }
                            
                            let concepts = Array(Set(matches.map { $0.conceptName })).filter { $0 != "个股直接相关" }
                            if !concepts.isEmpty {
                                let hasCoreConcept = matches.contains(where: { $0.matchType == "核心题材" })
                                HStack(spacing: 2) {
                                    Image(systemName: hasCoreConcept ? "lightbulb.fill" : "square.stack.3d.up.fill")
                                        .font(.system(size: 8))
                                        .foregroundColor(.cyan)
                                    Text("\(hasCoreConcept ? "题材" : "板块"): \(concepts.joined(separator: "/"))")
                                        .font(.system(size: 10, weight: .bold))
                                        .foregroundColor(.cyan)
                                }
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(Color.cyan.opacity(0.15))
                                .cornerRadius(4)
                            }
                            
                            Spacer()
                            
                            // 醒目的 AI 情绪与核心因子研判标签
                            if let summary = item.aiFactorSummary, !summary.isEmpty {
                                HStack(spacing: 3) {
                                    Text("AI: \(summary)")
                                        .font(.system(size: 10, weight: .heavy))
                                }
                                .foregroundColor(item.sentiment == .bullish ? .red : (item.sentiment == .bearish ? .green : .secondary))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background((item.sentiment == .bullish ? Color.red : (item.sentiment == .bearish ? Color.green : Color.gray)).opacity(0.12))
                                .cornerRadius(5)
                            } else {
                                HStack(spacing: 2) {
                                    Image(systemName: item.sentiment.iconName)
                                        .font(.system(size: 10, weight: .bold))
                                    Text("AI: \(item.sentiment.rawValue)")
                                        .font(.system(size: 11, weight: .heavy))
                                }
                                .foregroundColor(item.sentiment == .bullish ? .red : (item.sentiment == .bearish ? .green : .secondary))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 3)
                                .background(item.sentiment == .bullish ? Color.red.opacity(0.12) : (item.sentiment == .bearish ? Color.green.opacity(0.12) : Color.gray.opacity(0.12)))
                                .cornerRadius(5)
                            }
                        }
                    }
                } else {
                    HStack(spacing: 3) {
                        if let summary = item.aiFactorSummary, !summary.isEmpty {
                            Text("AI: \(summary)")
                                .font(.system(size: 10, weight: .semibold))
                        } else {
                            Image(systemName: item.sentiment.iconName)
                                .font(.system(size: 9))
                            Text("AI: \(item.sentiment.rawValue)")
                                .font(.system(size: 10, weight: .semibold))
                        }
                    }
                    .foregroundColor(item.sentiment == .bullish ? .red : (item.sentiment == .bearish ? .green : .secondary))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(item.sentiment == .bullish ? Color.red.opacity(0.1) : (item.sentiment == .bearish ? Color.green.opacity(0.1) : Color.gray.opacity(0.1)))
                    .cornerRadius(4)
                }
                
                // 标题 (若有)
                if !item.title.isEmpty {
                    Text(item.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(item.importance == .breaking ? .red : .primary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                
                // 正文内容
                Text(item.content)
                    .font(.system(size: 13))
                    .foregroundColor(.primary.opacity(0.9))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
                    .textSelection(.enabled)
                
                // 关联股票快捷标签（支持一键添加自选）
                let hasMentions = !item.relatedStockCodes.isEmpty || !item.relatedStockNames.isEmpty || !matches.isEmpty
                if hasMentions {
                    stockMentionsSection(for: item)
                        .padding(.top, 4)
                }
            }
            .padding(12)
            .background(Color.appSecondaryBackground)
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(item.importance == .breaking ? Color.red.opacity(0.4) : Color.white.opacity(0.06), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
    
    // MARK: - 关联股票快捷交互栏
    private func stockMentionsSection(for item: NewsItem) -> some View {
        var displayStocks: [(code: String, name: String)] = []
        
        // 1. 如果命中了自选股，优先把所有命中的自选股排在前面
        let matches = !item.matchedWatchlistStocks.isEmpty ? item.matchedWatchlistStocks : newsManager.getAllMatchedWatchlistAndConcepts(for: item, watchlist: stockData.watchlist)
        for match in matches {
            if !displayStocks.contains(where: { $0.code == match.symbol.code }) {
                displayStocks.append((code: match.symbol.code, name: match.symbol.name))
            }
        }
        
        // 2. 加入快讯提取出的股票代码与股票名称
        for (idx, code) in item.relatedStockCodes.enumerated() {
            let name = idx < item.relatedStockNames.count ? item.relatedStockNames[idx] : ""
            if !displayStocks.contains(where: { $0.code == code }) {
                displayStocks.append((code: code, name: name))
            }
        }
        
        // 3. 加入快讯提取出的股票名称 (通过字典反查代码)
        let nameToCodeDict: [String: String] = [
            "长飞光纤": "601869", "亨通光电": "600487", "中天科技": "600522", "烽火通信": "600498",
            "中际旭创": "300308", "新易盛": "300502", "天孚通信": "300394", "光迅科技": "002281",
            "贵州茅台": "600519", "五粮液": "000858", "宁德时代": "300750", "比亚迪": "002594",
            "赛力斯": "601127", "江淮汽车": "600418", "中芯国际": "688981", "北方华创": "002371",
            "海光信息": "688041", "寒武纪": "688256", "三花智控": "002050", "拓普集团": "601689",
            "工业富联": "601138", "浪潮信息": "000977", "中科曙光": "603019", "药明康德": "603259",
            "恒瑞医药": "600276", "中信证券": "600030", "东方财富": "300059", "同花顺": "300033",
            "万丰奥威": "002085", "中信海直": "000099", "阳光电源": "300274", "隆基绿能": "601012"
        ]
        for name in item.relatedStockNames {
            if let code = nameToCodeDict[name], !displayStocks.contains(where: { $0.code == code }) {
                displayStocks.append((code: code, name: name))
            }
        }
        
        return ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(displayStocks, id: \.code) { stk in
                    stockMentionButton(code: stk.code, fallbackName: stk.name, item: item)
                }
            }
        }
    }
    
    private func stockMentionButton(code: String, fallbackName: String, item: NewsItem) -> some View {
        let name: String
        if let matched = stockData.watchlist.first(where: { $0.code == code }) {
            name = matched.name
        } else if !fallbackName.isEmpty {
            name = fallbackName
        } else {
            name = code
        }
        
        let isAlreadyInWatchlist = stockData.watchlist.contains(where: { $0.code == code })
        
        return Button(action: {
            if !isAlreadyInWatchlist {
                let market = (code.hasPrefix("6") || code.hasPrefix("9")) ? "sh" : "sz"
                let newSymbol = StockSymbol(code: code, market: market, name: name)
                stockData.addSymbolDirectly(newSymbol)
                showToast("已将【\(name)】加入自选股")
            }
        }) {
            HStack(spacing: 4) {
                Image(systemName: isAlreadyInWatchlist ? "star.fill" : "plus.circle.fill")
                    .font(.system(size: 10))
                    .foregroundColor(isAlreadyInWatchlist ? .yellow : .blue)
                Text(code.isEmpty ? name : "\(name)(\(code))")
                    .font(.system(size: 11, weight: .medium))
                if !isAlreadyInWatchlist {
                    Text("+自选")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.blue)
                } else {
                    Text("自选")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(.yellow)
                }
            }
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(isAlreadyInWatchlist ? Color.yellow.opacity(0.16) : Color.blue.opacity(0.12))
            .cornerRadius(6)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(isAlreadyInWatchlist ? Color.yellow.opacity(0.5) : Color.blue.opacity(0.3), lineWidth: 1)
            )
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(isAlreadyInWatchlist)
    }
    
    // MARK: - 空状态视图
    private var emptyStateView: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "newspaper")
                .font(.system(size: 40))
                .foregroundColor(.secondary)
            Text("暂无匹配的财经资讯")
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(.secondary)
            Button(action: {
                newsManager.selectedCategory = .all
                newsManager.selectedSource = .all
                newsManager.selectedTwitterVCategory = .all
                newsManager.searchKeyword = ""
                newsManager.fetchAllNewsChannels()
            }) {
                Text("重置筛选并刷新")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
            .buttonStyle(PlainButtonStyle())
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.vertical, 40)
    }
    
    // MARK: - 辅助方法
    private func sourceColor(for source: NewsSource) -> Color {
        switch source {
        case .all: return .blue
        case .cailianshe: return .red
        case .wallstreet: return .blue
        case .sina: return .orange
        case .eastmoney: return .purple
        case .bloomberg: return Color(red: 0.6, green: 0.3, blue: 0.9)
        case .twitter: return Color(red: 0.1, green: 0.6, blue: 0.9)
        }
    }
    
    private var formattedUpdateTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: newsManager.lastUpdated)
    }
    
    private func showToast(_ message: String) {
        showingAddedStockToast = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation {
                if self.showingAddedStockToast == message {
                    self.showingAddedStockToast = nil
                }
            }
        }
    }
    
    /// 检测快讯是否与当前自选股或其所属板块概念匹配（直接复用全量知识库）
    private func findWatchlistMatch(for item: NewsItem) -> (name: String, concept: String)? {
        guard let match = newsManager.getMatchedWatchlistAndConcept(for: item, watchlist: stockData.watchlist) else {
            return nil
        }
        let displayName = match.matchedStock.name.isEmpty ? match.matchedStock.code : match.matchedStock.name
        return (name: displayName, concept: match.conceptName)
    }
}

// MARK: - 独立快讯详情弹窗面板 (点击推送通知或点击快讯卡片弹出)
public struct NewsDetailSheetView: View {
    public let item: NewsItem
    @Environment(\.presentationMode) var presentationMode
    @ObservedObject private var stockData = StockDataManager.shared
    @State private var isCopied: Bool = false
    
    public var body: some View {
        VStack(spacing: 0) {
            // 顶部导航栏
            HStack {
                HStack(spacing: 6) {
                    Image(systemName: "newspaper.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.blue)
                    
                    Text("资讯详情")
                        .font(.system(size: 16, weight: .heavy))
                    
                    // 来源标签
                    Text(item.source.rawValue)
                        .font(.system(size: 11, weight: .bold))
                        .foregroundColor(.blue)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 2)
                        .background(Color.blue.opacity(0.12))
                        .cornerRadius(4)
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
            
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // 1. 元信息栏（时间、重要度、AI研判）
                    HStack(spacing: 8) {
                        // 时间
                        HStack(spacing: 4) {
                            Image(systemName: "clock")
                                .font(.system(size: 11))
                            Text(item.formattedClockTime)
                                .font(.system(size: 12, design: .monospaced))
                            Text("(\(item.timeAgoText))")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        // 重要度
                        if item.importance == .breaking {
                            Text("🚨 全网重磅突发")
                                .font(.system(size: 11, weight: .heavy))
                                .foregroundColor(.white)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Color.red)
                                .cornerRadius(4)
                        }
                        
                        // AI 情绪与核心因子研判
                        if let summary = item.aiFactorSummary, !summary.isEmpty {
                            HStack(spacing: 3) {
                                Text("AI: \(summary)")
                                    .font(.system(size: 11, weight: .heavy))
                            }
                            .foregroundColor(item.sentiment == .bullish ? .red : (item.sentiment == .bearish ? .green : .secondary))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 3)
                            .background((item.sentiment == .bullish ? Color.red : (item.sentiment == .bearish ? Color.green : Color.gray)).opacity(0.12))
                            .cornerRadius(5)
                        } else {
                            HStack(spacing: 3) {
                                Image(systemName: item.sentiment.iconName)
                                    .font(.system(size: 10))
                                Text("AI研判: \(item.sentiment.rawValue)")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundColor(item.sentiment == .bullish ? .red : (item.sentiment == .bearish ? .green : .secondary))
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(item.sentiment == .bullish ? Color.red.opacity(0.12) : (item.sentiment == .bearish ? Color.green.opacity(0.12) : Color.gray.opacity(0.12)))
                            .cornerRadius(4)
                        }
                    }
                    .padding(10)
                    .background(Color.appSecondaryBackground)
                    .cornerRadius(8)
                    
                    // 2. 推特作者（若有）
                    if let handle = item.authorHandle, let name = item.authorName {
                        HStack(spacing: 8) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 24))
                                .foregroundColor(.cyan)
                            
                            VStack(alignment: .leading, spacing: 2) {
                                HStack(spacing: 4) {
                                    Text(name)
                                        .font(.system(size: 14, weight: .heavy))
                                    Image(systemName: "checkmark.seal.fill")
                                        .font(.system(size: 11))
                                        .foregroundColor(.blue)
                                }
                                Text(handle)
                                    .font(.system(size: 12, design: .monospaced))
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                        }
                        .padding(10)
                        .background(Color.cyan.opacity(0.08))
                        .cornerRadius(8)
                    }
                    
                    // 3. 标题（若有）
                    if !item.title.isEmpty {
                        Text(item.title)
                            .font(.system(size: 18, weight: .heavy))
                            .foregroundColor(item.importance == .breaking ? .red : .primary)
                            .lineSpacing(4)
                            .textSelection(.enabled)
                    }
                    
                    // 4. 正文内容（大字号舒适排版）
                    Text(item.content)
                        .font(.system(size: 15))
                        .foregroundColor(.primary.opacity(0.95))
                        .lineSpacing(6)
                        .textSelection(.enabled)
                    
                    // 5. 关联个股与自选/板块展示（支持多只自选股与东财板块）
                    let matches = !item.matchedWatchlistStocks.isEmpty ? item.matchedWatchlistStocks : FinancialNewsManager.shared.getAllMatchedWatchlistAndConcepts(for: item, watchlist: stockData.watchlist)
                    let displayDetailStocks: [(code: String, name: String)] = {
                        var list: [(code: String, name: String)] = []
                        for match in matches {
                            if !list.contains(where: { $0.code == match.symbol.code }) {
                                list.append((code: match.symbol.code, name: match.symbol.name))
                            }
                        }
                        for (idx, code) in item.relatedStockCodes.enumerated() {
                            let name = idx < item.relatedStockNames.count ? item.relatedStockNames[idx] : ""
                            if !list.contains(where: { $0.code == code }) {
                                list.append((code: code, name: name))
                            }
                        }
                        let nameToCodeDict: [String: String] = [
                            "长飞光纤": "601869", "亨通光电": "600487", "中天科技": "600522", "烽火通信": "600498",
                            "中际旭创": "300308", "新易盛": "300502", "天孚通信": "300394", "光迅科技": "002281",
                            "贵州茅台": "600519", "五粮液": "000858", "宁德时代": "300750", "比亚迪": "002594",
                            "赛力斯": "601127", "江淮汽车": "600418", "中芯国际": "688981", "北方华创": "002371",
                            "海光信息": "688041", "寒武纪": "688256", "三花智控": "002050", "拓普集团": "601689",
                            "工业富联": "601138", "浪潮信息": "000977", "中科曙光": "603019", "药明康德": "603259",
                            "恒瑞医药": "600276", "中信证券": "600030", "东方财富": "300059", "同花顺": "300033",
                            "万丰奥威": "002085", "中信海直": "000099", "阳光电源": "300274", "隆基绿能": "601012"
                        ]
                        for name in item.relatedStockNames {
                            if let code = nameToCodeDict[name], !list.contains(where: { $0.code == code }) {
                                list.append((code: code, name: name))
                            }
                        }
                        return list
                    }()
                    
                    if !displayDetailStocks.isEmpty || !matches.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            HStack {
                                Image(systemName: "star.fill")
                                    .foregroundColor(.yellow)
                                Text("关联股票与自选板块")
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundColor(.secondary)
                                Spacer()
                            }
                            
                            if !matches.isEmpty {
                                ForEach(matches) { match in
                                    HStack {
                                        HStack(spacing: 4) {
                                            Image(systemName: match.matchType == "自选个股" ? "star.fill" : "tag.fill")
                                                .font(.system(size: 10))
                                                .foregroundColor(match.matchType == "自选个股" ? .yellow : .cyan)
                                            Text("\(match.matchType): \(match.symbol.name) (\(match.symbol.code))")
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundColor(match.matchType == "自选个股" ? .yellow : .cyan)
                                        }
                                        Spacer()
                                        if match.conceptName != "个股直接相关" {
                                            HStack(spacing: 3) {
                                                Image(systemName: "square.stack.3d.up.fill")
                                                    .font(.system(size: 9))
                                                    .foregroundColor(.cyan)
                                                Text("东财板块: \(match.conceptName)")
                                                    .font(.system(size: 11, weight: .bold))
                                                    .foregroundColor(.cyan)
                                            }
                                        }
                                    }
                                    .padding(8)
                                    .background((match.matchType == "自选个股" ? Color.yellow : Color.cyan).opacity(0.12))
                                    .cornerRadius(6)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6)
                                            .stroke((match.matchType == "自选个股" ? Color.yellow : Color.cyan).opacity(0.4), lineWidth: 1)
                                    )
                                }
                            }
                            
                            ForEach(displayDetailStocks, id: \.code) { stk in
                                detailStockRow(code: stk.code, fallbackName: stk.name)
                            }
                        }
                        .padding(12)
                        .background(Color.appSecondaryBackground)
                        .cornerRadius(10)
                    }
                }
                .padding(16)
            }
            
            Divider()
            
            // 底部操作栏（复制、关闭）
            HStack(spacing: 12) {
                Button(action: {
                    #if os(macOS)
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(item.content, forType: .string)
                    #elseif canImport(UIKit)
                    UIPasteboard.general.string = item.content
                    #endif
                    isCopied = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                        isCopied = false
                    }
                }) {
                    HStack(spacing: 4) {
                        Image(systemName: isCopied ? "checkmark" : "doc.on.doc")
                        Text(isCopied ? "已复制全文" : "复制快讯内容")
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(Color.blue)
                    .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
                
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Text("关闭")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(.primary)
                        .frame(width: 80)
                        .frame(height: 38)
                        .background(Color.appSecondaryBackground)
                        .cornerRadius(8)
                }
                .buttonStyle(PlainButtonStyle())
            }
            .padding(16)
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 480)
        #endif
        .background(Color.appBackground)
    }
    
    private func detailStockRow(code: String, fallbackName: String) -> some View {
        let name: String
        if let matched = stockData.watchlist.first(where: { $0.code == code }) {
            name = matched.name
        } else if !fallbackName.isEmpty {
            name = fallbackName
        } else {
            name = code
        }
        let isAlreadyInWatchlist = stockData.watchlist.contains(where: { $0.code == code })
        let quote = stockData.quotes.values.first(where: { $0.symbol.code == code })
        
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(name)
                    .font(.system(size: 13, weight: .bold))
                Text(code)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundColor(.secondary)
            }
            
            Spacer()
            
            if let q = quote {
                Text(q.price)
                    .font(.system(size: 13, weight: .bold, design: .monospaced))
                    .foregroundColor(q.isPositive ? .red : (q.isFlat ? .secondary : .green))
                
                Text(q.priceChangePercent)
                    .font(.system(size: 12, weight: .heavy, design: .rounded))
                    .foregroundColor(q.isPositive ? .red : (q.isFlat ? .secondary : .green))
                    .frame(width: 65, alignment: .trailing)
            }
            
            Button(action: {
                if !isAlreadyInWatchlist {
                    let market = (code.hasPrefix("6") || code.hasPrefix("9")) ? "sh" : "sz"
                    let newSymbol = StockSymbol(code: code, market: market, name: name)
                    stockData.addSymbolDirectly(newSymbol)
                }
            }) {
                HStack(spacing: 2) {
                    Image(systemName: isAlreadyInWatchlist ? "checkmark" : "plus")
                        .font(.system(size: 10, weight: .bold))
                    Text(isAlreadyInWatchlist ? "已自选" : "加入自选")
                        .font(.system(size: 10, weight: .semibold))
                }
                .foregroundColor(isAlreadyInWatchlist ? .secondary : .white)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isAlreadyInWatchlist ? Color.appTertiaryBackground : Color.blue)
                .cornerRadius(6)
            }
            .buttonStyle(PlainButtonStyle())
            .disabled(isAlreadyInWatchlist)
        }
        .padding(8)
        .background(Color.appTertiaryBackground)
        .cornerRadius(6)
    }
}

// MARK: - 滚动偏移量首选项键
public struct ScrollOffsetPreferenceKey: PreferenceKey {
    public static var defaultValue: CGFloat = 0
    public static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}
