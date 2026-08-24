import Foundation
import Combine

/// 股票与指数多维模糊搜索服务（支持中文名、拼音首字母简拼、代码即时联想，完美 Unicode 转码）
public final class StockSearchService: ObservableObject {
    public static let shared = StockSearchService()
    
    @Published public var isSearching: Bool = false
    @Published public var searchResults: [StockSearchResult] = []
    @Published public var errorMessage: String? = nil
    
    private var currentTask: URLSessionDataTask?
    private var searchDebounceTimer: Timer?
    private let urlSession: URLSession
    
    // GBK 编码解析
    private let gbkEncoding = String.Encoding(
        rawValue: CFStringConvertEncodingToNSStringEncoding(CFStringEncoding(CFStringEncodings.GB_18030_2000.rawValue))
    )
    
    private init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 3.5
        self.urlSession = URLSession(configuration: config)
    }
    
    /// 执行模糊搜索（内置 200ms 防抖）
    public func search(query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        searchDebounceTimer?.invalidate()
        currentTask?.cancel()
        
        guard !trimmed.isEmpty else {
            DispatchQueue.main.async {
                self.searchResults = []
                self.isSearching = false
                self.errorMessage = nil
            }
            return
        }
        
        // 200ms 防抖，避免快速打字频繁请求
        searchDebounceTimer = Timer.scheduledTimer(withTimeInterval: 0.20, repeats: false) { [weak self] _ in
            self?.performDualSearch(query: trimmed)
        }
    }
    
    /// 清除搜索结果
    public func clear() {
        searchDebounceTimer?.invalidate()
        currentTask?.cancel()
        searchResults = []
        isSearching = false
        errorMessage = nil
    }
    
    /// 双引擎并发搜索（东方财富 Suggest API + 腾讯 Smartbox API 兜底）
    private func performDualSearch(query: String) {
        DispatchQueue.main.async {
            self.isSearching = true
            self.errorMessage = nil
        }
        
        // 1. 优先调用东方财富智能搜索 API（原生返回纯净 UTF-8 中文名称与代码）
        let eastmoneyUrlStr = "https://searchapi.eastmoney.com/api/suggest/get?input=\(query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query)&type=14&token=D43BF722C8E33BDC906FB84D85E326E8"
        
        guard let emUrl = URL(string: eastmoneyUrlStr) else {
            fallbackToTencentSearch(query: query)
            return
        }
        
        var request = URLRequest(url: emUrl)
        request.setValue("Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7)", forHTTPHeaderField: "User-Agent")
        
        currentTask = urlSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            
            if let data = data, error == nil,
               let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let table = json["QuotationCodeTable"] as? [String: Any],
               let dataList = table["Data"] as? [[String: Any]], !dataList.isEmpty {
                
                var results: [StockSearchResult] = []
                for item in dataList {
                    guard let code = item["Code"] as? String,
                          let name = item["Name"] as? String else { continue }
                    let pinyin = item["PinYin"] as? String ?? ""
                    let secTypeName = item["SecurityTypeName"] as? String ?? "A股"
                    let quoteId = item["QuoteID"] as? String ?? ""
                    
                    // 确定市场前缀
                    let market: String
                    if quoteId.hasPrefix("1.") {
                        market = "sh"
                    } else if quoteId.hasPrefix("0.") {
                        market = "sz"
                    } else if quoteId.hasPrefix("2.") {
                        market = "bj"
                    } else {
                        market = code.hasPrefix("6") || code.hasPrefix("5") ? "sh" : (code.hasPrefix("8") || code.hasPrefix("4") || code.hasPrefix("9") ? "bj" : "sz")
                    }
                    
                    let decodedName = self.decodeUnicodeEscapes(name)
                    let symbol = StockSymbol(code: code, market: market, name: decodedName)
                    let typeName = secTypeName.contains("指数") ? "指数" : (secTypeName.contains("ETF") ? "ETF" : "A股")
                    
                    if !results.contains(where: { $0.symbol.fullCode == symbol.fullCode }) {
                        results.append(StockSearchResult(symbol: symbol, pinyin: pinyin, typeName: typeName))
                    }
                }
                
                if !results.isEmpty {
                    DispatchQueue.main.async {
                        self.searchResults = results
                        self.isSearching = false
                    }
                    return
                }
            }
            
            // 东方财富未返回有效结果时，降级使用腾讯 Smartbox 引擎
            self.fallbackToTencentSearch(query: query)
        }
        currentTask?.resume()
    }
    
    /// 降级使用腾讯 Smartbox API 并做 Unicode 深度反转义
    private func fallbackToTencentSearch(query: String) {
        guard let encodedQuery = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed),
              let url = URL(string: "https://smartbox.gtimg.cn/s3/?t=all&q=\(encodedQuery)") else {
            DispatchQueue.main.async {
                self.searchResults = self.searchLocalPresets(query: query)
                self.isSearching = false
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.setValue("Mozilla/5.0", forHTTPHeaderField: "User-Agent")
        
        urlSession.dataTask(with: request) { [weak self] data, _, error in
            guard let self = self else { return }
            
            defer {
                DispatchQueue.main.async {
                    self.isSearching = false
                }
            }
            
            guard let data = data, error == nil else {
                DispatchQueue.main.async {
                    self.searchResults = self.searchLocalPresets(query: query)
                }
                return
            }
            
            let text = String(data: data, encoding: self.gbkEncoding) ?? String(data: data, encoding: .utf8) ?? ""
            let parsedResults = self.parseSmartboxResponse(text, originalQuery: query)
            
            DispatchQueue.main.async {
                if parsedResults.isEmpty {
                    let localMatches = self.searchLocalPresets(query: query)
                    if !localMatches.isEmpty {
                        self.searchResults = localMatches
                    } else if query.count == 6 && CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: query)) {
                        let sym = StockSymbol.create(from: query)
                        self.searchResults = [StockSearchResult(symbol: sym, pinyin: "", typeName: "A股")]
                    } else {
                        self.searchResults = []
                    }
                } else {
                    self.searchResults = parsedResults
                }
            }
        }.resume()
    }
    
    /// 解析腾讯 Smartbox 返回格式并彻底解码 Unicode
    private func parseSmartboxResponse(_ rawText: String, originalQuery: String) -> [StockSearchResult] {
        var results: [StockSearchResult] = []
        guard let equalIndex = rawText.firstIndex(of: "=") else { return results }
        
        let contentPart = String(rawText[rawText.index(after: equalIndex)...])
            .trimmingCharacters(in: CharacterSet(charactersIn: "\" \n\r\t;"))
        
        guard !contentPart.isEmpty && contentPart != "N" else { return results }
        
        let rawItems = contentPart.components(separatedBy: "^")
        for item in rawItems {
            let fields = item.components(separatedBy: "~")
            guard fields.count >= 4 else { continue }
            
            let market = fields[0].lowercased()
            let code = fields[1]
            let rawName = fields[2]
            let pinyin = fields[3]
            let rawType = fields.count > 4 ? fields[4] : "GP-A"
            
            // 彻底解码 \u8d35\u5dde\u8305\u53f0 等 Unicode 转义字符
            let cleanName = decodeUnicodeEscapes(rawName)
            
            let typeName: String
            switch rawType.uppercased() {
            case "GP-A", "GP": typeName = "A股"
            case "ZS": typeName = "指数"
            case "ETF": typeName = "ETF"
            case "LOF": typeName = "LOF"
            case "KJ": typeName = "基金"
            case "HK": typeName = "港股"
            case "US": typeName = "美股"
            default:
                if market == "hk" {
                    typeName = "港股"
                } else if market == "us" {
                    typeName = "美股"
                } else {
                    typeName = "A股"
                }
            }
            
            let validMarkets = ["sh", "sz", "bj", "hk", "us"]
            guard validMarkets.contains(market) else { continue }
            
            let symbol = StockSymbol(code: code, market: market, name: cleanName)
            let searchResult = StockSearchResult(symbol: symbol, pinyin: pinyin, typeName: typeName)
            
            if !results.contains(where: { $0.symbol.fullCode == symbol.fullCode }) {
                results.append(searchResult)
            }
        }
        
        return results
    }
    
    /// 将形如 \u8d35\u5dde\u8305\u53f0 的转义字符串解码为原生中文
    public func decodeUnicodeEscapes(_ input: String) -> String {
        guard input.contains("\\u") else { return input }
        
        var result = input
        let pattern = #"\\u([0-9a-fA-F]{4})"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: []) {
            let nsString = input as NSString
            let matches = regex.matches(in: input, options: [], range: NSRange(location: 0, length: nsString.length))
            for match in matches.reversed() {
                let hexString = nsString.substring(with: match.range(at: 1))
                if let intVal = UInt32(hexString, radix: 16), let scalar = UnicodeScalar(intVal) {
                    let char = String(Character(scalar))
                    let fullMatch = nsString.substring(with: match.range)
                    result = result.replacingOccurrences(of: fullMatch, with: char)
                }
            }
        }
        return result
    }
    
    /// 本地预设模糊匹配兜底
    private func searchLocalPresets(query: String) -> [StockSearchResult] {
        let q = query.lowercased()
        return StockSymbol.presets.filter { sym in
            sym.name.lowercased().contains(q) || sym.code.contains(q) || sym.fullCode.contains(q)
        }.map { sym in
            StockSearchResult(symbol: sym, pinyin: "", typeName: sym.code.hasPrefix("399") || sym.code == "000001" ? "指数" : "A股")
        }
    }
}
