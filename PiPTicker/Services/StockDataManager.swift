import Foundation
import Combine

public final class StockDataManager: ObservableObject {
    public static let shared = StockDataManager()
    
    // 自选股列表（任何变动即时持久化到本地并发布状态通知）
    @Published public var watchlist: [StockSymbol] = [] {
        didSet {
            saveState()
        }
    }
    
    // 股票最新行情字典（Key 为 fullCode，如 "sh600519"）
    @Published public var quotes: [String: StockQuote] = [:]
    
    // 当前投射到画中画 (PiP) 的焦点股票
    @Published public var focusedSymbol: StockSymbol
    
    // 画中画专用的焦点行情
    @Published public var focusedStockQuote: StockQuote
    
    // 行情更新状态
    @Published public var isUpdating: Bool = false
    @Published public var isMockMode: Bool = false
    @Published public var lastUpdated: Date = Date()
    @Published public var refreshInterval: TimeInterval = 2.0 // 默认 2s 轮询
    @Published public var marketStatusText: String = "交易中"
    
    private var pollTimer: Timer?
    private var mockTimer: Timer?
    private var isPaused: Bool = false
    private let urlSession: URLSession
    
    private let watchlistKey = "PiPTicker_AStock_Watchlist"
    private let focusedSymbolKey = "PiPTicker_AStock_FocusedSymbol"
    
    // GBK 编码解析
    private let gbkEncoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
    )
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 4.0
        self.urlSession = URLSession(configuration: config)
        
        // 1. 加载自选股
        let initialWatchlist: [StockSymbol]
        if let savedData = UserDefaults.standard.data(forKey: watchlistKey),
           let savedList = try? JSONDecoder().decode([StockSymbol].self, from: savedData),
           !savedList.isEmpty {
            initialWatchlist = savedList
        } else {
            initialWatchlist = StockSymbol.presets
        }
        self.watchlist = initialWatchlist
        
        // 2. 加载焦点股票
        let initialFocus: StockSymbol
        if let savedFocusData = UserDefaults.standard.data(forKey: focusedSymbolKey),
           let savedFocus = try? JSONDecoder().decode(StockSymbol.self, from: savedFocusData) {
            initialFocus = savedFocus
        } else {
            initialFocus = initialWatchlist.first ?? StockSymbol.presets[0]
        }
        self.focusedSymbol = initialFocus
        self.focusedStockQuote = StockQuote(symbol: initialFocus)
        
        updateMarketStatus()
    }
    
    // MARK: - 生命周期控制
    
    public func start() {
        isPaused = false
        if isMockMode {
            enableMockMode()
            return
        }
        
        // 立即拉取一次
        fetchQuotes()
        
        // 开启定时轮询
        startPollingTimer()
    }
    
    public func stop() {
        isPaused = true
        pollTimer?.invalidate()
        pollTimer = nil
        mockTimer?.invalidate()
        mockTimer = nil
    }
    
    public func setRefreshInterval(_ interval: TimeInterval) {
        self.refreshInterval = max(1.0, interval)
        if !isPaused && !isMockMode {
            startPollingTimer()
        }
    }
    
    private func startPollingTimer() {
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            guard let self = self, !self.isPaused, !self.isMockMode else { return }
            // 收盘后（周末、非交易时段）停止后台自动轮询，节省电量与网络请求；手动刷新依然可用
            self.updateMarketStatus()
            guard self.isMarketTradingHours else { return }
            self.fetchQuotes()
        }
    }
    
    // MARK: - 行情拉取与解析
    
    public func fetchQuotes() {
        guard !watchlist.isEmpty else { return }
        
        let fullCodes = watchlist.map { $0.fullCode }.joined(separator: ",")
        guard let url = URL(string: "https://qt.gtimg.cn/q=\(fullCodes)") else { return }
        
        isUpdating = true
        
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        urlSession.dataTask(with: request) { [weak self] data, response, error in
            guard let self = self else { return }
            
            defer {
                DispatchQueue.main.async {
                    self.isUpdating = false
                }
            }
            
            guard let data = data, error == nil else {
                print("[StockData] 请求失败: \(error?.localizedDescription ?? "未知错误")")
                return
            }
            
            // 使用 GBK 解码
            let text = String(data: data, encoding: self.gbkEncoding) ?? String(data: data, encoding: .utf8) ?? ""
            let parsedQuotes = self.parseTencentResponse(text)
            
            DispatchQueue.main.async {
                for quote in parsedQuotes {
                    self.quotes[quote.symbol.fullCode] = quote
                    
                    // 同步更新自选股里的官方名称（如果之前是纯数字）
                    if let index = self.watchlist.firstIndex(where: { $0.fullCode == quote.symbol.fullCode }) {
                        if self.watchlist[index].name != quote.symbol.name && !quote.symbol.name.isEmpty {
                            self.watchlist[index].name = quote.symbol.name
                        }
                    }
                }
                
                // 更新焦点股票行情
                if let focusQuote = self.quotes[self.focusedSymbol.fullCode] {
                    self.focusedStockQuote = focusQuote
                }
                
                self.lastUpdated = Date()
                self.updateMarketStatus()
            }
        }.resume()
    }
    
    /// 解析腾讯行情格式：v_sh600519="1~贵州茅台~600519~1277.40~1291.50~1291.50~...";
    private func parseTencentResponse(_ rawText: String) -> [StockQuote] {
        var results: [StockQuote] = []
        let lines = rawText.components(separatedBy: ";")
        
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty, let equalIndex = trimmed.firstIndex(of: "=") else { continue }
            
            let prefixPart = String(trimmed[..<equalIndex]) // 如 v_sh600519
            let codePart = prefixPart.replacingOccurrences(of: "v_", with: "").trimmingCharacters(in: .whitespaces)
            
            let contentPart = String(trimmed[trimmed.index(after: equalIndex)...])
                .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r\t;"))
            
            let parts = contentPart.components(separatedBy: "~")
            guard parts.count >= 35 else { continue }
            
            let name = parts[1]
            let code = parts[2]
            let rawPrice = parts[3]
            let yesterdayClose = parts[4]
            let todayOpen = parts[5]
            let volume = parts[6]
            let changeAmount = parts[31]
            let changePercentRaw = parts[32]
            let high = parts[33]
            let low = parts[34]
            let turnoverRaw = parts.count > 37 ? parts[37] : "--"
            
            let priceVal = Double(rawPrice) ?? 0.0
            let changeVal = Double(changeAmount) ?? 0.0
            let isPositive = changeVal > 0
            let isFlat = (changeVal == 0)
            
            let percentStr: String
            if changePercentRaw.contains("%") {
                percentStr = changePercentRaw
            } else {
                percentStr = String(format: "%@%.2f%%", changeVal > 0 ? "+" : "", Double(changePercentRaw) ?? 0.0)
            }
            
            // 格式化成交额 (原单位为 万元)
            var formattedTurnover = turnoverRaw
            if let turnoverWan = Double(turnoverRaw) {
                if turnoverWan >= 10000 {
                    formattedTurnover = String(format: "%.2f亿", turnoverWan / 10000.0)
                } else {
                    formattedTurnover = String(format: "%.0f万", turnoverWan)
                }
            }
            
            let market = codePart.hasPrefix("sh") ? "sh" : (codePart.hasPrefix("sz") ? "sz" : "bj")
            let symbol = StockSymbol(code: code, market: market, name: name)
            
            let quote = StockQuote(
                symbol: symbol,
                price: String(format: "%.2f", priceVal),
                priceChange: String(format: "%@%.2f", changeVal > 0 ? "+" : "", changeVal),
                priceChangePercent: percentStr,
                isPositive: isPositive,
                isFlat: isFlat,
                yesterdayClose: yesterdayClose,
                todayOpen: todayOpen,
                highPrice: high,
                lowPrice: low,
                volume: volume,
                turnover: formattedTurnover,
                updatedAt: Date()
            )
            results.append(quote)
        }
        
        return results
    }
    
    // MARK: - 自选股管理
    
    public func setFocusedStock(_ symbol: StockSymbol) {
        self.focusedSymbol = symbol
        if let quote = quotes[symbol.fullCode] {
            self.focusedStockQuote = quote
        } else {
            self.focusedStockQuote = StockQuote(symbol: symbol)
        }
        saveState()
        fetchQuotes()
    }
    
    public func addStock(input: String, completion: @escaping (Result<StockSymbol, Error>) -> Void) {
        let symbol = StockSymbol.create(from: input)
        
        if watchlist.contains(where: { $0.fullCode == symbol.fullCode }) {
            completion(.failure(NSError(domain: "PiPTicker", code: 400, userInfo: [NSLocalizedDescriptionKey: "该股票已在自选列表中"])))
            return
        }
        
        // 验证股票代码有效性并获取名称
        guard let url = URL(string: "https://qt.gtimg.cn/q=\(symbol.fullCode)") else {
            completion(.failure(NSError(domain: "PiPTicker", code: 400, userInfo: [NSLocalizedDescriptionKey: "无效的代码"])))
            return
        }
        
        var request = URLRequest(url: url)
        request.timeoutInterval = 4.0
        
        urlSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    completion(.failure(error ?? NSError(domain: "PiPTicker", code: 500, userInfo: [NSLocalizedDescriptionKey: "网络查询失败"])))
                }
                return
            }
            
            let text = String(data: data, encoding: self.gbkEncoding) ?? ""
            let parsed = self.parseTencentResponse(text)
            
            DispatchQueue.main.async {
                if let validQuote = parsed.first, !validQuote.symbol.name.isEmpty {
                    let newSymbol = validQuote.symbol
                    self.watchlist.append(newSymbol)
                    self.quotes[newSymbol.fullCode] = validQuote
                    self.saveState()
                    FinancialNewsManager.shared.analyzeStockWithAI(symbol: newSymbol, force: true)
                    completion(.success(newSymbol))
                } else {
                    completion(.failure(NSError(domain: "PiPTicker", code: 404, userInfo: [NSLocalizedDescriptionKey: "未查询到该股票代码，请检查输入"])))
                }
            }
        }.resume()
    }
    
    public func addSymbolDirectly(_ symbol: StockSymbol) {
        guard !watchlist.contains(where: { $0.fullCode == symbol.fullCode }) else { return }
        watchlist.append(symbol)
        saveState()
        fetchQuotes()
        FinancialNewsManager.shared.analyzeStockWithAI(symbol: symbol, force: true)
    }
    
    public func addSymbolDirectly(code: String, name: String, market: String) {
        let sym = StockSymbol(code: code, market: market, name: name)
        addSymbolDirectly(sym)
    }
    
    public func removeStock(_ symbol: StockSymbol) {
        watchlist.removeAll(where: { $0.fullCode == symbol.fullCode })
        quotes.removeValue(forKey: symbol.fullCode)
        if focusedSymbol.fullCode == symbol.fullCode, let first = watchlist.first {
            setFocusedStock(first)
        }
        saveState()
    }
    
    public func moveStock(from source: StockSymbol, to destination: StockSymbol) {
        guard let fromIndex = watchlist.firstIndex(of: source),
              let toIndex = watchlist.firstIndex(of: destination),
              fromIndex != toIndex else { return }
        let item = watchlist.remove(at: fromIndex)
        watchlist.insert(item, at: toIndex)
        saveState()
        fetchQuotes()
    }
    
    public func moveStock(fromOffsets: IndexSet, toOffset: Int) {
        watchlist.move(fromOffsets: fromOffsets, toOffset: toOffset)
        saveState()
        fetchQuotes()
    }
    
    public func saveState() {
        if let data = try? JSONEncoder().encode(watchlist) {
            UserDefaults.standard.set(data, forKey: watchlistKey)
            UserDefaults.standard.synchronize()
        }
        if let focusData = try? JSONEncoder().encode(focusedSymbol) {
            UserDefaults.standard.set(focusData, forKey: focusedSymbolKey)
            UserDefaults.standard.synchronize()
        }
    }
    
    // MARK: - 模拟模式
    
    public func enableMockMode() {
        isMockMode = true
        pollTimer?.invalidate()
        pollTimer = nil
        mockTimer?.invalidate()
        
        mockTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            
            for symbol in self.watchlist {
                var currentQuote = self.quotes[symbol.fullCode] ?? StockQuote(symbol: symbol)
                let basePrice = Double(currentQuote.price) ?? 100.0
                let delta = Double.random(in: -1.5...1.8)
                let newPrice = max(0.01, basePrice + delta)
                let yesterdayClose = Double(currentQuote.yesterdayClose) ?? basePrice
                let changeAmount = newPrice - yesterdayClose
                let changePercent = (changeAmount / yesterdayClose) * 100.0
                
                let isPositive = changeAmount > 0
                let isFlat = changeAmount == 0
                
                let updated = StockQuote(
                    symbol: symbol,
                    price: String(format: "%.2f", newPrice),
                    priceChange: String(format: "%@%.2f", changeAmount > 0 ? "+" : "", changeAmount),
                    priceChangePercent: String(format: "%@%.2f%%", changeAmount > 0 ? "+" : "", changePercent),
                    isPositive: isPositive,
                    isFlat: isFlat,
                    yesterdayClose: String(format: "%.2f", yesterdayClose),
                    todayOpen: currentQuote.todayOpen == "--" ? String(format: "%.2f", basePrice) : currentQuote.todayOpen,
                    highPrice: String(format: "%.2f", max(newPrice, Double(currentQuote.highPrice) ?? newPrice)),
                    lowPrice: String(format: "%.2f", min(newPrice, Double(currentQuote.lowPrice) ?? newPrice)),
                    volume: currentQuote.volume == "--" ? "128450" : currentQuote.volume,
                    turnover: currentQuote.turnover == "--" ? "25.32亿" : currentQuote.turnover,
                    updatedAt: Date()
                )
                
                self.quotes[symbol.fullCode] = updated
                if symbol.fullCode == self.focusedSymbol.fullCode {
                    self.focusedStockQuote = updated
                }
            }
            self.lastUpdated = Date()
        }
    }
    
    public func disableMockMode() {
        isMockMode = false
        mockTimer?.invalidate()
        mockTimer = nil
        start()
    }
    
    // MARK: - 交易时段检测
    
    public var isMarketTradingHours: Bool {
        let cal = Calendar.current
        let now = Date()
        let weekday = cal.component(.weekday, from: now) // 1=Sun, 7=Sat
        if weekday == 1 || weekday == 7 { return false }
        
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let timeInMinutes = hour * 60 + minute
        
        // 9:15 到 11:35 (早盘竞价与连续交易) 以及 12:55 到 15:05 (午盘与收盘竞价)
        let isMorningSession = (timeInMinutes >= 555 && timeInMinutes <= 695)
        let isAfternoonSession = (timeInMinutes >= 775 && timeInMinutes <= 905)
        
        return isMorningSession || isAfternoonSession
    }
    
    private func updateMarketStatus() {
        let cal = Calendar.current
        let now = Date()
        let weekday = cal.component(.weekday, from: now) // 1=Sun, 7=Sat
        
        if weekday == 1 || weekday == 7 {
            self.marketStatusText = "周末休市"
            return
        }
        
        let hour = cal.component(.hour, from: now)
        let minute = cal.component(.minute, from: now)
        let timeInMinutes = hour * 60 + minute
        
        if timeInMinutes >= 570 && timeInMinutes <= 690 { // 09:30 - 11:30
            self.marketStatusText = "早盘交易中"
        } else if timeInMinutes > 690 && timeInMinutes < 780 { // 11:30 - 13:00
            self.marketStatusText = "午间休市"
        } else if timeInMinutes >= 780 && timeInMinutes <= 900 { // 13:00 - 15:00
            self.marketStatusText = "午盘交易中"
        } else if timeInMinutes < 570 {
            self.marketStatusText = "未开盘 (盘前)"
        } else {
            self.marketStatusText = "已收盘"
        }
    }
}
