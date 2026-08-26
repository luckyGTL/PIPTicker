import Foundation
import Combine

/// 全球核心市场行情调度管理中心（官方美股盘前盘后秒级撮合通道 + 韩国股市大盘与龙头股）
public final class GlobalMarketManager: ObservableObject {
    public static let shared = GlobalMarketManager()
    
    // 全球主要大盘指数 (美股三大指数、韩国KOSPI/KOSDAQ)
    @Published public var globalIndices: [GlobalIndexQuote] = []
    
    // 美股科技巨头与核心龙头股（含常规价格与盘前/盘后实时交易数据、包含美光、闪迪、海力士、英伟达等）
    @Published public var usLeaderStocks: [USStockQuote] = []
    
    // 美股主要行业板块表现（含常规与盘前盘后实时动态涨势）
    @Published public var usSectors: [USSectorQuote] = []
    
    // 韩国股市核心龙头股票
    @Published public var koreaLeaderStocks: [KoreaStockQuote] = []
    
    // 状态控制
    @Published public var isRefreshing: Bool = false
    @Published public var lastUpdated: Date = Date()
    
    private var refreshTimer: Timer?
    private let urlSession: URLSession
    private let gbkEncoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
    )
    
    // 固定的韩国指数顺序（保持 KOSPI 综合指数第一，KOSDAQ 第二，刷新永不跳变颠倒）
    private let koreaIndexOrder = ["^KS11", "^KQ11"]
    
    // 固定的美股指数顺序（道指、纳指、标普）
    private let usIndexOrder = [".DJI", ".IXIC", ".INX"]
    
    // 固定的韩国核心龙头股排名顺序
    private let koreaStockOrder = [
        "005930.KS", // 三星电子
        "000660.KS", // SK海力士
        "005380.KS", // 现代汽车
        "373220.KS", // LG新能源
        "000270.KS", // 起亚汽车
        "068270.KS", // 赛尔群
        "035420.KS", // NAVER
        "005490.KS"  // 浦项制铁
    ]
    
    // 固定的美股龙头股排序（按科技/存储核心权重排序，包含美光、闪迪、海力士SKHY、英伟达等）
    private let usStockOrder = [
        "NVDA", "MU", "WDC", "SKHY", "TSLA", "AAPL", "MSFT", "GOOGL", "AMZN", "META", "TSM", "AVGO", "AMD", "QCOM", "INTC", "ARM", "LLY", "NFLX"
    ]
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 4.0
        self.urlSession = URLSession(configuration: config)
    }
    
    public func start() {
        fetchAllGlobalQuotes()
        startTimer()
    }
    
    public func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }
    
    private func startTimer() {
        refreshTimer?.invalidate()
        // 4 秒极速轮询，实现美股盘前盘后与大盘跳动实时可见
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 4.0, repeats: true) { [weak self] _ in
            self?.fetchAllGlobalQuotes()
        }
    }
    
    // MARK: - 综合抓取（确定性排序，解决刷新时位置颠倒跳变问题）
    
    public func fetchAllGlobalQuotes() {
        guard !isRefreshing else { return }
        isRefreshing = true
        
        let dispatchGroup = DispatchGroup()
        var fetchedUSIndices: [GlobalIndexQuote] = []
        var fetchedUSStocks: [USStockQuote] = []
        var fetchedUSSectors: [USSectorQuote] = []
        var fetchedKoreaIndices: [GlobalIndexQuote] = []
        var fetchedKoreaStocks: [KoreaStockQuote] = []
        
        // 1. 抓取美股指数与龙头股盘前盘后数据（秒级高速实时通道，涵盖美光、闪迪/西数等）
        dispatchGroup.enter()
        fetchRealtimeUSQuotes { indices, stocks, sectors in
            fetchedUSIndices = indices
            fetchedUSStocks = stocks
            fetchedUSSectors = sectors
            dispatchGroup.leave()
        }
        
        // 2. 抓取韩国股市指数与龙头股行情 (含三星、SK海力士)
        dispatchGroup.enter()
        fetchKoreaQuotes { kIndices, kStocks in
            fetchedKoreaIndices = kIndices
            fetchedKoreaStocks = kStocks
            dispatchGroup.leave()
        }
        
        dispatchGroup.notify(queue: .global(qos: .userInitiated)) { [weak self] in
            guard let self = self else { return }
            
            // 确定性排序美股指数
            let sortedUSIndices = fetchedUSIndices.sorted { a, b in
                let idxA = self.usIndexOrder.firstIndex(of: a.symbol) ?? 99
                let idxB = self.usIndexOrder.firstIndex(of: b.symbol) ?? 99
                return idxA < idxB
            }
            
            // 确定性排序韩国指数 (KOSPI 综合指数固定在左，KOSDAQ 固定在右，绝对不乱跳)
            let sortedKoreaIndices = fetchedKoreaIndices.sorted { a, b in
                let idxA = self.koreaIndexOrder.firstIndex(of: a.symbol) ?? 99
                let idxB = self.koreaIndexOrder.firstIndex(of: b.symbol) ?? 99
                return idxA < idxB
            }
            
            // 确定性排序美股龙头个股
            let sortedUSStocks = fetchedUSStocks.sorted { a, b in
                let idxA = self.usStockOrder.firstIndex(of: a.symbol) ?? 99
                let idxB = self.usStockOrder.firstIndex(of: b.symbol) ?? 99
                return idxA < idxB
            }
            
            // 确定性排序韩国龙头股
            let sortedKoreaStocks = fetchedKoreaStocks.sorted { a, b in
                let idxA = self.koreaStockOrder.firstIndex(of: a.symbol) ?? 99
                let idxB = self.koreaStockOrder.firstIndex(of: b.symbol) ?? 99
                return idxA < idxB
            }
            
            let finalGlobalIndices = sortedUSIndices + sortedKoreaIndices
            
            DispatchQueue.main.async {
                self.globalIndices = finalGlobalIndices
                self.usLeaderStocks = sortedUSStocks
                self.usSectors = fetchedUSSectors
                self.koreaLeaderStocks = sortedKoreaStocks
                self.lastUpdated = Date()
                self.isRefreshing = false
            }
        }
    }
    
    // MARK: - 官方美股盘前盘后实时数据直连（秒级动态跳动，涵盖美光MU、闪迪WDC、海力士SKHY、英伟达NVDA等全量龙头与十大核心板块）
    
    private func fetchRealtimeUSQuotes(completion: @escaping ([GlobalIndexQuote], [USStockQuote], [USSectorQuote]) -> Void) {
        let queryList = "gb_dji,gb_ixic,gb_inx,gb_soxx,gb_xlk,gb_xly,gb_xlc,gb_xlv,gb_xle,gb_xlf,gb_xli,gb_xlp,gb_xrt,gb_igv,gb_smh,gb_nvda,gb_mu,gb_wdc,gb_skhy,gb_tsla,gb_aapl,gb_msft,gb_googl,gb_amzn,gb_meta,gb_tsm,gb_avgo,gb_amd,gb_qcom,gb_intc,gb_arm,gb_lly,gb_nflx,gb_pltr,gb_jpm,gb_gs,gb_xom,gb_cvx,gb_ba,gb_ge,gb_wmt,gb_cost,gb_coin,gb_mstr"
        let urlStr = "http://hq.sinajs.cn/list=\(queryList)"
        guard let url = URL(string: urlStr) else {
            completion([], [], [])
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        request.setValue("https://finance.sina.com.cn", forHTTPHeaderField: "Referer")
        
        urlSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self, let data = data, error == nil else {
                completion([], [], [])
                return
            }
            
            DispatchQueue.global(qos: .userInitiated).async {
                let text = String(data: data, encoding: self.gbkEncoding) ?? String(data: data, encoding: .utf8) ?? ""
                let lines = text.components(separatedBy: ";")
                
                var indices: [GlobalIndexQuote] = []
                var stocks: [USStockQuote] = []
                var sectorETFs: [String: (regularPct: Double, prePostPct: Double?)] = [:]
                
                for line in lines {
                    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !trimmed.isEmpty, let equalIdx = trimmed.firstIndex(of: "=") else { continue }
                    
                    let varName = String(trimmed[..<equalIdx]).trimmingCharacters(in: .whitespaces)
                    let rawVal = String(trimmed[trimmed.index(after: equalIdx)...])
                        .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r\t;"))
                    let parts = rawVal.components(separatedBy: ",")
                    // 安全容错：指数与部分行业ETF返回字段数在 10~26 之间，支持 >= 3 正常解析常规价与涨跌幅
                    guard parts.count >= 3 else { continue }
                    
                    let name = parts[0].trimmingCharacters(in: .whitespaces)
                    let regularPrice = Double(parts[1]) ?? 0.0
                    let regularChangePct = Double(parts[2]) ?? 0.0
                    let tradeTime = parts.count > 3 ? parts[3].trimmingCharacters(in: .whitespaces) : ""
                    let regularChangeAmt = parts.count > 4 ? (Double(parts[4]) ?? 0.0) : 0.0
                    let totalMarketCapStr = parts.count > 12 ? parts[12].trimmingCharacters(in: .whitespaces) : ""
                    
                    // 盘前 / 盘后实时数据字段 (parts[21]: 盘前/盘后价格, parts[22]: 盘前/盘后涨跌幅, parts[24]: 美东时间)
                    var prePostPriceVal: Double? = nil
                    var prePostChangePctVal: Double? = nil
                    var prePostTimeStr = ""
                    if parts.count >= 25 {
                        prePostPriceVal = Double(parts[21])
                        prePostChangePctVal = Double(parts[22])
                        prePostTimeStr = parts[24].trimmingCharacters(in: .whitespaces)
                    }
                    
                    let isPrePostActive = (prePostPriceVal != nil && prePostPriceVal! > 0)
                    let finalPrePostPrice = isPrePostActive ? prePostPriceVal : nil
                    let finalPrePostChangePct: Double? = {
                        guard isPrePostActive, let p = prePostPriceVal else { return nil }
                        if let pct = prePostChangePctVal, abs(pct) > 0.0001 {
                            return pct
                        } else if regularPrice > 0 {
                            return ((p - regularPrice) / regularPrice) * 100.0
                        }
                        return nil
                    }()
                    
                    let cleanCode = varName
                        .replacingOccurrences(of: "var ", with: "")
                        .replacingOccurrences(of: "var", with: "")
                        .replacingOccurrences(of: "hq_str_gb_", with: "")
                        .replacingOccurrences(of: "gb_", with: "")
                        .trimmingCharacters(in: .whitespacesAndNewlines)
                        .lowercased()
                    
                    if cleanCode == "dji" {
                        indices.append(GlobalIndexQuote(
                            symbol: ".DJI",
                            name: "道琼斯工业指数",
                            region: "美股",
                            currentPrice: regularPrice,
                            changeAmount: regularChangeAmt,
                            changePercent: regularChangePct,
                            statusText: isPrePostActive ? "盘前/后" : "常规时段",
                            updateTime: isPrePostActive ? prePostTimeStr : tradeTime
                        ))
                    } else if cleanCode == "ixic" {
                        indices.append(GlobalIndexQuote(
                            symbol: ".IXIC",
                            name: "纳斯达克综合指数",
                            region: "美股",
                            currentPrice: regularPrice,
                            changeAmount: regularChangeAmt,
                            changePercent: regularChangePct,
                            statusText: isPrePostActive ? "盘前/后" : "常规时段",
                            updateTime: isPrePostActive ? prePostTimeStr : tradeTime
                        ))
                    } else if cleanCode == "inx" {
                        indices.append(GlobalIndexQuote(
                            symbol: ".INX",
                            name: "标普500指数",
                            region: "美股",
                            currentPrice: regularPrice,
                            changeAmount: regularChangeAmt,
                            changePercent: regularChangePct,
                            statusText: isPrePostActive ? "盘前/后" : "常规时段",
                            updateTime: isPrePostActive ? prePostTimeStr : tradeTime
                        ))
                    } else if ["soxx", "smh", "xlk", "xly", "xlc", "xlv", "xle", "xlf", "xli", "xlp", "xrt", "igv"].contains(cleanCode) {
                        // 行业ETF官方直连行情
                        sectorETFs[cleanCode] = (regularPct: regularChangePct, prePostPct: finalPrePostChangePct)
                    } else {
                        let symbolClean = cleanCode.uppercased()
                        let meta = self.getUSStockMeta(symbol: symbolClean, defaultName: name)
                        
                        var capFormatted = ""
                        if let cap = Double(totalMarketCapStr), cap > 0 {
                            capFormatted = String(format: "$%.2fB", cap / 1_000_000_000.0)
                        }
                        
                        let quote = USStockQuote(
                            symbol: symbolClean,
                            nameCn: meta.cn,
                            nameEn: name,
                            regularPrice: regularPrice,
                            regularChange: regularChangeAmt,
                            regularChangePercent: regularChangePct,
                            prePostPrice: finalPrePostPrice,
                            prePostChangePercent: finalPrePostChangePct,
                            marketCapFormatted: capFormatted,
                            volumeFormatted: prePostTimeStr.isEmpty ? tradeTime : prePostTimeStr,
                            sectorCategory: meta.sector,
                            isPrePostActive: isPrePostActive
                        )
                        stocks.append(quote)
                    }
                }
                
                // 实时计算美股前十大核心行业板块表现 (融合官方行业 ETF 与实时成分股盘前盘后深度撮合行情)
                let sectors = self.calculateUSSectorsFromStocks(stocks, sectorETFs: sectorETFs)
                completion(indices, stocks, sectors)
            }
        }.resume()
    }
    
    private func calculateUSSectorsFromStocks(_ stocks: [USStockQuote], sectorETFs: [String: (regularPct: Double, prePostPct: Double?)]) -> [USSectorQuote] {
        func avgPct(_ list: [USStockQuote]) -> Double {
            guard !list.isEmpty else { return 0.0 }
            return list.map { $0.regularChangePercent }.reduce(0, +) / Double(list.count)
        }
        func avgPrePost(_ list: [USStockQuote]) -> Double? {
            let active = list.compactMap { $0.prePostChangePercent }
            guard !active.isEmpty else { return nil }
            return active.reduce(0, +) / Double(active.count)
        }
        
        func buildSector(name: String, etfKey: String, constituentSymbols: [String], iconName: String) -> USSectorQuote {
            let constituentStocks = stocks.filter { constituentSymbols.contains($0.symbol) }
            let etfData = sectorETFs[etfKey]
            
            let regularChange = etfData?.regularPct ?? avgPct(constituentStocks)
            let prePostChange = etfData?.prePostPct ?? avgPrePost(constituentStocks)
            
            // 领涨龙头（优先使用当前实时有效涨跌幅）
            let bestStock = constituentStocks.max(by: {
                ($0.prePostChangePercent ?? $0.regularChangePercent) < ($1.prePostChangePercent ?? $1.regularChangePercent)
            })
            
            let leadingText: String
            if let best = bestStock {
                let bestPct = best.prePostChangePercent ?? best.regularChangePercent
                leadingText = "\(best.symbol) (\(String(format: "%+.1f%%", bestPct)))"
            } else {
                leadingText = etfKey.uppercased()
            }
            
            return USSectorQuote(
                name: name,
                changePercent: regularChange,
                prePostChangePercent: prePostChange,
                leadingStock: leadingText,
                iconName: iconName
            )
        }
        
        var sectorList: [USSectorQuote] = [
            buildSector(name: "半导体与存储芯片", etfKey: "soxx", constituentSymbols: ["NVDA", "TSM", "AVGO", "AMD", "QCOM", "MU", "WDC", "SKHY", "INTC", "ARM"], iconName: "cpu.fill"),
            buildSector(name: "科技巨头与云计算", etfKey: "xlk", constituentSymbols: ["AAPL", "MSFT", "GOOGL", "AMZN", "META"], iconName: "laptopcomputer"),
            buildSector(name: "AI与企业级软件", etfKey: "igv", constituentSymbols: ["PLTR", "MSFT", "GOOGL", "META", "AMZN"], iconName: "brain.head.profile"),
            buildSector(name: "新能源汽车与智驾", etfKey: "xly", constituentSymbols: ["TSLA"], iconName: "car.fill"),
            buildSector(name: "生物医药与新药创新", etfKey: "xlv", constituentSymbols: ["LLY"], iconName: "cross.case.fill"),
            buildSector(name: "金融科技与数字资产", etfKey: "coin", constituentSymbols: ["COIN", "MSTR"], iconName: "bitcoinsign.circle.fill"),
            buildSector(name: "银行与华尔街投行", etfKey: "xlf", constituentSymbols: ["JPM", "GS"], iconName: "building.columns.fill"),
            buildSector(name: "通信服务与流媒体", etfKey: "xlc", constituentSymbols: ["NFLX", "AMZN", "GOOGL", "META"], iconName: "play.tv.fill"),
            buildSector(name: "能源石油与大宗商品", etfKey: "xle", constituentSymbols: ["XOM", "CVX"], iconName: "flame.circle.fill"),
            buildSector(name: "工业制造与航空航天", etfKey: "xli", constituentSymbols: ["BA", "GE"], iconName: "airplane.circle.fill")
        ]
        
        // 动态按照当前实时涨跌幅（盘前/盘后优先，否则常规交易涨跌）降序排列，确保呈现美股实时 Top 10 板块
        sectorList.sort { s1, s2 in
            let p1 = s1.prePostChangePercent ?? s1.changePercent
            let p2 = s2.prePostChangePercent ?? s2.changePercent
            return p1 > p2
        }
        
        return sectorList
    }
    
    private func getUSStockMeta(symbol: String, defaultName: String) -> (cn: String, sector: String) {
        switch symbol {
        case "NVDA": return ("英伟达", "AI算力/GPU龙头")
        case "MU": return ("美光科技", "HBM3E/存储芯片龙头")
        case "WDC": return ("闪迪/西数", "NAND闪存/固态存储")
        case "SKHY": return ("SK海力士", "HBM3E/存储芯片霸主")
        case "TSLA": return ("特斯拉", "新能源汽车/智驾")
        case "AAPL": return ("苹果", "消费电子")
        case "MSFT": return ("微软", "企业云/AI平台")
        case "GOOGL": return ("谷歌", "人工智能/搜索引擎")
        case "AMZN": return ("亚马逊", "电商/云服务")
        case "META": return ("Meta", "开源AI/社交网络")
        case "TSM": return ("台积电", "晶圆代工龙头")
        case "AVGO": return ("博通", "通信芯片/AI定制")
        case "AMD": return ("AMD", "CPU/AI芯片")
        case "QCOM": return ("高通", "移动通信芯片")
        case "INTC": return ("英特尔", "CPU/半导体制造")
        case "ARM": return ("ARM控股", "芯片架构设计")
        case "LLY": return ("礼来", "减肥药/生物制药")
        case "NFLX": return ("奈飞", "全球流媒体")
        case "PLTR": return ("Palantir", "AI企业软件/大数据")
        case "JPM": return ("摩根大通", "全能银行/金融巨头")
        case "GS": return ("高盛", "华尔街顶级投行")
        case "XOM": return ("埃克森美孚", "全球石油综合巨头")
        case "CVX": return ("雪佛龙", "石油天然气龙头")
        case "BA": return ("波音", "商业航空/军工防务")
        case "GE": return ("通用电气", "航空发动机/工业制造")
        case "WMT": return ("沃尔玛", "全球零售连锁")
        case "COST": return ("开市客", "会员制仓储超市")
        case "COIN": return ("Coinbase", "加密资产交易所")
        case "MSTR": return ("微策投资", "比特币储备/商业智能")
        default: return (defaultName, "美股核心")
        }
    }
    
    // MARK: - 韩国股市核心标的抓取
    
    private func fetchKoreaQuotes(completion: @escaping ([GlobalIndexQuote], [KoreaStockQuote]) -> Void) {
        let targets = [
            (sym: "^KS11", name: "^KS11", isIndex: true, cn: "韩国综合指数 (KOSPI)", kr: "코스피", ind: "韩国大盘"),
            (sym: "^KQ11", name: "^KQ11", isIndex: true, cn: "韩国科斯达克 (KOSDAQ)", kr: "코스닥", ind: "韩国中小盘"),
            (sym: "005930.KS", name: "005930.KS", isIndex: false, cn: "三星电子", kr: "삼성전자", ind: "半导体/消费电子"),
            (sym: "000660.KS", name: "000660.KS", isIndex: false, cn: "SK海力士", kr: "SK하이닉스", ind: "HBM存储芯片龙头"),
            (sym: "005380.KS", name: "005380.KS", isIndex: false, cn: "现代汽车", kr: "현대차", ind: "汽车整车"),
            (sym: "373220.KS", name: "373220.KS", isIndex: false, cn: "LG新能源", kr: "LG에너지솔루션", ind: "动力电池"),
            (sym: "000270.KS", name: "000270.KS", isIndex: false, cn: "起亚汽车", kr: "기아", ind: "汽车整车"),
            (sym: "068270.KS", name: "068270.KS", isIndex: false, cn: "赛尔群", kr: "셀트리온", ind: "生物制药"),
            (sym: "035420.KS", name: "035420.KS", isIndex: false, cn: "NAVER", kr: "네이버", ind: "互联网平台"),
            (sym: "005490.KS", name: "005490.KS", isIndex: false, cn: "浦项制铁", kr: "POSCO홀딩스", ind: "钢铁与资源")
        ]
        
        let dispatchGroup = DispatchGroup()
        var indices: [GlobalIndexQuote] = []
        var stocks: [KoreaStockQuote] = []
        let lock = NSLock()
        
        for item in targets {
            dispatchGroup.enter()
            let urlStr = "https://query1.finance.yahoo.com/v8/finance/chart/\(item.sym)?interval=1d&range=1d"
            guard let url = URL(string: urlStr) else {
                dispatchGroup.leave()
                continue
            }
            
            var req = URLRequest(url: url)
            req.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
            
            urlSession.dataTask(with: req) { data, _, error in
                defer { dispatchGroup.leave() }
                guard let data = data, error == nil,
                      let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                      let chart = json["chart"] as? [String: Any],
                      let result = chart["result"] as? [[String: Any]],
                      let first = result.first,
                      let meta = first["meta"] as? [String: Any] else {
                    return
                }
                
                let currentPrice = meta["regularMarketPrice"] as? Double ?? 0.0
                let prevClose = (meta["previousClose"] as? Double) ?? (meta["chartPreviousClose"] as? Double) ?? currentPrice
                let chgAmt = currentPrice - prevClose
                let chgPct = prevClose > 0 ? (chgAmt / prevClose) * 100.0 : 0.0
                
                lock.lock()
                if item.isIndex {
                    indices.append(GlobalIndexQuote(
                        symbol: item.sym,
                        name: item.cn,
                        region: "韩股",
                        currentPrice: currentPrice,
                        changeAmount: chgAmt,
                        changePercent: chgPct,
                        statusText: "韩股",
                        updateTime: "实时"
                    ))
                } else {
                    stocks.append(KoreaStockQuote(
                        symbol: item.sym,
                        nameCn: item.cn,
                        nameKr: item.kr,
                        currentPrice: currentPrice,
                        changeAmount: chgAmt,
                        changePercent: chgPct,
                        industry: item.ind
                    ))
                }
                lock.unlock()
            }.resume()
        }
        
        dispatchGroup.notify(queue: .main) {
            completion(indices, stocks)
        }
    }
}
