// SPDX-License-Identifier: unlicensed
pragma solidity 0.8.10;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "hardhat/console.sol";
import "./DogeSwap.sol";


contract Egod is IERC20, Ownable {
    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    address constant ZERO = 0x0000000000000000000000000000000000000000;
    address constant WDOGE = 0xB7ddC6414bf4F5515b52D8BdD69973Ae205ff101;

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
 
    IDogeswapRouter public router;
    address public pair;
 
    bool public swapEnabled = false;
    uint256 public swapThreshold = _totalSupply * 1 / 1000; // 0.1%
    uint256 public maxSwapSize = _totalSupply * 1 / 100; //1%
    uint256 public tokensToSell;

    mapping(address => bool) public excludedFromMaxWallet;
    uint maxWallet = _totalSupply * 1 / 100; //1%
    function setExcludedFromMaxWallet(address addr, bool excluded) public onlyOwner {
        excludedFromMaxWallet[addr] = excluded;
    }
 
    bool inSwap;
    modifier swapping() { inSwap = true; _; inSwap = false; }

    mapping(address => bool) public heathens;
    uint256 meditation = 3;
    function setHeathen(address addr, bool heathen) public onlyOwner {
        heathens[addr] = heathen;
    }
    bool public doBotProtection = true;
    function setDoBotProtection(bool _doBotProtection) public onlyOwner {
        doBotProtection = _doBotProtection;
    }
 
    constructor() {
        router = IDogeswapRouter(ROUTER_ADDRESS);

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
 
    receive() external payable { }
 
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

        if(sender == pair){
            buyFees();
            if (tradingStartBlock != 0 && block.number < tradingStartBlock + meditation) {
                heathens[recipient] = true;
            }
        }
 
        if(recipient == pair){
            sellFees();
            if (doBotProtection) {
                require(!heathens[sender], "Heathen!");
            }
        }
 
        //Exchange tokens
        if(shouldSwapBack()){ swapBack(); }
 
        _balances[sender] = _balances[sender] - amount;
 
        uint256 amountReceived = shouldTakeFee(sender) ? takeFee(recipient, amount) : amount;
        _balances[recipient] = _balances[recipient] + amountReceived;
 
        if (!excludedFromMaxWallet[recipient]) {
            require(_balances[recipient] <= maxWallet, "Max wallet limit reached");
        }

        emit Transfer(sender, recipient, amountReceived);
        return true;
    }
 
    function _basicTransfer(address sender, address recipient, uint256 amount) internal returns (bool) {
        _balances[sender] = _balances[sender] - amount;
        _balances[recipient] = _balances[recipient] + (amount);
        emit Transfer(sender, recipient, amount);
        return true;
    }
 
    // Internal Functions
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
 
    function shouldTakeFee(address sender) internal view returns (bool) {
        return !isFeeExempt[sender];
    }
 
    function takeFee(address sender, uint256 amount) internal returns (uint256) {
        uint256 feeAmount = amount / 100 * (totalFee);
 
        _balances[address(this)] = _balances[address(this)] + (feeAmount);
        emit Transfer(sender, address(this), feeAmount);
 
        return amount - (feeAmount);
    }
 
    function shouldSwapBack() internal view returns (bool) {
        return msg.sender != pair
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
        path[1] = WDOGE;
 
        uint256 balanceBefore = address(this).balance;
 
        router.swapExactTokensForWDOGESupportingFeeOnTransferTokens(
            amountToSwap,
            0,
            path,
            address(this),
            block.timestamp
        );
 
        uint256 amountDOGE = address(this).balance - (balanceBefore);
 
        uint256 totalDOGEFee = totalFee - (liquidityFee / (2));
 
        uint256 amountDOGELiquidity = amountDOGE * (liquidityFee) / (totalDOGEFee) / (2);
        uint256 amountDOGEMarketing = amountDOGE - amountDOGELiquidity;
 
        (bool MarketingSuccess,) = payable(marketingFeeReceiver).call{value: amountDOGEMarketing, gas: 30000}("");
        require(MarketingSuccess, "receiver rejected WDOGE transfer");
 
        addLiquidity(amountToLiquify, amountDOGELiquidity);
    }
 
    function addLiquidity(uint256 tokenAmount, uint256 DOGEAmount) private {
    if(tokenAmount > 0){
            router.addLiquidityWDOGE{value: DOGEAmount}(
                address(this),
                tokenAmount,
                0,
                0,
                autoLiquidityReceiver,
                block.timestamp
            );
            emit AutoLiquify(DOGEAmount, tokenAmount);
        }
    }
 
    // External Functions
    function checkSwapThreshold() external view returns (uint256) {
        return swapThreshold;
    }
 
    function isNotInSwap() external view returns (bool) {
        return !inSwap;
    }
 
    // Only Owner allowed
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
 
    // Stuck Balances Functions
    function rescueToken(address tokenAddress, uint256 tokens) public onlyOwner returns (bool success) {
        return IERC20(tokenAddress).transfer(msg.sender, tokens);
    }
 
    function clearStuckBalance(uint256 amountPercentage) external onlyOwner {
        uint256 amountDOGE = address(this).balance;
        payable(msg.sender).transfer(amountDOGE * amountPercentage / 100);
    }
 
    uint256 tradingStartBlock = 0;
    function enableTrading(uint256 tokensForLiquidity) external payable onlyOwner {
        require(!swapEnabled, "trading already enabled");
        pair = IDogeswapFactory(router.factory()).createPair(WDOGE, address(this));

        excludedFromMaxWallet[pair] = true;
        excludedFromMaxWallet[address(router)] = true;
        excludedFromMaxWallet[router.factory()] = true;

        _balances[msg.sender] = _balances[msg.sender] - tokensForLiquidity;
        _balances[address(this)] = _balances[address(this)] + tokensForLiquidity;
        _allowances[address(this)][address(router)] = type(uint256).max;
        
        router.addLiquidityWDOGE{value: msg.value}(address(this), tokensForLiquidity, 0, 0, owner(), block.timestamp);
        IERC20(pair).approve(address(router), type(uint256).max);

        swapEnabled = true;
        tradingStartBlock = block.number;
    }

    event AutoLiquify(uint256 amountDOGE, uint256 amountTokens);
 
}
