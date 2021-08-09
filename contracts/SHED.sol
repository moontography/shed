// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/utils/Address.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Factory.sol';
import '@uniswap/v2-core/contracts/interfaces/IUniswapV2Pair.sol';
import '@uniswap/v2-periphery/contracts/interfaces/IUniswapV2Router02.sol';

contract SHED is Context, IERC20, Ownable {
  using SafeMath for uint256;
  using Address for address;

  address payable public marketingAddress =
    payable(0x2d1B8ba4a49C0338A301BD16ff43E4A6d2604dc3); // Marketing Address
  address public immutable deadAddress =
    0x000000000000000000000000000000000000dEaD;
  mapping(address => uint256) private _rOwned;
  mapping(address => uint256) private _tOwned;
  mapping(address => mapping(address => uint256)) private _allowances;
  mapping(address => bool) private _isSniper;
  address[] private _confirmedSnipers;

  mapping(address => bool) private _isExcludedFromFee;
  mapping(address => bool) private _isExcluded;
  address[] private _excluded;

  uint256 private constant MAX = ~uint256(0);
  uint256 private _tTotal = 1000000000000 * 10**9;
  uint256 public _supplyToStopBurning = _tTotal.div(10**6);
  uint256 private _rTotal = (MAX - (MAX % _tTotal));
  uint256 private _tFeeTotal;

  string private _name = 'Shed Coin';
  string private _symbol = 'SHED';
  uint8 private _decimals = 9;

  uint256 public _taxFee = 0;
  uint256 private _previousTaxFee = _taxFee;

  uint256 public _liquidityFee = 2;
  uint256 private _previousLiquidityFee = _liquidityFee;

  uint256 public _burnFee = 4;
  uint256 private _previousBurnFee = _burnFee;

  uint256 private _maxPriceImpPerc = 2;

  uint256 private _maxBuyPercent = 1;
  uint256 private _maxBuySeconds = 2 * 60 * 60; // 2 hours in seconds after launch
  bool public overrideMaxBuy = false;

  uint256 public launchTime;

  IUniswapV2Router02 public uniswapV2Router;
  address public uniswapV2Pair;

  // PancakeSwap: 0x10ED43C718714eb63d5aA57B78B54704E256024E
  // Uniswap V2: 0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D
  address private _uniswapRouterAddress =
    0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;

  bool inSwapAndLiquify;

  bool tradingOpen = false;

  event SwapETHForTokens(uint256 amountIn, address[] path);

  event SwapTokensForETH(uint256 amountIn, address[] path);

  modifier lockTheSwap() {
    inSwapAndLiquify = true;
    _;
    inSwapAndLiquify = false;
  }

  constructor() {
    _rOwned[_msgSender()] = _rTotal;
    emit Transfer(address(0), _msgSender(), _tTotal);
  }

  function initContract() external onlyOwner {
    IUniswapV2Router02 _uniswapV2Router = IUniswapV2Router02(
      _uniswapRouterAddress
    );
    uniswapV2Pair = IUniswapV2Factory(_uniswapV2Router.factory()).createPair(
      address(this),
      _uniswapV2Router.WETH()
    );

    uniswapV2Router = _uniswapV2Router;

    _isExcludedFromFee[owner()] = true;
    _isExcludedFromFee[address(this)] = true;
  }

  function openTrading() external onlyOwner {
    _liquidityFee = _previousLiquidityFee;
    _taxFee = _previousTaxFee;
    _burnFee = _previousBurnFee;
    tradingOpen = true;
    launchTime = block.timestamp;
  }

  function closeTrading() external onlyOwner {
    tradingOpen = false;
  }

  function name() public view returns (string memory) {
    return _name;
  }

  function symbol() public view returns (string memory) {
    return _symbol;
  }

  function decimals() public view returns (uint8) {
    return _decimals;
  }

  function totalSupply() public view override returns (uint256) {
    return _tTotal;
  }

  function balanceOf(address account) public view override returns (uint256) {
    if (_isExcluded[account]) return _tOwned[account];
    return tokenFromReflection(_rOwned[account]);
  }

  function transfer(address recipient, uint256 amount)
    public
    override
    returns (bool)
  {
    _transfer(_msgSender(), recipient, amount);
    return true;
  }

  function allowance(address owner, address spender)
    public
    view
    override
    returns (uint256)
  {
    return _allowances[owner][spender];
  }

  function approve(address spender, uint256 amount)
    public
    override
    returns (bool)
  {
    _approve(_msgSender(), spender, amount);
    return true;
  }

  function transferFrom(
    address sender,
    address recipient,
    uint256 amount
  ) public override returns (bool) {
    _transfer(sender, recipient, amount);
    _approve(
      sender,
      _msgSender(),
      _allowances[sender][_msgSender()].sub(
        amount,
        'ERC20: transfer amount exceeds allowance'
      )
    );
    return true;
  }

  function increaseAllowance(address spender, uint256 addedValue)
    external
    virtual
    returns (bool)
  {
    _approve(
      _msgSender(),
      spender,
      _allowances[_msgSender()][spender].add(addedValue)
    );
    return true;
  }

  function decreaseAllowance(address spender, uint256 subtractedValue)
    external
    virtual
    returns (bool)
  {
    _approve(
      _msgSender(),
      spender,
      _allowances[_msgSender()][spender].sub(
        subtractedValue,
        'ERC20: decreased allowance below zero'
      )
    );
    return true;
  }

  function isExcludedFromReward(address account) external view returns (bool) {
    return _isExcluded[account];
  }

  function totalFees() external view returns (uint256) {
    return _tFeeTotal;
  }

  function isEnforcingMaxBuy() public view returns (bool) {
    return !overrideMaxBuy && block.timestamp <= launchTime.add(_maxBuySeconds);
  }

  function overrideMaxRestriction(bool canBuyAnyAmount) external {
    overrideMaxBuy = canBuyAnyAmount;
  }

  function reflectionFromToken(uint256 tAmount, bool deductTransferFee)
    public
    view
    returns (uint256)
  {
    require(tAmount <= _tTotal, 'Amount must be less than supply');
    if (!deductTransferFee) {
      (uint256 rAmount, , , , , ) = _getValues(tAmount);
      return rAmount;
    } else {
      (, uint256 rTransferAmount, , , , ) = _getValues(tAmount);
      return rTransferAmount;
    }
  }

  function tokenFromReflection(uint256 rAmount) public view returns (uint256) {
    require(rAmount <= _rTotal, 'Amount must be less than total reflections');
    uint256 currentRate = _getRate();
    return rAmount.div(currentRate);
  }

  function excludeFromReward(address account) public onlyOwner {
    require(!_isExcluded[account], 'Account is already excluded');
    if (_rOwned[account] > 0) {
      _tOwned[account] = tokenFromReflection(_rOwned[account]);
    }
    _isExcluded[account] = true;
    _excluded.push(account);
  }

  function includeInReward(address account) external onlyOwner {
    require(_isExcluded[account], 'Account is already excluded');
    for (uint256 i = 0; i < _excluded.length; i++) {
      if (_excluded[i] == account) {
        _excluded[i] = _excluded[_excluded.length - 1];
        _tOwned[account] = 0;
        _isExcluded[account] = false;
        _excluded.pop();
        break;
      }
    }
  }

  function _approve(
    address owner,
    address spender,
    uint256 amount
  ) private {
    require(owner != address(0), 'ERC20: approve from the zero address');
    require(spender != address(0), 'ERC20: approve to the zero address');

    _allowances[owner][spender] = amount;
    emit Approval(owner, spender, amount);
  }

  function _transfer(
    address from,
    address to,
    uint256 amount
  ) private {
    require(from != address(0), 'ERC20: transfer from the zero address');
    require(to != address(0), 'ERC20: transfer to the zero address');
    require(amount > 0, 'Transfer amount must be greater than zero');
    require(!_isSniper[to], 'You have no power here!');
    require(!_isSniper[msg.sender], 'You have no power here!');

    // buy
    if (
      from == uniswapV2Pair &&
      to != address(uniswapV2Router) &&
      !_isExcludedFromFee[to]
    ) {
      require(tradingOpen, 'Trading not yet enabled.');

      // antibot
      if (block.timestamp == launchTime) {
        _isSniper[to] = true;
        _confirmedSnipers.push(to);
      }

      // check max buy restriction after launch
      if (isEnforcingMaxBuy()) {
        require(
          amount <= balanceOf(uniswapV2Pair).mul(_maxBuyPercent).div(100),
          'you have exceeded the maximum you can buy immediately after launch'
        );
      }
    }

    uint256 contractTokenBalance = balanceOf(address(this));

    //sell
    if (!inSwapAndLiquify && tradingOpen && to == uniswapV2Pair) {
      if (contractTokenBalance > 0) {
        if (
          contractTokenBalance >
          balanceOf(uniswapV2Pair).mul(_maxPriceImpPerc).div(100)
        ) {
          contractTokenBalance = balanceOf(uniswapV2Pair)
            .mul(_maxPriceImpPerc)
            .div(100);
        }
        swapTokens(contractTokenBalance);
      }
    }

    bool takeFee = false;

    //take fee only on swaps
    if (
      (from == uniswapV2Pair || to == uniswapV2Pair) &&
      !(_isExcludedFromFee[from] || _isExcludedFromFee[to])
    ) {
      takeFee = true;
    }

    _checkAndStopBurning();

    _tokenTransfer(from, to, amount, takeFee);
  }

  function swapTokens(uint256 contractTokenBalance) private lockTheSwap {
    swapTokensForEth(contractTokenBalance);

    //Send to Marketing address
    uint256 contractETHBalance = address(this).balance;
    if (contractETHBalance > 0) {
      sendETHToMarketing(address(this).balance);
    }
  }

  function _checkAndStopBurning() private {
    if (_burnFee == 0) return;
    uint256 _supplyNotBurned = totalSupply().sub(balanceOf(deadAddress));
    if (_supplyNotBurned <= _supplyToStopBurning) {
      setBurnFeePercent(0);
    }
  }

  function sendETHToMarketing(uint256 amount) private {
    // marketingAddress.transfer(amount);
    // Ignore the boolean return value. If it gets stuck, then retrieve via `emergencyWithdraw`.
    marketingAddress.call{ value: amount }('');
  }

  function swapTokensForEth(uint256 tokenAmount) private {
    // generate the uniswap pair path of token -> weth
    address[] memory path = new address[](2);
    path[0] = address(this);
    path[1] = uniswapV2Router.WETH();

    _approve(address(this), address(uniswapV2Router), tokenAmount);

    // make the swap
    uniswapV2Router.swapExactTokensForETHSupportingFeeOnTransferTokens(
      tokenAmount,
      0, // accept any amount of ETH
      path,
      address(this), // The contract
      block.timestamp
    );

    emit SwapTokensForETH(tokenAmount, path);
  }

  function addLiquidity(uint256 tokenAmount, uint256 ethAmount) private {
    // approve token transfer to cover all possible scenarios
    _approve(address(this), address(uniswapV2Router), tokenAmount);

    // add the liquidity
    uniswapV2Router.addLiquidityETH{ value: ethAmount }(
      address(this),
      tokenAmount,
      0, // slippage is unavoidable
      0, // slippage is unavoidable
      owner(),
      block.timestamp
    );
  }

  function _tokenTransfer(
    address sender,
    address recipient,
    uint256 amount,
    bool takeFee
  ) private {
    if (!takeFee) removeAllFee();

    if (_isExcluded[sender] && !_isExcluded[recipient]) {
      _transferFromExcluded(sender, recipient, amount);
    } else if (!_isExcluded[sender] && _isExcluded[recipient]) {
      _transferToExcluded(sender, recipient, amount);
    } else if (_isExcluded[sender] && _isExcluded[recipient]) {
      _transferBothExcluded(sender, recipient, amount);
    } else {
      _transferStandard(sender, recipient, amount);
    }

    if (!takeFee) restoreAllFee();
  }

  function _transferStandard(
    address sender,
    address recipient,
    uint256 tAmount
  ) private {
    (
      uint256 rAmount,
      uint256 rTransferAmount,
      uint256 rFee,
      ,
      uint256 tFee,
      uint256 tLiquidity
    ) = _getValues(tAmount);
    _rOwned[sender] = _rOwned[sender].sub(rAmount);

    uint256 _recipientBalBefore = balanceOf(recipient);
    uint256 _deadBalBefore = balanceOf(deadAddress);

    (uint256 rBurnAmount, ) = _adjustReflectBalanceRefs(
      recipient,
      rTransferAmount
    );
    _takeLiquidityReflectAndEmitTransfers(
      sender,
      recipient,
      _recipientBalBefore,
      _deadBalBefore,
      rBurnAmount,
      tLiquidity,
      rFee,
      tFee
    );
  }

  function _transferToExcluded(
    address sender,
    address recipient,
    uint256 tAmount
  ) private {
    (
      uint256 rAmount,
      uint256 rTransferAmount,
      uint256 rFee,
      uint256 tTransferAmount,
      uint256 tFee,
      uint256 tLiquidity
    ) = _getValues(tAmount);
    _rOwned[sender] = _rOwned[sender].sub(rAmount);

    uint256 _recipientBalBefore = balanceOf(recipient);
    uint256 _deadBalBefore = balanceOf(deadAddress);

    _adjustTotalBalanceRefs(recipient, tTransferAmount, rTransferAmount);
    (uint256 rBurnAmount, ) = _adjustReflectBalanceRefs(
      recipient,
      rTransferAmount
    );
    _takeLiquidityReflectAndEmitTransfers(
      sender,
      recipient,
      _recipientBalBefore,
      _deadBalBefore,
      rBurnAmount,
      tLiquidity,
      rFee,
      tFee
    );
  }

  function _transferFromExcluded(
    address sender,
    address recipient,
    uint256 tAmount
  ) private {
    (
      uint256 rAmount,
      uint256 rTransferAmount,
      uint256 rFee,
      ,
      uint256 tFee,
      uint256 tLiquidity
    ) = _getValues(tAmount);
    _tOwned[sender] = _tOwned[sender].sub(tAmount);
    _rOwned[sender] = _rOwned[sender].sub(rAmount);

    uint256 _recipientBalBefore = balanceOf(recipient);
    uint256 _deadBalBefore = balanceOf(deadAddress);

    (uint256 rBurnAmount, ) = _adjustReflectBalanceRefs(
      recipient,
      rTransferAmount
    );
    _takeLiquidityReflectAndEmitTransfers(
      sender,
      recipient,
      _recipientBalBefore,
      _deadBalBefore,
      rBurnAmount,
      tLiquidity,
      rFee,
      tFee
    );
  }

  function _transferBothExcluded(
    address sender,
    address recipient,
    uint256 tAmount
  ) private {
    (
      uint256 rAmount,
      uint256 rTransferAmount,
      uint256 rFee,
      uint256 tTransferAmount,
      uint256 tFee,
      uint256 tLiquidity
    ) = _getValues(tAmount);
    _tOwned[sender] = _tOwned[sender].sub(tAmount);
    _rOwned[sender] = _rOwned[sender].sub(rAmount);

    uint256 _recipientBalBefore = balanceOf(recipient);
    uint256 _deadBalBefore = balanceOf(deadAddress);

    _adjustTotalBalanceRefs(recipient, tTransferAmount, rTransferAmount);
    (uint256 rBurnAmount, ) = _adjustReflectBalanceRefs(
      recipient,
      rTransferAmount
    );
    _takeLiquidityReflectAndEmitTransfers(
      sender,
      recipient,
      _recipientBalBefore,
      _deadBalBefore,
      rBurnAmount,
      tLiquidity,
      rFee,
      tFee
    );
  }

  function _adjustTotalBalanceRefs(
    address recipient,
    uint256 tTransferAmount,
    uint256 rTransferAmount
  ) private {
    uint256 tBurnAmount = calculateBurnFee(tTransferAmount);
    uint256 tRecipientAmount = rTransferAmount.sub(tBurnAmount);
    _tOwned[recipient] = _tOwned[recipient].add(tRecipientAmount);
    _tOwned[deadAddress] = _tOwned[deadAddress].add(tBurnAmount);
  }

  function _adjustReflectBalanceRefs(address recipient, uint256 rTransferAmount)
    private
    returns (uint256, uint256)
  {
    uint256 rBurnAmount = calculateBurnFee(rTransferAmount);
    uint256 rRecipientAmount = rTransferAmount.sub(rBurnAmount);
    _rOwned[recipient] = _rOwned[recipient].add(rRecipientAmount);
    _rOwned[deadAddress] = _rOwned[deadAddress].add(rBurnAmount);
    return (rBurnAmount, rRecipientAmount);
  }

  function _takeLiquidityReflectAndEmitTransfers(
    address sender,
    address recipient,
    uint256 recipientBalBefore,
    uint256 deadBalBefore,
    uint256 rBurnAmount,
    uint256 tLiquidity,
    uint256 rFee,
    uint256 tFee
  ) private {
    _takeLiquidity(tLiquidity);
    _reflectFee(rFee, tFee);
    emit Transfer(
      sender,
      recipient,
      balanceOf(recipient).sub(recipientBalBefore)
    );
    if (rBurnAmount > 0) {
      emit Transfer(
        sender,
        deadAddress,
        balanceOf(deadAddress).sub(deadBalBefore)
      );
    }
  }

  function _reflectFee(uint256 rFee, uint256 tFee) private {
    _rTotal = _rTotal.sub(rFee);
    _tFeeTotal = _tFeeTotal.add(tFee);
  }

  function _getValues(uint256 tAmount)
    private
    view
    returns (
      uint256,
      uint256,
      uint256,
      uint256,
      uint256,
      uint256
    )
  {
    (uint256 tTransferAmount, uint256 tFee, uint256 tLiquidity) = _getTValues(
      tAmount
    );
    (uint256 rAmount, uint256 rTransferAmount, uint256 rFee) = _getRValues(
      tAmount,
      tFee,
      tLiquidity,
      _getRate()
    );
    return (rAmount, rTransferAmount, rFee, tTransferAmount, tFee, tLiquidity);
  }

  function _getTValues(uint256 tAmount)
    private
    view
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    uint256 tFee = calculateTaxFee(tAmount);
    uint256 tLiquidity = calculateLiquidityFee(tAmount);
    uint256 tTransferAmount = tAmount.sub(tFee).sub(tLiquidity);
    return (tTransferAmount, tFee, tLiquidity);
  }

  function _getRValues(
    uint256 tAmount,
    uint256 tFee,
    uint256 tLiquidity,
    uint256 currentRate
  )
    private
    pure
    returns (
      uint256,
      uint256,
      uint256
    )
  {
    uint256 rAmount = tAmount.mul(currentRate);
    uint256 rFee = tFee.mul(currentRate);
    uint256 rLiquidity = tLiquidity.mul(currentRate);
    uint256 rTransferAmount = rAmount.sub(rFee).sub(rLiquidity);
    return (rAmount, rTransferAmount, rFee);
  }

  function _getRate() private view returns (uint256) {
    (uint256 rSupply, uint256 tSupply) = _getCurrentSupply();
    return rSupply.div(tSupply);
  }

  function _getCurrentSupply() private view returns (uint256, uint256) {
    uint256 rSupply = _rTotal;
    uint256 tSupply = _tTotal;
    for (uint256 i = 0; i < _excluded.length; i++) {
      if (_rOwned[_excluded[i]] > rSupply || _tOwned[_excluded[i]] > tSupply)
        return (_rTotal, _tTotal);
      rSupply = rSupply.sub(_rOwned[_excluded[i]]);
      tSupply = tSupply.sub(_tOwned[_excluded[i]]);
    }
    if (rSupply < _rTotal.div(_tTotal)) return (_rTotal, _tTotal);
    return (rSupply, tSupply);
  }

  function _takeLiquidity(uint256 tLiquidity) private {
    uint256 currentRate = _getRate();
    uint256 rLiquidity = tLiquidity.mul(currentRate);
    _rOwned[address(this)] = _rOwned[address(this)].add(rLiquidity);
    if (_isExcluded[address(this)])
      _tOwned[address(this)] = _tOwned[address(this)].add(tLiquidity);
  }

  function calculateTaxFee(uint256 _amount) private view returns (uint256) {
    return _amount.mul(_taxFee).div(10**2);
  }

  function calculateLiquidityFee(uint256 _amount)
    private
    view
    returns (uint256)
  {
    return _amount.mul(_liquidityFee).div(10**2);
  }

  function calculateBurnFee(uint256 _amount) private view returns (uint256) {
    return _amount.mul(_burnFee).div(10**2);
  }

  function removeAllFee() private {
    if (_taxFee == 0 && _liquidityFee == 0) return;

    _previousTaxFee = _taxFee;
    _previousLiquidityFee = _liquidityFee;
    _previousBurnFee = _burnFee;

    _taxFee = 0;
    _liquidityFee = 0;
    _burnFee = 0;
  }

  function restoreAllFee() private {
    _taxFee = _previousTaxFee;
    _liquidityFee = _previousLiquidityFee;
    _burnFee = _previousBurnFee;
  }

  function isExcludedFromFee(address account) public view returns (bool) {
    return _isExcludedFromFee[account];
  }

  function excludeFromFee(address account) public onlyOwner {
    _isExcludedFromFee[account] = true;
  }

  function includeInFee(address account) public onlyOwner {
    _isExcludedFromFee[account] = false;
  }

  function setTaxFeePercent(uint256 taxFee) external onlyOwner {
    _taxFee = taxFee;
  }

  function setLiquidityFeePercent(uint256 liquidityFee) external onlyOwner {
    _liquidityFee = liquidityFee;
  }

  function setBurnFeePercent(uint256 burnFee) public onlyOwner {
    _burnFee = burnFee;
  }

  function setSupplyToStopBurning(uint256 supplyToStopBurning)
    external
    onlyOwner
  {
    _supplyToStopBurning = supplyToStopBurning;
  }

  function setMarketingAddress(address _marketingAddress) external onlyOwner {
    marketingAddress = payable(_marketingAddress);
  }

  function transferToAddressETH(address payable recipient, uint256 amount)
    private
  {
    // recipient.transfer(amount);
    // Ignore the boolean return value. If it gets stuck, then retrieve via `emergencyWithdraw`.
    recipient.call{ value: amount }('');
  }

  function isRemovedSniper(address account) public view returns (bool) {
    return _isSniper[account];
  }

  function _removeSniper(address account) external onlyOwner {
    require(account != _uniswapRouterAddress, 'We can not blacklist Uniswap');
    require(!_isSniper[account], 'Account is already blacklisted');
    _isSniper[account] = true;
    _confirmedSnipers.push(account);
  }

  function _amnestySniper(address account) external onlyOwner {
    require(_isSniper[account], 'Account is not blacklisted');
    for (uint256 i = 0; i < _confirmedSnipers.length; i++) {
      if (_confirmedSnipers[i] == account) {
        _confirmedSnipers[i] = _confirmedSnipers[_confirmedSnipers.length - 1];
        _isSniper[account] = false;
        _confirmedSnipers.pop();
        break;
      }
    }
  }

  function setMaxPriceImpPerc(uint256 rate) external onlyOwner {
    _maxPriceImpPerc = rate;
  }

  // Withdraw ETH that gets stuck in contract by accident
  function emergencyWithdraw() external onlyOwner {
    payable(owner()).send(address(this).balance);
  }

  //to recieve ETH from uniswapV2Router when swaping
  receive() external payable {}
}
