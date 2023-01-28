// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol";
import "@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol";

address constant ROUTER_ADDRESS = 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;


contract Egod_Eth is IERC20, Ownable {
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address constant ZERO = 0x0000000000000000000000000000000000000000;

    string constant _name = "Egod"; 
    string constant _symbol = "$SAVIOR";
    uint8 constant _decimals = 0;
    uint256 _totalSupply = 1000000000000000000;
 
    mapping (address => uint256) _balances;
    mapping (address => mapping (address => uint256)) _allowances;
    mapping (address => bool) public isFeeExempt;
 
    // Detailed Fees
    uint256 public liquidityFee;
    uint256 public marketingFee;
    uint256 public totalFee;
 
    uint256 public BuyliquidityFee    = 0;
    uint256 public BuymarketingFee    = 0;
    uint256 public BuytotalFee        = BuyliquidityFee + BuymarketingFee;
 
    uint256 public SellliquidityFee    = 3;
    uint256 public SellmarketingFee    = 3;
    uint256 public SelltotalFee        = SellliquidityFee + SellmarketingFee;

    // Fees receivers
    address public autoLiquidityReceiver;
    address public marketingFeeReceiver;
 
    IUniswapV2Router02 public router;
    mapping (address => bool) public pairs;
 
    bool public swapEnabled = false;
    uint256 public swapThreshold = _totalSupply * 1 / 1000; // 0.1%
    uint256 public maxSwapSize = _totalSupply * 1 / 100; //1%
    uint256 public tokensToSell;

    mapping(address => bool) public excludedFromMaxWallet;
    uint public maxWallet = _totalSupply * 1 / 100; //1%
 
    bool inSwap;
    modifier swapping() { inSwap = true; _; inSwap = false; }
 
    // CONSTRUCT A SHIT
    constructor() {
        router = IUniswapV2Router02(ROUTER_ADDRESS);

        _allowances[address(this)][address(router)] = type(uint256).max;
 
        isFeeExempt[msg.sender] = true;
        isFeeExempt[address(this)] = true;
        excludedFromMaxWallet[msg.sender] = true;
        excludedFromMaxWallet[address(this)] = true;
        
 
        _balances[msg.sender] = _totalSupply;
        emit Transfer(address(0), msg.sender, _totalSupply);

        autoLiquidityReceiver = owner();
        marketingFeeReceiver = owner();
    }
 
    // GIMME MONEY SHIT
    receive() external payable { }
 
    // ERC20 SHIT
    function totalSupply() external view override returns (uint256) { return _totalSupply; }
    function decimals() external pure returns (uint8) { return _decimals; }
    function symbol() external pure returns (string memory) { return _symbol; }
    function name() external pure returns (string memory) { return _name; }
    function balanceOf(address account) public view override returns (uint256) { return _balances[account]; }
    function allowance(address holder, address spender) external view override returns (uint256) { return _allowances[holder][spender]; }
    function approve(address spender, uint256 amount) public override returns (bool) {
        _allowances[msg.sender][spender] = amount;
        emit Approval(msg.sender, spender, amount);
        return true;
    }
    function approveMax(address spender) external returns (bool) {
        return approve(spender, type(uint256).max);
    }
 
    // TRANSFER SHIT
    function transfer(address recipient, uint256 amount) external override returns (bool) {
        return _transferFrom(msg.sender, recipient, amount);
    }
 
    function transferFrom(address sender, address recipient, uint256 amount) external override returns (bool) {
        if(_allowances[sender][msg.sender] != type(uint256).max){
            require(_allowances[sender][msg.sender] >= amount, "Not enough allowance");
            _allowances[sender][msg.sender] = _allowances[sender][msg.sender] - amount;
        }
 
        return _transferFrom(sender, recipient, amount);
    }
 
    function _transferFrom(address sender, address recipient, uint256 amount) internal returns (bool) {
        if(inSwap){ return _basicTransfer(sender, recipient, amount); }

        if(!swapEnabled) {
            bool permission = msg.sender == owner() || isFeeExempt[msg.sender] || isFeeExempt[sender] || isFeeExempt[recipient];
            require(permission, "Swap not enabled and you don't have permission to transfer.");
        }

        // Assume zero tax
        uint256 amountReceived = amount;

        // Take tokens from sender
        _balances[sender] = _balances[sender] - amount;

        // Take fees if necessary
        bool isDexSwap = pairs[sender] || pairs[recipient];
        bool isExcludedFromFee = isFeeExempt[sender] || isFeeExempt[recipient];
        if (isDexSwap && !isExcludedFromFee) {
            if(pairs[sender]){
                buyFees();
            } else if(pairs[recipient]){
                sellFees();
            }

            // Maybe we should swap back
            if(shouldSwapBack()){ swapBack(); }

            // Actual amount recieved after fees
            amountReceived = takeFee(sender, amount);
        }
 
        // Increase recipient balance
        _balances[recipient] = _balances[recipient] + amountReceived;
 
        // Check max wallet
        if (!excludedFromMaxWallet[recipient] && maxWallet > 0) {
            require(_balances[recipient] <= maxWallet, "Max wallet limit reached");
        }

        // ERC20 event
        emit Transfer(sender, recipient, amountReceived);
        return true;
    }
 
    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        _balances[sender] = _balances[sender] - amount;
        _balances[recipient] = _balances[recipient] + (amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }
 
    // FEES SHIT
    function buyFees() internal{
        liquidityFee    = BuyliquidityFee;
        marketingFee    = BuymarketingFee;
        totalFee        = BuytotalFee;
    }
 
    function sellFees() internal{
        liquidityFee    = SellliquidityFee;
        marketingFee    = SellmarketingFee;
        totalFee        = SelltotalFee;
    }

    function takeFee(address sender, uint256 amount) internal returns (uint256) {
        uint256 feeAmount = amount / 100 * (totalFee);
 
        _balances[address(this)] = _balances[address(this)] + (feeAmount);
        emit Transfer(sender, address(this), feeAmount);
 
        return amount - feeAmount;
    }
 
    // AUTO LP SHIT
    function shouldSwapBack() internal view returns (bool) {
        return !pairs[msg.sender]
        && !inSwap
        && swapEnabled
        && _balances[address(this)] >= swapThreshold;
    }
 
    function manualSwapBack() external onlyOwner {
        swapBack();
    }

    function swapBack() internal swapping {
        uint256 contractTokenBalance = balanceOf(address(this));
        if(contractTokenBalance >= maxSwapSize){
            tokensToSell = maxSwapSize;            
        }
        else{
            tokensToSell = contractTokenBalance;
        }
 
        uint256 amountToLiquify = tokensToSell / (totalFee) * (liquidityFee) / (2);
        uint256 amountToSwap = tokensToSell - (amountToLiquify);
 
        address[] memory path = new address[](2);
        path[0] = address(this);
        path[1] = router.WETH();
 
        uint256 balanceBefore = address(this).balance;
 
        // router.swapExactTokensForWWETHSupportingFeeOnTransferTokens(
        router.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );
 
        uint256 amountWETH = address(this).balance - (balanceBefore);
 
        uint256 totalWETHFee = totalFee - (liquidityFee / (2));
 
        uint256 amountWETHLiquidity = amountWETH * (liquidityFee) / (totalWETHFee) / (2);
        uint256 amountWETHMarketing = amountWETH - amountWETHLiquidity;
 
        (bool MarketingSuccess,) = payable(marketingFeeReceiver).call{value: amountWETHMarketing, gas: 30000}("");
        require(MarketingSuccess, "receiver rejected WWETH transfer");
 
        addLiquidity(amountToLiquify, amountWETHLiquidity);
    }
 
    function addLiquidity(uint256 tokenAmount, uint256 amountWETH) private {
        if(tokenAmount > 0){
            router.addLiquidityETH{value: amountWETH}(
                address(this),
                tokenAmount,
                0,
                0,
                autoLiquidityReceiver,
                block.timestamp
            );
            emit AutoLiquify(amountWETH, tokenAmount);
        }
    }
 
    // ADMIN SETTINGS SHIT
    function setBuyFees(uint256 _liquidityFee, uint256 _marketingFee) external onlyOwner {
        BuyliquidityFee = _liquidityFee;
        BuymarketingFee = _marketingFee;
        BuytotalFee = _liquidityFee + _marketingFee;
    }
 
    function setSellFees(uint256 _liquidityFee, uint256 _marketingFee) external onlyOwner {
        SellliquidityFee = _liquidityFee;
        SellmarketingFee = _marketingFee;
        SelltotalFee = _liquidityFee + _marketingFee;
    }
 
    function setFeeReceivers(address _autoLiquidityReceiver, address _marketingFeeReceiver) external onlyOwner {
        autoLiquidityReceiver = _autoLiquidityReceiver;
        marketingFeeReceiver = _marketingFeeReceiver;
    }
 
    function setSwapBackSettings(bool _enabled, uint256 _percentage_min_base10000, uint256 _percentage_max_base10000) external onlyOwner {
        swapEnabled = _enabled;
        swapThreshold = _totalSupply / (10000) * (_percentage_min_base10000);
        maxSwapSize = _totalSupply / (10000) * (_percentage_max_base10000);
    }
 
    function setIsFeeExempt(address holder, bool exempt) external onlyOwner {
        isFeeExempt[holder] = exempt;
    }

    function setExcludedFromMaxWallet(address addr, bool excluded) public onlyOwner {
        excludedFromMaxWallet[addr] = excluded;
    }

    function setMaxWallet(uint256 _maxWallet) external onlyOwner {
        maxWallet = _maxWallet;
    }
 
    // PANIC SHIT
    function rescueToken(address tokenAddress, uint256 tokens) public onlyOwner returns (bool success) {
        return IERC20(tokenAddress).transfer(msg.sender, tokens);
    }
 
    function clearStuckBalance(uint256 amountPercentage) external onlyOwner {
        uint256 amountWETH = address(this).balance;
        payable(msg.sender).transfer(amountWETH * amountPercentage / 100);
    }
 
    // OPEN TRADING SHIT
    function enableTrading() external payable onlyOwner {
        require(!swapEnabled, "trading already enabled");
        swapEnabled = true;
    }

    function addTradingPair(address pair) public onlyOwner {
        excludedFromMaxWallet[pair] = true;
        IERC20(pair).approve(address(router), type(uint256).max);
    }

    event AutoLiquify(uint256 amountWETH, uint256 amountTokens);

    // BRIDGE SHIT
    mapping(address => bool) public bridgeyBois;
    uint256 public currentSupply = 0;

    function setBridge(address addr, bool isBridge) external onlyOwner {
        bridgeyBois[addr] = isBridge;
    }

    modifier onlyBridge() {
        require(bridgeyBois[msg.sender], "Only bridge can call this function.");
        _;
    }

    function mint(address to, uint256 amount) external onlyBridge {
        currentSupply = currentSupply + amount;
        require(currentSupply <= _totalSupply, "Total supply reached");
        _balances[to] = _balances[to] + amount;
        emit Transfer(address(0), to, amount);
    }

    function burnFrom(address from, uint256 amount) external onlyBridge {
        require(currentSupply >= amount, "Go away.");
        if(_allowances[from][msg.sender] != type(uint256).max){
            require(_allowances[from][msg.sender] >= amount, "Not enough allowance");
            _allowances[from][msg.sender] = _allowances[from][msg.sender] - amount;
        }
        require(_balances[from] >= amount, "Insufficient balance.");
        _balances[from] = _balances[from] - amount;
        currentSupply = currentSupply - amount;
        emit Transfer(from, address(0), amount);
    }
}
