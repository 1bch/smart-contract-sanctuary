// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/SafeERC20Upgradeable.sol";
import "@openzeppelin/contracts/proxy/Initializable.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../interfaces/ICERC20.sol";
import "../interfaces/IAdapter.sol";
import "../interfaces/INutmeg.sol";
import "../lib/Governable.sol";

contract CompoundAdapter is Governable, IAdapter {
    using SafeMath for uint;
    using SafeERC20Upgradeable for IERC20Upgradeable;

    struct PosInfo {
        uint collAmt;
        uint sumIpcStart;
    }

    address public nutmeg;

    uint private constant MULTIPLIER = 10**18;

    address[] public baseTokens; // array of base tokens
    mapping(address => bool) public baseTokenMap; // e.g., Dai
    mapping(address => address) public tokenPairs; // Dai -> cDai or cDai -> Dai;
    mapping(address => uint) public totalMintAmt;
    mapping(address => uint) public sumIpcMap;
    mapping(uint => PosInfo) public posInfoMap;

    mapping(address => uint) public totalLoan;
    mapping(address => uint) public totalCollateral;
    mapping(address => uint) public totalLoss;

    function initialize(address nutmegAddr, address governorAddr) external initializer {
        nutmeg = nutmegAddr;
        __Governable__init(governorAddr);
    }

    modifier onlyNutmeg() {
        require(msg.sender == nutmeg, 'only nutmeg can call');
        _;
    }

    /// @dev Add baseToken collToken pairs
    function addTokenPair(address baseToken, address collToken) external onlyGov {
        baseTokenMap[baseToken] = true;
        tokenPairs[baseToken] = collToken;
        baseTokens.push(baseToken);
    }

    /// @dev Remove baseToken collToken pairs
    function removeTokenPair(address baseToken) external onlyGov {
        baseTokenMap[baseToken] = false;
        tokenPairs[baseToken] = address(0);
    }

    /// @notice Open a position.
    /// @param baseToken Base token of the position.
    /// @param collToken Collateral token of the position.
    /// @param baseAmt Amount of collateral in base token.
    /// @param borrowAmt Amount of base token to be borrowed from nutmeg.
    function openPosition(address baseToken, address collToken, uint baseAmt, uint borrowAmt)
        external onlyNutmeg override {
        require(baseAmt > 0, 'openPosition: invalid base amount');
        require(baseTokenMap[baseToken], 'openPosition: invalid baseToken address');
        require(tokenPairs[baseToken] == collToken, 'openPosition: invalid cToken address');

        uint posId = INutmeg(nutmeg).getCurrPositionId();
        INutmeg.Position memory pos = INutmeg(nutmeg).getPosition(posId);
        require(IERC20Upgradeable(baseToken).balanceOf(pos.owner) >= baseAmt, 'openPosition: insufficient balance');

        // borrow base tokens from nutmeg
        INutmeg(nutmeg).borrow(baseToken, collToken, baseAmt, borrowAmt);

        _increaseDebtAndCollateral(baseToken, posId);

        // mint collateral tokens from compound
        pos = INutmeg(nutmeg).getPosition(posId);
        uint mintAmt = _doMint(pos, borrowAmt);
        uint currSumIpc = _calcLatestSumIpc(collToken);
        totalMintAmt[collToken] = totalMintAmt[collToken].add(mintAmt);
        PosInfo storage posInfo = posInfoMap[posId];
        posInfo.sumIpcStart = currSumIpc;
        posInfo.collAmt = mintAmt;

        // set the collAmt to the position in nutmeg.
        INutmeg(nutmeg).setCollAmt(posId, mintAmt);
        emit openPositionEvent(posId, INutmeg(nutmeg).getCurrSender(), baseAmt, borrowAmt);
    }

    /// @notice Close a position by the borrower
    function closePosition() external onlyNutmeg override returns (uint) {
        uint posId = INutmeg(nutmeg).getCurrPositionId();
        INutmeg.Position memory pos = INutmeg(nutmeg).getPosition(posId);
        require(pos.owner == INutmeg(nutmeg).getCurrSender(), 'closePosition: original caller is not the owner');

        uint collAmt = _getCollTokenAmount(pos);
        uint redeemAmt = _doRedeem(pos, collAmt);

        // allow nutmeg to receive redeemAmt from the adapter
        IERC20Upgradeable(pos.baseToken).safeApprove(nutmeg, 0);
        IERC20Upgradeable(pos.baseToken).safeApprove(nutmeg, redeemAmt);

        // repay to nutmeg
        _decreaseDebtAndCollateral(pos.baseToken, pos.id, redeemAmt);
        INutmeg(nutmeg).repay(pos.baseToken, redeemAmt);
        pos = INutmeg(nutmeg).getPosition(posId);
        totalLoss[pos.baseToken] =
            totalLoss[pos.baseToken].add(pos.repayDeficit);
        totalMintAmt[pos.collToken] = totalMintAmt[pos.collToken].sub(pos.collAmt);
        emit closePositionEvent(posId, INutmeg(nutmeg).getCurrSender(), redeemAmt);
        return redeemAmt;
    }

    /// @notice Liquidate a position
    function liquidate() external override onlyNutmeg  {
        uint posId = INutmeg(nutmeg).getCurrPositionId();
        INutmeg.Position memory pos = INutmeg(nutmeg).getPosition(posId);
        require(_okToLiquidate(pos), 'liquidate: position is not ready for liquidation yet.');

        uint amount = _getCollTokenAmount(pos);
        uint redeemAmt = _doRedeem(pos, amount);
        IERC20Upgradeable(pos.baseToken).safeApprove(nutmeg, 0);
        IERC20Upgradeable(pos.baseToken).safeApprove(nutmeg, redeemAmt);

        // liquidate the position in nutmeg.
        _decreaseDebtAndCollateral(pos.baseToken, posId, redeemAmt);
        INutmeg(nutmeg).liquidate(pos.baseToken, redeemAmt);
        pos = INutmeg(nutmeg).getPosition(posId);
        totalLoss[pos.baseToken] = totalLoss[pos.baseToken].add(pos.repayDeficit);
        totalMintAmt[pos.collToken] = totalMintAmt[pos.collToken].sub(pos.collAmt);
        emit liquidateEvent(posId, INutmeg(nutmeg).getCurrSender());
    }
    /// @notice Get value of credit tokens
    function creditTokenValue(address baseToken) public returns (uint) {
        address collToken = tokenPairs[baseToken];
        require(collToken != address(0), "settleCreditEvent: invalid collateral token" );
        uint collTokenBal = ICERC20(collToken).balanceOf(address(this));
        return collTokenBal.mul(ICERC20(collToken).exchangeRateCurrent());
    }

    /// @notice Settle credit event
    /// @param baseToken The base token address
    function settleCreditEvent( address baseToken, uint collateralLoss, uint poolLoss) external override onlyNutmeg {
        require(baseTokenMap[baseToken] , "settleCreditEvent: invalid base token" );
        require(collateralLoss <= totalCollateral[baseToken], "settleCreditEvent: invalid collateral" );
        require(poolLoss <= totalLoan[baseToken], "settleCreditEvent: invalid poolLoss" );

        INutmeg(nutmeg).distributeCreditLosses(baseToken, collateralLoss, poolLoss);

        emit creditEvent(baseToken, collateralLoss, poolLoss);
        totalLoss[baseToken] = 0;
        totalLoan[baseToken] = totalLoan[baseToken].sub(poolLoss);
        totalCollateral[baseToken] = totalCollateral[baseToken].sub(collateralLoss);
    }

    function _increaseDebtAndCollateral(address token, uint posId) internal {
        INutmeg.Position memory pos = INutmeg(nutmeg).getPosition(posId);
        totalLoan[token] = totalLoan[token].add(pos.loanAmt);
        totalCollateral[token] = totalCollateral[token].add(pos.baseAmt);
    }

    /// @dev decreaseDebtAndCollateral
    function _decreaseDebtAndCollateral(address token, uint posId, uint redeemAmt) internal {
        INutmeg.Position memory pos = INutmeg(nutmeg).getPosition(posId);
        uint totalLoans = pos.loanAmt;
        if (redeemAmt >= totalLoans) {
            totalLoan[token] = totalLoan[token].sub(totalLoans);
        } else {
            totalLoan[token] = totalLoan[token].sub(redeemAmt);
        }
        totalCollateral[token] = totalCollateral[token].sub(pos.baseAmt);
    }

    /// @dev Do the mint from the 3rd party pool.this
    function _doMint(INutmeg.Position memory pos, uint amount) internal returns(uint) {
        uint balBefore = ICERC20(pos.collToken).balanceOf(address(this));
        IERC20Upgradeable(pos.baseToken).safeApprove(pos.collToken, 0);
        IERC20Upgradeable(pos.baseToken).safeApprove(pos.collToken, amount);
        uint result = ICERC20(pos.collToken).mint(amount);
        require(result == 0, '_doMint mint error');
        uint balAfter = ICERC20(pos.collToken).balanceOf(address(this));
        uint mintAmount = balAfter.sub(balBefore);
        require(mintAmount > 0, 'opnPos: zero mnt');
        return mintAmount;
    }

    /// @dev Do the redeem from the 3rd party pool.
    function _doRedeem(INutmeg.Position memory pos, uint amount) internal returns(uint) {
        uint balBefore = IERC20Upgradeable(pos.baseToken).balanceOf(address(this));
        uint result = ICERC20(pos.collToken).redeem(amount);
        require(result == 0, 'rdm fail');
        uint balAfter = IERC20Upgradeable(pos.baseToken).balanceOf(address(this));
        uint redeemAmt = balAfter.sub(balBefore);
        return redeemAmt;
    }

    /// @dev Get the amount of cTokens a position holds
    function _getCollTokenAmount(INutmeg.Position memory pos) internal returns(uint) {
        uint currSumIpc = _calcLatestSumIpc(pos.collToken);
        PosInfo storage posInfo = posInfoMap[pos.id];
        uint interest = posInfo.collAmt.mul(currSumIpc.sub(posInfo.sumIpcStart)).div(MULTIPLIER);
        return posInfo.collAmt.add(interest);
    }

    /// @dev Calculate the latest sumIpc.
    /// @param collToken The cToken.
    function _calcLatestSumIpc(address collToken) internal returns(uint) {
        uint balance = ICERC20(collToken).balanceOf(address(this));
        uint mintBalance = totalMintAmt[collToken];
        uint interest = mintBalance > balance ? mintBalance.sub(balance) : 0;
        uint currIpc = (mintBalance == 0) ? 0 : (interest.mul(MULTIPLIER)).div(mintBalance);
        sumIpcMap[collToken] = sumIpcMap[collToken].add(currIpc);
        return sumIpcMap[collToken];
    }

    /// @dev Check if the position is eligible to be liquidated.
    function _okToLiquidate(INutmeg.Position memory pos) internal view returns(bool) {
        uint interest = INutmeg(nutmeg).getPositionInterest(pos.baseToken, pos.id);
        return (interest.mul(2) >= pos.baseAmt);
    }

    function version() public virtual pure returns (string memory) {
        return "1.0.4";
    }
}

// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface ICERC20 {
    function mint(uint) external returns (uint);
    function redeem(uint) external returns (uint);
    function transfer(address dst, uint amount) external returns (bool);
    function balanceOf(address) external view returns (uint);
    function redeemUnderlying(uint) external returns (uint);
    function exchangeRateCurrent() external returns (uint);
    function supplyRatePerBlock() external returns (uint);
    function approve(address spender, uint amount) external returns (bool);
}

// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

interface IAdapter {
    function openPosition( address baseToken, address collToken, uint collAmount, uint borrowAmount ) external;
    function closePosition() external returns (uint);
    function liquidate() external;
    function settleCreditEvent(
        address baseToken, uint collateralLoss, uint poolLoss) external;

    event openPositionEvent(uint positionId, address caller, uint baseAmt, uint borrowAmount);
    event closePositionEvent(uint positionId, address caller, uint amount);
    event liquidateEvent(uint positionId, address caller);
    event creditEvent(address token, uint collateralLoss, uint poolLoss);
}

// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface INutmeg {
    enum Tranche {AA, A, BBB}
    enum StakeStatus {Uninitialized, Open, Closed}
    enum PositionStatus {Uninitialized, Open, Closed, Liquidated}

    struct Pool {
        bool isExists;
        address baseToken; // base token of this pool, e.g., WETH, DAI.
        uint[3] interestRates; // interest rate per block of each tranche. supposed to be updated everyday.
        uint[3] principals; // principals of each tranche, from lenders
        uint[3] loans; // loans of each tranche, from borrowers.
        uint[3] interests; // interests accrued from loans for each tranche.

        uint totalCollateral; // total collaterals in base token from borrowers.
        uint latestAccruedBlock; // the block number of the latest interest accrual action.
        uint sumRtb; // sum of interest rate per block (after adjustment) times # of blocks
        uint irAdjustPct; // interest rate adjustment in percentage, e.g., 1, 99.
        bool isIrAdjustPctNegative; // whether interestRateAdjustPct is negative
        uint[3] sumIpp; // sum of interest per principal.
        uint[3] lossMultiplier;
        uint[3] lossZeroCounter;
    }

    struct Stake {
        uint id;
        StakeStatus status;
        address owner;
        address pool;
        uint tranche; // tranche of the pool, 0 - AA, 1 - A, 2 - BBB.
        uint principal;
        uint sumIppStart;
        uint earnedInterest;
        uint lossMultiplierBase;
        uint lossZeroCounterBase;
    }

    struct Position {
        uint id; // id of the position.
        PositionStatus status; // status of the position, Open, Close, and Liquidated.
        address owner; // borrower's address
        address adapter; // adapter's address
        address baseToken; // base token that the borrower borrows from the pool
        address collToken; // collateral token that the borrower got from 3rd party pool.
        uint loanAmt; // loans of all tranches
        uint baseAmt; // amount of the base token the borrower put into pool as the collateral.
        uint collAmt; // amount of collateral token the borrower got from 3rd party pool.
        uint borrowAmt; // amount of base tokens borrowed from the pool.
        uint sumRtbStart; // rate times block when the position is created.
        uint repayDeficit; // repay pool loss
    }

    struct NutDist {
        uint endBlock;
        uint amount;
    }

    /// @dev Get all stake IDs of a lender
    function getStakeIds(address lender) external view returns (uint[] memory);

    /// @dev Get all position IDs of a borrower
    function getPositionIds(address borrower) external view returns (uint[] memory);

    /// @dev Get the maximum available borrow amount
    function getMaxBorrowAmount(address token, uint collAmount) external view returns(uint);

    /// @dev Get the current position while under execution.
    function getCurrPositionId() external view returns (uint);

    /// @dev Get the next position ID while under execution.
    function getNextPositionId() external view returns (uint);

    /// @dev Get the current sender while under execution
    function getCurrSender() external view returns (address);

    function getPosition(uint id) external view returns (Position memory);

    function getPositionInterest(address token, uint positionId) external view returns(uint);

    function getPoolInfo(address token) external view returns(uint, uint, uint);

    /// @dev Set the collateral amount from the 3rd party pool to a position
    function setCollAmt(uint posId, uint collAmt) external;

    /// @dev Borrow tokens from the pool.
    function borrow(address token, address collAddr, uint baseAmount, uint borrowAmount) external;

    /// @dev Repays tokens to the pool.
    function repay(address token, uint repayAmount) external;

    /// @dev Liquidate a position when conditions are satisfied
    function liquidate(address token, uint repayAmount) external;

    /// @dev Settle credit event
    function distributeCreditLosses( address baseToken, uint collateralLoss, uint poolLoss) external;
    event addPoolEvent(address bank, uint interestRateA);
    event stakeEvent(address bank, address owner, uint tranche, uint amount, uint depId);
    event unstakeEvent(address bank, address owner, uint tranche, uint amount, uint depId);
}

// SPDX-License-Identifier: MIT

pragma solidity 0.7.6;

import "@openzeppelin/contracts/proxy/Initializable.sol";
contract Governable is Initializable {
  address public governor;
  address public pendingGovernor;

  modifier onlyGov() {
    require(msg.sender == governor, 'bad gov');
    _;
  }

  function __Governable__init(address _governor) internal initializer {
    require( _governor != address(0), 'zero gov');
    governor = _governor;
  }

  /// @dev Set the pending governor, which will be the governor once accepted.
  /// @param addr The address of the pending governor.
  function setPendingGovernor(address addr) external onlyGov {
    pendingGovernor = addr;
  }

  /// @dev Accept to become the new governor. Must be called by the pending governor.
  function acceptGovernor() external {
    require(msg.sender == pendingGovernor, 'no pend');
    pendingGovernor = address(0);
    governor = msg.sender;
  }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20Upgradeable {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

import "./IERC20Upgradeable.sol";
import "../../math/SafeMathUpgradeable.sol";
import "../../utils/AddressUpgradeable.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20Upgradeable {
    using SafeMathUpgradeable for uint256;
    using AddressUpgradeable for address;

    function safeTransfer(IERC20Upgradeable token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20Upgradeable token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20Upgradeable token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20Upgradeable token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20Upgradeable token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value, "SafeERC20: decreased allowance below zero");
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20Upgradeable token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMathUpgradeable {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        uint256 c = a + b;
        if (c < a) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b > a) return (false, 0);
        return (true, a - b);
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) return (true, 0);
        uint256 c = a * b;
        if (c / a != b) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a / b);
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a % b);
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        return a - b;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: modulo by zero");
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {trySub}.
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        return a - b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryDiv}.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting with custom message when dividing by zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryMod}.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a % b;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.7.0;

/**
 * @dev Collection of functions related to the address type
 */
library AddressUpgradeable {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

// SPDX-License-Identifier: MIT

// solhint-disable-next-line compiler-version
pragma solidity >=0.4.24 <0.8.0;

import "../utils/Address.sol";

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since a proxied contract can't have a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {UpgradeableProxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 */
abstract contract Initializable {

    /**
     * @dev Indicates that the contract has been initialized.
     */
    bool private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Modifier to protect an initializer function from being invoked twice.
     */
    modifier initializer() {
        require(_initializing || _isConstructor() || !_initialized, "Initializable: contract is already initialized");

        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }

        _;

        if (isTopLevelCall) {
            _initializing = false;
        }
    }

    /// @dev Returns true if and only if the function is running in the constructor
    function _isConstructor() private view returns (bool) {
        return !Address.isContract(address(this));
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.2 <0.8.0;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
      return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        uint256 c = a + b;
        if (c < a) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b > a) return (false, 0);
        return (true, a - b);
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) return (true, 0);
        uint256 c = a * b;
        if (c / a != b) return (false, 0);
        return (true, c);
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a / b);
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        if (b == 0) return (false, 0);
        return (true, a % b);
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        return a - b;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) return 0;
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: modulo by zero");
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {trySub}.
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        return a - b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryDiv}.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting with custom message when dividing by zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryMod}.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        return a % b;
    }
}

{
  "metadata": {
    "useLiteralContent": true
  },
  "optimizer": {
    "enabled": true,
    "runs": 200
  },
  "outputSelection": {
    "*": {
      "*": [
        "evm.bytecode",
        "evm.deployedBytecode",
        "abi"
      ]
    }
  }
}