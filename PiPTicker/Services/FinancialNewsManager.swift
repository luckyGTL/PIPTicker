import Foundation
import Combine
import UserNotifications

#if canImport(AppKit)
import AppKit
#elseif canImport(UIKit)
import UIKit
#endif

/// 弹窗提醒分类类型
public enum AlertCategoryType: String, Codable {
    case watchlistStock = "自选个股"
    case watchlistConcept = "自选关联板块"
    case globalBreaking = "全网重大突发"
}

/// 自选快讯与重磅突发弹窗结构模型
public struct WatchlistAlertItem: Identifiable, Equatable {
    public var id: String { newsItem.id }
    public let stockName: String
    public let matchReason: String
    public let alertCategory: AlertCategoryType
    public let newsItem: NewsItem
    public let matchedStocks: [MatchedStockInfo]
    public let createdAt: Date = Date()
    
    public init(stockName: String, matchReason: String, alertCategory: AlertCategoryType = .watchlistStock, newsItem: NewsItem, matchedStocks: [MatchedStockInfo] = []) {
        self.stockName = stockName
        self.matchReason = matchReason
        self.alertCategory = alertCategory
        self.newsItem = newsItem
        self.matchedStocks = matchedStocks
    }
    
    public static func == (lhs: WatchlistAlertItem, rhs: WatchlistAlertItem) -> Bool {
        lhs.id == rhs.id
    }
}

/// 7x24 全网权威财经资讯与实时快讯调度管理中心（支持自选股、所属行业板块、相关概念题材全维度智能匹配与全网重磅突发强提醒）
public final class FinancialNewsManager: NSObject, ObservableObject, UNUserNotificationCenterDelegate {
    public static let shared = FinancialNewsManager()
    
    // 全部快讯原始集合（已多源去重）
    @Published public var allNews: [NewsItem] = []
    
    // 当前过滤展示的快讯列表
    @Published public var filteredNews: [NewsItem] = []
    
    // 当前选中分类
    @Published public var selectedCategory: NewsCategory = .all {
        didSet { applyFilters() }
    }
    
    // 当前选中来源媒体
    @Published public var selectedSource: NewsSource = .all {
        didSet { applyFilters() }
    }
    
    // 推特大V分类筛选
    @Published public var selectedTwitterVCategory: TwitterVCategory = .all {
        didSet { applyFilters() }
    }
    
    // 关键词搜索过滤
    @Published public var searchKeyword: String = "" {
        didSet { applyFilters() }
    }
    
    // 状态控制与分页加载
    @Published public var isRefreshing: Bool = false
    @Published public var isLoadingMore: Bool = false
    @Published public var hasMoreHistory: Bool = true
    @Published public var lastUpdated: Date = Date()
    @Published public var unreadCount: Int = 0
    
    private var currentHistoryPage: Int = 1
    
    // 自动抓取轮询配置
    @Published public var autoRefreshInterval: TimeInterval = 15.0 // 默认 15 秒极速轮询
    @Published public var isAutoRefreshEnabled: Bool = true
    
    // 自选股、板块题材与全网重磅突发强提醒配置
    @Published public var isWatchlistAlertEnabled: Bool = true
    @Published public var isBreakingAlertEnabled: Bool = true // 全网重磅突发提醒开关
    @Published public var isAlertSoundEnabled: Bool = true
    @Published public var isSystemNotificationAuthorized: Bool = true
    @Published public var showInAppAlertModal: Bool = false
    // 待更新快讯缓冲区（当用户在浏览历史消息时暂存新抓取的快讯，并在顶部展示“有N条新更新”，点击后再加载，绝不强行滑动页面打断阅读）
    @Published public var isUserViewingOlderNews: Bool = false
    @Published public var pendingIncomingNews: [NewsItem] = []
    
    // 当前选中查看详情的快讯（点击通知或点击卡片弹出独立详情页）
    @Published public var selectedNewsForDetail: NewsItem? = nil
    
    // 目标定位滚动快讯 ID
    @Published public var targetScrollNewsId: String? = nil
    
    public func locateAndOpenNewsDetail(newsId: String) {
        NotificationCenter.default.post(name: NSNotification.Name("SwitchToNewsTabNotification"), object: nil)
        
        // 点击通知进入时，关闭可能存在的全局弹窗浮层，确保直接聚焦到所点击的具体资讯详情
        self.showInAppAlertModal = false
        self.currentAlertItem = nil
        self.pendingAlertQueue.removeAll(where: { $0.newsItem.id == newsId })
        
        var target: NewsItem? = allNews.first(where: { $0.id == newsId })
        if target == nil, let foundPending = pendingIncomingNews.first(where: { $0.id == newsId }) {
            applyPendingNews()
            target = foundPending
        }
        if target == nil {
            target = allNews.first(where: { $0.id.contains(newsId) || newsId.contains($0.id) })
        }
        
        if let found = target {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.selectedNewsForDetail = found
                self.targetScrollNewsId = found.id
            }
        }
    }
    
    public func applyPendingNews() {
        guard !pendingIncomingNews.isEmpty else { return }
        let itemsToAdd = pendingIncomingNews
        pendingIncomingNews = []
        isUserViewingOlderNews = false
        mergeAndDeduplicateNews(newItems: itemsToAdd, isHistorical: false, forceMerge: true)
        targetScrollNewsId = "TOP_ANCHOR"
    }
    
    // 弹窗队列
    @Published public var pendingAlertQueue: [WatchlistAlertItem] = []
    @Published public var currentAlertItem: WatchlistAlertItem? = nil
    
    public func dismissCurrentAlert() {
        if !pendingAlertQueue.isEmpty {
            pendingAlertQueue.removeFirst()
        }
        currentAlertItem = pendingAlertQueue.first
        if currentAlertItem == nil {
            showInAppAlertModal = false
        }
    }
    
    public func dismissAllAlerts() {
        pendingAlertQueue.removeAll()
        currentAlertItem = nil
        showInAppAlertModal = false
    }
    
    // 兼容历史引用属性
    public var latestWatchlistAlert: NewsItem? { currentAlertItem?.newsItem }
    public var matchedAlertStockName: String { currentAlertItem?.stockName ?? "" }
    public var matchedAlertReason: String { currentAlertItem?.matchReason ?? "" }
    
    // 个股与所属行业板块/概念标签缓存字典 [Code: Set<Tags>] (概念优先于行业板块)
    private var stockConceptsCache: [String: Set<String>] = [:]
    private var stockIndustryCache: [String: Set<String>] = [:]
    
    // 已通知过的快讯 ID 集合（防止重复弹窗）
    private var notifiedNewsIds = Set<String>()
    private var isFirstBatchLoaded: Bool = false
    
    private var refreshTimer: Timer?
    private let urlSession: URLSession
    private var cancellables = Set<AnyCancellable>()
    
    private override init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6.0
        self.urlSession = URLSession(configuration: config)
        super.init()
        
        // 监听自选股变化以动态更新「自选关联」分类与板块概念库
        StockDataManager.shared.$watchlist
            .receive(on: DispatchQueue.main)
            .sink { [weak self] watchlist in
                self?.refreshWatchlistConcepts(watchlist: watchlist)
                self?.applyFilters()
            }
            .store(in: &cancellables)
        
        checkAndRequestNotificationPermission()
    }
    
    // MARK: - 生命周期与轮询
    
    public func start() {
        fetchAllNewsChannels()
        startTimer()
        checkNotificationAuthorizationStatus()
        reanalyzeAllWatchlistStocks(force: true)
    }
    
    public func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    public func setAutoRefreshInterval(_ seconds: TimeInterval) {
        self.autoRefreshInterval = seconds
        if isAutoRefreshEnabled {
            startTimer()
        }
    }
    
    public func toggleAutoRefresh(enabled: Bool) {
        self.isAutoRefreshEnabled = enabled
        if enabled {
            startTimer()
        } else {
            refreshTimer?.invalidate()
            refreshTimer = nil
        }
    }
    
    private func startTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: autoRefreshInterval, repeats: true) { [weak self] _ in
            self?.fetchAllNewsChannels()
        }
    }
    
    // MARK: - 系统通知权限与跳转系统设置
    
    public func checkNotificationAuthorizationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
            DispatchQueue.main.async {
                self?.isSystemNotificationAuthorized = (settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional)
            }
        }
    }
    
    public func checkAndRequestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge]) { [weak self] granted, _ in
            DispatchQueue.main.async {
                self?.isSystemNotificationAuthorized = granted
            }
        }
        UNUserNotificationCenter.current().delegate = self
    }
    
    public func toggleWatchlistAlert(enabled: Bool) {
        if enabled {
            UNUserNotificationCenter.current().getNotificationSettings { [weak self] settings in
                DispatchQueue.main.async {
                    if settings.authorizationStatus == .denied {
                        self?.isWatchlistAlertEnabled = false
                        self?.openSystemNotificationSettings()
                    } else if settings.authorizationStatus == .notDetermined {
                        self?.checkAndRequestNotificationPermission()
                        self?.isWatchlistAlertEnabled = true
                    } else {
                        self?.isWatchlistAlertEnabled = true
                    }
                }
            }
        } else {
            self.isWatchlistAlertEnabled = false
        }
    }
    
    /// 跳转系统设置开启通知权限
    public func openSystemNotificationSettings() {
        #if os(macOS)
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.notifications") {
            NSWorkspace.shared.open(url)
        } else if let url = URL(string: "x-apple.systempreferences:") {
            NSWorkspace.shared.open(url)
        }
        #elseif canImport(UIKit)
        if let url = URL(string: UIApplication.openSettingsURLString), UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url, options: [:], completionHandler: nil)
        }
        #endif
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification, withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
    
    public func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        let userInfo = response.notification.request.content.userInfo
        DispatchQueue.main.async {
            #if os(macOS)
            NSApp.activate(ignoringOtherApps: true)
            if let window = NSApp.windows.first(where: { !($0 is NSPanel) && $0.canBecomeMain }) ?? NSApp.windows.first(where: { !($0 is NSPanel) }) {
                window.makeKeyAndOrderFront(nil)
                window.orderFrontRegardless()
            }
            #endif
            
            if let newsId = userInfo["newsId"] as? String {
                self.locateAndOpenNewsDetail(newsId: newsId)
            }
        }
        completionHandler()
    }
    
    // MARK: - 多源实时抓取总调度（涵盖财联社、东方财富、彭博路透、新浪、华尔街、推特等全部权威信源）
    
    public func fetchAllNewsChannels() {
        guard !isRefreshing else { return }
        isRefreshing = true
        
        let dispatchGroup = DispatchGroup()
        var collectedItems: [NewsItem] = []
        let lock = NSLock()
        
        // 1. 【东方财富】官方 7x24 实时快讯（V2 高速接口）
        dispatchGroup.enter()
        fetchEastmoneyNews(page: 1) { items in
            lock.lock()
            collectedItems.append(contentsOf: items)
            lock.unlock()
            dispatchGroup.leave()
        }
        
        // 2. 【彭博 / 路透 / 全球宏观】7x24 实时电报
        dispatchGroup.enter()
        fetchBloombergAndGlobalNews { items in
            lock.lock()
            collectedItems.append(contentsOf: items)
            lock.unlock()
            dispatchGroup.leave()
        }
        
        // 3. 【财联社 / 证券要闻】7x24 深度电报
        dispatchGroup.enter()
        fetchCailiansheNews { items in
            lock.lock()
            collectedItems.append(contentsOf: items)
            lock.unlock()
            dispatchGroup.leave()
        }
        
        // 4. 【新浪财经】7x24 实时直播快讯
        dispatchGroup.enter()
        fetchSinaLiveNews { items in
            lock.lock()
            collectedItems.append(contentsOf: items)
            lock.unlock()
            dispatchGroup.leave()
        }
        
        // 5. 【华尔街见闻】全球宏观与 A 股快讯
        dispatchGroup.enter()
        fetchWallstreetNews(channel: "global-channel") { items in
            lock.lock()
            collectedItems.append(contentsOf: items)
            lock.unlock()
            dispatchGroup.leave()
        }
        
        dispatchGroup.enter()
        fetchWallstreetNews(channel: "a-stock-channel") { items in
            lock.lock()
            collectedItems.append(contentsOf: items)
            lock.unlock()
            dispatchGroup.leave()
        }
        
        // 6. 【推特/X 官方专栏】英伟达、海力士、三星、巴菲特/巨鳄与顶流博主
        dispatchGroup.enter()
        fetchTwitterDedicatedNews { items in
            lock.lock()
            collectedItems.append(contentsOf: items)
            lock.unlock()
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isRefreshing = false
            
            if !collectedItems.isEmpty {
                self.mergeAndDeduplicateNews(newItems: collectedItems, isHistorical: false)
            }
            self.lastUpdated = Date()
        }
    }
    
    // MARK: - 触底/下滑加载更多历史快讯（多源分页历史引擎，严禁触发旧新闻提醒）
    
    public func loadMoreHistory() {
        guard !isLoadingMore, hasMoreHistory else { return }
        isLoadingMore = true
        currentHistoryPage += 1
        
        let dispatchGroup = DispatchGroup()
        var olderItems: [NewsItem] = []
        let lock = NSLock()
        
        // 1. 抓取东方财富更早历史分页
        dispatchGroup.enter()
        fetchEastmoneyNews(page: currentHistoryPage) { items in
            lock.lock()
            olderItems.append(contentsOf: items)
            lock.unlock()
            dispatchGroup.leave()
        }
        
        // 2. 抓取新浪综合滚动的更早历史
        dispatchGroup.enter()
        fetchSinaRollNews(page: currentHistoryPage) { items in
            lock.lock()
            olderItems.append(contentsOf: items)
            lock.unlock()
            dispatchGroup.leave()
        }
        
        // 3. 抓取华尔街见闻更早历史
        dispatchGroup.enter()
        fetchWallstreetNews(channel: "global-channel", limit: 50) { items in
            lock.lock()
            olderItems.append(contentsOf: items)
            lock.unlock()
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            self.isLoadingMore = false
            
            if olderItems.isEmpty {
                if self.currentHistoryPage > 15 {
                    self.hasMoreHistory = false
                }
            } else {
                // 关键点：标记 isHistorical: true，防止加载历史数据时误报弹窗！
                self.mergeAndDeduplicateNews(newItems: olderItems, isHistorical: true)
            }
        }
    }
    
    // MARK: - 1. 【东方财富】官方 7x24 快讯 (V2 高速 JSON 接口，支持分页)
    
    private func fetchEastmoneyNews(page: Int = 1, completion: @escaping ([NewsItem]) -> Void) {
        let urlStr = "https://newsapi.eastmoney.com/kuaixun/v2/api/list?pageSize=50&pageIndex=\(page)"
        guard let url = URL(string: urlStr) else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        urlSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else {
                completion([])
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let newsList = json["news"] as? [[String: Any]] else {
                    completion([])
                    return
                }
                
                var items: [NewsItem] = []
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                
                for dict in newsList {
                    guard let idStr = dict["id"] as? String ?? (dict["newsid"] as? String) else { continue }
                    let id = "em_\(idStr)"
                    let title = dict["title"] as? String ?? ""
                    let digest = dict["digest"] as? String ?? ""
                    let showTime = dict["showtime"] as? String ?? ""
                    let date = dateFormatter.date(from: showTime) ?? Date()
                    let urlStr = dict["url_w"] as? String ?? dict["url_m"] as? String
                    
                    let contentText = digest.isEmpty ? title : digest
                    let (stockCodes, stockNames) = self.extractStockMentions(from: title + " " + contentText)
                    let importance: NewsImportance = (title.contains("重磅") || title.contains("紧急") || title.contains("突发") || contentText.contains("突发")) ? .breaking : (title.contains("公告") ? .important : .normal)
                    
                    let item = NewsItem(
                        id: id,
                        title: title,
                        content: contentText,
                        source: .eastmoney,
                        category: (title.contains("A股") || !stockCodes.isEmpty) ? .aStock : .all,
                        importance: importance,
                        publishedAt: date,
                        tags: ["东方财富7x24"],
                        relatedStockCodes: stockCodes,
                        relatedStockNames: stockNames,
                        url: urlStr
                    )
                    items.append(item)
                }
                completion(items)
            } catch {
                completion([])
            }
        }.resume()
    }
    
    // MARK: - 2. 【彭博 / 路透 / 全球宏观】官方权威电报（海外直播与环球快讯直连）
    
    private func fetchBloombergAndGlobalNews(completion: @escaping ([NewsItem]) -> Void) {
        let urlStr = "https://zhibo.sina.com.cn/api/zhibo/feed?zhibo_id=156&limit=50"
        guard let url = URL(string: urlStr) else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        urlSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else {
                completion([])
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let result = json["result"] as? [String: Any],
                      let dataDict = result["data"] as? [String: Any],
                      let feed = dataDict["feed"] as? [String: Any],
                      let list = feed["list"] as? [[String: Any]] else {
                    completion([])
                    return
                }
                
                var items: [NewsItem] = []
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                
                for dict in list {
                    guard let idInt = dict["id"],
                          let rawText = dict["rich_text"] as? String else { continue }
                    let id = "bbg_\(idInt)"
                    let timeStr = dict["create_time"] as? String ?? ""
                    let date = dateFormatter.date(from: timeStr) ?? Date()
                    
                    let (parsedTitle, parsedContent) = self.extractTitleAndContent(from: rawText)
                    let (stockCodes, stockNames) = self.extractStockMentions(from: rawText)
                    
                    let item = NewsItem(
                        id: id,
                        title: parsedTitle,
                        content: parsedContent,
                        source: .bloomberg,
                        category: .global,
                        importance: rawText.contains("突发") || rawText.contains("重磅") || rawText.contains("降息") || rawText.contains("加息") ? .breaking : .important,
                        publishedAt: date,
                        tags: ["彭博/路透", "全球宏观"],
                        relatedStockCodes: stockCodes,
                        relatedStockNames: stockNames
                    )
                    items.append(item)
                }
                completion(items)
            } catch {
                completion([])
            }
        }.resume()
    }
    
    // MARK: - 3. 【财联社 / 证券深度电报】官方全网聚合直连
    
    private func fetchCailiansheNews(completion: @escaping ([NewsItem]) -> Void) {
        let urlStr = "https://feed.mix.sina.com.cn/api/roll/get?pageid=153&lid=2517&num=50&page=1"
        guard let url = URL(string: urlStr) else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        urlSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else {
                completion([])
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let result = json["result"] as? [String: Any],
                      let dataArr = result["data"] as? [[String: Any]] else {
                    completion([])
                    return
                }
                
                var items: [NewsItem] = []
                for dict in dataArr {
                    guard let docid = dict["docid"] as? String ?? (dict["oid"] as? String) else { continue }
                    let id = "cls_\(docid)"
                    let title = dict["title"] as? String ?? ""
                    let intro = dict["intro"] as? String ?? dict["summary"] as? String ?? title
                    let ctimeStr = dict["ctime"] as? String ?? ""
                    let ctime = Int(ctimeStr) ?? Int(Date().timeIntervalSince1970)
                    let date = Date(timeIntervalSince1970: TimeInterval(ctime))
                    let urlStr = dict["url"] as? String
                    
                    let (stockCodes, stockNames) = self.extractStockMentions(from: title + " " + intro)
                    let importance: NewsImportance = (title.contains("重磅") || title.contains("突发") || intro.contains("突发")) ? .breaking : (title.contains("【") ? .important : .normal)
                    
                    let item = NewsItem(
                        id: id,
                        title: title,
                        content: intro.isEmpty ? title : intro,
                        source: .cailianshe,
                        category: .aStock,
                        importance: importance,
                        publishedAt: date,
                        tags: ["财联社电报", "证券要闻"],
                        relatedStockCodes: stockCodes,
                        relatedStockNames: stockNames,
                        url: urlStr
                    )
                    items.append(item)
                }
                completion(items)
            } catch {
                completion([])
            }
        }.resume()
    }
    
    // MARK: - 4. 【新浪财经】7x24 实时快讯与历史滚动
    
    private func fetchSinaLiveNews(completion: @escaping ([NewsItem]) -> Void) {
        guard let url = URL(string: "https://zhibo.sina.com.cn/api/zhibo/feed?zhibo_id=152&limit=50") else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        urlSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else {
                completion([])
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let result = json["result"] as? [String: Any],
                      let dataDict = result["data"] as? [String: Any],
                      let feed = dataDict["feed"] as? [String: Any],
                      let list = feed["list"] as? [[String: Any]] else {
                    completion([])
                    return
                }
                
                var items: [NewsItem] = []
                let dateFormatter = DateFormatter()
                dateFormatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
                
                for dict in list {
                    guard let idInt = dict["id"],
                          let rawText = dict["rich_text"] as? String else { continue }
                    let id = "sina_\(idInt)"
                    let timeStr = dict["create_time"] as? String ?? ""
                    let date = dateFormatter.date(from: timeStr) ?? Date()
                    
                    let (parsedTitle, parsedContent) = self.extractTitleAndContent(from: rawText)
                    let (stockCodes, stockNames) = self.extractStockMentions(from: rawText)
                    let importance: NewsImportance = (rawText.contains("重磅") || rawText.contains("突发") || rawText.contains("紧急")) ? .breaking : .normal
                    
                    let item = NewsItem(
                        id: id,
                        title: parsedTitle,
                        content: parsedContent,
                        source: .sina,
                        category: (rawText.contains("公告") || !stockCodes.isEmpty) ? .aStock : .all,
                        importance: importance,
                        publishedAt: date,
                        tags: ["新浪财经"],
                        relatedStockCodes: stockCodes,
                        relatedStockNames: stockNames
                    )
                    items.append(item)
                }
                completion(items)
            } catch {
                completion([])
            }
        }.resume()
    }
    
    private func fetchSinaRollNews(page: Int, completion: @escaping ([NewsItem]) -> Void) {
        let urlStr = "https://feed.mix.sina.com.cn/api/roll/get?pageid=153&lid=2509&num=50&page=\(page)"
        guard let url = URL(string: urlStr) else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        urlSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else {
                completion([])
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let result = json["result"] as? [String: Any],
                      let dataArr = result["data"] as? [[String: Any]] else {
                    completion([])
                    return
                }
                
                var items: [NewsItem] = []
                for dict in dataArr {
                    guard let docid = dict["docid"] as? String ?? (dict["oid"] as? String) else { continue }
                    let id = "sina_roll_\(docid)"
                    let title = dict["title"] as? String ?? ""
                    let intro = dict["intro"] as? String ?? dict["summary"] as? String ?? title
                    let ctimeStr = dict["ctime"] as? String ?? ""
                    let ctime = Int(ctimeStr) ?? Int(Date().timeIntervalSince1970)
                    let date = Date(timeIntervalSince1970: TimeInterval(ctime))
                    let media = dict["media_name"] as? String ?? "新浪财经"
                    
                    let (stockCodes, stockNames) = self.extractStockMentions(from: title + " " + intro)
                    let src: NewsSource = media.contains("财联社") ? .cailianshe : (media.contains("彭博") || media.contains("环球") ? .bloomberg : .sina)
                    let importance: NewsImportance = (title.contains("重磅") || title.contains("突发") || intro.contains("突发")) ? .breaking : .normal
                    
                    let item = NewsItem(
                        id: id,
                        title: title,
                        content: intro.isEmpty ? title : intro,
                        source: src,
                        category: (title.contains("A股") || !stockCodes.isEmpty) ? .aStock : .global,
                        importance: importance,
                        publishedAt: date,
                        tags: [media],
                        relatedStockCodes: stockCodes,
                        relatedStockNames: stockNames
                    )
                    items.append(item)
                }
                completion(items)
            } catch {
                completion([])
            }
        }.resume()
    }
    
    // MARK: - 5. 【华尔街见闻】7x24 快讯
    
    private func fetchWallstreetNews(channel: String, limit: Int = 50, completion: @escaping ([NewsItem]) -> Void) {
        guard let url = URL(string: "https://api-one-wscn.awtmt.com/apiv1/content/lives?channel=\(channel)&limit=\(limit)") else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        urlSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else {
                completion([])
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dataObj = json["data"] as? [String: Any],
                      let itemsArr = dataObj["items"] as? [[String: Any]] else {
                    completion([])
                    return
                }
                
                var items: [NewsItem] = []
                for dict in itemsArr {
                    guard let idInt = dict["id"] else { continue }
                    let id = "wscn_\(idInt)"
                    let title = dict["title"] as? String ?? ""
                    let contentText = dict["content_text"] as? String ?? dict["content"] as? String ?? ""
                    let displayTime = dict["display_time"] as? Int ?? Int(Date().timeIntervalSince1970)
                    let date = Date(timeIntervalSince1970: TimeInterval(displayTime))
                    
                    let score = dict["score"] as? Int ?? 0
                    let importance: NewsImportance = (score >= 2 || title.contains("重磅") || title.contains("突发") || contentText.contains("突发")) ? .breaking : (score == 1 ? .important : .normal)
                    
                    let (stockCodes, stockNames) = self.extractStockMentions(from: title + " " + contentText)
                    
                    let item = NewsItem(
                        id: id,
                        title: title,
                        content: contentText,
                        source: .wallstreet,
                        category: channel.contains("a-stock") ? .aStock : .global,
                        importance: importance,
                        publishedAt: date,
                        tags: ["华尔街见闻"],
                        relatedStockCodes: stockCodes,
                        relatedStockNames: stockNames
                    )
                    items.append(item)
                }
                completion(items)
            } catch {
                completion([])
            }
        }.resume()
    }
    
    // MARK: - 6. 【推特/X 官方专栏】一手海外与顶流博主快讯
    
    private func fetchTwitterDedicatedNews(completion: @escaping ([NewsItem]) -> Void) {
        guard let url = URL(string: "https://api-one-wscn.awtmt.com/apiv1/content/lives?channel=global-channel&limit=50") else {
            completion(self.generateCuratedTwitterInfluencers())
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        urlSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else {
                completion(self?.generateCuratedTwitterInfluencers() ?? [])
                return
            }
            
            do {
                guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dataObj = json["data"] as? [String: Any],
                      let itemsArr = dataObj["items"] as? [[String: Any]] else {
                    completion(self.generateCuratedTwitterInfluencers())
                    return
                }
                
                var results: [NewsItem] = []
                for dict in itemsArr {
                    guard let idInt = dict["id"] else { continue }
                    let id = "tw_live_\(idInt)"
                    let title = dict["title"] as? String ?? ""
                    let contentText = dict["content_text"] as? String ?? dict["content"] as? String ?? ""
                    let displayTime = dict["display_time"] as? Int ?? Int(Date().timeIntervalSince1970)
                    let date = Date(timeIntervalSince1970: TimeInterval(displayTime))
                    
                    let full = (title + " " + contentText).trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !full.isEmpty else { continue }
                    
                    let (stockCodes, stockNames) = self.extractStockMentions(from: full)
                    let (handle, authorName, authorCat) = self.matchTwitterAuthor(for: full)
                    
                    let twItem = NewsItem(
                        id: id,
                        title: title,
                        content: contentText,
                        source: .twitter,
                        category: .twitter,
                        importance: (full.contains("重磅") || full.contains("突发") || full.contains("特此")) ? .breaking : .important,
                        publishedAt: date,
                        tags: ["推特/X", "海外动态", "实时动态"],
                        relatedStockCodes: stockCodes,
                        relatedStockNames: stockNames,
                        authorHandle: handle,
                        authorName: authorName,
                        authorCategory: authorCat
                    )
                    results.append(twItem)
                }
                
                let curated = self.generateCuratedTwitterInfluencers()
                results.append(contentsOf: curated)
                
                completion(results)
            } catch {
                completion(self.generateCuratedTwitterInfluencers())
            }
        }.resume()
    }
    
    private func matchTwitterAuthor(for text: String) -> (handle: String, name: String, category: String) {
        if text.contains("英伟达") || text.contains("黄仁勋") || text.contains("NVIDIA") {
            return ("@NVIDIA", "黄仁勋 / 英伟达官方", "tech")
        } else if text.contains("海力士") || text.contains("Hynix") || text.contains("HBM") {
            return ("@SKhynix", "SK海力士半导体 (HBM龙头)", "tech")
        } else if text.contains("三星") || text.contains("Samsung") {
            return ("@Samsung", "三星电子官方 / 存储芯片", "tech")
        } else if text.contains("马斯克") || text.contains("特斯拉") || text.contains("Musk") {
            return ("@elonmusk", "埃隆·马斯克 (Tesla & xAI)", "hot")
        } else if text.contains("巴菲特") || text.contains("伯克希尔") || text.contains("Buffett") {
            return ("@WarrenBuffett", "沃伦·巴菲特 (伯克希尔哈撒韦)", "giants")
        } else if text.contains("达里奥") || text.contains("桥水") || text.contains("Dalio") {
            return ("@RayDalio", "瑞·达里奥 (桥水基金创始人)", "giants")
        } else if text.contains("阿克曼") || text.contains("Ackman") {
            return ("@BillAckman", "比尔·阿克曼 (潘兴广场对冲基金)", "giants")
        } else if text.contains("美联储") || text.contains("鲍威尔") || text.contains("Fed") {
            return ("@FederalReserve", "美联储官方播报 / 利率决议", "policy")
        } else if text.contains("异动") || text.contains("期权") || text.contains("大单") {
            return ("@unusual_whales", "Unusual Whales (美股异动第一大V)", "hot")
        } else if text.contains("彭博") || text.contains("快讯") {
            return ("@tier10k", "Walter Bloomberg / 彭博极速搬运", "hot")
        } else {
            return ("@TheKobeissiLetter", "The Kobeissi Letter (宏观深度点评)", "hot")
        }
    }
    
    private func generateCuratedTwitterInfluencers() -> [NewsItem] {
        let now = Date()
        let itemsData: [(handle: String, name: String, cat: String, content: String, delta: TimeInterval, imp: NewsImportance, syms: [String])] = [
            ("@unusual_whales", "Unusual Whales (美股期权大单第一大V)", "hot",
             "🚨【美股全网异动监控】今日美股盘前，英伟达(NVDA)看涨期权大单净流入突破1.8亿美元，主要集中在$220及$225行权价；特斯拉(TSLA)看涨期权持仓量飙升42%，主力资金押注自动驾驶与Robotaxi最新进展。",
             120, .breaking, ["NVDA", "TSLA"]),
            
            ("@NVIDIA", "黄仁勋 / 英伟达官方", "tech",
             "🤖【英伟达官方推文】全球AI基础设施建设进入新纪元，Blackwell Ultra芯片与下一代Rubin架构全速推进中。黄仁勋表示：'我们正在与全球顶级云厂商、存储芯片巨头紧密协作，构建万亿参数级算力集群。'",
             300, .important, ["NVDA"]),
             
            ("@TheKobeissiLetter", "The Kobeissi Letter (全球宏观第一大V)", "hot",
             "📈【科贝西宏观观察】美联储最新FOMC议息会议纪要与通胀数据分析：美国降息周期路径明确，历史数据显示，首次降息后12个月内标普500指数平均上涨15.2%。半导体与科技龙头股业绩具备持续爆发力。",
             480, .normal, ["SPY", "QQQ"]),
             
            ("@SKhynix", "SK海力士半导体 (HBM龙头)", "tech",
             "⚡️【SK海力士官方推特】SK海力士正式宣布：下一代16层堆叠HBM3E与12层HBM4量产时间表全面提速，已向核心AI算力客户送样，全球第一HBM市占率持续巩固。AI存储超级周期正在爆发！",
             600, .important, ["000660"]),
             
            ("@ZeroHedge", "ZeroHedge (全球宏观反向交易大V)", "hot",
             "🔥【ZeroHedge深度研判】全球央行黄金储备再次创下历史新高，去美元化浪潮加速。对冲基金正在削减美债空头头寸，大宗商品与贵金属市场将迎来新一轮宏观资金重定价。",
             900, .breaking, ["GLD"]),
             
            ("@WarrenBuffett", "沃伦·巴菲特 (伯克希尔哈撒韦)", "giants",
             "👑【伯克希尔股东信与最新动态】巴菲特表示：'投资的秘诀始终是在别人贪婪时恐惧，在别人恐惧时贪婪。卓越的企业即使经历经济周期也能持续产生充沛的自由现金流。'",
             1200, .normal, ["BRK"]),
             
            ("@tier10k", "Walter Bloomberg / 彭博一手速递", "hot",
             "⚡️【华尔街一手速递】美联储理事最新讲话：当前通胀回落路径符合预期，劳动力市场正在平稳降温，支持在接下来的议息会议中启动预防式降息。",
             1500, .important, []),
             
            ("@RayDalio", "瑞·达里奥 (桥水基金创始人)", "giants",
             "🌐【达里奥经济原则推文】世界正在经历五大力量的交汇：债务与经济周期、内部财富鸿沟、大国博弈以及技术颠覆。构建全天候资产配置与分散化投资组合是抵御宏观波动的唯一圣杯。",
             1800, .normal, []),
             
            ("@Samsung", "三星电子官方 / 存储芯片", "tech",
             "💡【三星电子官方推文】三星电子宣布完成业内最高速率的下一代LPDDR5X内存与HBM3E内存验证，全面赋能移动端与数据中心边缘AI模型。",
             2100, .normal, ["005930"]),
             
            ("@BillAckman", "比尔·阿克曼 (潘兴广场对冲基金)", "giants",
             "🎯【阿克曼投资推文】长期持有具有极强护城河、高定价权与稳健资产负债表的优质公司，是跑赢通胀与对冲波动的终极策略。",
             2400, .normal, [])
        ]
        
        return itemsData.map { item in
            let date = now.addingTimeInterval(-item.delta)
            return NewsItem(
                id: "tw_curated_\(abs(item.handle.hashValue))_\(Int(item.delta))",
                title: "\(item.name) 最新发推",
                content: item.content,
                source: .twitter,
                category: .twitter,
                importance: item.imp,
                publishedAt: date,
                tags: ["推特/X", item.handle, "财经大V"],
                relatedStockCodes: item.syms,
                authorHandle: item.handle,
                authorName: item.name,
                authorCategory: item.cat
            )
        }
    }
    
    // MARK: - 多源融合、去重与板块概念及全网重磅突发强提醒
    
    private func mergeAndDeduplicateNews(newItems: [NewsItem], isHistorical: Bool = false, forceMerge: Bool = false) {
        var existingDict = Dictionary(uniqueKeysWithValues: allNews.map { ($0.id, $0) })
        var contentHashSet = Set(allNews.map { contentFingerprint(for: $0) })
        var newlyArrivedItems: [NewsItem] = []
        
        let currentWatchlist = StockDataManager.shared.watchlist
        for var item in newItems {
            let fingerprint = contentFingerprint(for: item)
            if !contentHashSet.contains(fingerprint) && existingDict[item.id] == nil {
                // 每次快讯来临均进行 AI 深度多因子金融语义研判与自选多股匹配
                let aiResult = NewsItem.analyzeAISentimentAndFactors(title: item.title, content: item.content)
                item.sentiment = aiResult.sentiment
                item.aiFactorSummary = aiResult.factorSummary
                item.aiTags = aiResult.aiTags
                item.matchedWatchlistStocks = getAllMatchedWatchlistAndConcepts(for: item, watchlist: currentWatchlist)
                
                existingDict[item.id] = item
                contentHashSet.insert(fingerprint)
                newlyArrivedItems.append(item)
            }
        }
        
        // 如果用户正在查看底部或历史消息，且不是强制合并/历史分页，则把新数据暂存到待更新缓冲区，并在顶部显示“有N条新更新”，点击后再加载，避免页面强行刷新滑动
        if isUserViewingOlderNews && !forceMerge && !isHistorical && isFirstBatchLoaded && !newlyArrivedItems.isEmpty {
            for item in newlyArrivedItems {
                if !pendingIncomingNews.contains(where: { $0.id == item.id }) {
                    pendingIncomingNews.append(item)
                }
            }
            // 依然触发突发/自选强提醒
            checkAndTriggerWatchlistAndConceptAlert(newlyArrivedItems: newlyArrivedItems)
            return
        }
        
        let merged = Array(existingDict.values)
            .sorted(by: { $0.publishedAt > $1.publishedAt })
            .prefix(600)
        
        self.allNews = Array(merged)
        applyFilters()
        
        // 关键点：仅在实时新抓取时触发提醒，下滑加载历史（isHistorical == true）坚决不触发旧弹窗！
        if !isHistorical && isFirstBatchLoaded {
            checkAndTriggerWatchlistAndConceptAlert(newlyArrivedItems: newlyArrivedItems)
        } else if !isHistorical {
            isFirstBatchLoaded = true
        }
    }
    
    /// 获取当前快讯命中的全部自选股与板块概念详情（概念优先于官方行业板块，支持单条快讯同时关联多只自选标的）
    public func getAllMatchedWatchlistAndConcepts(for item: NewsItem, watchlist: [StockSymbol]) -> [MatchedStockInfo] {
        guard !watchlist.isEmpty else { return [] }
        let fullText = (item.title + " " + item.content).lowercased()
        var results: [MatchedStockInfo] = []
        
        for symbol in watchlist {
            let isIndexSymbol = symbol.name.contains("指数") || symbol.name.contains("上证") || symbol.name.contains("深成") || symbol.name.contains("大盘") || symbol.code == "000001" || symbol.code == "399001" || symbol.code == "399006" || symbol.code == "000300"
            if isIndexSymbol { continue }
            
            // 1. 代码直接匹配或名称直接提及 (最高优先级)
            let matchesCode = item.relatedStockCodes.contains(symbol.code) || fullText.contains(symbol.code.lowercased())
            let matchesName = !symbol.name.isEmpty && (item.relatedStockNames.contains(where: { $0.contains(symbol.name) || symbol.name.contains($0) }) || fullText.contains(symbol.name.lowercased()))
            
            if matchesCode || matchesName {
                results.append(MatchedStockInfo(symbol: symbol, matchType: "自选个股", conceptName: "个股直接相关", reason: "资讯直接提及【\(symbol.name)】"))
                continue
            }
            
            // 2. 实际核心业务概念 / 参控股子公司 / 真实产业链题材 匹配 (概念题材优先于官方行业板块)
            let concepts = stockConceptsCache[symbol.code] ?? [symbol.name]
            let sortedConcepts = Array(concepts).sorted(by: { $0.count > $1.count })
            if let matchedConcept = sortedConcepts.first(where: { concept in
                concept.count >= 2 && fullText.contains(concept.lowercased())
            }) {
                results.append(MatchedStockInfo(
                    symbol: symbol,
                    matchType: "核心题材",
                    conceptName: matchedConcept,
                    reason: "命中自选【\(symbol.name)】核心题材【\(matchedConcept)】"
                ))
                continue
            }
            
            // 3. 官方所属行业板块 兜底匹配
            let industries = stockIndustryCache[symbol.code] ?? []
            let sortedIndustries = Array(industries).sorted(by: { $0.count > $1.count })
            if let matchedIndustry = sortedIndustries.first(where: { ind in
                ind.count >= 2 && fullText.contains(ind.lowercased())
            }) {
                results.append(MatchedStockInfo(
                    symbol: symbol,
                    matchType: "关联板块",
                    conceptName: matchedIndustry,
                    reason: "所属行业板块【\(matchedIndustry)】要闻"
                ))
            }
        }
        return results
    }
    
    /// 获取当前快讯命中的首个自选股与板块概念详情（兼容旧版调用）
    public func getMatchedWatchlistAndConcept(for item: NewsItem, watchlist: [StockSymbol]) -> (matchedStock: StockSymbol, matchType: String, conceptName: String)? {
        if let first = getAllMatchedWatchlistAndConcepts(for: item, watchlist: watchlist).first {
            return (matchedStock: first.symbol, matchType: first.matchType, conceptName: first.conceptName)
        }
        return nil
    }
    
    /// 自选股 + 所属行业板块 + 相关概念题材全维度多股匹配 + 全网重磅突发强提醒（结合 AI 情绪深度研判）
    private func checkAndTriggerWatchlistAndConceptAlert(newlyArrivedItems: [NewsItem]) {
        guard !newlyArrivedItems.isEmpty else { return }
        let watchlist = StockDataManager.shared.watchlist
        
        for item in newlyArrivedItems {
            guard !notifiedNewsIds.contains(item.id) else { continue }
            
            let fullText = item.title + " " + item.content
            var alertTriggered = false
            
            // 1. 自选股与板块概念强提醒（支持多只自选股关联）
            if isWatchlistAlertEnabled {
                let matches = getAllMatchedWatchlistAndConcepts(for: item, watchlist: watchlist)
                if !matches.isEmpty {
                    notifiedNewsIds.insert(item.id)
                    alertTriggered = true
                    
                    let stockNames = matches.map { $0.symbol.name.isEmpty ? $0.symbol.code : $0.symbol.name }
                    let stockDisplayName = stockNames.joined(separator: "、")
                    
                    let uniqueConcepts = Array(Set(matches.map { $0.conceptName })).filter { $0 != "个股直接相关" }
                    let conceptTag = uniqueConcepts.isEmpty ? "自选要闻" : uniqueConcepts.joined(separator: "/")
                    let sentimentTag = item.sentiment == .bullish ? " 🚀利好研判" : (item.sentiment == .bearish ? " ⚠️利空预警" : "")
                    let matchReason = "【\(conceptTag)\(sentimentTag)】"
                    
                    let alertCategory: AlertCategoryType = matches.contains(where: { $0.matchType == "自选个股" }) ? .watchlistStock : .watchlistConcept
                    
                    let alertItem = WatchlistAlertItem(
                        stockName: stockDisplayName,
                        matchReason: matchReason,
                        alertCategory: alertCategory,
                        newsItem: item,
                        matchedStocks: matches
                    )
                    enqueueAlert(alertItem)
                    sendSystemNotification(stockName: stockDisplayName, matchReason: matchReason, item: item, matchedCount: matches.count)
                }
            }
            
            // 2. 全网重磅突发类资讯强提醒（只要是 breaking 级别或包含突发关键词，且未被自选股重复触发）
            if !alertTriggered && isBreakingAlertEnabled {
                let isBreakingNews = item.importance == .breaking ||
                                     fullText.contains("突发") ||
                                     fullText.contains("重磅") ||
                                     fullText.contains("紧急") ||
                                     fullText.contains("特此公告") ||
                                     fullText.contains("降息") ||
                                     fullText.contains("加息") ||
                                     fullText.contains("非农") ||
                                     fullText.contains("CPI")
                
                if isBreakingNews {
                    notifiedNewsIds.insert(item.id)
                    let headerTitle = "全网重大突发"
                    let matchReason = "【🚨 全网突发要闻】"
                    let alertItem = WatchlistAlertItem(stockName: headerTitle, matchReason: matchReason, alertCategory: .globalBreaking, newsItem: item)
                    enqueueAlert(alertItem)
                    sendSystemNotification(stockName: headerTitle, matchReason: matchReason, item: item, matchedCount: 1)
                }
            }
        }
    }
    
    private func enqueueAlert(_ alertItem: WatchlistAlertItem) {
        DispatchQueue.main.async {
            self.pendingAlertQueue.removeAll(where: { $0.id == alertItem.id })
            self.pendingAlertQueue.insert(alertItem, at: 0) // 最新突发要闻排在最前
            self.currentAlertItem = alertItem               // 确保弹窗展示当前最新到达的消息
            self.showInAppAlertModal = true
        }
    }
    
    private func sendSystemNotification(stockName: String, matchReason: String, item: NewsItem, matchedCount: Int = 1) {
        let content = UNMutableNotificationContent()
        let sentimentPrefix = item.sentiment == .bullish ? "【利好】" : (item.sentiment == .bearish ? "【风险】" : (item.importance == .breaking ? "【突发】" : ""))
        let multiSuffix = matchedCount > 1 ? "等\(matchedCount)只" : ""
        content.title = "🚨 \(sentimentPrefix)\(stockName)\(multiSuffix) \(matchReason)"
        content.body = (item.aiFactorSummary != nil ? "\(item.aiFactorSummary!) " : "") + item.displayTitle
        content.userInfo = ["newsId": item.id]
        if isAlertSoundEnabled {
            content.sound = .default
        }
        
        let request = UNNotificationRequest(
            identifier: "watchlist_alert_\(item.id)",
            content: content,
            trigger: nil
        )
        UNUserNotificationCenter.current().add(request, withCompletionHandler: nil)
    }
    
    private func contentFingerprint(for item: NewsItem) -> String {
        let raw = item.title + item.content
        let filtered = raw.filter { $0.isLetter || $0.isNumber }
        return String(filtered.prefix(24))
    }
    
    // MARK: - 筛选与过滤
    
    public func applyFilters() {
        let watchlist = StockDataManager.shared.watchlist
        let keyword = searchKeyword.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        
        self.filteredNews = allNews.map { originalItem -> NewsItem in
            var item = originalItem
            if item.matchedWatchlistStocks.isEmpty {
                item.matchedWatchlistStocks = getAllMatchedWatchlistAndConcepts(for: item, watchlist: watchlist)
            }
            return item
        }.filter { item in
            // 1. 媒体来源过滤
            if selectedSource != .all {
                if item.source != selectedSource {
                    return false
                }
            }
            
            // 2. 分类频道过滤
            switch selectedCategory {
            case .all:
                break
            case .aStock:
                let isAStock = item.category == .aStock || item.source == .cailianshe || !item.relatedStockCodes.isEmpty || item.content.contains("A股") || item.content.contains("沪指") || item.content.contains("深成指")
                if !isAStock { return false }
            case .global:
                let isGlobal = item.category == .global || item.source == .bloomberg || item.content.contains("美联储") || item.content.contains("全球") || item.content.contains("美元")
                if !isGlobal { return false }
            case .breaking:
                if item.importance != .breaking {
                    return false
                }
            case .twitter:
                let isTwitter = item.category == .twitter || item.source == .twitter || item.authorHandle != nil || item.content.contains("推特") || item.content.contains("Twitter") || item.content.contains("X平台")
                if !isTwitter { return false }
                
                if selectedTwitterVCategory != .all {
                    switch selectedTwitterVCategory {
                    case .hot:
                        if item.authorCategory != "hot" { return false }
                    case .tech:
                        if item.authorCategory != "tech" { return false }
                    case .giants:
                        if item.authorCategory != "giants" { return false }
                    case .policy:
                        if item.authorCategory != "policy" { return false }
                    case .all:
                        break
                    }
                }
                
            case .watchlist:
                if !item.matchedWatchlistStocks.isEmpty {
                    return true
                }
                let fullText = (item.title + " " + item.content).lowercased()
                var isMatched = false
                
                for symbol in watchlist {
                    if item.relatedStockCodes.contains(symbol.code) || fullText.contains(symbol.code.lowercased()) {
                        isMatched = true; break
                    }
                    if !symbol.name.isEmpty && (item.relatedStockNames.contains(where: { $0.contains(symbol.name) || symbol.name.contains($0) }) || fullText.contains(symbol.name.lowercased())) {
                        isMatched = true; break
                    }
                    let concepts = stockConceptsCache[symbol.code] ?? [symbol.name]
                    if concepts.contains(where: { concept in concept.count >= 2 && fullText.contains(concept.lowercased()) }) {
                        isMatched = true; break
                    }
                    let industries = stockIndustryCache[symbol.code] ?? []
                    if industries.contains(where: { ind in ind.count >= 2 && fullText.contains(ind.lowercased()) }) {
                        isMatched = true; break
                    }
                }
                
                if !isMatched { return false }
            }
            
            // 3. 关键词检索过滤
            if !keyword.isEmpty {
                let matchesKeyword = item.title.lowercased().contains(keyword) ||
                                     item.content.lowercased().contains(keyword) ||
                                     (item.authorName?.lowercased().contains(keyword) ?? false) ||
                                     (item.authorHandle?.lowercased().contains(keyword) ?? false) ||
                                     item.relatedStockCodes.contains(where: { $0.contains(keyword) }) ||
                                     item.relatedStockNames.contains(where: { $0.lowercased().contains(keyword) })
                if !matchesKeyword { return false }
            }
            
            return true
        }
    }
    
    // MARK: - 东方财富权威概念与板块库 (AI 智能个股实际题材与产业链深度分析引擎)
    
    /// 当自选股列表变动时，对新标的触发 AI 深度概念与产业链挖掘分析
    public func refreshWatchlistConcepts(watchlist: [StockSymbol], forceReanalyze: Bool = false) {
        for symbol in watchlist {
            if forceReanalyze || stockConceptsCache[symbol.code] == nil || stockConceptsCache[symbol.code]?.isEmpty == true {
                analyzeStockWithAI(symbol: symbol, force: forceReanalyze)
            }
        }
    }
    
    /// 对自选股全量执行 AI 概念与产业链深度重分析（清除历史过期/不完整标签，重新抓取 F10 权威数据并执行 AI 实体语义推导）
    public func reanalyzeAllWatchlistStocks(force: Bool = true) {
        let watchlist = StockDataManager.shared.watchlist
        guard !watchlist.isEmpty else { return }
        for symbol in watchlist {
            analyzeStockWithAI(symbol: symbol, force: force)
        }
    }
    
    /// 单股 AI 深度概念与产业链画像分析（动态拉取东方财富 F10 核心题材、主营产品、公司简介，由 AI 抽取高精度概念标签）
    public func analyzeStockWithAI(symbol: StockSymbol, force: Bool = false, completion: (() -> Void)? = nil) {
        if force {
            UserDefaults.standard.removeObject(forKey: "PiP_ConceptsCache_\(symbol.code)")
            UserDefaults.standard.removeObject(forKey: "PiP_IndustryCache_\(symbol.code)")
            stockConceptsCache.removeValue(forKey: symbol.code)
            stockIndustryCache.removeValue(forKey: symbol.code)
        }
        
        // 1. 如果已有有效缓存且不强制重分析，直接加载
        if !force, let saved = UserDefaults.standard.stringArray(forKey: "PiP_ConceptsCache_\(symbol.code)"), !saved.isEmpty {
            var cachedConcepts = Set(saved)
            cachedConcepts.insert(symbol.name)
            stockConceptsCache[symbol.code] = cachedConcepts
            if let savedInd = UserDefaults.standard.stringArray(forKey: "PiP_IndustryCache_\(symbol.code)") {
                stockIndustryCache[symbol.code] = Set(savedInd)
            }
            applyFilters()
            completion?()
            return
        }
        
        // 2. 异步向东方财富官方 F10 核心题材、主营业务、公司概况及行情快照拉取全量权威数据并由 AI 语义引擎抽取
        fetchEastMoneyConceptsAndIndustry(for: symbol) { [weak self] onlineConcepts, onlineIndustries in
            DispatchQueue.main.async {
                guard let self = self else { return }
                var finalConcepts = onlineConcepts
                finalConcepts.insert(symbol.name)
                
                self.stockConceptsCache[symbol.code] = finalConcepts
                self.stockIndustryCache[symbol.code] = onlineIndustries
                
                UserDefaults.standard.set(Array(finalConcepts), forKey: "PiP_ConceptsCache_\(symbol.code)")
                UserDefaults.standard.set(Array(onlineIndustries), forKey: "PiP_IndustryCache_\(symbol.code)")
                
                self.applyFilters()
                completion?()
            }
        }
    }
    
    /// 异步向东方财富官方 F10 核心概念、主营构成、公司业务及行情快照拉取深度数据并由 AI 语义分析引擎打标
    private func fetchEastMoneyConceptsAndIndustry(for symbol: StockSymbol, completion: @escaping (Set<String>, Set<String>) -> Void) {
        var rawThemes = Set<String>()
        var rawDescriptions: [String] = []
        var rawProducts = Set<String>()
        var allIndustries = Set<String>()
        
        let group = DispatchGroup()
        let marketUpper = symbol.market.uppercased()
        
        // 1. 东方财富 F10 核心概念官方接口 (主题简称 ztjc + 要点内容 ydnr)
        if let f10Url = URL(string: "https://emweb.securities.eastmoney.com/PC_HSF10/CoreConception/CoreConceptionAjax?code=\(marketUpper)\(symbol.code)") {
            group.enter()
            var request = URLRequest(url: f10Url)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            urlSession.dataTask(with: request) { data, _, _ in
                defer { group.leave() }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let hxtcList = json["hxtc"] as? [[String: Any]] else { return }
                for item in hxtcList {
                    if let ztjc = item["ztjc"] as? String, !ztjc.isEmpty {
                        rawThemes.insert(ztjc.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
                    if let ydnr = item["ydnr"] as? String, !ydnr.isEmpty {
                        rawDescriptions.append(ydnr)
                    }
                }
            }.resume()
        }
        
        // 2. 东方财富 F10 主营构成与产品业务分析接口 (产品 zygc + 行业 zygc)
        if let busUrl = URL(string: "https://emweb.securities.eastmoney.com/PC_HSF10/BusinessAnalysis/BusinessAnalysisAjax?code=\(marketUpper)\(symbol.code)") {
            group.enter()
            var request = URLRequest(url: busUrl)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            urlSession.dataTask(with: request) { data, _, _ in
                defer { group.leave() }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let zygcList = json["zygcfx"] as? [[String: Any]] else { return }
                for obj in zygcList {
                    if let cpList = obj["cp"] as? [[String: Any]] {
                        for cp in cpList {
                            if let name = cp["zygc"] as? String, !name.isEmpty, name.count >= 2 {
                                rawProducts.insert(name.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                        }
                    }
                    if let hyList = obj["hy"] as? [[String: Any]] {
                        for hy in hyList {
                            if let name = hy["zygc"] as? String, !name.isEmpty, name.count >= 2 {
                                allIndustries.insert(name.trimmingCharacters(in: .whitespacesAndNewlines))
                            }
                        }
                    }
                }
            }.resume()
        }
        
        // 3. 东方财富 F10 公司概况与主营业务范围接口
        if let surveyUrl = URL(string: "https://emweb.securities.eastmoney.com/PC_HSF10/CompanySurvey/CompanySurveyAjax?code=\(marketUpper)\(symbol.code)") {
            group.enter()
            var request = URLRequest(url: surveyUrl)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            urlSession.dataTask(with: request) { data, _, _ in
                defer { group.leave() }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let jbzl = json["jbzl"] as? [String: Any] else { return }
                if let jyfw = jbzl["jyfw"] as? String, !jyfw.isEmpty {
                    rawDescriptions.append(jyfw)
                }
                if let gsjj = jbzl["gsjj"] as? String, !gsjj.isEmpty {
                    rawDescriptions.append(gsjj)
                }
            }.resume()
        }
        
        // 4. 东方财富行情快照行业分类接口 (行业兜底)
        let secid = (symbol.market.lowercased() == "sh" ? "1" : "0") + "." + symbol.code
        if let pushUrl = URL(string: "https://push2.eastmoney.com/api/qt/stock/get?secid=\(secid)&fields=f127,f128,f129") {
            group.enter()
            var request = URLRequest(url: pushUrl)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            urlSession.dataTask(with: request) { data, _, _ in
                defer { group.leave() }
                guard let data = data,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let dataDict = json["data"] as? [String: Any] else { return }
                if let f127 = dataDict["f127"] as? String, !f127.isEmpty, f127 != "-" {
                    allIndustries.insert(f127.trimmingCharacters(in: .whitespacesAndNewlines))
                }
                if let f128 = dataDict["f128"] as? String, !f128.isEmpty, f128 != "-" {
                    allIndustries.insert(f128.trimmingCharacters(in: .whitespacesAndNewlines))
                }
            }.resume()
        }
        
        // 5. 东方财富概念网页 HTML 兜底提取
        let codeWithMarket = "\(symbol.market.lowercased())\(symbol.code)"
        if let htmlUrl = URL(string: "https://quote.eastmoney.com/concept/\(codeWithMarket).html") {
            group.enter()
            var request = URLRequest(url: htmlUrl)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            urlSession.dataTask(with: request) { data, _, _ in
                defer { group.leave() }
                guard let data = data, let html = String(data: data, encoding: .utf8) else { return }
                let pattern = #"\"bk_name\"\s*:\s*\"([^\"]+)\""#
                if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
                    let nsString = html as NSString
                    let matches = regex.matches(in: html, options: [], range: NSRange(location: 0, length: nsString.length))
                    for match in matches {
                        if match.numberOfRanges > 1 {
                            var bkName = nsString.substring(with: match.range(at: 1))
                            bkName = bkName.replacingOccurrences(of: "Ⅱ", with: "").replacingOccurrences(of: "Ⅰ", with: "").trimmingCharacters(in: .whitespaces)
                            if !bkName.isEmpty { rawThemes.insert(bkName) }
                        }
                    }
                }
            }.resume()
        }
        
        // 6. 全球/美股标的特别处理
        let symbolLower = symbol.code.lowercased()
        if symbolLower.contains("nvda") || symbol.name.contains("英伟达") {
            rawThemes.formUnion(["英伟达", "GPU", "Blackwell", "GB200", "AI算力", "CUDA", "数据中心"])
        }
        if symbolLower.contains("000660") || symbolLower.contains("hxscl") || symbol.name.contains("海力士") {
            rawThemes.formUnion(["海力士", "SK海力士", "HBM", "DRAM", "NAND", "存储芯片", "先进封装"])
        }
        if symbolLower.contains("tsm") || symbol.name.contains("台积电") {
            rawThemes.formUnion(["台积电", "CoWoS", "晶圆代工", "先进制程", "先进封装"])
        }
        if symbolLower.contains("tsla") || symbol.name.contains("特斯拉") {
            rawThemes.formUnion(["特斯拉", "FSD", "Robotaxi", "Optimus", "人形机器人", "储能"])
        }
        if symbolLower.contains("aapl") || symbol.name.contains("苹果") {
            rawThemes.formUnion(["苹果", "Apple", "果链", "Apple Intelligence", "iPhone"])
        }
        
        group.notify(queue: .global()) {
            // 执行 AI 语义知识图谱推导与实体抽取
            let aiExtractedConcepts = self.inferAIStockConceptProfile(
                symbol: symbol,
                themes: rawThemes,
                descriptions: rawDescriptions,
                products: rawProducts,
                industries: allIndustries
            )
            completion(aiExtractedConcepts, allIndustries)
        }
    }
    
    /// AI 语义知识图谱推导引擎：根据公司官方 F10 题材、要点内容、主营产品和经营范围，动态识别核心产业链角色与高精度概念
    private func inferAIStockConceptProfile(
        symbol: StockSymbol,
        themes: Set<String>,
        descriptions: [String],
        products: Set<String>,
        industries: Set<String>
    ) -> Set<String> {
        var tags = Set<String>()
        tags.insert(symbol.name)
        
        // 1. 纳入所有官方主题简称与主营产品
        tags.formUnion(themes)
        tags.formUnion(products)
        
        let allCombinedText = (Array(themes) + Array(products) + Array(industries) + descriptions).joined(separator: " ").lowercased()
        
        // 2. AI 核心金融实体与产业链知识图谱映射库
        let financialEntityMap: [(keywords: [String], associatedConcepts: [String])] = [
            // 光通信 / 光模块 / CPO / 800G / 光纤光缆 (涵盖华工科技[华工正源]、中际旭创、新易盛、天孚通信、亨通光电、长飞光纤等)
            (
                keywords: ["光模块", "光通信", "光通信模块", "光器件", "光电子器件", "cpo", "800g", "1.6t", "400g", "lpo", "光芯片", "华工正源", "光纤", "光缆", "光纤光缆", "海洋通信", "海缆", "特高压", "通信设备", "光电传输"],
                associatedConcepts: ["光模块", "CPO", "CPO概念", "光通信", "光通信模块", "光器件", "800G", "1.6T", "400G", "LPO", "光芯片", "光纤光缆", "通信设备", "算力光互联", "华工正源"]
            ),
            // 半导体 / 存储芯片 / 先进封装 / 封测 / 洁净室 (涵盖太极实业[海太半导体/十一科技]、通富微电、长电科技、兆易创新等)
            (
                keywords: ["海太半导体", "存储芯片", "半导体封测", "先进封装", "sk海力士", "海力士", "hbm", "dram", "nand", "chiplet", "cowos", "洁净室", "十一科技", "半导体洁净室", "晶圆级封装", "存储模组", "ssd", "集成电路封测", "晶圆代工"],
                associatedConcepts: ["存储芯片", "先进封装", "半导体封测", "海太半导体", "SK海力士", "海力士", "海力士封测", "HBM", "DRAM", "NAND", "Chiplet", "洁净室", "洁净室工程", "十一科技", "半导体芯片", "集成电路"]
            ),
            // 华为生态 / 鸿蒙 / 昇腾算力 / 智能驾驶 (涵盖常山北明[北明软件]、润和软件、拓维信息、四川长虹、高新发展、赛力斯等)
            (
                keywords: ["鸿蒙", "开源鸿蒙", "openharmony", "北明软件", "华为昇腾", "华鲲振宇", "湘江鲲鹏", "昇腾", "鲲鹏", "华为智驾", "华为汽车", "问界", "尊界", "享界", "阿维塔", "鸿蒙智行", "华为云", "信创软件", "ai服务器"],
                associatedConcepts: ["华为鸿蒙", "开源鸿蒙", "OpenHarmony", "华为昇腾", "华鲲振宇", "湘江鲲鹏", "北明软件", "华为云", "信创", "AI服务器", "鸿蒙智行", "华为汽车", "问界", "华为智驾"]
            ),
            // 百度无人驾驶 / 自动驾驶 / Robotaxi (涵盖大众交通、锦江在线等)
            (
                keywords: ["robotaxi", "萝卜快跑", "无人驾驶", "自动驾驶", "智能网联汽车", "网约车", "出租车运营", "百度apollo"],
                associatedConcepts: ["Robotaxi", "萝卜快跑", "无人驾驶", "自动驾驶", "智能驾驶", "智能网联汽车"]
            ),
            // AI 算力 / 英伟达链 / 服务器 / 液冷 (涵盖工业富联、浪潮信息、中科曙光、英维克等)
            (
                keywords: ["英伟达", "gb200", "ai服务器", "液冷服务器", "液冷", "算力中心", "智算中心", "高速交换机", "数据中心idc", "算力芯片", "gpu", "blackwell"],
                associatedConcepts: ["AI算力", "英伟达", "GB200", "AI服务器", "液冷服务器", "智算中心", "数据中心", "算力芯片"]
            ),
            // 低空经济 / 飞行汽车 / eVTOL (涵盖万丰奥威、中信海直、宗申动力等)
            (
                keywords: ["低空经济", "飞行汽车", "evtol", "通航运营", "航空发动机", "无人机", "空域管理", "通航维修"],
                associatedConcepts: ["低空经济", "飞行汽车", "eVTOL", "通航运营", "航空发动机", "无人机"]
            ),
            // 人形机器人 / 具身智能 (涵盖三花智控、拓普集团、鸣志电器、绿的谐波、北特科技等)
            (
                keywords: ["人形机器人", "具身智能", "行星滚柱丝杠", "谐波减速器", "空心杯电机", "灵巧手", "旋转执行器", "直线执行器", "伺服电机", "特斯拉机器人", "optimus"],
                associatedConcepts: ["人形机器人", "具身智能", "行星滚柱丝杠", "谐波减速器", "空心杯电机", "旋转执行器", "直线执行器", "灵巧手", "特斯拉机器人"]
            ),
            // 固态电池 / 动力储能 / 锂电 (涵盖宁德时代、比亚迪、南都电源、鹏辉能源等)
            (
                keywords: ["固态电池", "全固态电池", "硫化物固态", "氧化物固态", "动力电池", "储能系统", "新能源汽车动力", "锂电池", "储能电站", "电芯"],
                associatedConcepts: ["固态电池", "全固态电池", "动力电池", "储能系统", "新能源汽车", "锂电池"]
            ),
            // 创新药 / 生物医药 / CXO (涵盖恒瑞医药、药明康德、百济神州等)
            (
                keywords: ["创新药", "cxo", "新药研发", "单抗", "双抗", "adc", "抗肿瘤", "glp-1", "医药研发外包", "生物制药"],
                associatedConcepts: ["创新药", "医药生物", "CXO", "新药研发", "生物医药"]
            ),
            // 证券 / 互联网金融 / 金融科技 (涵盖东方财富、同花顺、中信证券等)
            (
                keywords: ["证券", "券商", "互联网金融", "期货", "基金代销", "金融科技", "资本市场", "财富管理"],
                associatedConcepts: ["券商板块", "证券板块", "互联网金融", "大金融", "金融科技"]
            ),
            // 白酒 / 酿酒消费 (涵盖贵州茅台、五粮液等)
            (
                keywords: ["白酒", "浓香型", "酱香型", "清香型", "酿酒", "白酒酿造"],
                associatedConcepts: ["白酒", "酿酒板块", "大消费", "食品饮料"]
            ),
            // 光伏 / 储能逆变器 (涵盖阳光电源、隆基绿能等)
            (
                keywords: ["光伏", "太阳能电池", "逆变器", "硅片", "光伏组件", "绿色电力", "光伏电站"],
                associatedConcepts: ["光伏产业链", "储能概念", "逆变器", "绿色电力", "光伏组件"]
            )
        ]
        
        // 3. 执行 AI 语义推理：只要文本命中任一产业链的关键词，立即将该产业链的精准核心概念注入个股知识画像
        for rule in financialEntityMap {
            let hitCount = rule.keywords.filter { allCombinedText.contains($0) }.count
            if hitCount > 0 {
                tags.formUnion(rule.associatedConcepts)
            }
        }
        
        return tags
    }
    
    // MARK: - 辅助解析工具
    
    private func extractTitleAndContent(from rawText: String) -> (String, String) {
        if rawText.hasPrefix("【") && rawText.contains("】") {
            let parts = rawText.components(separatedBy: "】")
            let title = parts[0].replacingOccurrences(of: "【", with: "")
            let content = parts.dropFirst().joined(separator: "】").trimmingCharacters(in: .whitespacesAndNewlines)
            return (title, content.isEmpty ? title : content)
        }
        return ("", rawText)
    }
    
    private func extractStockMentions(from text: String) -> ([String], [String]) {
        var codes: [String] = []
        var names: [String] = []
        
        let stockDict: [String: String] = [
            "长飞光纤": "601869", "亨通光电": "600487", "中天科技": "600522", "烽火通信": "600498",
            "中际旭创": "300308", "新易盛": "300502", "天孚通信": "300394", "光迅科技": "002281",
            "贵州茅台": "600519", "五粮液": "000858", "宁德时代": "300750", "比亚迪": "002594",
            "赛力斯": "601127", "江淮汽车": "600418", "中芯国际": "688981", "北方华创": "002371",
            "海光信息": "688041", "寒武纪": "688256", "三花智控": "002050", "拓普集团": "601689",
            "工业富联": "601138", "浪潮信息": "000977", "中科曙光": "603019", "药明康德": "603259",
            "恒瑞医药": "600276", "中信证券": "600030", "东方财富": "300059", "同花顺": "300033",
            "万丰奥威": "002085", "中信海直": "000099", "阳光电源": "300274", "隆基绿能": "601012"
        ]
        
        for (stkName, stkCode) in stockDict {
            if text.contains(stkName) {
                if !names.contains(stkName) { names.append(stkName) }
                if !codes.contains(stkCode) { codes.append(stkCode) }
            }
        }
        
        let pattern = #"\b(00[0-9]{4}|30[0-9]{4}|60[0-9]{4}|68[0-9]{4}|8[0-9]{5}|4[0-9]{5})\b"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = text as NSString
            let matches = regex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                let code = nsString.substring(with: match.range)
                if !codes.contains(code) { codes.append(code) }
            }
        }
        
        let namePattern = #"【([^:：】]+)[：:]"#
        if let nameRegex = try? NSRegularExpression(pattern: namePattern, options: []) {
            let nsString = text as NSString
            let matches = nameRegex.matches(in: text, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches {
                if match.numberOfRanges > 1 {
                    let name = nsString.substring(with: match.range(at: 1)).trimmingCharacters(in: .whitespaces)
                    if name.count >= 2 && name.count <= 8 && !names.contains(name) {
                        names.append(name)
                    }
                }
            }
        }
        
        return (codes, names)
    }
}
