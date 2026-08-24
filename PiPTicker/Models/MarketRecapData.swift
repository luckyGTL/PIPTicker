import Foundation

/// 板块资金流向与走势数据模型
public struct SectorFlowItem: Identifiable, Codable {
    public var id: String { code }
    public let code: String              // 板块代码，如 new_blhy
    public let name: String              // 板块名称，如 酿酒行业、半导体
    public let changePercent: Double     // 今日涨跌幅 (%)
    public let change3DPercent: Double   // 近 3 天累计涨跌幅 (%)
    public let netInflow: Double         // 今日主力资金净流入 (元)
    public let netInflow3D: Double       // 近 3 天累计主力资金净流入 (元)
    public let totalInflow: Double       // 今日总流入 (元)
    public let totalOutflow: Double      // 今日总流出 (元)
    public let leadingStockName: String  // 领涨个股名称
    public let leadingStockChange: Double// 领涨个股涨幅 (%)
    public let upCount: Int              // 板块内上涨家数
    public let downCount: Int            // 板块内下跌家数
    public var limitUpCount: Int         // 板块内涨停封板家数
    public var limitDownCount: Int       // 板块内跌停地板家数
    
    public init(
        code: String,
        name: String,
        changePercent: Double,
        change3DPercent: Double = 0.0,
        netInflow: Double,
        netInflow3D: Double = 0.0,
        totalInflow: Double = 0.0,
        totalOutflow: Double = 0.0,
        leadingStockName: String = "",
        leadingStockChange: Double = 0.0,
        upCount: Int = 0,
        downCount: Int = 0,
        limitUpCount: Int = 0,
        limitDownCount: Int = 0
    ) {
        self.code = code
        self.name = name
        self.changePercent = changePercent
        self.change3DPercent = change3DPercent
        self.netInflow = netInflow
        self.netInflow3D = netInflow3D
        self.totalInflow = totalInflow
        self.totalOutflow = totalOutflow
        self.leadingStockName = leadingStockName
        self.leadingStockChange = leadingStockChange
        self.upCount = upCount
        self.downCount = downCount
        self.limitUpCount = limitUpCount
        self.limitDownCount = limitDownCount
    }
    
    public var formattedNetInflow: String {
        let absVal = abs(netInflow)
        let sign = netInflow >= 0 ? "+" : "-"
        if absVal >= 100_000_000 {
            return String(format: "%@%.2f亿", sign, absVal / 100_000_000)
        } else if absVal >= 10_000 {
            return String(format: "%@%.1f万", sign, absVal / 10_000)
        } else {
            return String(format: "%@%.0f元", sign, absVal)
        }
    }
    
    public var formattedNetInflow3D: String {
        let absVal = abs(netInflow3D)
        let sign = netInflow3D >= 0 ? "+" : "-"
        if absVal >= 100_000_000 {
            return String(format: "%@%.2f亿", sign, absVal / 100_000_000)
        } else if absVal >= 10_000 {
            return String(format: "%@%.1f万", sign, absVal / 10_000)
        } else {
            return String(format: "%@%.0f元", sign, absVal)
        }
    }
}

/// 涨停封板 / 跌停地板个股数据模型
public struct LimitStockItem: Identifiable, Codable {
    public var id: String { code }
    public let code: String          // 股票代码，如 600519
    public let name: String          // 股票名称
    public let price: Double         // 最新价格
    public let changePercent: Double // 涨跌幅 (%)
    public let turnoverAmount: Double// 成交额 (元)
    public let limitConsecutive: Int // 连板天数 (如 1, 2, 3连板)
    public let sectorName: String    // 所属行业板块
    public let limitReason: String   // 涨停/跌停原因/概念
    public let firstLimitTime: String// 首次封板时间
    
    public init(
        code: String,
        name: String,
        price: Double,
        changePercent: Double,
        turnoverAmount: Double = 0.0,
        limitConsecutive: Int = 1,
        sectorName: String = "",
        limitReason: String = "",
        firstLimitTime: String = ""
    ) {
        self.code = code
        self.name = name
        self.price = price
        self.changePercent = changePercent
        self.turnoverAmount = turnoverAmount
        self.limitConsecutive = limitConsecutive
        self.sectorName = sectorName
        self.limitReason = limitReason
        self.firstLimitTime = firstLimitTime
    }
    
    public var formattedTurnover: String {
        if turnoverAmount >= 100_000_000 {
            return String(format: "%.2f亿", turnoverAmount / 100_000_000)
        } else if turnoverAmount >= 10_000 {
            return String(format: "%.1f万", turnoverAmount / 10_000)
        } else {
            return String(format: "%.0f元", turnoverAmount)
        }
    }
}

/// A股大盘情绪小结模型
public struct MarketSentimentSummary: Codable {
    public var limitUpCount: Int = 0        // 涨停封板家数
    public var limitDownCount: Int = 0      // 跌停地板家数
    public var advanceCount: Int = 0        // 全市场上涨家数
    public var declineCount: Int = 0        // 全市场下跌家数
    public var totalMarketTurnover: Double = 0.0 // 两市总成交额 (元)
    public var maxConsecutiveLadder: Int = 0 // 今日最高连板数
    
    public init(
        limitUpCount: Int = 0,
        limitDownCount: Int = 0,
        advanceCount: Int = 0,
        declineCount: Int = 0,
        totalMarketTurnover: Double = 0.0,
        maxConsecutiveLadder: Int = 0
    ) {
        self.limitUpCount = limitUpCount
        self.limitDownCount = limitDownCount
        self.advanceCount = advanceCount
        self.declineCount = declineCount
        self.totalMarketTurnover = totalMarketTurnover
        self.maxConsecutiveLadder = maxConsecutiveLadder
    }
    
    public var formattedTurnover: String {
        return String(format: "%.2f 亿元", totalMarketTurnover / 100_000_000)
    }
}
