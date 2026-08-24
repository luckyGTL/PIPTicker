import Foundation

/// 权威财经资讯来源渠道
public enum NewsSource: String, CaseIterable, Codable, Identifiable {
    case all = "全部"
    case cailianshe = "财联社"
    case wallstreet = "华尔街见闻"
    case sina = "新浪财经"
    case eastmoney = "东方财富"
    case bloomberg = "彭博/路透"
    case twitter = "推特/X"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .all: return "globe.asia.australia.fill"
        case .cailianshe: return "bolt.fill"
        case .wallstreet: return "chart.line.uptrend.xyaxis"
        case .sina: return "antenna.radiowaves.left.and.right"
        case .eastmoney: return "newspaper.fill"
        case .bloomberg: return "dollarsign.circle.fill"
        case .twitter: return "bubble.left.and.bubble.right.fill"
        }
    }
    
    public var themeColorHex: String {
        switch self {
        case .all: return "#3B82F6"
        case .cailianshe: return "#EF4444"
        case .wallstreet: return "#3B82F6"
        case .sina: return "#F59E0B"
        case .eastmoney: return "#EC4899"
        case .bloomberg: return "#8B5CF6"
        case .twitter: return "#0EA5E9"
        }
    }
}

/// 资讯分类频道（包含独立推特专栏）
public enum NewsCategory: String, CaseIterable, Codable, Identifiable {
    case all = "全部快讯"
    case breaking = "重磅突发"
    case aStock = "A股公司"
    case twitter = "推特专栏"
    case global = "全球宏观"
    case watchlist = "自选关联"
    
    public var id: String { rawValue }
    
    public var iconName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .breaking: return "flame.fill"
        case .aStock: return "chart.bar.xaxis"
        case .twitter: return "bubble.left.and.bubble.right.fill"
        case .global: return "globe"
        case .watchlist: return "star.fill"
        }
    }
}

/// 推特大V分类筛选
public enum TwitterVCategory: String, CaseIterable, Identifiable {
    case all = "全部博主"
    case hot = "🔥 爆款网红大V"
    case tech = "🤖 芯片与科技巨头"
    case giants = "👑 华尔街对冲巨鳄"
    case policy = "🏛️ 央行与监管"
    
    public var id: String { rawValue }
}

/// 资讯重要等级
public enum NewsImportance: Int, Codable, Comparable {
    case normal = 0
    case important = 1
    case breaking = 2
    
    public static func < (lhs: NewsImportance, rhs: NewsImportance) -> Bool {
        return lhs.rawValue < rhs.rawValue
    }
}

/// AI 财经情绪分析模型 (利好 / 利空 / 中性)
public enum NewsSentiment: String, Codable {
    case bullish = "利好"
    case bearish = "利空"
    case neutral = "中性"
    
    public var iconName: String {
        switch self {
        case .bullish: return "arrow.up.circle.fill"
        case .bearish: return "arrow.down.circle.fill"
        case .neutral: return "minus.circle.fill"
        }
    }
    
    public var themeColorHex: String {
        switch self {
        case .bullish: return "#EF4444" // 红色利好
        case .bearish: return "#10B981" // 绿色利空
        case .neutral: return "#6B7280" // 灰色中性
        }
    }
}

/// 命中的自选股与板块匹配模型
public struct MatchedStockInfo: Identifiable, Codable, Hashable {
    public var id: String { symbol.fullCode }
    public let symbol: StockSymbol
    public let matchType: String // "自选个股" / "关联板块"
    public let conceptName: String // "光纤光缆" / "个股直接相关" / "CPO光模块"
    public let reason: String // 匹配原因详情
    
    public init(symbol: StockSymbol, matchType: String, conceptName: String, reason: String = "") {
        self.symbol = symbol
        self.matchType = matchType
        self.conceptName = conceptName
        self.reason = reason
    }
}

/// 7x24 实时财经快讯数据模型
public struct NewsItem: Identifiable, Codable, Hashable {
    public let id: String
    public var title: String
    public var content: String
    public var source: NewsSource
    public var category: NewsCategory
    public var importance: NewsImportance
    public var sentiment: NewsSentiment
    public var publishedAt: Date
    public var tags: [String]
    public var relatedStockCodes: [String] // 提取出的 6 位股票代码
    public var relatedStockNames: [String] // 提取出的股票名称
    public var url: String?
    
    // AI 深度金融语义研判字段
    public var aiFactorSummary: String? // 如 "🚀 业绩高增 · 签订大单" 或 "⚠️ 股东减持 · 监管调查"
    public var aiTags: [String]         // 如 ["光通信", "业绩预增", "大额订单"]
    public var matchedWatchlistStocks: [MatchedStockInfo] // 本条快讯命中的全部自选股清单
    
    // 推特/X 专属博主作者字段
    public var authorHandle: String? // 如 @unusual_whales, @NVIDIA, @WarrenBuffett
    public var authorName: String?   // 如 "Unusual Whales 异动", "黄仁勋 / 英伟达", "沃伦·巴菲特"
    public var authorCategory: String? // "hot", "tech", "giants", "policy"
    
    public init(
        id: String,
        title: String = "",
        content: String,
        source: NewsSource,
        category: NewsCategory = .all,
        importance: NewsImportance = .normal,
        sentiment: NewsSentiment? = nil,
        publishedAt: Date = Date(),
        tags: [String] = [],
        relatedStockCodes: [String] = [],
        relatedStockNames: [String] = [],
        url: String? = nil,
        aiFactorSummary: String? = nil,
        aiTags: [String] = [],
        matchedWatchlistStocks: [MatchedStockInfo] = [],
        authorHandle: String? = nil,
        authorName: String? = nil,
        authorCategory: String? = nil
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.content = content.trimmingCharacters(in: .whitespacesAndNewlines)
        self.source = source
        self.category = category
        self.importance = importance
        self.publishedAt = publishedAt
        self.tags = tags
        self.relatedStockCodes = relatedStockCodes
        self.relatedStockNames = relatedStockNames
        self.url = url
        self.matchedWatchlistStocks = matchedWatchlistStocks
        self.authorHandle = authorHandle
        self.authorName = authorName
        self.authorCategory = authorCategory
        
        if let sent = sentiment, let summary = aiFactorSummary {
            self.sentiment = sent
            self.aiFactorSummary = summary
            self.aiTags = aiTags
        } else {
            let aiResult = NewsItem.analyzeAISentimentAndFactors(title: title, content: content)
            self.sentiment = sentiment ?? aiResult.sentiment
            self.aiFactorSummary = aiFactorSummary ?? aiResult.factorSummary
            self.aiTags = !aiTags.isEmpty ? aiTags : aiResult.aiTags
        }
    }
    
    public var displayTitle: String {
        if !title.isEmpty {
            return title
        }
        let clean = content.replacingOccurrences(of: "\n", with: " ")
        if clean.count <= 45 {
            return clean
        }
        return String(clean.prefix(45)) + "..."
    }
    
    public var timeAgoText: String {
        let now = Date()
        let interval = now.timeIntervalSince(publishedAt)
        
        if interval < 60 {
            return "刚刚"
        } else if interval < 3600 {
            let minutes = Int(interval / 60)
            return "\(minutes)分钟前"
        } else if interval < 86400 {
            let hours = Int(interval / 3600)
            return "\(hours)小时前"
        } else {
            let days = Int(interval / 86400)
            return "\(days)天前"
        }
    }
    
    public var formattedClockTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: publishedAt)
    }
    
    /// AI 深度多因子金融语义研判模型（提取驱动因子、情绪评分与结构化标签）
    public static func analyzeAISentimentAndFactors(title: String, content: String) -> (sentiment: NewsSentiment, factorSummary: String, aiTags: [String]) {
        let text = title + " " + content
        
        // 1. 利好驱动因子库与权重
        let bullishFactors: [(keywords: [String], tag: String, weight: Int)] = [
            (["净利润大增", "净利暴增", "同比增长", "扭亏为盈", "业绩预增", "业绩大幅增长", "超预期", "盈利大增", "翻倍"], "业绩高增", 3),
            (["中标", "大单", "签订重大合同", "获订单", "大额合同", "框架协议", "签署战略合作", "斩获大单"], "签订大单", 3),
            (["增持", "回购注销", "斥资回购", "高管增持", "股权激励", "重组获批", "注入优质资产"], "回购增持", 2),
            (["突破", "量产", "自主可控", "研发成功", "取得专利", "获批上市", "打破垄断", "首发成功"], "重大突破", 2),
            (["政策支持", "补贴支持", "专项资金", "国家战略", "降准降息", "鼓励发展", "税收优惠"], "政策利好", 2),
            (["主力资金净流入", "机构大额买入", "涨停突破", "上调评级", "买入评级", "目标价上调"], "资金抢筹", 2),
            (["出海加速", "全球交付", "海外大单", "市占率第一", "行业龙头"], "出海扩张", 1)
        ]
        
        // 2. 利空风险因子库与权重
        let bearishFactors: [(keywords: [String], tag: String, weight: Int)] = [
            (["净利润下滑", "亏损扩大", "大幅亏损", "同比下降", "业绩预减", "业绩变脸", "不及预期", "大幅下滑"], "业绩预减", 3),
            (["立案调查", "行政处罚", "违规被查", "通报批评", "警示函", "监管问询", "公开谴责"], "监管立案", 3),
            (["减持", "清仓减持", "套现", "大股东减持", "拟减持", "大宗折价", "折价抛售"], "股东减持", 3),
            (["退市风险", "终止上市", "债务违约", "破产重整", "破产清算", "无法偿还", "暴雷"], "退市违约", 4),
            (["重大诉讼", "仲裁", "银行账户冻结", "股权冻结", "查封资产", "强制执行"], "诉讼冻结", 2),
            (["制裁", "加征关税", "贸易摩擦", "出口管制", "实体清单", "限制进口"], "外部制裁", 2),
            (["跌停", "闪崩", "重组失败", "终止收购", "终止重组", "质押平仓", "强平"], "重组终止", 2)
        ]
        
        var bullishScore = 0
        var detectedBullishTags: [String] = []
        for factor in bullishFactors {
            for kw in factor.keywords {
                if text.contains(kw) {
                    bullishScore += factor.weight
                    if !detectedBullishTags.contains(factor.tag) {
                        detectedBullishTags.append(factor.tag)
                    }
                    break
                }
            }
        }
        
        var bearishScore = 0
        var detectedBearishTags: [String] = []
        for factor in bearishFactors {
            for kw in factor.keywords {
                if text.contains(kw) {
                    bearishScore += factor.weight
                    if !detectedBearishTags.contains(factor.tag) {
                        detectedBearishTags.append(factor.tag)
                    }
                    break
                }
            }
        }
        
        let sentiment: NewsSentiment
        let factorSummary: String
        var aiTags: [String] = []
        
        if bullishScore > bearishScore && bullishScore >= 2 {
            sentiment = .bullish
            let topTags = Array(detectedBullishTags.prefix(2))
            factorSummary = "🚀 " + topTags.joined(separator: " · ")
            aiTags = detectedBullishTags
        } else if bearishScore > bullishScore && bearishScore >= 2 {
            sentiment = .bearish
            let topTags = Array(detectedBearishTags.prefix(2))
            factorSummary = "⚠️ " + topTags.joined(separator: " · ")
            aiTags = detectedBearishTags
        } else {
            sentiment = .neutral
            factorSummary = "📌 行业动态"
            aiTags = ["常规资讯"]
        }
        
        return (sentiment, factorSummary, aiTags)
    }
    
    /// AI 自然语言金融情绪分析器 (保留兼容易用性)
    public static func analyzeSentiment(title: String, content: String) -> NewsSentiment {
        return analyzeAISentimentAndFactors(title: title, content: content).sentiment
    }
}
