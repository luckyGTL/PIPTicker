#if canImport(UIKit)
import UIKit
import Combine

/// 画中画单个股票卡片组件（具备实时几何自适应能力，缩放缩小时动态调优字号与展示层级）
final class PiPStockCardView: UIView {
    private let nameLabel = UILabel()
    private let codeLabel = UILabel()
    private let priceLabel = UILabel()
    private let changeBadgeLabel = UILabel()
    private let changeAmountLabel = UILabel()
    
    private let mainStack = UIStackView()
    private let topStack = UIStackView()
    private let bottomStack = UIStackView()
    
    var isRedUpGreenDown: Bool = true
    private var totalCount: Int = 4
    
    override init(frame: CGRect) {
        super.init(frame: frame)
        setupView()
    }
    
    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupView()
    }
    
    private func setupView() {
        backgroundColor = UIColor(white: 0.12, alpha: 0.95)
        layer.cornerRadius = 5
        layer.borderWidth = 0.5
        layer.borderColor = UIColor(white: 0.22, alpha: 1.0).cgColor
        layer.masksToBounds = true
        
        nameLabel.textColor = UIColor(white: 0.96, alpha: 1.0)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.adjustsFontSizeToFitWidth = true
        nameLabel.minimumScaleFactor = 0.6
        // 绝对优先保证股票名称完整展示，无论水平还是垂直方向均不可挤压
        nameLabel.setContentCompressionResistancePriority(.required, for: .horizontal)
        nameLabel.setContentCompressionResistancePriority(.required, for: .vertical)
        nameLabel.setContentHuggingPriority(.defaultLow, for: .horizontal)
        nameLabel.setContentHuggingPriority(.required, for: .vertical)
        
        codeLabel.textColor = UIColor(white: 0.60, alpha: 1.0)
        codeLabel.font = UIFont.systemFont(ofSize: 9, weight: .medium)
        codeLabel.adjustsFontSizeToFitWidth = true
        codeLabel.minimumScaleFactor = 0.5
        // 股票代码设为最低抗压缩优先级，空间不足时优先压缩或隐藏代码
        codeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        codeLabel.setContentHuggingPriority(.required, for: .horizontal)
        
        priceLabel.textColor = .white
        priceLabel.adjustsFontSizeToFitWidth = true
        priceLabel.minimumScaleFactor = 0.35
        priceLabel.setContentCompressionResistancePriority(.defaultHigh, for: .vertical)
        priceLabel.setContentHuggingPriority(.defaultLow, for: .vertical)
        
        changeBadgeLabel.textColor = .white
        changeBadgeLabel.textAlignment = .center
        changeBadgeLabel.layer.cornerRadius = 2.5
        changeBadgeLabel.layer.masksToBounds = true
        changeBadgeLabel.adjustsFontSizeToFitWidth = true
        changeBadgeLabel.minimumScaleFactor = 0.5
        changeBadgeLabel.setContentHuggingPriority(.required, for: .horizontal)
        
        changeAmountLabel.textColor = UIColor(white: 0.7, alpha: 1.0)
        changeAmountLabel.adjustsFontSizeToFitWidth = true
        changeAmountLabel.minimumScaleFactor = 0.5
        
        topStack.axis = .horizontal
        topStack.alignment = .firstBaseline
        topStack.distribution = .fill
        topStack.spacing = 3
        topStack.addArrangedSubview(nameLabel)
        topStack.addArrangedSubview(codeLabel)
        
        bottomStack.axis = .horizontal
        bottomStack.alignment = .center
        bottomStack.spacing = 2
        bottomStack.addArrangedSubview(changeBadgeLabel)
        bottomStack.addArrangedSubview(changeAmountLabel)
        
        mainStack.axis = .vertical
        mainStack.alignment = .fill
        mainStack.distribution = .fill
        mainStack.spacing = 0
        mainStack.translatesAutoresizingMaskIntoConstraints = false
        
        mainStack.addArrangedSubview(topStack)
        mainStack.addArrangedSubview(priceLabel)
        mainStack.addArrangedSubview(bottomStack)
        
        addSubview(mainStack)
        
        setContentHuggingPriority(.defaultLow, for: .horizontal)
        setContentHuggingPriority(.defaultLow, for: .vertical)
        setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        setContentCompressionResistancePriority(.defaultLow, for: .vertical)
        
        let leading = mainStack.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 2.5)
        let trailing = mainStack.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -2.5)
        let top = mainStack.topAnchor.constraint(equalTo: topAnchor, constant: 1.5)
        let bottom = mainStack.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -1.5)
        
        trailing.priority = UILayoutPriority(999)
        bottom.priority = UILayoutPriority(999)
        
        NSLayoutConstraint.activate([
            leading,
            trailing,
            top,
            bottom
        ])
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        adaptToCurrentBounds()
    }
    
    /// 当画中画被用户捏合缩小或放大时，实时根据实际像素高度/宽度自适应调优字号与显示权重
    private func adaptToCurrentBounds() {
        let h = bounds.height
        let w = bounds.width
        guard h > 0, w > 0 else { return }
        
        let availableWidth = w - 8
        
        if h < 48 || (totalCount >= 7 && h < 58) {
            // 【8只缩小/极小微型档位】：上下垂直空间由「股票名称」与「当前现价」平分，居中对称布局绝不溢出
            let nameSize = max(8.0, min(11.0, h * 0.32))
            let priceSize = max(9.5, min(14.0, h * 0.42))
            
            nameLabel.font = UIFont.systemFont(ofSize: nameSize, weight: .bold)
            nameLabel.textAlignment = .center
            codeLabel.isHidden = true // 彻底隐藏代码，100% 空间留给股票名称
            
            priceLabel.font = UIFont.systemFont(ofSize: priceSize, weight: .heavy, width: .compressed)
            priceLabel.textAlignment = .center
            
            // 隐藏第三行微标与跌额，使两行垂直呼吸空间增加 100%
            bottomStack.isHidden = true
            changeAmountLabel.isHidden = true
            mainStack.spacing = 0.5
        } else if h < 72 {
            // 【紧凑中型档位】：股票名称优先，如果代码展示不全则彻底隐藏
            let nameSize = max(11, min(14, h * 0.26))
            let priceSize = max(13, min(20, h * 0.36))
            let badgeSize = max(8.5, min(11, h * 0.18))
            
            nameLabel.font = UIFont.systemFont(ofSize: nameSize, weight: .bold)
            nameLabel.textAlignment = .left
            let codeFontSize = max(7.5, nameSize * 0.65)
            codeLabel.font = UIFont.systemFont(ofSize: codeFontSize, weight: .medium)
            
            // 精确测算：股票名称所需宽度 + 股票代码完整宽度 + 间距
            let nameWidth = nameLabel.intrinsicContentSize.width
            let codeWidth = codeLabel.intrinsicContentSize.width
            let isCodeOverflow = (nameWidth + codeWidth + 4) > availableWidth
            
            // 若宽度不足以完整展示 6 位代码，直接隐藏代码，绝不截断
            codeLabel.isHidden = isCodeOverflow || (w < 88)
            
            priceLabel.font = UIFont.systemFont(ofSize: priceSize, weight: .heavy, width: .compressed)
            priceLabel.textAlignment = .left
            
            bottomStack.isHidden = false
            changeBadgeLabel.font = UIFont.systemFont(ofSize: badgeSize, weight: .bold)
            changeAmountLabel.isHidden = (w < 90)
            changeAmountLabel.font = UIFont.systemFont(ofSize: badgeSize, weight: .semibold)
            mainStack.spacing = 1
        } else {
            // 【宽屏大档位】：智能检测是否截断
            let nameSize = max(13, min(18, h * 0.24))
            let priceSize = max(17, min(36, h * 0.40))
            let badgeSize = max(10, min(13, h * 0.18))
            
            nameLabel.font = UIFont.systemFont(ofSize: nameSize, weight: .bold)
            nameLabel.textAlignment = .left
            let codeFontSize = max(9, nameSize * 0.70)
            codeLabel.font = UIFont.systemFont(ofSize: codeFontSize, weight: .medium)
            
            let nameWidth = nameLabel.intrinsicContentSize.width
            let codeWidth = codeLabel.intrinsicContentSize.width
            let isCodeOverflow = (nameWidth + codeWidth + 6) > availableWidth
            
            // 空间充足且能完整容纳时展示，否则彻底隐藏
            codeLabel.isHidden = isCodeOverflow
            
            priceLabel.font = UIFont.systemFont(ofSize: priceSize, weight: .heavy, width: .compressed)
            priceLabel.textAlignment = .left
            
            bottomStack.isHidden = false
            changeBadgeLabel.font = UIFont.systemFont(ofSize: badgeSize, weight: .bold)
            changeAmountLabel.isHidden = false
            changeAmountLabel.font = UIFont.systemFont(ofSize: badgeSize, weight: .semibold)
            mainStack.spacing = 2
        }
    }
    
    func applyStyle(totalCount: Int) {
        self.totalCount = totalCount
        setNeedsLayout()
        layoutIfNeeded()
    }
    
    func configure(with quote: StockQuote) {
        nameLabel.text = quote.symbol.name
        codeLabel.text = quote.symbol.code
        priceLabel.text = quote.price
        changeBadgeLabel.text = " \(quote.priceChangePercent) "
        changeAmountLabel.text = quote.priceChange
        adaptToCurrentBounds()
        
        let redColor = UIColor(red: 0.92, green: 0.26, blue: 0.21, alpha: 1.0)
        let greenColor = UIColor(red: 0.18, green: 0.80, blue: 0.44, alpha: 1.0)
        let flatColor = UIColor(white: 0.65, alpha: 1.0)
        
        let activeColor: UIColor
        if quote.isFlat {
            activeColor = flatColor
        } else if isRedUpGreenDown {
            activeColor = quote.isPositive ? redColor : greenColor
        } else {
            activeColor = quote.isPositive ? greenColor : redColor
        }
        
        UIView.transition(with: priceLabel, duration: 0.08, options: .transitionCrossDissolve, animations: {
            self.priceLabel.textColor = activeColor
            self.changeBadgeLabel.backgroundColor = activeColor
            self.changeAmountLabel.textColor = activeColor
        })
    }
}

/// 投射到画中画（PiP）浮窗内部的 A 股多股实时行情控制器（16:9 极宽满屏）
public final class PiPTickerViewController: UIViewController {
    
    private let containerView = UIView()
    private let headerBarView = UIView()
    private let marketStatusLabel = UILabel()
    private let timeLabel = UILabel()
    private var headerHeightConstraint: NSLayoutConstraint?
    private var gridTopConstraint: NSLayoutConstraint?
    
    private let gridStackView = UIStackView()
    private var cardViews: [PiPStockCardView] = []
    
    public var isRedUpGreenDown: Bool = true {
        didSet {
            for card in cardViews {
                card.isRedUpGreenDown = isRedUpGreenDown
            }
            updateData()
        }
    }
    
    // 画中画展示的股票数量（1 ~ 8 只）
    public var displayCount: Int = 4 {
        didSet {
            let clamped = max(1, min(8, displayCount))
            if clamped != oldValue {
                rebuildAdaptiveGrid()
                updateData()
            }
        }
    }
    
    private var cancellables = Set<AnyCancellable>()
    
    public override func viewDidLoad() {
        super.viewDidLoad()
        // 16:9 极宽满屏基准尺寸 (360 x 202.5)，解锁 iOS 画中画最大屏幕宽度
        preferredContentSize = CGSize(width: 360, height: 202.5)
        setupUI()
        bindData()
    }
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        let currentHeight = view.bounds.height
        let isMinimal = currentHeight < 115
        
        // 最小化模式下自动隐藏顶部状态栏，把全部高度 100% 释放给 8 支股票网格
        if isMinimal {
            headerBarView.isHidden = true
            headerHeightConstraint?.constant = 0
            gridTopConstraint?.constant = 0
            gridStackView.spacing = 1.5
        } else {
            headerBarView.isHidden = false
            headerHeightConstraint?.constant = (currentHeight < 140) ? 13 : 16
            gridTopConstraint?.constant = 3
            gridStackView.spacing = 3
            marketStatusLabel.font = UIFont.systemFont(ofSize: (currentHeight < 140) ? 8 : 10, weight: .bold)
            timeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: (currentHeight < 140) ? 8 : 9, weight: .medium)
        }
    }
    
    private func setupUI() {
        view.backgroundColor = .black
        
        containerView.translatesAutoresizingMaskIntoConstraints = false
        containerView.backgroundColor = .clear
        view.addSubview(containerView)
        
        // 顶部小状态栏
        headerBarView.translatesAutoresizingMaskIntoConstraints = false
        headerBarView.backgroundColor = UIColor(white: 0.08, alpha: 0.9)
        headerBarView.layer.cornerRadius = 3
        
        marketStatusLabel.font = UIFont.systemFont(ofSize: 10, weight: .bold)
        marketStatusLabel.textColor = UIColor(red: 0.95, green: 0.75, blue: 0.25, alpha: 1.0)
        marketStatusLabel.text = "● A股行情"
        marketStatusLabel.translatesAutoresizingMaskIntoConstraints = false
        
        timeLabel.font = UIFont.monospacedDigitSystemFont(ofSize: 9, weight: .medium)
        timeLabel.textColor = UIColor(white: 0.6, alpha: 1.0)
        timeLabel.text = "--:--:--"
        timeLabel.translatesAutoresizingMaskIntoConstraints = false
        
        headerBarView.addSubview(marketStatusLabel)
        headerBarView.addSubview(timeLabel)
        
        let headerHeight = headerBarView.heightAnchor.constraint(equalToConstant: 16)
        self.headerHeightConstraint = headerHeight
        
        NSLayoutConstraint.activate([
            marketStatusLabel.leadingAnchor.constraint(equalTo: headerBarView.leadingAnchor, constant: 4),
            marketStatusLabel.centerYAnchor.constraint(equalTo: headerBarView.centerYAnchor),
            
            timeLabel.trailingAnchor.constraint(equalTo: headerBarView.trailingAnchor, constant: -4),
            timeLabel.centerYAnchor.constraint(equalTo: headerBarView.centerYAnchor),
            headerHeight
        ])
        
        // 16:9 自适应宽屏网格布局
        gridStackView.axis = .vertical
        gridStackView.alignment = .fill
        gridStackView.distribution = .fillEqually
        gridStackView.spacing = 3
        gridStackView.translatesAutoresizingMaskIntoConstraints = false
        
        containerView.addSubview(headerBarView)
        containerView.addSubview(gridStackView)
        
        let gridTop = gridStackView.topAnchor.constraint(equalTo: headerBarView.bottomAnchor, constant: 3)
        self.gridTopConstraint = gridTop
        
        NSLayoutConstraint.activate([
            containerView.topAnchor.constraint(equalTo: view.topAnchor, constant: 2),
            containerView.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 2),
            containerView.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -2),
            containerView.bottomAnchor.constraint(equalTo: view.bottomAnchor, constant: -2),
            
            headerBarView.topAnchor.constraint(equalTo: containerView.topAnchor),
            headerBarView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            headerBarView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            
            gridTop,
            gridStackView.leadingAnchor.constraint(equalTo: containerView.leadingAnchor),
            gridStackView.trailingAnchor.constraint(equalTo: containerView.trailingAnchor),
            gridStackView.bottomAnchor.constraint(equalTo: containerView.bottomAnchor)
        ])
        
        rebuildAdaptiveGrid()
    }
    
    /// 根据 16:9 极宽满屏排版规则自适应铺满
    private func rebuildAdaptiveGrid() {
        gridStackView.arrangedSubviews.forEach { $0.removeFromSuperview() }
        cardViews.removeAll()
        
        let count = max(1, min(8, displayCount))
        let rowCounts = getRowDistribution(for: count)
        
        for rowItems in rowCounts {
            let rowStack = UIStackView()
            rowStack.axis = .horizontal
            rowStack.alignment = .fill
            rowStack.distribution = .fillEqually
            rowStack.spacing = 3
            
            for _ in 0..<rowItems {
                let card = PiPStockCardView()
                card.isRedUpGreenDown = isRedUpGreenDown
                card.applyStyle(totalCount: count)
                cardViews.append(card)
                rowStack.addArrangedSubview(card)
            }
            gridStackView.addArrangedSubview(rowStack)
        }
    }
    
    /// 计算 16:9 宽屏下 1~8 只股票的最优行列分配
    private func getRowDistribution(for count: Int) -> [Int] {
        switch count {
        case 1: return [1]           // 1 行 1 列 (超大横卡)
        case 2: return [2]           // 1 行 2 列 (满宽左右双卡)
        case 3: return [3]           // 1 行 3 列 (横向 3 连卡)
        case 4: return [2, 2]        // 2 行 2 列 (2x2 宽屏网格)
        case 5: return [3, 2]        // 2 行 (上3下2)
        case 6: return [3, 3]        // 2 行 3 列 (3x2 宽屏网格)
        case 7: return [4, 3]        // 2 行 (上4下3)
        case 8: return [4, 4]        // 2 行 4 列 (8只宽幅满屏大屏)
        default: return [2, 2]
        }
    }
    
    private func bindData() {
        Publishers.CombineLatest(StockDataManager.shared.$quotes, StockDataManager.shared.$watchlist)
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.updateData()
            }
            .store(in: &cancellables)
        
        StockDataManager.shared.$marketStatusText
            .receive(on: DispatchQueue.main)
            .sink { [weak self] status in
                self?.marketStatusLabel.text = "● A股 \(status)"
            }
            .store(in: &cancellables)
    }
    
    public func updateData() {
        let manager = StockDataManager.shared
        let watchlist = manager.watchlist
        
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        timeLabel.text = formatter.string(from: manager.lastUpdated)
        
        let count = min(displayCount, watchlist.count)
        
        if cardViews.count != displayCount {
            rebuildAdaptiveGrid()
        }
        
        for (index, card) in cardViews.enumerated() {
            if index < count {
                let symbol = watchlist[index]
                let quote = manager.quotes[symbol.fullCode] ?? StockQuote(symbol: symbol)
                card.configure(with: quote)
                card.isHidden = false
            } else if index < watchlist.count {
                let symbol = watchlist[index]
                let quote = manager.quotes[symbol.fullCode] ?? StockQuote(symbol: symbol)
                card.configure(with: quote)
                card.isHidden = false
            } else {
                card.isHidden = false
            }
        }
    }
    
    public func setDisplayCount(_ count: Int) {
        let clamped = max(1, min(8, count))
        guard clamped != displayCount else { return }
        self.displayCount = clamped
    }
}
#endif
