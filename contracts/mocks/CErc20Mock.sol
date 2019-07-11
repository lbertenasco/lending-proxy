pragma solidity ^0.5.8;
import "openzeppelin-solidity/contracts/math/SafeMath.sol";

import '../compound/EIP20NonStandardInterface.sol';
import '../compound/EIP20Interface.sol';
import '../compound/ErrorReporter.sol';

contract CErc20Mock is TokenErrorReporter {
    using SafeMath for uint;

    bool public constant isCToken = true;

    /**
     * @notice Underlying asset for this CToken
     */
    address public underlying;

    /**
     * @notice EIP-20 token name for this token
     */
    string public name;

    /**
     * @notice EIP-20 token symbol for this token
     */
    string public symbol;

    /**
     * @notice EIP-20 token decimals for this token
     */
    uint public decimals;

    /**
     * @notice Total number of tokens in circulation
     */
    uint256 public totalSupply;

    /**
     * @notice Official record of token balances for each account
     */
    mapping (address => uint256) public accountTokens;

    /**
     * @notice Construct a new money market
     * @param underlying_ The address of the underlying asset
     * @param name_ ERC-20 name of this token
     * @param symbol_ ERC-20 symbol of this token
     * @param decimals_ ERC-20 decimal precision of this token
     */
    constructor(address underlying_,
                string memory name_,
                string memory symbol_,
                uint decimals_) public {
        name = name_;
        symbol = symbol_;
        decimals = decimals_;
        // Set underlying
        underlying = underlying_;
        EIP20Interface(underlying).totalSupply(); // Sanity check the underlying
    }

    /*** User Interface ***/

    /**
     * @notice Sender supplies assets into the market and receives cTokens in exchange
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param mintAmount The amount of the underlying asset to supply
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function mint(uint mintAmount) external returns (uint) {
      uint tokenExpValue = getExpTokenValue();

      uint mintedTokens = (mintAmount.mul(1e18)).div(tokenExpValue);

      totalSupply = totalSupply.add(mintedTokens);
      accountTokens[msg.sender] = accountTokens[msg.sender].add(mintedTokens);
      return uint(doTransferIn(msg.sender, mintAmount));
    }

    function supplyUnderlying(uint supplyAmount) external returns (uint) {
      return uint(doTransferIn(msg.sender, supplyAmount));
    }

    /**
     * @notice Sender redeems cTokens in exchange for the underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemTokens The number of cTokens to redeem into underlying
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeem(uint redeemTokens) external returns (uint) {
      /* return redeemInternal(redeemTokens); */
      // TODO Add % of exchangeRate here
      totalSupply = totalSupply.sub(redeemTokens);
      accountTokens[msg.sender] = accountTokens[msg.sender].sub(redeemTokens);
      // TODO FIX ME
      return uint(doTransferOut(msg.sender, redeemTokens));
    }

    /**
     * @notice Sender redeems cTokens in exchange for a specified amount of underlying asset
     * @dev Accrues interest whether or not the operation succeeds, unless reverted
     * @param redeemAmount The amount of underlying to redeem
     * @return uint 0=success, otherwise a failure (see ErrorReporter.sol for details)
     */
    function redeemUnderlying(uint redeemAmount) external returns (uint) {
      uint tokenExpValue = getExpTokenValue();

      uint redeemTokens = redeemAmount.mul(1e18).div(tokenExpValue);

      totalSupply = totalSupply.sub(redeemTokens);
      accountTokens[msg.sender] = accountTokens[msg.sender].sub(redeemTokens);
      return uint(doTransferOut(msg.sender, redeemAmount));
    }

    /**
     * @notice Get the token balance of the `owner`
     * @param owner The address of the account to query
     * @return The number of tokens owned by `owner`
     */
    function balanceOf(address owner) external view returns (uint256) {
      return accountTokens[owner];
    }

    /**
     * @notice Get the underlying balance of the `owner`
     * @dev This also accrues interest in a transaction
     * @param owner The address of the account to query
     * @return The amount of underlying owned by `owner`
     */
    function balanceOfUnderlying(address owner) public returns (uint) {
      uint underlyingBalance = EIP20Interface(underlying).balanceOf(address(this));
      if (accountTokens[owner] == 0) return 0;
      uint tokenExpValue = getExpTokenValue();
      return (totalSupply.mul(1e18).div(accountTokens[owner])).mul(underlyingBalance).div(1e18);
      /* return tokenExpValue.mul().div(1e18); */
      /* return totalSupply.div(accountTokens[owner]).mul(underlyingBalance); */
    }


    function getExpTokenValue() public view returns (uint) {
      uint totalUnderlying = EIP20Interface(underlying).balanceOf(address(this));
      uint tokenValue = 1e18;
      if (totalSupply > 0 && totalUnderlying > 0) {
        totalUnderlying = totalUnderlying.mul(1e18);
        tokenValue = totalUnderlying.div(totalSupply);
      }
      return tokenValue;
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
