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
    uint transferError = uint(doTransferIn(msg.sender, mintAmount));
    require(transferError == uint(Error.NO_ERROR), "underlying transfer failed");

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
    uint preTokenBalance = cErc20.balanceOf(address(this));

    uint redeemError = cErc20.redeemUnderlying(redeemAmount);
    require(redeemError == uint(Error.NO_ERROR), "underlying redeeming failed");

    uint postTokenBalance = cErc20.balanceOf(address(this));

    uint redeemedTokens = preTokenBalance.sub(postTokenBalance);

    uint transferError = uint(doTransferOut(msg.sender, redeemAmount));
    require(transferError == uint(Error.NO_ERROR), "underlying transfer failed");


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
      accountTokens[msg.sender] = getUpdatedAccountTokens(account);
      accountRatioUpdatedAt[account] = block.number;
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
    return getUpdatedAccountTokens(account).sub(accountUnderlying[msg.sender]);
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

    uint transferError = uint(doTransferOut(msg.sender, currentEarnings));
    require(transferError == uint(Error.NO_ERROR), "underlying transfer failed");

    totalTokens = totalTokens.sub(redeemedTokens);
    totalEarnings = totalEarnings.add(currentEarnings);

    earningsExchangeRateExp = cErc20.exchangeRateStored();
    earningsRatioUpdatedAt = block.number;

    emit Redeem(msg.sender, currentEarnings, redeemedTokens);

  }


  /* ERC20 HELPERS */

  /**
   * @dev Checks whether or not there is sufficient allowance for this contract to move amount from `from` and
   *      whether or not `from` has a balance of at least `amount`. Does NOT do a transfer.
   */
  function checkTransferIn(address from, uint amount) internal view returns (Error) {
      EIP20Interface token = EIP20Interface(underlying);

      if (token.allowance(from, address(this)) < amount) {
          return Error.TOKEN_INSUFFICIENT_ALLOWANCE;
      }

      if (token.balanceOf(from) < amount) {
          return Error.TOKEN_INSUFFICIENT_BALANCE;
      }

      return Error.NO_ERROR;
  }

  /**
   * @dev Similar to EIP20 transfer, except it handles a False result from `transferFrom` and returns an explanatory
   *      error code rather than reverting.  If caller has not called `checkTransferIn`, this may revert due to
   *      insufficient balance or insufficient allowance. If caller has called `checkTransferIn` prior to this call,
   *      and it returned Error.NO_ERROR, this should not revert in normal conditions.
   *
   *      Note: This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
   *            See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
   */
  function doTransferIn(address from, uint amount) internal returns (Error) {
      EIP20NonStandardInterface token = EIP20NonStandardInterface(underlying);
      bool result;

      token.transferFrom(from, address(this), amount);

      // solium-disable-next-line security/no-inline-assembly
      assembly {
          switch returndatasize()
              case 0 {                      // This is a non-standard ERC-20
                  result := not(0)          // set result to true
              }
              case 32 {                     // This is a complaint ERC-20
                  returndatacopy(0, 0, 32)
                  result := mload(0)        // Set `result = returndata` of external call
              }
              default {                     // This is an excessively non-compliant ERC-20, revert.
                  revert(0, 0)
              }
      }

      if (!result) {
          return Error.TOKEN_TRANSFER_IN_FAILED;
      }

      return Error.NO_ERROR;
  }

  /**
   * @dev Similar to EIP20 transfer, except it handles a False result from `transfer` and returns an explanatory
   *      error code rather than reverting. If caller has not called checked protocol's balance, this may revert due to
   *      insufficient cash held in this contract. If caller has checked protocol's balance prior to this call, and verified
   *      it is >= amount, this should not revert in normal conditions.
   *
   *      Note: This wrapper safely handles non-standard ERC-20 tokens that do not return a value.
   *            See here: https://medium.com/coinmonks/missing-return-value-bug-at-least-130-tokens-affected-d67bf08521ca
   */
  function doTransferOut(address payable to, uint amount) internal returns (Error) {
      EIP20NonStandardInterface token = EIP20NonStandardInterface(underlying);
      bool result;

      token.transfer(to, amount);

      // solium-disable-next-line security/no-inline-assembly
      assembly {
          switch returndatasize()
              case 0 {                      // This is a non-standard ERC-20
                  result := not(0)          // set result to true
              }
              case 32 {                     // This is a complaint ERC-20
                  returndatacopy(0, 0, 32)
                  result := mload(0)        // Set `result = returndata` of external call
              }
              default {                     // This is an excessively non-compliant ERC-20, revert.
                  revert(0, 0)
              }
      }

      if (!result) {
          return Error.TOKEN_TRANSFER_OUT_FAILED;
      }

      return Error.NO_ERROR;
  }
}
