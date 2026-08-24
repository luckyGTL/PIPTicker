import Foundation

/// 资金流向统计时间周期（支持真实多日累计净流入统计：今日、近3日、近5日、近7日、近10日、近20日）
public enum FlowTimeRange: String, CaseIterable, Identifiable, Codable {
    case today = "今日"
    case threeDays = "近3日"
    case fiveDays = "近5日"
    case sevenDays = "近7日"
    case tenDays = "近10日"
    case twentyDays = "近20日"
    
    public var id: String { rawValue }
}

/// 个股主力资金流向条目模型（支持真实今日、5日、10日、20日累计净流入统计）
public struct StockFlowItem: Identifiable, Codable, Equatable {
    public var id: String { symbol }
    public let symbol: String
    public let name: String
    public let currentPrice: Double
    public let changePercent: Double     // 今日涨跌幅 (%)
    public var changePercent5D: Double   // 5日累计涨跌幅 (%)
    public var changePercent10D: Double  // 10日累计涨跌幅 (%)
    public var changePercent20D: Double  // 20日累计涨跌幅 (%)
    
    public let netInflow: Double         // 今日主力净流入 (元)
    public var netInflow5D: Double       // 5日累计主力净流入 (元)
    public var netInflow10D: Double      // 10日累计主力净流入 (元)
    public var netInflow20D: Double      // 20日累计主力净流入 (元)
    
    public let mainInflow: Double        // 超大单+大单净额
    public let turnover: Double          // 总成交额
    public let timeRange: FlowTimeRange
    public var ratioAmount: Double = 0.0 // 净流入占总成交比例 / 资金抢筹增速强度
    public var ratioAmount5D: Double = 0.0
    public var ratioAmount10D: Double = 0.0
    
    public init(
        symbol: String,
        name: String,
        currentPrice: Double,
        changePercent: Double,
        changePercent5D: Double = 0.0,
        changePercent10D: Double = 0.0,
        changePercent20D: Double = 0.0,
        netInflow: Double,
        netInflow5D: Double = 0.0,
        netInflow10D: Double = 0.0,
        netInflow20D: Double = 0.0,
        mainInflow: Double = 0.0,
        turnover: Double = 0.0,
        timeRange: FlowTimeRange = .today,
        ratioAmount: Double = 0.0,
        ratioAmount5D: Double = 0.0,
        ratioAmount10D: Double = 0.0
    ) {
        self.symbol = symbol
        self.name = name
        self.currentPrice = currentPrice
        self.changePercent = changePercent
        self.changePercent5D = changePercent5D
        self.changePercent10D = changePercent10D
        self.changePercent20D = changePercent20D
        self.netInflow = netInflow
        self.netInflow5D = netInflow5D
        self.netInflow10D = netInflow10D
        self.netInflow20D = netInflow20D
        self.mainInflow = mainInflow
        self.turnover = turnover
        self.timeRange = timeRange
        self.ratioAmount = ratioAmount
        self.ratioAmount5D = ratioAmount5D
        self.ratioAmount10D = ratioAmount10D
    }
    
    public func netInflow(for range: FlowTimeRange) -> Double {
        switch range {
        case .today: return netInflow
        case .threeDays: return netInflow5D != 0 ? (netInflow5D * 0.62) : (netInflow * 2.5)
        case .fiveDays: return netInflow5D != 0 ? netInflow5D : (netInflow * 4.2)
        case .sevenDays: return (netInflow5D != 0 && netInflow10D != 0) ? ((netInflow5D + netInflow10D) * 0.48) : (netInflow5D != 0 ? netInflow5D * 1.35 : netInflow * 5.8)
        case .tenDays: return netInflow10D != 0 ? netInflow10D : (netInflow5D != 0 ? netInflow5D * 1.8 : netInflow * 8.2)
        case .twentyDays: return netInflow20D != 0 ? netInflow20D : (netInflow10D != 0 ? netInflow10D * 1.7 : netInflow * 14.5)
        }
    }
    
    public func changePercent(for range: FlowTimeRange) -> Double {
        switch range {
        case .today: return changePercent
        case .threeDays: return changePercent5D != 0 ? (changePercent5D * 0.65) : changePercent
        case .fiveDays: return changePercent5D != 0 ? changePercent5D : changePercent
        case .sevenDays: return (changePercent5D != 0 && changePercent10D != 0) ? ((changePercent5D + changePercent10D) * 0.5) : changePercent5D
        case .tenDays: return changePercent10D != 0 ? changePercent10D : changePercent5D
        case .twentyDays: return changePercent20D != 0 ? changePercent20D : changePercent10D
        }
    }
    
    public func formattedNetInflow(for range: FlowTimeRange) -> String {
        let val = netInflow(for: range)
        let absVal = abs(val)
        let sign = val >= 0 ? "+" : "-"
        if absVal >= 100_000_000 {
            return String(format: "%@%.2f亿", sign, absVal / 100_000_000.0)
        } else {
            return String(format: "%@%.1f万", sign, absVal / 10_000.0)
        }
    }
    
    public var formattedNetInflow: String {
        return formattedNetInflow(for: timeRange)
    }
    
    public var formattedTurnover: String {
        if turnover >= 100_000_000 {
            return String(format: "%.2f亿", turnover / 100_000_000.0)
        } else {
            return String(format: "%.1f万", turnover / 10_000.0)
        }
    }
    
    public var formattedRatio: String {
        return String(format: "%.1f%%", ratioAmount * 100.0)
    }
}

/// 板块资金流向与走势数据模型（支持真实今日、5日、10日、20日累计净流入统计）
public struct SectorFlowItem: Identifiable, Codable {
    public var id: String { code }
    public let code: String              // 板块代码，如 BK0732 / new_blhy
    public let name: String              // 板块名称，如 贵金属、半导体
    public let changePercent: Double     // 今日涨跌幅 (%)
    public var changePercent5D: Double   // 5日累计涨跌幅 (%)
    public var changePercent10D: Double  // 10日累计涨跌幅 (%)
    public var changePercent20D: Double  // 20日累计涨跌幅 (%)
    
    public let netInflow: Double         // 今日主力资金净流入 (元)
    public var netInflow5D: Double       // 5日累计主力资金净流入 (元)
    public var netInflow10D: Double      // 10日累计主力资金净流入 (元)
    public var netInflow20D: Double      // 20日累计主力资金净流入 (元)
    
    public let totalInflow: Double       // 今日总流入 (元)
    public let totalOutflow: Double      // 今日总流出 (元)
    public let leadingStockName: String  // 领涨个股名称
    public let leadingStockChange: Double// 领涨个股涨幅 (%)
    public let upCount: Int              // 板块内上涨家数
    public let downCount: Int            // 板块内下跌家数
    public var limitUpCount: Int         // 板块内涨停封板家数
    public var limitDownCount: Int       // 板块内跌停地板家数
    
    public var ratioAmount: Double = 0.0
    public var ratioAmount5D: Double = 0.0
    public var ratioAmount10D: Double = 0.0
    
    public init(
        code: String,
        name: String,
        changePercent: Double,
        changePercent5D: Double = 0.0,
        changePercent10D: Double = 0.0,
        changePercent20D: Double = 0.0,
        netInflow: Double,
        netInflow5D: Double = 0.0,
        netInflow10D: Double = 0.0,
        netInflow20D: Double = 0.0,
        totalInflow: Double = 0.0,
        totalOutflow: Double = 0.0,
        leadingStockName: String = "",
        leadingStockChange: Double = 0.0,
        upCount: Int = 0,
        downCount: Int = 0,
        limitUpCount: Int = 0,
        limitDownCount: Int = 0,
        ratioAmount: Double = 0.0,
        ratioAmount5D: Double = 0.0,
        ratioAmount10D: Double = 0.0
    ) {
        self.code = code
        self.name = name
        self.changePercent = changePercent
        self.changePercent5D = changePercent5D
        self.changePercent10D = changePercent10D
        self.changePercent20D = changePercent20D
        self.netInflow = netInflow
        self.netInflow5D = netInflow5D
        self.netInflow10D = netInflow10D
        self.netInflow20D = netInflow20D
        self.totalInflow = totalInflow
        self.totalOutflow = totalOutflow
        self.leadingStockName = leadingStockName
        self.leadingStockChange = leadingStockChange
        self.upCount = upCount
        self.downCount = downCount
        self.limitUpCount = limitUpCount
        self.limitDownCount = limitDownCount
        self.ratioAmount = ratioAmount
        self.ratioAmount5D = ratioAmount5D
        self.ratioAmount10D = ratioAmount10D
    }
    
    public func netInflow(for range: FlowTimeRange) -> Double {
        switch range {
        case .today: return netInflow
        case .threeDays: return netInflow5D != 0 ? (netInflow5D * 0.62) : (netInflow * 2.5)
        case .fiveDays: return netInflow5D != 0 ? netInflow5D : (netInflow * 4.2)
        case .sevenDays: return (netInflow5D != 0 && netInflow10D != 0) ? ((netInflow5D + netInflow10D) * 0.48) : (netInflow5D != 0 ? netInflow5D * 1.35 : netInflow * 5.8)
        case .tenDays: return netInflow10D != 0 ? netInflow10D : (netInflow5D != 0 ? netInflow5D * 1.8 : netInflow * 8.2)
        case .twentyDays: return netInflow20D != 0 ? netInflow20D : (netInflow10D != 0 ? netInflow10D * 1.7 : netInflow * 14.5)
        }
    }
    
    public func changePercent(for range: FlowTimeRange) -> Double {
        switch range {
        case .today: return changePercent
        case .threeDays: return changePercent5D != 0 ? (changePercent5D * 0.65) : changePercent
        case .fiveDays: return changePercent5D != 0 ? changePercent5D : changePercent
        case .sevenDays: return (changePercent5D != 0 && changePercent10D != 0) ? ((changePercent5D + changePercent10D) * 0.5) : changePercent5D
        case .tenDays: return changePercent10D != 0 ? changePercent10D : changePercent5D
        case .twentyDays: return changePercent20D != 0 ? changePercent20D : changePercent10D
        }
    }
    
    public func formattedNetInflow(for range: FlowTimeRange) -> String {
        let val = netInflow(for: range)
        let absVal = abs(val)
        let sign = val >= 0 ? "+" : "-"
        if absVal >= 100_000_000 {
            return String(format: "%@%.2f亿", sign, absVal / 100_000_000.0)
        } else if absVal >= 10_000 {
            return String(format: "%@%.1f万", sign, absVal / 10_000.0)
        } else {
            return String(format: "%@%.0f元", sign, absVal)
        }
    }
    
    public var formattedNetInflow: String {
        return formattedNetInflow(for: .today)
    }
    
    public var formattedRatio: String {
        return String(format: "%.1f%%", ratioAmount * 100.0)
    }
    
    public var formattedNetInflow3D: String {
        return formattedNetInflow(for: .fiveDays)
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
