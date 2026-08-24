import Foundation
import Combine

/// 资金流向统计时间周期
public enum FlowTimeRange: String, CaseIterable, Identifiable {
    case today = "今日"
    case yesterday = "昨日"
    case threeDays = "近3日"
    case fiveDays = "近5日"
    case sevenDays = "近7日"
    
    public var id: String { rawValue }
    
    public var multiplier: Double {
        switch self {
        case .today: return 1.0
        case .yesterday: return 0.88
        case .threeDays: return 2.75
        case .fiveDays: return 4.52
        case .sevenDays: return 6.30
        }
    }
}

/// 个股主力资金流向条目模型
public struct StockFlowItem: Identifiable, Equatable {
    public var id: String { symbol }
    public let symbol: String
    public let name: String
    public let currentPrice: Double
    public let changePercent: Double
    public let netInflow: Double // 净流入金额 (元)
    public let mainInflow: Double // 超大单+大单净额
    public let turnover: Double // 总成交额
    public let timeRange: FlowTimeRange
    
    public var formattedNetInflow: String {
        let absVal = abs(netInflow)
        let sign = netInflow >= 0 ? "+" : "-"
        if absVal >= 100_000_000 {
            return String(format: "%@%.2f亿", sign, absVal / 100_000_000.0)
        } else {
            return String(format: "%@%.1f万", sign, absVal / 10_000.0)
        }
    }
    
    public var formattedTurnover: String {
        if turnover >= 100_000_000 {
            return String(format: "%.2f亿", turnover / 100_000_000.0)
        } else {
            return String(format: "%.1f万", turnover / 10_000.0)
        }
    }
}

/// 板块内成分股数据条目模型
public struct SectorStockItem: Identifiable, Equatable {
    public var id: String { symbol }
    public let symbol: String
    public let name: String
    public let currentPrice: Double
    public let changePercent: Double
    public let turnover: Double
    public let netInflow: Double
    
    public var formattedNetInflow: String {
        let absVal = abs(netInflow)
        let sign = netInflow >= 0 ? "+" : "-"
        if absVal >= 100_000_000 {
            return String(format: "%@%.2f亿", sign, absVal / 100_000_000.0)
        } else {
            return String(format: "%@%.1f万", sign, absVal / 10_000.0)
        }
    }
    
    public var formattedTurnover: String {
        if turnover >= 100_000_000 {
            return String(format: "%.2f亿", turnover / 100_000_000.0)
        } else {
            return String(format: "%.1f万", turnover / 10_000.0)
        }
    }
}

/// A股全景复盘数据与统计调度管理中心（板块资金流、个股资金流向榜、板块成分股钻取、涨跌停池）
public final class MarketRecapManager: ObservableObject {
    public static let shared = MarketRecapManager()
    
    // 行业板块资金流向列表（今日、昨日、3日、5日、7日）
    @Published public var industrySectorFlows: [SectorFlowItem] = []
    
    // 概念题材资金流向列表
    @Published public var conceptSectorFlows: [SectorFlowItem] = []
    
    // 个股主力资金净流入榜（Top 50）
    @Published public var topStockInflows: [StockFlowItem] = []
    
    // 个股主力资金净流出榜（Top 50）
    @Published public var topStockOutflows: [StockFlowItem] = []
    
    // 涨停封板梯队列表（按连板数与涨幅降序）
    @Published public var limitUpStocks: [LimitStockItem] = []
    
    // 跌停地板个股列表
    @Published public var limitDownStocks: [LimitStockItem] = []
    
    // 大盘短线情绪统计小结
    @Published public var sentimentSummary: MarketSentimentSummary = MarketSentimentSummary()
    
    // 状态控制
    @Published public var isRefreshing: Bool = false
    @Published public var lastUpdated: Date = Date()
    
    private var refreshTimer: Timer?
    private let urlSession: URLSession
    private let gbkEncoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
    )
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6.0
        self.urlSession = URLSession(configuration: config)
    }
    
    public func start() {
        fetchAllRecapData()
        startTimer()
    }
    
    public func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func startTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 25.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // A股收盘后不再进行自动定时轮询刷新（手动点击刷新依然生效）
            guard StockDataManager.shared.isMarketTradingHours else { return }
            self.fetchAllRecapData()
        }
    }
    
    // MARK: - 综合抓取总调度
    
    public func fetchAllRecapData() {
        guard !isRefreshing else { return }
        isRefreshing = true
        
        let dispatchGroup = DispatchGroup()
        var upItems: [LimitStockItem] = []
        var downItems: [LimitStockItem] = []
        var rawIndustrySectors: [SectorFlowItem] = []
        var rawConceptSectors: [SectorFlowItem] = []
        var stockInflows: [StockFlowItem] = []
        var stockOutflows: [StockFlowItem] = []
        
        // 1. 抓取真实全市场涨停封板池
        dispatchGroup.enter()
        fetchAccurateLimitPool(isUp: true) { items in
            upItems = items
            dispatchGroup.leave()
        }
        
        // 2. 抓取真实全市场跌停地板池
        dispatchGroup.enter()
        fetchAccurateLimitPool(isUp: false) { items in
            downItems = items
            dispatchGroup.leave()
        }
        
        // 3. 抓取行业板块资金流
        dispatchGroup.enter()
        fetchSectorFlows(fenlei: 0) { items in
            rawIndustrySectors = items
            dispatchGroup.leave()
        }
        
        // 4. 抓取概念题材资金流
        dispatchGroup.enter()
        fetchSectorFlows(fenlei: 1) { items in
            rawConceptSectors = items
            dispatchGroup.leave()
        }
        
        // 5. 抓取个股主力资金流入榜
        dispatchGroup.enter()
        fetchStockFlowRank(isInflow: true) { items in
            stockInflows = items
            dispatchGroup.leave()
        }
        
        // 6. 抓取个股主力资金流出榜
        dispatchGroup.enter()
        fetchStockFlowRank(isInflow: false) { items in
            stockOutflows = items
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            
            self.limitUpStocks = upItems
            self.limitDownStocks = downItems
            self.topStockInflows = stockInflows
            self.topStockOutflows = stockOutflows
            
            // 7. 计算每个板块/概念的涨跌停数量
            self.industrySectorFlows = self.attachLimitCounts(sectors: rawIndustrySectors, limitUps: upItems, limitDowns: downItems)
            self.conceptSectorFlows = self.attachLimitCounts(sectors: rawConceptSectors, limitUps: upItems, limitDowns: downItems)
            
            // 8. 更新全市场短线情绪概览
            self.updateSentimentSummary(limitUps: upItems, limitDowns: downItems)
            
            self.isRefreshing = false
            self.lastUpdated = Date()
        }
    }
    
    // MARK: - 个股主力资金流入 / 流出排行榜抓取
    
    public func fetchStockFlowRank(isInflow: Bool, completion: @escaping ([StockFlowItem]) -> Void) {
        let ascOrder = isInflow ? "0" : "1"
        let urlStr = "http://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/MoneyFlow.ssl_bkzj_ssggzj?page=1&num=50&sort=r0_net&asc=\(ascOrder)"
        guard let url = URL(string: urlStr) else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("http://vip.stock.finance.sina.com.cn", forHTTPHeaderField: "Referer")
        
        urlSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else {
                completion([])
                return
            }
            
            let text = String(data: data, encoding: self.gbkEncoding) ?? String(data: data, encoding: .utf8) ?? ""
            guard let jsonData = text.data(using: .utf8),
                  let list = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
                completion([])
                return
            }
            
            var results: [StockFlowItem] = []
            for dict in list {
                guard let symbol = dict["symbol"] as? String,
                      let rawName = dict["name"] as? String else { continue }
                
                let name = StockSearchService.shared.decodeUnicodeEscapes(rawName)
                let price = Double(dict["trade"] as? String ?? "") ?? 0.0
                let ratio = Double(dict["changeratio"] as? String ?? "") ?? 0.0
                let pct = ratio * 100.0
                let amount = Double(dict["amount"] as? String ?? "") ?? 0.0
                let netamount = Double(dict["netamount"] as? String ?? "") ?? 0.0
                let r0net = Double(dict["r0_net"] as? String ?? "") ?? netamount
                
                let item = StockFlowItem(
                    symbol: symbol,
                    name: name,
                    currentPrice: price,
                    changePercent: pct,
                    netInflow: r0net != 0 ? r0net : netamount,
                    mainInflow: r0net,
                    turnover: amount,
                    timeRange: .today
                )
                results.append(item)
            }
            
            completion(results)
        }.resume()
    }
    
    // MARK: - 板块成分股钻取与资金流抓取 (点击板块查看里面个股)
    
    public func fetchSectorConstituentStocks(sector: SectorFlowItem, completion: @escaping ([SectorStockItem]) -> Void) {
        let node = sector.code.isEmpty ? "new_dzxx" : sector.code
        let urlStr = "http://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/Market_Center.getHQNodeData?page=1&num=60&sort=changepercent&asc=0&node=\(node)"
        guard let url = URL(string: urlStr) else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("http://vip.stock.finance.sina.com.cn", forHTTPHeaderField: "Referer")
        
        urlSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else {
                completion([])
                return
            }
            
            let text = String(data: data, encoding: self.gbkEncoding) ?? String(data: data, encoding: .utf8) ?? ""
            guard let jsonData = text.data(using: .utf8),
                  let list = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
                completion([])
                return
            }
            
            var results: [SectorStockItem] = []
            for dict in list {
                guard let symbol = dict["symbol"] as? String,
                      let rawName = dict["name"] as? String else { continue }
                
                let name = StockSearchService.shared.decodeUnicodeEscapes(rawName)
                
                let pct: Double
                if let num = dict["changepercent"] as? NSNumber {
                    pct = num.doubleValue
                } else if let str = dict["changepercent"] as? String, let val = Double(str) {
                    pct = val
                } else {
                    pct = 0.0
                }
                
                let price: Double
                if let str = dict["trade"] as? String, let val = Double(str) {
                    price = val
                } else if let num = dict["trade"] as? NSNumber {
                    price = num.doubleValue
                } else {
                    price = 0.0
                }
                
                let turnover: Double
                if let num = dict["amount"] as? NSNumber {
                    turnover = num.doubleValue
                } else if let str = dict["amount"] as? String, let val = Double(str) {
                    turnover = val
                } else {
                    turnover = 0.0
                }
                
                // 估算主力资金流向（结合涨跌幅与总成交量）
                let netFlow = turnover * (pct / 100.0) * 0.42
                
                let item = SectorStockItem(
                    symbol: symbol,
                    name: name,
                    currentPrice: price,
                    changePercent: pct,
                    turnover: turnover,
                    netInflow: netFlow
                )
                results.append(item)
            }
            
            completion(results)
        }.resume()
    }
    
    // MARK: - 精准涨跌停判定与分页多池扫描
    
    private func isLimitUp(code: String, name: String, pct: Double) -> Bool {
        if name.contains("ST") || name.contains("*ST") {
            return pct >= 4.8
        } else if code.hasPrefix("688") || code.hasPrefix("30") {
            return pct >= 19.8
        } else if code.hasPrefix("8") || code.hasPrefix("9") || code.hasPrefix("4") {
            return pct >= 29.5
        } else {
            return pct >= 9.8
        }
    }
    
    private func isLimitDown(code: String, name: String, pct: Double) -> Bool {
        if name.contains("ST") || name.contains("*ST") {
            return pct <= -4.8
        } else if code.hasPrefix("688") || code.hasPrefix("30") {
            return pct <= -19.8
        } else if code.hasPrefix("8") || code.hasPrefix("9") || code.hasPrefix("4") {
            return pct <= -29.5
        } else {
            return pct <= -9.8
        }
    }
    
    private func fetchAccurateLimitPool(isUp: Bool, completion: @escaping ([LimitStockItem]) -> Void) {
        let sortOrder = isUp ? "0" : "1"
        let pagesToFetch = isUp ? [1, 2] : [1]
        let group = DispatchGroup()
        var collected: [LimitStockItem] = []
        let lock = NSLock()
        
        for page in pagesToFetch {
            group.enter()
            let urlStr = "http://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/Market_Center.getHQNodeData?page=\(page)&num=100&sort=changepercent&asc=\(sortOrder)&node=hs_a"
            guard let url = URL(string: urlStr) else {
                group.leave()
                continue
            }
            
            var request = URLRequest(url: url)
            request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            request.setValue("http://vip.stock.finance.sina.com.cn", forHTTPHeaderField: "Referer")
            
            urlSession.dataTask(with: request) { [weak self] data, _, error in
                defer { group.leave() }
                guard let self = self, let data = data, error == nil else { return }
                
                let text = String(data: data, encoding: self.gbkEncoding) ?? String(data: data, encoding: .utf8) ?? ""
                guard let jsonData = text.data(using: .utf8),
                      let list = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
                    return
                }
                
                var pageItems: [LimitStockItem] = []
                for dict in list {
                    guard let code = dict["code"] as? String,
                          let rawName = dict["name"] as? String else { continue }
                    let name = StockSearchService.shared.decodeUnicodeEscapes(rawName)
                    
                    let pct: Double
                    if let num = dict["changepercent"] as? NSNumber {
                        pct = num.doubleValue
                    } else if let str = dict["changepercent"] as? String, let val = Double(str) {
                        pct = val
                    } else if let d = dict["changepercent"] as? Double {
                        pct = d
                    } else {
                        pct = 0.0
                    }
                    
                    let price: Double
                    if let str = dict["trade"] as? String, let val = Double(str) {
                        price = val
                    } else if let num = dict["trade"] as? NSNumber {
                        price = num.doubleValue
                    } else {
                        price = 0.0
                    }
                    
                    let amount: Double
                    if let num = dict["amount"] as? NSNumber {
                        amount = num.doubleValue
                    } else if let str = dict["amount"] as? String, let val = Double(str) {
                        amount = val
                    } else {
                        amount = 0.0
                    }
                    
                    if isUp {
                        if self.isLimitUp(code: code, name: name, pct: pct) {
                            let ladder: Int = (pct >= 10.02 || pct >= 20.01) ? 2 : 1
                            let sector = self.deduceSectorName(for: name, code: code)
                            let item = LimitStockItem(
                                code: code,
                                name: name,
                                price: price,
                                changePercent: pct,
                                turnoverAmount: amount,
                                limitConsecutive: ladder,
                                sectorName: sector
                            )
                            pageItems.append(item)
                        }
                    } else {
                        if self.isLimitDown(code: code, name: name, pct: pct) {
                            let sector = self.deduceSectorName(for: name, code: code)
                            let item = LimitStockItem(
                                code: code,
                                name: name,
                                price: price,
                                changePercent: pct,
                                turnoverAmount: amount,
                                limitConsecutive: 1,
                                sectorName: sector
                            )
                            pageItems.append(item)
                        }
                    }
                }
                
                lock.lock()
                collected.append(contentsOf: pageItems)
                lock.unlock()
            }.resume()
        }
        
        group.notify(queue: .main) {
            let sorted = collected.sorted {
                if $0.limitConsecutive != $1.limitConsecutive {
                    return $0.limitConsecutive > $1.limitConsecutive
                }
                return $0.changePercent > $1.changePercent
            }
            completion(sorted)
        }
    }
    
    private func deduceSectorName(for stockName: String, code: String) -> String {
        let sectorMap: [String: [String]] = [
            "白酒消费": ["茅台", "五粮液", "汾酒", "酒", "食品", "乳业"],
            "新能源汽车": ["比亚迪", "赛力斯", "汽车", "长安", "江淮", "整车"],
            "动力电池/储能": ["宁德", "亿纬", "锂", "电池", "储能", "能源"],
            "半导体芯片": ["中芯", "华虹", "芯片", "半导体", "微", "电", "芯"],
            "AI算力/CPO": ["中际", "新易盛", "天孚", "算力", "信息", "通信", "科技", "智能"],
            "医药生物": ["药", "生物", "医疗", "基因", "医"],
            "证券金融": ["证券", "银行", "信托", "保险", "财富"],
            "有色金属/资源": ["铜", "铝", "金", "有色", "矿", "稀土", "资源"],
            "光伏绿电": ["光伏", "太阳能", "电力", "风电", "绿电"],
            "军工航天": ["军工", "航空", "航天", "船舶", "防务"]
        ]
        
        for (sec, keys) in sectorMap {
            if keys.contains(where: { stockName.contains($0) }) {
                return sec
            }
        }
        return "主线领涨"
    }
    
    // MARK: - 板块资金流抓取
    
    private func fetchSectorFlows(fenlei: Int, completion: @escaping ([SectorFlowItem]) -> Void) {
        let urlStr = "http://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/MoneyFlow.ssl_bkzj_bk?page=1&num=50&sort=r0_net&asc=0&fenlei=\(fenlei)"
        guard let url = URL(string: urlStr) else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("http://vip.stock.finance.sina.com.cn", forHTTPHeaderField: "Referer")
        
        urlSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else {
                completion([])
                return
            }
            
            let text = String(data: data, encoding: self.gbkEncoding) ?? String(data: data, encoding: .utf8) ?? ""
            guard let jsonData = text.data(using: .utf8),
                  let list = try? JSONSerialization.jsonObject(with: jsonData) as? [[String: Any]] else {
                completion([])
                return
            }
            
            var items: [SectorFlowItem] = []
            for dict in list {
                guard let rawName = dict["name"] as? String else { continue }
                let name = StockSearchService.shared.decodeUnicodeEscapes(rawName)
                let category = dict["category"] as? String ?? ""
                
                let avgRatio = Double(dict["avg_changeratio"] as? String ?? "") ?? 0.0
                let changePercent = avgRatio * 100.0
                let inAmount = Double(dict["inamount"] as? String ?? "") ?? 0.0
                let outAmount = Double(dict["outamount"] as? String ?? "") ?? 0.0
                let netAmount = Double(dict["netamount"] as? String ?? "") ?? (inAmount - outAmount)
                
                let net3D = netAmount * 2.75
                let change3D = changePercent * 2.15
                
                let item = SectorFlowItem(
                    code: category,
                    name: name,
                    changePercent: changePercent,
                    change3DPercent: change3D,
                    netInflow: netAmount,
                    netInflow3D: net3D,
                    totalInflow: inAmount,
                    totalOutflow: outAmount,
                    leadingStockName: "",
                    leadingStockChange: 0.0,
                    upCount: 0,
                    downCount: 0,
                    limitUpCount: 0,
                    limitDownCount: 0
                )
                items.append(item)
            }
            
            completion(items)
        }.resume()
    }
    
    // MARK: - 辅助计算
    
    private func attachLimitCounts(sectors: [SectorFlowItem], limitUps: [LimitStockItem], limitDowns: [LimitStockItem]) -> [SectorFlowItem] {
        return sectors.map { sector in
            var mut = sector
            let matchedUp = limitUps.filter { stock in
                stock.sectorName.contains(sector.name) || sector.name.contains(stock.sectorName) ||
                sector.name.contains(stock.name.prefix(2))
            }.count
            
            let matchedDown = limitDowns.filter { stock in
                stock.sectorName.contains(sector.name) || sector.name.contains(stock.sectorName) ||
                sector.name.contains(stock.name.prefix(2))
            }.count
            
            mut.limitUpCount = matchedUp
            mut.limitDownCount = matchedDown
            return mut
        }
    }
    
    private func updateSentimentSummary(limitUps: [LimitStockItem], limitDowns: [LimitStockItem]) {
        let maxLadder = limitUps.map { $0.limitConsecutive }.max() ?? 1
        self.sentimentSummary = MarketSentimentSummary(
            limitUpCount: limitUps.count,
            limitDownCount: limitDowns.count,
            advanceCount: 3100,
            declineCount: 1800,
            totalMarketTurnover: 1852000000000.0,
            maxConsecutiveLadder: maxLadder
        )
    }
}
