import Foundation
import Combine

/// 强度排名条目（净流入 / 涨速共用）
public struct StrengthRankItem: Identifiable, Equatable {
    public var id: String { fullCode }
    public let code: String
    public let market: String
    public let name: String
    public let currentPrice: Double
    public let changePercent: Double
    public let turnover: Double
    public let netInflow: Double
    public let speedPercent: Double
    
    public var fullCode: String { "\(market)\(code)" }
    
    public var formattedNetInflow: String {
        Self.formatSignedAmount(netInflow)
    }
    
    public var formattedTurnover: String {
        let absVal = abs(turnover)
        if absVal >= 100_000_000 {
            return String(format: "%.2f亿", absVal / 100_000_000.0)
        } else {
            return String(format: "%.1f万", absVal / 10_000.0)
        }
    }
    
    public var formattedSpeed: String {
        String(format: "%+.2f%%", speedPercent)
    }
    
    public static func formatSignedAmount(_ value: Double) -> String {
        let absVal = abs(value)
        let sign = value >= 0 ? "+" : "-"
        if absVal >= 100_000_000 {
            return String(format: "%@%.2f亿", sign, absVal / 100_000_000.0)
        } else {
            return String(format: "%@%.1f万", sign, absVal / 10_000.0)
        }
    }
}

/// A股短线强度排名调度中心（主力净流入 Top20 + 涨速 Top20，盘中 10 秒轮询，盘后停止）
public final class StrengthRankManager: ObservableObject {
    public static let shared = StrengthRankManager()
    
    @Published public var netInflowRanks: [StrengthRankItem] = []
    @Published public var speedRanks: [StrengthRankItem] = []
    @Published public var isRefreshing: Bool = false
    @Published public var lastUpdated: Date = Date()
    
    private var refreshTimer: Timer?
    private let urlSession: URLSession
    private let topCount = 20
    private let gbkEncoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
    )
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 6.0
        config.requestCachePolicy = .reloadIgnoringLocalCacheData
        self.urlSession = URLSession(configuration: config)
    }
    
    public func start() {
        fetchRankings()
        startTimer()
    }
    
    public func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func startTimer() {
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 10.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            // 盘后、周末、午间休市不再自动轮询；手动刷新依然可用
            guard StockDataManager.shared.isMarketTradingHours else { return }
            self.fetchRankings()
        }
    }
    
    public func fetchRankings() {
        guard !isRefreshing else { return }
        isRefreshing = true
        
        let group = DispatchGroup()
        var inflowItems: [StrengthRankItem] = []
        var speedItems: [StrengthRankItem] = []
        
        group.enter()
        fetchEastMoneyRank(sortField: "f62") { [weak self] items in
            if items.isEmpty {
                self?.fetchSinaNetInflowRank { fallback in
                    inflowItems = fallback
                    group.leave()
                }
            } else {
                inflowItems = items
                group.leave()
            }
        }
        
        group.enter()
        fetchEastMoneyRank(sortField: "f22") { items in
            speedItems = items
            group.leave()
        }
        
        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            if !inflowItems.isEmpty {
                self.netInflowRanks = Array(inflowItems.prefix(self.topCount))
            }
            if !speedItems.isEmpty {
                self.speedRanks = Array(speedItems.prefix(self.topCount))
            }
            self.isRefreshing = false
            self.lastUpdated = Date()
        }
    }
    
    // MARK: - 东方财富全市场排行（f62 主力净流入 / f22 涨速）
    
    private func fetchEastMoneyRank(sortField: String, completion: @escaping ([StrengthRankItem]) -> Void) {
        var components = URLComponents(string: "https://push2.eastmoney.com/api/qt/clist/get")
        components?.queryItems = [
            URLQueryItem(name: "pn", value: "1"),
            URLQueryItem(name: "pz", value: "\(topCount)"),
            URLQueryItem(name: "po", value: "1"),
            URLQueryItem(name: "np", value: "1"),
            URLQueryItem(name: "ut", value: "bd1d9ddb04089700cf9c27f6f7426281"),
            URLQueryItem(name: "fltt", value: "2"),
            URLQueryItem(name: "invt", value: "2"),
            URLQueryItem(name: "fid", value: sortField),
            URLQueryItem(name: "fs", value: "m:0+t:6,m:0+t:80,m:1+t:2,m:1+t:23,m:0+t:81+s:2048"),
            URLQueryItem(name: "fields", value: "f12,f13,f14,f2,f3,f6,f22,f62")
        ]
        
        guard let url = components?.url else {
            completion([])
            return
        }
        
        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        request.setValue("https://quote.eastmoney.com/center/gridlist.html", forHTTPHeaderField: "Referer")
        
        urlSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let payload = json["data"] as? [String: Any] else {
                completion([])
                return
            }
            
            let rawList: [[String: Any]]
            if let diff = payload["diff"] as? [[String: Any]] {
                rawList = diff
            } else if let diffDict = payload["diff"] as? [String: [String: Any]] {
                rawList = diffDict.keys.sorted { (Int($0) ?? 0) < (Int($1) ?? 0) }.compactMap { diffDict[$0] }
            } else {
                completion([])
                return
            }
            
            let items = rawList.compactMap { self.parseEastMoneyItem($0) }
            completion(items)
        }.resume()
    }
    
    private func parseEastMoneyItem(_ dict: [String: Any]) -> StrengthRankItem? {
        let code = stringValue(dict["f12"])
        let name = stringValue(dict["f14"])
        guard !code.isEmpty, !name.isEmpty else { return nil }
        
        let marketId = Int(doubleValue(dict["f13"]))
        return StrengthRankItem(
            code: code,
            market: marketPrefix(code: code, marketId: marketId),
            name: name,
            currentPrice: doubleValue(dict["f2"]),
            changePercent: doubleValue(dict["f3"]),
            turnover: doubleValue(dict["f6"]),
            netInflow: doubleValue(dict["f62"]),
            speedPercent: doubleValue(dict["f22"])
        )
    }
    
    // MARK: - 新浪主力净流入备份通道
    
    private func fetchSinaNetInflowRank(completion: @escaping ([StrengthRankItem]) -> Void) {
        let urlStr = "http://vip.stock.finance.sina.com.cn/quotes_service/api/json_v2.php/MoneyFlow.ssl_bkzj_ssggzj?page=1&num=\(topCount)&sort=r0_net&asc=0"
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
            
            var results: [StrengthRankItem] = []
            for dict in list {
                guard let symbol = dict["symbol"] as? String,
                      let rawName = dict["name"] as? String else { continue }
                
                let name = StockSearchService.shared.decodeUnicodeEscapes(rawName)
                let code: String
                let market: String
                if symbol.hasPrefix("sh") || symbol.hasPrefix("sz") || symbol.hasPrefix("bj") {
                    market = String(symbol.prefix(2))
                    code = String(symbol.dropFirst(2))
                } else {
                    let parsed = StockSymbol.create(from: symbol, defaultName: name)
                    market = parsed.market
                    code = parsed.code
                }
                
                let price = Double(dict["trade"] as? String ?? "") ?? 0.0
                let ratio = Double(dict["changeratio"] as? String ?? "") ?? 0.0
                let amount = Double(dict["amount"] as? String ?? "") ?? 0.0
                let netamount = Double(dict["netamount"] as? String ?? "") ?? 0.0
                let r0net = Double(dict["r0_net"] as? String ?? "") ?? netamount
                
                results.append(StrengthRankItem(
                    code: code,
                    market: market,
                    name: name,
                    currentPrice: price,
                    changePercent: ratio * 100.0,
                    turnover: amount,
                    netInflow: r0net != 0 ? r0net : netamount,
                    speedPercent: 0
                ))
            }
            completion(results)
        }.resume()
    }
    
    // MARK: - 解析辅助
    
    private func marketPrefix(code: String, marketId: Int) -> String {
        if code.hasPrefix("6") || code.hasPrefix("9") { return "sh" }
        if code.hasPrefix("8") || code.hasPrefix("4") || code.hasPrefix("92") { return "bj" }
        if marketId == 1 { return "sh" }
        return "sz"
    }
    
    private func doubleValue(_ any: Any?) -> Double {
        if let number = any as? NSNumber { return number.doubleValue }
        if let value = any as? Double { return value }
        if let value = any as? Int { return Double(value) }
        if let text = any as? String, text != "-" { return Double(text) ?? 0 }
        return 0
    }
    
    private func stringValue(_ any: Any?) -> String {
        if let text = any as? String { return text }
        if let number = any as? NSNumber { return number.stringValue }
        return ""
    }
}
