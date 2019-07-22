pragma solidity ^0.5.8;

import "openzeppelin-solidity/contracts/math/SafeMath.sol";
import 'openzeppelin-solidity/contracts/ownership/Ownable.sol';

import './compound/CErc20.sol';
import './compound/ErrorReporter.sol';

contract SupplyPool is Ownable, TokenErrorReporter {
  using SafeMath for uint;

  /*
   * @notice Constructor: Instantiate SupplyPool contract.
   * @dev Constructor function.
   */
  address public underlying;
  CErc20 public cErc20;

  /**
   * @notice Event emitted when tokens are minted
   */
  event Mint(address minter, uint mintAmount, uint mintTokens);

  /**
   * @notice Event emitted when tokens are redeemed
   */
  event Redeem(address redeemer, uint redeemAmount, uint redeemTokens);

  /**
   * @notice Official record of cToken balances for each account
   */
  mapping (address => uint256) public accountTokens;

  mapping (address => uint256) public accountRatioUpdatedAt;

  mapping (address => uint256) public accountPastEarnings;

  /**
   * @notice Official record of underlying balances for each account
   */
  mapping (address => uint256) public accountUnderlying;


  uint public ownerFeeExp; // * 1e18;

  uint public earningsExchangeRateExp;
  uint public earningsRatioUpdatedAt;

  uint public totalTokens;
  uint public totalLockedUnderlying;
  uint public totalEarnings;

  constructor(address underlying_, CErc20 cErc20_) public {
    // Set underlying, Compound and cErc20 addresses.

    EIP20Interface token = EIP20Interface(underlying_);
    token.totalSupply();
    require(token.approve(address(cErc20_), uint(-1)));

    require(cErc20_.isCToken());
    require(cErc20_.underlying() == address(underlying_));

    underlying = underlying_;
    cErc20 = cErc20_;
  }

  function isSupplyPool() external pure returns (bool) {
    return true;
  }

  /**
   * @notice Sender supplies assets into the market and receives cTokens in exchange
   * @dev Accrues interest whether or not the operation succeeds, unless reverted
   * @param mintAmount The amount of the underlying asset to supply
   * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
   */
  function mint(uint mintAmount) external returns (uint) {
    // TODO On Prod Use accure interest first to have a stable interest rate through the entire excecution

    EIP20NonStandardInterface token = EIP20NonStandardInterface(underlying);
    token.transferFrom(msg.sender, address(this), mintAmount);

    uint preMintTokenBalance = cErc20.balanceOf(address(this));
    uint mintError = cErc20.mint(mintAmount);
    require(mintError == uint(Error.NO_ERROR), "token minting failed");
    uint postMintTokenBalance = cErc20.balanceOf(address(this));

    uint mintedTokens = postMintTokenBalance.sub(preMintTokenBalance);

    // First we update token values
    totalTokens = totalTokens.add(mintedTokens);
    updateAccountTokens(msg.sender);
    accountTokens[msg.sender] = accountTokens[msg.sender].add(mintedTokens);

    // Then we update underlying values
    accountUnderlying[msg.sender] = accountUnderlying[msg.sender].add(mintAmount);
    totalLockedUnderlying = totalLockedUnderlying.add(mintAmount);

    emit Mint(msg.sender, mintAmount, mintedTokens);

    return mintError;
  }

  /**
   * @notice Sender redeems cTokens in exchange for a specified amount of underlying asset
   * @dev Accrues interest whether or not the operation succeeds, unless reverted
   * @param redeemAmount The amount of underlying to redeem
   * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
   */
  function redeemUnderlying(uint redeemAmount) external returns (uint) {
    require(accountUnderlying[msg.sender] >= redeemAmount, "redeem amount exceeds account underlying balance");

    // TODO On Prod Use accure interest first to have a stable interest rate through the entire excecution

    uint preTokenBalance = cErc20.balanceOf(address(this));

    uint redeemError = cErc20.redeemUnderlying(redeemAmount);
    require(redeemError == uint(Error.NO_ERROR), "underlying redeeming failed");

    uint postTokenBalance = cErc20.balanceOf(address(this));

    uint redeemedTokens = preTokenBalance.sub(postTokenBalance);

    EIP20NonStandardInterface token = EIP20NonStandardInterface(underlying);
    token.transfer(msg.sender, redeemAmount);

    // First we update token values
    totalTokens = totalTokens.sub(redeemedTokens);
    updateAccountTokens(msg.sender);
    accountTokens[msg.sender] = accountTokens[msg.sender].sub(redeemedTokens);

    // Then we update underlying values
    accountUnderlying[msg.sender] = accountUnderlying[msg.sender].sub(redeemAmount);
    totalLockedUnderlying = totalLockedUnderlying.sub(redeemAmount);

    emit Redeem(msg.sender, redeemAmount, redeemedTokens);

    return redeemError;
  }

  function updateAccountTokens(address account) public {
    if (accountRatioUpdatedAt[account] < earningsRatioUpdatedAt) {
      uint preUpdateTokens = accountTokens[account];
      accountTokens[account] = getUpdatedAccountTokens(account);
      accountRatioUpdatedAt[account] = block.number;

      uint tokensTakenFromAccount = preUpdateTokens.sub(accountTokens[account]);
      uint underlyingEarningsOfAccount = tokensTakenFromAccount.mul(earningsExchangeRateExp).div(1e18);
      accountPastEarnings[account] = accountPastEarnings[account].add(underlyingEarningsOfAccount);
    }
  }

  function getUpdatedAccountTokens(address account) public view returns (uint) {
    if (accountRatioUpdatedAt[account] < earningsRatioUpdatedAt) {
      return accountUnderlying[msg.sender].mul(1e18).div(earningsExchangeRateExp);
    }
    return accountTokens[msg.sender];
  }


  function getCurrentEarning() public returns (uint) {
    uint underlyingBalance = cErc20.balanceOfUnderlying(address(this));
    return underlyingBalance.sub(totalLockedUnderlying);
  }

  function balanceOf(address account) external view returns (uint) {
    return getUpdatedAccountTokens(account);
  }

  function earningsOf(address account) external view returns (uint) {
    return getUpdatedAccountTokens(account).add(accountPastEarnings[account]).sub(accountUnderlying[account]);
  }

  function pastEarningsOf(address account) external view returns (uint) {
    return accountPastEarnings[account];
  }


  /* ADMIN HELPERS */

  function takeEarnings() public onlyOwner {
    uint currentEarnings = getCurrentEarning();

    require(currentEarnings > 0);

    uint preTokenBalance = cErc20.balanceOf(address(this));

    uint redeemError = cErc20.redeemUnderlying(currentEarnings);
    require(redeemError == uint(Error.NO_ERROR), "underlying redeeming failed");

    uint postTokenBalance = cErc20.balanceOf(address(this));

    uint redeemedTokens = preTokenBalance.sub(postTokenBalance);

    EIP20NonStandardInterface token = EIP20NonStandardInterface(underlying);
    token.transfer(msg.sender, currentEarnings);

    totalTokens = totalTokens.sub(redeemedTokens);
    totalEarnings = totalEarnings.add(currentEarnings);

    earningsExchangeRateExp = cErc20.exchangeRateStored();
    earningsRatioUpdatedAt = block.number;

    emit Redeem(msg.sender, currentEarnings, redeemedTokens);

  }

}
