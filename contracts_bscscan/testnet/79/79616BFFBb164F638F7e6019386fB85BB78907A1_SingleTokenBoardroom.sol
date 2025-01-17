// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol';
import '@openzeppelin/contracts/utils/math/SafeMath.sol';
import '../ContractGuard.sol';
import '../Interfaces/IBasisAsset.sol';
import '../Interfaces/ITreasury.sol';
import '../Interfaces/IPancakeRouter02.sol';
import '../common/Statistics.sol';

contract ShareWrapper {
	using SafeMath for uint256;
	using SafeERC20 for IERC20;

	IERC20 public wantToken;

	uint256 private _totalSupply;
	mapping(address => uint256) private _balances;

	function totalSupply() public view returns (uint256) {
		return _totalSupply;
	}

	function balanceOf(address account) public view returns (uint256) {
		return _balances[account];
	}

	function stake(uint256 amount) public virtual {
		_totalSupply = _totalSupply.add(amount);
		_balances[msg.sender] = _balances[msg.sender].add(amount);
		wantToken.safeTransferFrom(msg.sender, address(this), amount);
	}

	function withdraw(uint256 amount) public virtual {
		uint256 directorShare = _balances[msg.sender];
		require(
			directorShare >= amount,
			'Boardroom: withdraw request greater than staked amount'
		);
		_totalSupply = _totalSupply.sub(amount);
		_balances[msg.sender] = directorShare.sub(amount);
		wantToken.safeTransfer(msg.sender, amount);
	}
}

abstract contract Boardroom is ShareWrapper, ContractGuard, Statistics {
	using SafeERC20 for IERC20;
	using Address for address;
	using SafeMath for uint256;

	/* ========== DATA STRUCTURES ========== */

	struct Boardseat {
		uint256 lastSnapshotIndex;
		uint256 cashRewardEarned;
		uint256 shareRewardEarned;
		uint256 epochTimerStart;
	}

	struct BoardSnapshot {
		uint256 time;
		uint256 cashRewardReceived;
		uint256 cashRewardPerShare;
		uint256 shareRewardReceived;
		uint256 shareRewardPerShare;
	}

	/* ========== STATE VARIABLES ========== */

	// governance
	address public operator;

	// flags
	bool public initialized = false;

	IERC20 public cash;
	IERC20 public share;
	ITreasury public treasury;
	IPancakeRouter02 public router;
	address[] public cashToStablePath;
	address[] public shareToStablePath;

	mapping(address => Boardseat) public directors;
	BoardSnapshot[] public boardHistory;

	// protocol parameters
	uint256 public withdrawLockupEpochs;
	uint256 public rewardLockupEpochs;

	/* ========== EVENTS ========== */

	event Initialized(address indexed executor, uint256 at);
	event Staked(address indexed user, uint256 amount);
	event Withdrawn(address indexed user, uint256 amount);
	event RewardPaid(
		address indexed user,
		uint256 cashReward,
		uint256 shareReward
	);
	event RewardAdded(
		address indexed user,
		uint256 cashReward,
		uint256 shareReward
	);

	function _getWantTokenPrice() internal view virtual returns (uint256);

	/* ========== Modifiers =============== */

	modifier onlyOperator() {
		require(
			operator == msg.sender,
			'Boardroom: caller is not the operator'
		);
		_;
	}

	modifier directorExists() {
		require(
			balanceOf(msg.sender) > 0,
			'Boardroom: The director does not exist'
		);
		_;
	}

	modifier updateReward(address director) {
		if (director != address(0)) {
			Boardseat memory seat = directors[director];
			(uint256 cashRewardEarned, uint256 sharedRewardEarned) = earned(
				director
			);
			seat.cashRewardEarned = cashRewardEarned;
			seat.shareRewardEarned = sharedRewardEarned;
			seat.lastSnapshotIndex = latestSnapshotIndex();
			directors[director] = seat;
		}
		_;
	}

	modifier notInitialized() {
		require(!initialized, 'Boardroom: already initialized');
		_;
	}

	/* ========== GOVERNANCE ========== */

	constructor(
		IERC20 _cash,
		IERC20 _share,
		IERC20 _wantToken,
		ITreasury _treasury,
		IPancakeRouter02 _router,
		address[] memory _cashToStablePath,
		address[] memory _shareToStablePath
	) {
		cash = _cash;
		share = _share;
		wantToken = _wantToken;
		treasury = _treasury;
		cashToStablePath = _cashToStablePath;
		shareToStablePath = _shareToStablePath;
		router = _router;

		BoardSnapshot memory genesisSnapshot = BoardSnapshot({
			time: block.number,
			cashRewardReceived: 0,
			shareRewardReceived: 0,
			cashRewardPerShare: 0,
			shareRewardPerShare: 0
		});
		boardHistory.push(genesisSnapshot);

		withdrawLockupEpochs = 6; // Lock for 6 epochs (36h) before release withdraw
		rewardLockupEpochs = 3; // Lock for 3 epochs (18h) before release claimReward

		initialized = true;
		operator = msg.sender;
		emit Initialized(msg.sender, block.number);
	}

	function setOperator(address _operator) external onlyOperator {
		operator = _operator;
	}

	function setLockUp(
		uint256 _withdrawLockupEpochs,
		uint256 _rewardLockupEpochs
	) external onlyOperator {
		require(
			_withdrawLockupEpochs >= _rewardLockupEpochs &&
				_withdrawLockupEpochs <= 56,
			'_withdrawLockupEpochs: out of range'
		); // <= 2 week
		withdrawLockupEpochs = _withdrawLockupEpochs;
		rewardLockupEpochs = _rewardLockupEpochs;
	}

	/* ========== VIEW FUNCTIONS ========== */

	// =========== Snapshot getters

	function latestSnapshotIndex() public view returns (uint256) {
		return boardHistory.length.sub(1);
	}

	function getLatestSnapshot() internal view returns (BoardSnapshot memory) {
		return boardHistory[latestSnapshotIndex()];
	}

	function getLastSnapshotIndexOf(address director)
		public
		view
		returns (uint256)
	{
		return directors[director].lastSnapshotIndex;
	}

	function getLastSnapshotOf(address director)
		internal
		view
		returns (BoardSnapshot memory)
	{
		return boardHistory[getLastSnapshotIndexOf(director)];
	}

	function canWithdraw(address director) external view returns (bool) {
		return
			directors[director].epochTimerStart.add(withdrawLockupEpochs) <=
			treasury.epoch();
	}

	function canClaimReward(address director) external view returns (bool) {
		return
			directors[director].epochTimerStart.add(rewardLockupEpochs) <=
			treasury.epoch();
	}

	function epoch() external view returns (uint256) {
		return treasury.epoch();
	}

	function nextEpochPoint() external view returns (uint256) {
		return treasury.nextEpochPoint();
	}

	function getDollarPrice() external view returns (uint256) {
		return treasury.getDollarPrice();
	}

	// =========== Director getters

	function rewardPerShare() external view returns (uint256, uint256) {
		return (
			getLatestSnapshot().cashRewardPerShare,
			getLatestSnapshot().shareRewardPerShare
		);
	}

	function earned(address director) public view returns (uint256, uint256) {
		uint256 latestCRPS = getLatestSnapshot().cashRewardPerShare;
		uint256 storedCRPS = getLastSnapshotOf(director).cashRewardPerShare;

		uint256 latestSRPS = getLatestSnapshot().shareRewardPerShare;
		uint256 storedSRPS = getLastSnapshotOf(director).shareRewardPerShare;

		return (
			balanceOf(director).mul(latestCRPS.sub(storedCRPS)).div(1e18).add(
				directors[director].cashRewardEarned
			),
			balanceOf(director).mul(latestSRPS.sub(storedSRPS)).div(1e18).add(
				directors[director].shareRewardEarned
			)
		);
	}

	/* ========== MUTATIVE FUNCTIONS ========== */

	function stake(uint256 amount)
		public
		override
		onlyOneBlock
		updateReward(msg.sender)
	{
		_stake(amount);
	}

	function _stake(uint256 amount) internal {
		require(amount > 0, 'Boardroom: Cannot stake 0');
		super.stake(amount);
		directors[msg.sender].epochTimerStart = treasury.epoch(); // reset timer
		emit Staked(msg.sender, amount);
	}

	function withdraw(uint256 amount)
		public
		override
		onlyOneBlock
		directorExists
		updateReward(msg.sender)
	{
		require(amount > 0, 'Boardroom: Cannot withdraw 0');
		require(
			directors[msg.sender].epochTimerStart.add(withdrawLockupEpochs) <=
				treasury.epoch(),
			'Boardroom: still in withdraw lockup'
		);
		claimReward();
		super.withdraw(amount);
		emit Withdrawn(msg.sender, amount);
	}

	function exit() external {
		withdraw(balanceOf(msg.sender));
	}

	function claimReward() public updateReward(msg.sender) {
		uint256 cashReward = directors[msg.sender].cashRewardEarned;
		uint256 shareReward = directors[msg.sender].shareRewardEarned;

		if (cashReward > 0 || shareReward > 0) {
			require(
				directors[msg.sender].epochTimerStart.add(rewardLockupEpochs) <=
					treasury.epoch(),
				'Boardroom: still in reward lockup'
			);
			directors[msg.sender].epochTimerStart = treasury.epoch(); // reset timer
			directors[msg.sender].cashRewardEarned = 0;
			directors[msg.sender].shareRewardEarned = 0;

			if (cashReward > 0) cash.safeTransfer(msg.sender, cashReward);
			if (shareReward > 0) share.safeTransfer(msg.sender, shareReward);
			emit RewardPaid(msg.sender, cashReward, shareReward);
		}
	}

	function allocateSeigniorage(uint256 cashAmount, uint256 shareAmount)
		external
		onlyOneBlock
		onlyOperator
	{
		require(
			cashAmount > 0 || shareAmount > 0,
			'Boardroom: Cannot allocate 0'
		);
		require(
			totalSupply() > 0,
			'Boardroom: Cannot allocate when totalSupply is 0'
		);

		// Create & add new snapshot
		uint256 prevCRPS = getLatestSnapshot().cashRewardPerShare;
		uint256 nextCRPS = prevCRPS.add(
			cashAmount.mul(1e18).div(totalSupply())
		);

		uint256 prevSRPS = getLatestSnapshot().shareRewardPerShare;
		uint256 nextSRPS = prevSRPS.add(
			shareAmount.mul(1e18).div(totalSupply())
		);

		BoardSnapshot memory newSnapshot = BoardSnapshot({
			time: block.number,
			cashRewardReceived: cashAmount,
			cashRewardPerShare: nextCRPS,
			shareRewardReceived: shareAmount,
			shareRewardPerShare: nextSRPS
		});
		boardHistory.push(newSnapshot);

		if (cashAmount > 0)
			cash.safeTransferFrom(msg.sender, address(this), cashAmount);
		if (shareAmount > 0)
			share.safeTransferFrom(msg.sender, address(this), shareAmount);
		emit RewardAdded(msg.sender, cashAmount, shareAmount);
	}

	function APR() external view override returns (uint256) {
		if (boardHistory.length == 0) return 0;

		uint256 prevCRPS = 0;
		uint256 prevSRPS = 0;
		if (boardHistory.length > 1) {
			prevCRPS = boardHistory[boardHistory.length - 2].cashRewardPerShare;
			prevSRPS = boardHistory[boardHistory.length - 2]
				.shareRewardPerShare;
		}

		uint256 epochCRPS = boardHistory[boardHistory.length - 1]
			.cashRewardPerShare
			.sub(prevCRPS);

		uint256 epochSRPS = boardHistory[boardHistory.length - 1]
			.shareRewardPerShare
			.sub(prevSRPS);

		// 31536000 = seconds in a year
		return
			(epochCRPS.mul(_getTokenPrice(router, cashToStablePath)) +
				epochSRPS.mul(_getTokenPrice(router, shareToStablePath)))
				.mul(31536000)
				.div(treasury.PERIOD())
				.div(_getWantTokenPrice());
	}

	function TVL() external view override returns (uint256) {
		return totalSupply().mul(_getWantTokenPrice()).div(1e18);
	}

	function governanceRecoverUnsupported(
		IERC20 _token,
		uint256 _amount,
		address _to
	) external onlyOperator {
		// do not allow to drain core tokens
		require(address(_token) != address(cash), 'cash');
		require(address(_token) != address(share), 'share');
		require(address(_token) != address(wantToken), 'wantToken');
		_token.safeTransfer(_to, _amount);
	}
}

// SPDX-License-Identifier: MIT
pragma solidity >=0.8.0;

import './Boardroom.sol';

contract SingleTokenBoardroom is Boardroom {
	address[] public wantToStablePath;

	constructor(
		IERC20 _cash,
		IERC20 _share,
		IERC20 _wantToken,
		ITreasury _treasury,
		IPancakeRouter02 _router,
		address[] memory _cashToStablePath,
		address[] memory _shareToStablePath,
		address[] memory _wantToStablePath
	)
		Boardroom(
			_cash,
			_share,
			_wantToken,
			_treasury,
			_router,
			_cashToStablePath,
			_shareToStablePath
		)
	{
		wantToStablePath = _wantToStablePath;
	}

	function _getWantTokenPrice() internal view override returns (uint256) {
		return _getTokenPrice(router, wantToStablePath);
	}
}

pragma solidity >=0.8.0;

contract ContractGuard {
	mapping(uint256 => mapping(address => bool)) private _status;

	function checkSameOriginReentranted() internal view returns (bool) {
		return _status[block.number][tx.origin];
	}

	function checkSameSenderReentranted() internal view returns (bool) {
		return _status[block.number][msg.sender];
	}

	modifier onlyOneBlock() {
		require(
			!checkSameOriginReentranted(),
			'ContractGuard: one block, one function'
		);
		require(
			!checkSameSenderReentranted(),
			'ContractGuard: one block, one function'
		);

		_;

		_status[block.number][tx.origin] = true;
		_status[block.number][msg.sender] = true;
	}
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import './IMintableToken.sol';

interface IBasisAsset is IMintableToken {
	function burn(uint256 amount) external;

	function burnFrom(address from, uint256 amount) external;

	function isOperator() external returns (bool);

	function operator() external view returns (address);

	function rebase(uint256 epoch, int256 supplyDelta) external;

	function rebaseSupply() external view returns (uint256);
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IMintableToken {
	function mint(address recipient_, uint256 amount_) external returns (bool);
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface IPancakeRouter01 {
	function factory() external pure returns (address);

	function WETH() external pure returns (address);

	function addLiquidity(
		address tokenA,
		address tokenB,
		uint256 amountADesired,
		uint256 amountBDesired,
		uint256 amountAMin,
		uint256 amountBMin,
		address to,
		uint256 deadline
	)
		external
		returns (
			uint256 amountA,
			uint256 amountB,
			uint256 liquidity
		);

	function addLiquidityETH(
		address token,
		uint256 amountTokenDesired,
		uint256 amountTokenMin,
		uint256 amountETHMin,
		address to,
		uint256 deadline
	)
		external
		payable
		returns (
			uint256 amountToken,
			uint256 amountETH,
			uint256 liquidity
		);

	function removeLiquidity(
		address tokenA,
		address tokenB,
		uint256 liquidity,
		uint256 amountAMin,
		uint256 amountBMin,
		address to,
		uint256 deadline
	) external returns (uint256 amountA, uint256 amountB);

	function removeLiquidityETH(
		address token,
		uint256 liquidity,
		uint256 amountTokenMin,
		uint256 amountETHMin,
		address to,
		uint256 deadline
	) external returns (uint256 amountToken, uint256 amountETH);

	function removeLiquidityWithPermit(
		address tokenA,
		address tokenB,
		uint256 liquidity,
		uint256 amountAMin,
		uint256 amountBMin,
		address to,
		uint256 deadline,
		bool approveMax,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external returns (uint256 amountA, uint256 amountB);

	function removeLiquidityETHWithPermit(
		address token,
		uint256 liquidity,
		uint256 amountTokenMin,
		uint256 amountETHMin,
		address to,
		uint256 deadline,
		bool approveMax,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external returns (uint256 amountToken, uint256 amountETH);

	function swapExactTokensForTokens(
		uint256 amountIn,
		uint256 amountOutMin,
		address[] calldata path,
		address to,
		uint256 deadline
	) external returns (uint256[] memory amounts);

	function swapTokensForExactTokens(
		uint256 amountOut,
		uint256 amountInMax,
		address[] calldata path,
		address to,
		uint256 deadline
	) external returns (uint256[] memory amounts);

	function swapExactETHForTokens(
		uint256 amountOutMin,
		address[] calldata path,
		address to,
		uint256 deadline
	) external payable returns (uint256[] memory amounts);

	function swapTokensForExactETH(
		uint256 amountOut,
		uint256 amountInMax,
		address[] calldata path,
		address to,
		uint256 deadline
	) external returns (uint256[] memory amounts);

	function swapExactTokensForETH(
		uint256 amountIn,
		uint256 amountOutMin,
		address[] calldata path,
		address to,
		uint256 deadline
	) external returns (uint256[] memory amounts);

	function swapETHForExactTokens(
		uint256 amountOut,
		address[] calldata path,
		address to,
		uint256 deadline
	) external payable returns (uint256[] memory amounts);

	function quote(
		uint256 amountA,
		uint256 reserveA,
		uint256 reserveB
	) external pure returns (uint256 amountB);

	function getAmountOut(
		uint256 amountIn,
		uint256 reserveIn,
		uint256 reserveOut
	) external pure returns (uint256 amountOut);

	function getAmountIn(
		uint256 amountOut,
		uint256 reserveIn,
		uint256 reserveOut
	) external pure returns (uint256 amountIn);

	function getAmountsOut(uint256 amountIn, address[] calldata path)
		external
		view
		returns (uint256[] memory amounts);

	function getAmountsIn(uint256 amountOut, address[] calldata path)
		external
		view
		returns (uint256[] memory amounts);
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import './IPancakeRouter01.sol';

interface IPancakeRouter02 is IPancakeRouter01 {
	function removeLiquidityETHSupportingFeeOnTransferTokens(
		address token,
		uint256 liquidity,
		uint256 amountTokenMin,
		uint256 amountETHMin,
		address to,
		uint256 deadline
	) external returns (uint256 amountETH);

	function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
		address token,
		uint256 liquidity,
		uint256 amountTokenMin,
		uint256 amountETHMin,
		address to,
		uint256 deadline,
		bool approveMax,
		uint8 v,
		bytes32 r,
		bytes32 s
	) external returns (uint256 amountETH);

	function swapExactTokensForTokensSupportingFeeOnTransferTokens(
		uint256 amountIn,
		uint256 amountOutMin,
		address[] calldata path,
		address to,
		uint256 deadline
	) external;

	function swapExactETHForTokensSupportingFeeOnTransferTokens(
		uint256 amountOutMin,
		address[] calldata path,
		address to,
		uint256 deadline
	) external payable;

	function swapExactTokensForETHSupportingFeeOnTransferTokens(
		uint256 amountIn,
		uint256 amountOutMin,
		address[] calldata path,
		address to,
		uint256 deadline
	) external;
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

interface ITreasury {
	function PERIOD() external view returns (uint256);

	function epoch() external view returns (uint256);

	function nextEpochPoint() external view returns (uint256);

	function getDollarPrice() external view returns (uint256);
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '../Interfaces/IPancakeRouter02.sol';

abstract contract PriceCalculator {
	function _getTokenPrice(
		IPancakeRouter02 router,
		address[] memory tokenToStable
	) internal view virtual returns (uint256) {
		//special case where token is stable
		if (tokenToStable.length == 1) {
			return 1e18;
		}

		uint256[] memory amounts = router.getAmountsOut(1e18, tokenToStable);
		return amounts[amounts.length - 1];
	}

	function _getLPTokenPrice(
		IPancakeRouter02 router,
		address[] memory token0ToStable,
		address[] memory token1ToStable,
		IERC20 lpToken
	) internal view virtual returns (uint256) {
		uint256 token0InPool = IERC20(token0ToStable[0]).balanceOf(
			address(lpToken)
		);
		uint256 token1InPool = IERC20(token1ToStable[0]).balanceOf(
			address(lpToken)
		);

		uint256 totalPriceOfPool = token0InPool *
			(_getTokenPrice(router, token0ToStable)) +
			token1InPool *
			(_getTokenPrice(router, token1ToStable));

		return totalPriceOfPool / (lpToken.totalSupply());
	}
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.8.0;

import '@openzeppelin/contracts/token/ERC20/IERC20.sol';
import '../Interfaces/IPancakeRouter02.sol';
import './PriceCalculator.sol';

abstract contract Statistics is PriceCalculator {
	function APR() external view virtual returns (uint256);

	function TVL() external view virtual returns (uint256);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
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
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

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

pragma solidity ^0.8.0;

import "../IERC20.sol";
import "../../../utils/Address.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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
        assembly {
            size := extcodesize(account)
        }
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

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
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
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
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
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
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
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

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
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) private pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

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

pragma solidity ^0.8.0;

// CAUTION
// This version of SafeMath should only be used with Solidity 0.8 or later,
// because it relies on the compiler's built in overflow checks.

/**
 * @dev Wrappers over Solidity's arithmetic operations.
 *
 * NOTE: `SafeMath` is no longer needed starting with Solidity 0.8. The compiler
 * now has built in overflow checking.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
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
        return a + b;
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
        return a * b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator.
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
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
    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
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
    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
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
    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}

{
  "remappings": [],
  "optimizer": {
    "enabled": true,
    "runs": 200
  },
  "evmVersion": "istanbul",
  "libraries": {},
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