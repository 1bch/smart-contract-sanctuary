// Be name Khoda
// SPDX-License-Identifier: MIT
pragma solidity 0.8.8;

// =================================================================================================================
//  _|_|_|    _|_|_|_|  _|    _|    _|_|_|      _|_|_|_|  _|                                                       |
//  _|    _|  _|        _|    _|  _|            _|            _|_|_|      _|_|_|  _|_|_|      _|_|_|    _|_|       |
//  _|    _|  _|_|_|    _|    _|    _|_|        _|_|_|    _|  _|    _|  _|    _|  _|    _|  _|        _|_|_|_|     |
//  _|    _|  _|        _|    _|        _|      _|        _|  _|    _|  _|    _|  _|    _|  _|        _|           |
//  _|_|_|    _|_|_|_|    _|_|    _|_|_|        _|        _|  _|    _|    _|_|_|  _|    _|    _|_|_|    _|_|_|     |
// =================================================================================================================
// ========================= DEUSZapper =========================
// ==============================================================
// DEUS Finance: https://github.com/DeusFinance

// Primary Author(s)
// Vahid Gh: https://github.com/vahid-dev

// Reviewer(s) / Contributor(s)

import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";

// import "@uniswap/lib/contracts/libraries/Babylonian.sol";
library Babylonian {
	function sqrt(uint256 y) internal pure returns (uint256 z) {
		if (y > 3) {
			z = y;
			uint256 x = y / 2 + 1;
			while (x < z) {
				z = x;
				x = (y / x + x) / 2;
			}
		} else if (y != 0) {
			z = 1;
		}
		// else z = 0
	}
}

interface IUniswapV2Router02 {
	function factory() external pure returns (address);
	function addLiquidity(
		address tokenA,
		address tokenB,
		uint256 amountADesired,
		uint256 amountBDesired,
		uint256 amountAMin,
		uint256 amountBMin,
		address to,
		uint256 deadline
	) external returns (uint256 amountA, uint256 amountB, uint256 liquidity);

	function removeLiquidity(
		address tokenA,
		address tokenB,
		uint256 liquidity,
		uint256 amountAMin,
		uint256 amountBMin,
		address to,
		uint256 deadline
	) external returns (uint256 amountA, uint256 amountB);

	function swapExactTokensForTokens(
		uint256 amountIn,
		uint256 amountOutMin,
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

	function getAmountsOut(
		uint256 amountIn, 
		address[] calldata path
	) external view returns (uint256[] memory amounts);

	function getAmountsIn(
		uint256 amountOut, 
		address[] calldata path
	) external view returns (uint256[] memory amounts);
}

interface IUniwapV2Pair {
	function token0() external pure returns (address);
	function token1() external pure returns (address);
    function totalSupply() external view returns (uint);
	function getReserves() external view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast);
}

interface IStaking {
	function depositFor(address _user, uint256 amount) external;
}

contract DEI_COLLATERAL_ZAPPER is Ownable {
	using SafeERC20 for IERC20;

	bool public stopped;
	uint256 private immutable missing_decimals = 1; // depend on collateral decimals
	uint256 private constant deadline = 0xf000000000000000000000000000000000000000000000000000000000000000;
	address public uniswap_router;
	address public pair_address;
	address public collateral_address;
	address public deus_address;
	address public dei_address;
	
	address public staking_address;

	constructor (
		address _pair_address,
		address _collateral_address,
		address _deus_address,
		address _dei_address,
		address _staking_address,
		address _uniswap_router
	) {
		pair_address = _pair_address;
		collateral_address = _collateral_address;
		deus_address = _deus_address;
		dei_address = _dei_address;
		uniswap_router = _uniswap_router;
		staking_address = _staking_address;
        init();
	}

	// circuit breaker modifiers
	modifier stopInEmergency() {
		require(!stopped, "ZAPPER: TEMPORARILY_PAUSED");
		_;
	}

	function zapInNativecoin(
		address[] calldata path,
		uint256 minLPAmount,
		bool transferResidual  // Set false to save gas by donating the residual remaining after a Zap
	) external payable {
		uint[] memory amounts_out = IUniswapV2Router02(uniswap_router).swapExactETHForTokens{value: msg.value}(1, path, address(this), deadline);
		uint collateral_amount = amounts_out[amounts_out.length - 1];

		(uint256 token0Bought, uint256 token1Bought) = _buyTokens(collateral_address, collateral_amount);

		uint256 LPBought = _uniDeposit(IUniwapV2Pair(pair_address).token0(),
									IUniwapV2Pair(pair_address).token1(),
									token0Bought,
									token1Bought,
									transferResidual);

		require(LPBought >= minLPAmount, "ZAPPER: INSUFFICIENT_OUTPUT_AMOUNT");

		IStaking(staking_address).depositFor(msg.sender, LPBought);

		emit ZappedIn(address(0), pair_address, collateral_amount, LPBought, transferResidual);
	}


	function zapInERC20(
		address[] calldata path,
		uint256 amountIn,
		uint256 minLPAmount,
		bool transferResidual  // Set false to save gas by donating the residual remaining after a Zap
	) external {
		require(path.length >= 2, "ZAPPER: WRONG_PATH");
		if (IERC20(path[0]).allowance(address(this), uniswap_router) == 0) IERC20(path[0]).safeApprove(uniswap_router, type(uint).max);

		IERC20(path[0]).transferFrom(msg.sender, address(this), amountIn);

		uint[] memory amounts_out = IUniswapV2Router02(uniswap_router).swapExactTokensForTokens(amountIn, 1, path, address(this), deadline);
		uint collateral_amount = amounts_out[amounts_out.length - 1];

		(uint256 token0Bought, uint256 token1Bought) = _buyTokens(collateral_address, collateral_amount);

		uint256 LPBought = _uniDeposit(IUniwapV2Pair(pair_address).token0(),
									IUniwapV2Pair(pair_address).token1(),
									token0Bought,
									token1Bought,
									transferResidual);

		require(LPBought >= minLPAmount, "ZAPPER: INSUFFICIENT_OUTPUT_AMOUNT");

		IStaking(staking_address).depositFor(msg.sender, LPBought);

		emit ZappedIn(path[0], pair_address, amountIn, LPBought, transferResidual);
	}

	function zapInCollateral(
		uint256 amountIn,
		uint256 minLPAmount,
		bool transferResidual  // Set false to save gas by donating the residual remaining after a Zap
	) external stopInEmergency {
		IERC20(collateral_address).safeTransferFrom(msg.sender, address(this), amountIn);

		(uint256 token0Bought, uint256 token1Bought) = _buyTokens(collateral_address, amountIn);

		uint256 LPBought = _uniDeposit(IUniwapV2Pair(pair_address).token0(),
									IUniwapV2Pair(pair_address).token1(),
									token0Bought,
									token1Bought,
									transferResidual);

		require(LPBought >= minLPAmount, "ZAPPER: INSUFFICIENT_OUTPUT_AMOUNT");

		IStaking(staking_address).depositFor(msg.sender, LPBought);

		emit ZappedIn(collateral_address, pair_address, amountIn, LPBought, transferResidual);
	}

    function zapInDEI(
		uint256 amountIn,
		uint256 minLPAmount,
		bool transferResidual  // Set false to save gas by donating the residual remaining after a Zap
	) external stopInEmergency {
		IERC20(dei_address).safeTransferFrom(msg.sender, address(this), amountIn);

		(uint256 token0Bought, uint256 token1Bought) = _buyTokens(dei_address, amountIn);

		uint256 LPBought = _uniDeposit(IUniwapV2Pair(pair_address).token0(),
									IUniwapV2Pair(pair_address).token1(),
									token0Bought,
									token1Bought,
									transferResidual);

		require(LPBought >= minLPAmount, "ZAPPER: INSUFFICIENT_OUTPUT_AMOUNT");

		IStaking(staking_address).depositFor(msg.sender, LPBought);

		emit ZappedIn(dei_address, pair_address, amountIn, LPBought, transferResidual);
	}

	function zapInDEUS(
		uint amountIn,
		uint minLPAmount,
		bool transferResidual,
		address[] calldata path
	) external stopInEmergency {
		IERC20(deus_address).safeTransferFrom(msg.sender, address(this), amountIn);

		uint[] memory amounts_out = IUniswapV2Router02(uniswap_router).swapExactTokensForTokens(amountIn, 1, path, address(this), deadline);
		uint dei_amount = amounts_out[amounts_out.length - 1];

		(uint256 token0Bought, uint256 token1Bought) = _buyTokens(dei_address, dei_amount);

		uint256 LPBought = _uniDeposit(IUniwapV2Pair(pair_address).token0(),
									IUniwapV2Pair(pair_address).token1(),
									token0Bought,
									token1Bought,
									transferResidual);

		require(LPBought >= minLPAmount, "ZAPPER: INSUFFICIENT_OUTPUT_AMOUNT");

		IStaking(staking_address).depositFor(msg.sender, LPBought);

		emit ZappedIn(deus_address, pair_address, amountIn, LPBought, transferResidual);
	}

	function _buyTokens(address inputToken, uint256 _amount) internal returns(uint256 token0Bought, uint256 token1Bought) {
		IUniwapV2Pair pair = IUniwapV2Pair(pair_address);
		(uint res0, uint256 res1, ) = pair.getReserves();
		if (inputToken == pair.token0()) {
			uint256 amountToSwap = calculateSwapInAmount(res0, _amount);	
			if (amountToSwap <= 0) amountToSwap = _amount / 2;
			token1Bought = _token2Token(
							inputToken,
							pair.token1(), // it depend on pair tokens (token0 or token1)
							amountToSwap
						);
			token0Bought = _amount - amountToSwap;
		} else {
			uint256 amountToSwap = calculateSwapInAmount(res1, _amount);
			if (amountToSwap <= 0) amountToSwap = _amount / 2;
			token0Bought = _token2Token(
								inputToken,
								pair.token0(), // it depend on pair tokens (token0 or token1)
								amountToSwap
							);
			token1Bought = _amount - amountToSwap;
		}
	}

	function _token2Token(
		address _fromToken,
		address _toToken,
		uint256 tokens2Trade
	) internal returns (uint256 tokenBought) {
		address[] memory path = new address[](2);
		path[0] = _fromToken;
		path[1] = _toToken;

		tokenBought = IUniswapV2Router02(uniswap_router).swapExactTokensForTokens(
			tokens2Trade,
			1,
			path,
			address(this),
			deadline
		) [path.length - 1];

		require(tokenBought > 0, "ZAPPER: Error swapExactTokensForTokens");
	}

	function calculateSwapInAmount(uint256 reserveIn, uint256 userIn)
		internal
		pure
		returns (uint256)
	{
		return (Babylonian.sqrt(reserveIn * ((userIn * 3988000) + (reserveIn * 3988009))) - (reserveIn * 1997)) / 1994;
	}

	function _approveToken(
		address token,
		address spender,
		uint256 amount
	) public onlyOwner {
		IERC20 _token = IERC20(token);
		_token.safeApprove(spender, 0);
		_token.safeApprove(spender, amount);
	}

	function _uniDeposit(
		address _toUnipoolToken0,
		address _toUnipoolToken1,
		uint256 token0Bought,
		uint256 token1Bought,
		bool transferResidual
	) internal returns(uint256) {
		(uint256 amountA, uint256 amountB, uint256 LP) =
			IUniswapV2Router02(uniswap_router).addLiquidity(
				_toUnipoolToken0,
				_toUnipoolToken1,
				token0Bought,
				token1Bought,
				1,
				1,
				address(this),
				deadline
			);

		if (transferResidual) {
			//Returning Residue in token0, if any.
			if (token0Bought - amountA > 0) {
				IERC20(_toUnipoolToken0).safeTransfer(
					msg.sender,
					token0Bought - amountA
				);
			}

			//Returning Residue in token1, if any
			if (token1Bought - amountB > 0) {
				IERC20(_toUnipoolToken1).safeTransfer(
					msg.sender,
					token1Bought - amountB
				);
			}
		}

		return LP;
	}

	function init() public onlyOwner {
		_approveToken(
			IUniwapV2Pair(pair_address).token0(),
			uniswap_router,
			type(uint).max
		);
		_approveToken(
			IUniwapV2Pair(pair_address).token1(),
			uniswap_router,
			type(uint).max
		);
		_approveToken(
			deus_address,
			uniswap_router,
			type(uint).max
		);
		_approveToken(
			pair_address,
			staking_address,
			type(uint).max
		);
	}

	function getAmountOutLPERC20ORNativecoin(uint amount, address[] memory path) public view returns (uint percentage, uint lp) {
		uint[] memory amountsout = IUniswapV2Router02(uniswap_router).getAmountsOut(amount, path);
		uint usdc_amount = amountsout[amountsout.length - 1];
		return getAmountOutLPCollateral(usdc_amount);
	}

	function getAmountOutLPDEUS(uint amount, address[] memory path) public view returns (uint percentage, uint lp) {
		uint[] memory amountsout = IUniswapV2Router02(uniswap_router).getAmountsOut(amount, path);
		uint dei_amount = amountsout[amountsout.length - 1];
		IUniwapV2Pair pair = IUniwapV2Pair(pair_address);
        uint totalSupply = pair.totalSupply();
		(uint res0, uint256 res1, ) = pair.getReserves(); 
		uint dei_to_usdc_amount;
		if (dei_address == pair.token0()) {
			dei_to_usdc_amount = calculateSwapInAmount(res0, dei_amount);
			uint dei_pure_amount = dei_amount - dei_to_usdc_amount; 
			percentage = dei_pure_amount * 1e6 / (res0 + dei_amount);
			lp = dei_pure_amount * totalSupply / res0;
		} else {
			dei_to_usdc_amount = calculateSwapInAmount(res1, dei_amount);
			uint dei_pure_amount = dei_amount - dei_to_usdc_amount; 
			percentage = dei_pure_amount * 1e6 / (res1 + dei_amount);
			lp = dei_pure_amount * totalSupply / res1;
		}
	}

	function getAmountOutLPDEI(uint amount) public view returns (uint percentage, uint lp){
        IUniwapV2Pair pair = IUniwapV2Pair(pair_address);
        uint totalSupply = pair.totalSupply();
		(uint res0, uint256 res1, ) = pair.getReserves(); 
		uint dei_to_usdc_amount;
		if (dei_address == pair.token0()) {
			dei_to_usdc_amount = calculateSwapInAmount(res0, amount);
			uint dei_pure_amount = amount - dei_to_usdc_amount; 
			percentage = dei_pure_amount * 1e6 / (res0 + amount);
			lp = dei_pure_amount * totalSupply / res0;
		} else {
			dei_to_usdc_amount = calculateSwapInAmount(res1, amount);
			uint dei_pure_amount = amount - dei_to_usdc_amount; 
			percentage = dei_pure_amount * 1e6 / (res1 + amount);
			lp = dei_pure_amount * totalSupply / res1;
		}
    }

	function getAmountOutLPCollateral(uint usdc_amount) public view returns (uint percentage, uint lp){
        IUniwapV2Pair pair = IUniwapV2Pair(pair_address);
        uint totalSupply = pair.totalSupply();
		(uint res0, uint256 res1, ) = pair.getReserves(); 
		uint usdc_to_dei_amount;
		if (collateral_address == pair.token0()) {
			usdc_to_dei_amount = calculateSwapInAmount(res0, usdc_amount);
			uint usdc_pure_amount = usdc_amount - usdc_to_dei_amount; 
			percentage = usdc_pure_amount * 1e6 / (res0 + usdc_amount);
			lp = usdc_pure_amount * totalSupply / res0;
		} else {
			usdc_to_dei_amount = calculateSwapInAmount(res1, usdc_amount);
			uint usdc_pure_amount = usdc_amount - usdc_to_dei_amount; 
			percentage = usdc_pure_amount * 1e6 / (res1 + usdc_amount);
			lp = usdc_pure_amount * totalSupply / res1;
		}
    }

	function setStaking(address _staking_address) external onlyOwner {
        staking_address = _staking_address;
        emit StakingSet(staking_address);
    }

	// to Pause the contract
	function toggleContractActive() external onlyOwner {
		stopped = !stopped;
	}

	function emergencyWithdrawERC20(address token, address to, uint amount) external onlyOwner {
		IERC20(token).transfer(to, amount);
	}

    function emergencyWithdrawETH(address payable to, uint amount) external onlyOwner {
        payable(to).transfer(amount);
    }

	receive() external payable {
		revert();
	}

	event StakingSet(address staking_address);
	event ZappedIn(address input_token, address output_token, uint input_amount, uint output_amount, bool transfer_residual);
}

// Dar panahe Khoda

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/Context.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _setOwner(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _setOwner(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
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

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
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

{
  "optimizer": {
    "enabled": true,
    "runs": 100000
  },
  "outputSelection": {
    "*": {
      "*": [
        "evm.bytecode",
        "evm.deployedBytecode",
        "abi"
      ]
    }
  },
  "metadata": {
    "useLiteralContent": true
  },
  "libraries": {}
}