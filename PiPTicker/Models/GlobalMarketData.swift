import Foundation

/// 全球主要大盘指数数据模型
public struct GlobalIndexQuote: Identifiable, Codable {
    public var id: String { symbol }
    public let symbol: String        // 如 .DJI, .IXIC, .INX, ^KS11, ^KQ11
    public let name: String          // 如 道琼斯、纳斯达克、标普500、韩国KOSPI、韩国KOSDAQ
    public let region: String        // 如 美股、韩股
    public let currentPrice: Double  // 当前点位
    public let changeAmount: Double  // 涨跌点数
    public let changePercent: Double // 涨跌幅 (%)
    public let statusText: String    // 交易状态 (如 交易中、已收盘、盘前)
    public let updateTime: String    // 更新时间
    
    public init(
        symbol: String,
        name: String,
        region: String,
        currentPrice: Double,
        changeAmount: Double,
        changePercent: Double,
        statusText: String = "已收盘",
        updateTime: String = ""
    ) {
        self.symbol = symbol
        self.name = name
        self.region = region
        self.currentPrice = currentPrice
        self.changeAmount = changeAmount
        self.changePercent = changePercent
        self.statusText = statusText
        self.updateTime = updateTime
    }
}

/// 美股龙头股票行情（含盘中价与盘前/盘后实时数据）
public struct USStockQuote: Identifiable, Codable {
    public var id: String { symbol }
    public let symbol: String            // 如 NVDA, AAPL, TSLA, MSFT
    public let nameCn: String            // 如 英伟达、苹果、特斯拉
    public let nameEn: String            // 如 Nvidia Corporation
    public let regularPrice: Double      // 盘中常规最新价 ($)
    public let regularChange: Double     // 盘中涨跌额 ($)
    public let regularChangePercent: Double // 盘中涨跌幅 (%)
    public let prePostPrice: Double?     // 盘前/盘后实时价 ($)
    public let prePostChangePercent: Double? // 盘前/盘后涨跌幅 (%)
    public let marketCapFormatted: String // 市值 (如 3.25万亿美元)
    public let volumeFormatted: String   // 成交量/额
    public let sectorCategory: String    // 所属板块 (如 半导体芯片、新能源车、科技云)
    public let isPrePostActive: Bool     // 当前是否处于盘前/盘后交易时段
    
    public init(
        symbol: String,
        nameCn: String,
        nameEn: String = "",
        regularPrice: Double,
        regularChange: Double,
        regularChangePercent: Double,
        prePostPrice: Double? = nil,
        prePostChangePercent: Double? = nil,
        marketCapFormatted: String = "",
        volumeFormatted: String = "",
        sectorCategory: String = "科技",
        isPrePostActive: Bool = false
    ) {
        self.symbol = symbol
        self.nameCn = nameCn
        self.nameEn = nameEn
        self.regularPrice = regularPrice
        self.regularChange = regularChange
        self.regularChangePercent = regularChangePercent
        self.prePostPrice = prePostPrice
        self.prePostChangePercent = prePostChangePercent
        self.marketCapFormatted = marketCapFormatted
        self.volumeFormatted = volumeFormatted
        self.sectorCategory = sectorCategory
        self.isPrePostActive = isPrePostActive
    }
}

/// 美股行业板块涨跌数据模型（含常规涨跌与盘前盘后涨跌）
public struct USSectorQuote: Identifiable, Codable {
    public var id: String { name }
    public let name: String              // 如 半导体与硬件、软件与互联网、新能源汽车、生物制药
    public let changePercent: Double     // 今日常规涨跌幅 (%)
    public let prePostChangePercent: Double? // 盘前/盘后实时涨跌幅 (%)
    public let leadingStock: String      // 领涨龙头 (如 英伟达 NVDA +3.2%)
    public let iconName: String          // SF Symbols 图标
    
    public init(
        name: String,
        changePercent: Double,
        prePostChangePercent: Double? = nil,
        leadingStock: String,
        iconName: String = "chart.bar.fill"
    ) {
        self.name = name
        self.changePercent = changePercent
        self.prePostChangePercent = prePostChangePercent
        self.leadingStock = leadingStock
        self.iconName = iconName
    }
}

/// 韩国股市龙头股票行情模型
public struct KoreaStockQuote: Identifiable, Codable {
    public var id: String { symbol }
    public let symbol: String            // 如 005930.KS, 000660.KS
    public let nameCn: String            // 如 三星电子、SK海力士、现代汽车
    public let nameKr: String            // 韩文原名
    public let currentPrice: Double      // 当前价格 (韩元 ₩)
    public let changeAmount: Double      // 涨跌额 (₩)
    public let changePercent: Double     // 涨跌幅 (%)
    public let industry: String          // 所属行业
    
    public init(
        symbol: String,
        nameCn: String,
        nameKr: String = "",
        currentPrice: Double,
        changeAmount: Double,
        changePercent: Double,
        industry: String = ""
    ) {
        self.symbol = symbol
        self.nameCn = nameCn
        self.nameKr = nameKr
        self.currentPrice = currentPrice
        self.changeAmount = changeAmount
        self.changePercent = changePercent
        self.industry = industry
    }
    
    public var formattedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        let numStr = formatter.string(from: NSNumber(value: currentPrice)) ?? "\(currentPrice)"
        return "₩\(numStr)"
    }
}
