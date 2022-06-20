// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import '@openzeppelin/contracts/access/Ownable.sol';
import '@openzeppelin/contracts/token/ERC20/IERC20.sol';

interface IERC20Decimals is IERC20 {
  function decimals() external view returns (uint8);
}

/**
 * @title SHEDSwap
 * @dev Swap SHED for Metis/BNB
 */
contract SHEDSwap is Ownable {
  IERC20Decimals private shed =
    IERC20Decimals(0x8420Cb59B1718Da87c0DCD7bB2E64525B0AD61A1);
  IERC20Decimals private metis =
    IERC20Decimals(0xe552Fb52a4F19e44ef5A967632DBc320B0820639);

  uint256 public shedPerBnb = 2100763666;
  uint256 public shedPerMetis = 1076973778;

  mapping(address => bool) public swapped;

  function swap() external {
    require(!swapped[msg.sender], 'already swapped');
    swapped[msg.sender] = true;

    uint256 _shedBalance = shed.balanceOf(msg.sender);
    require(_shedBalance > 0, 'you do not have any SHED to swap');
    shed.transferFrom(msg.sender, address(this), _shedBalance);

    // handle BNB reimbursement
    uint256 _bnbToReimburse = getBnbToReimburse(_shedBalance);
    require(
      address(this).balance >= _bnbToReimburse,
      'not enough BNB to reimburse'
    );
    (bool success, ) = payable(msg.sender).call{ value: _bnbToReimburse }('');
    require(success, 'did not successfully reimburse BNB');

    // handle Metis reimbursement
    uint256 _metisToReimburse = getMetisToReimburse(_shedBalance);
    require(
      metis.balanceOf(address(this)) >= _metisToReimburse,
      'not enough Metis to reimburse'
    );
    metis.transfer(msg.sender, _metisToReimburse);
  }

  function getBnbToReimburse(uint256 _shedBalance)
    public
    view
    returns (uint256)
  {
    return (_shedBalance * 10**18) / (shedPerBnb * shed.decimals());
  }

  function getMetisToReimburse(uint256 _shedBalance)
    public
    view
    returns (uint256)
  {
    return (_shedBalance * metis.decimals()) / (shedPerMetis * shed.decimals());
  }

  function getShed() external view returns (address) {
    return address(shed);
  }

  function getMetis() external view returns (address) {
    return address(metis);
  }

  function setShedPerBnb(uint256 _ratio) external onlyOwner {
    shedPerBnb = _ratio;
  }

  function setShedPerMetis(uint256 _ratio) external onlyOwner {
    shedPerMetis = _ratio;
  }

  function setSwapped(address _wallet, bool _swapped) external onlyOwner {
    swapped[_wallet] = _swapped;
  }

  function withdrawTokens(address _tokenAddy, uint256 _amount)
    external
    onlyOwner
  {
    IERC20 _token = IERC20(_tokenAddy);
    _amount = _amount > 0 ? _amount : _token.balanceOf(address(this));
    require(_amount > 0, 'make sure there is a balance available to withdraw');
    _token.transfer(owner(), _amount);
  }

  function withdrawETH(uint256 _amountWei) external onlyOwner {
    _amountWei = _amountWei == 0 ? address(this).balance : _amountWei;
    payable(owner()).call{ value: _amountWei }('');
  }

  receive() external payable {}
}
