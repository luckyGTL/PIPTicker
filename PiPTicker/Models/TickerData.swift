import Foundation

/// A股股票标识
public struct StockSymbol: Identifiable, Codable, Hashable {
    public var id: String { fullCode } // e.g. "sh600519", "sz300750"
    public let code: String            // "600519"
    public let market: String          // "sh", "sz", "bj"
    public var name: String            // "贵州茅台"
    
    public var fullCode: String {
        return "\(market.lowercased())\(code)"
    }
    
    public var marketDisplayName: String {
        switch market.lowercased() {
        case "sh": return "上交所"
        case "sz": return "深交所"
        case "bj": return "北交所"
        default: return market.uppercased()
        }
    }
    
    public init(code: String, market: String, name: String) {
        self.code = code
        self.market = market.lowercased()
        self.name = name
    }
    
    public static func create(from rawInput: String, defaultName: String = "") -> StockSymbol {
        let trimmed = rawInput.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if trimmed.hasPrefix("sh") || trimmed.hasPrefix("sz") || trimmed.hasPrefix("bj") {
            let market = String(trimmed.prefix(2))
            let code = String(trimmed.dropFirst(2))
            return StockSymbol(code: code, market: market, name: defaultName.isEmpty ? code : defaultName)
        }
        
        // 自动识别 A股 市场前缀
        let market: String
        if trimmed == "000001" && (defaultName.contains("上证") || defaultName.isEmpty) {
            market = "sh"
        } else if trimmed.hasPrefix("6") || trimmed.hasPrefix("900") || trimmed.hasPrefix("688") {
            market = "sh"
        } else if trimmed.hasPrefix("0") || trimmed.hasPrefix("3") {
            market = "sz"
        } else if trimmed.hasPrefix("4") || trimmed.hasPrefix("8") || trimmed.hasPrefix("920") {
            market = "bj"
        } else {
            market = "sh"
        }
        return StockSymbol(code: trimmed, market: market, name: defaultName.isEmpty ? trimmed : defaultName)
    }
    
    public static let presets: [StockSymbol] = [
        StockSymbol(code: "000001", market: "sh", name: "上证指数"),
        StockSymbol(code: "399001", market: "sz", name: "深证成指"),
        StockSymbol(code: "399006", market: "sz", name: "创业板指"),
        StockSymbol(code: "600519", market: "sh", name: "贵州茅台"),
        StockSymbol(code: "300750", market: "sz", name: "宁德时代"),
        StockSymbol(code: "002594", market: "sz", name: "比亚迪"),
        StockSymbol(code: "688981", market: "sh", name: "中芯国际"),
        StockSymbol(code: "300059", market: "sz", name: "东方财富")
    ]
}

/// A股实时行情数据
public struct StockQuote: Identifiable, Equatable, Codable {
    public var id: String { symbol.fullCode }
    public var symbol: StockSymbol
    public var price: String              // 当前价格 "1277.40"
    public var priceChange: String        // 涨跌额 "-14.10"
    public var priceChangePercent: String // 涨跌幅 "-1.09%"
    public var isPositive: Bool           // 涨跌状态 (true 涨, false 跌)
    public var isFlat: Bool               // 是否平盘
    public var yesterdayClose: String     // 昨收
    public var todayOpen: String          // 今开
    public var highPrice: String          // 最高
    public var lowPrice: String           // 最低
    public var volume: String             // 成交量 (手/万手)
    public var turnover: String           // 成交额 (万元/亿元)
    public var updatedAt: Date
    
    public init(
        symbol: StockSymbol,
        price: String = "--.--",
        priceChange: String = "0.00",
        priceChangePercent: String = "0.00%",
        isPositive: Bool = true,
        isFlat: Bool = false,
        yesterdayClose: String = "--",
        todayOpen: String = "--",
        highPrice: String = "--",
        lowPrice: String = "--",
        volume: String = "--",
        turnover: String = "--",
        updatedAt: Date = Date()
    ) {
        self.symbol = symbol
        self.price = price
        self.priceChange = priceChange
        self.priceChangePercent = priceChangePercent
        self.isPositive = isPositive
        self.isFlat = isFlat
        self.yesterdayClose = yesterdayClose
        self.todayOpen = todayOpen
        self.highPrice = highPrice
        self.lowPrice = lowPrice
        self.volume = volume
        self.turnover = turnover
        self.updatedAt = updatedAt
    }
}

/// 股票模糊搜索联想结果
public struct StockSearchResult: Identifiable, Hashable, Codable {
    public var id: String { symbol.fullCode }
    public let symbol: StockSymbol
    public let pinyin: String
    public let typeName: String // "A股", "指数", "ETF", "港股", "美股"
    
    public init(symbol: StockSymbol, pinyin: String = "", typeName: String = "A股") {
        self.symbol = symbol
        self.pinyin = pinyin
        self.typeName = typeName
    }
}
