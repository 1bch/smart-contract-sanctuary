// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

// Version 11-Mar-2021

// File @boringcrypto/boring-solidity/contracts/libraries/[email protected]
// License-Identifier: MIT

/// @notice A library for performing overflow-/underflow-safe math,
/// updated with awesomeness from of DappHub (https://github.com/dapphub/ds-math).
library BoringMath {
    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require((c = a + b) >= b, "BoringMath: Add Overflow");
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require((c = a - b) <= a, "BoringMath: Underflow");
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require(b == 0 || (c = a * b) / b == a, "BoringMath: Mul Overflow");
    }
}

// File @polycity/core/contracts/uniswapv2/interfaces/[email protected]
// License-Identifier: GPL-3.0
interface IUniswapV2Factory {
    function getPair(address tokenA, address tokenB) external view returns (address pair);
}

// File @polycity/core/contracts/uniswapv2/interfaces/[email protected]
// License-Identifier: GPL-3.0
interface IUniswapV2Pair {
    function token0() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;
}

// File @boringcrypto/boring-solidity/contracts/interfaces/[email protected]
// License-Identifier: MIT
interface IERC20 {

}

// File @polycity/antiquebox-sdk/contracts/[email protected]
// License-Identifier: MIT
interface IAntiqueBoxV1 {
    function deposit(
        IERC20 token_,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external payable returns (uint256 amountOut, uint256 shareOut);

    function toAmount(
        IERC20 token,
        uint256 share,
        bool roundUp
    ) external view returns (uint256 amount);

    function toShare(
        IERC20 token,
        uint256 amount,
        bool roundUp
    ) external view returns (uint256 share);

    function transfer(
        IERC20 token,
        address from,
        address to,
        uint256 share
    ) external;

    function withdraw(
        IERC20 token_,
        address from,
        address to,
        uint256 amount,
        uint256 share
    ) external returns (uint256 amountOut, uint256 shareOut);
}

// File contracts/swappers/PolyCityDexSwapper.sol
// License-Identifier: MIT
contract PolyCityDexSwapperV1 {
    using BoringMath for uint256;

    // Local variables
    IAntiqueBoxV1 public immutable antiqueBox;
    IUniswapV2Factory public immutable factory;
    bytes32 public pairCodeHash;

    constructor(
        IAntiqueBoxV1 antiqueBox_,
        IUniswapV2Factory factory_,
        bytes32 pairCodeHash_
    ) public {
        antiqueBox = antiqueBox_;
        factory = factory_;
        pairCodeHash = pairCodeHash_;
    }

    // Given an input amount of an asset and pair reserves, returns the maximum output amount of the other asset
    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountOut) {
        uint256 amountInWithFee = amountIn.mul(997);
        uint256 numerator = amountInWithFee.mul(reserveOut);
        uint256 denominator = reserveIn.mul(1000).add(amountInWithFee);
        amountOut = numerator / denominator;
    }

    // Given an output amount of an asset and pair reserves, returns a required input amount of the other asset
    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) internal pure returns (uint256 amountIn) {
        uint256 numerator = reserveIn.mul(amountOut).mul(1000);
        uint256 denominator = reserveOut.sub(amountOut).mul(997);
        amountIn = (numerator / denominator).add(1);
    }

    // Swaps to a flexible amount, from an exact input amount
    /// @notice Withdraws 'amountFrom' of token 'from' from the AntiqueBox account for this swapper.
    /// Swaps it for at least 'amountToMin' of token 'to'.
    /// Transfers the swapped tokens of 'to' into the AntiqueBox using a plain ERC20 transfer.
    /// Returns the amount of tokens 'to' transferred to AntiqueBox.
    /// (The AntiqueBox skim function will be used by the caller to get the swapped funds).
    function swap(
        IERC20 fromToken,
        IERC20 toToken,
        address recipient,
        uint256 shareToMin,
        uint256 shareFrom
    ) public returns (uint256 extraShare, uint256 shareReturned) {
        (IERC20 token0, IERC20 token1) = fromToken < toToken ? (fromToken, toToken) : (toToken, fromToken);
        IUniswapV2Pair pair =
            IUniswapV2Pair(
                uint256(
                    keccak256(abi.encodePacked(hex"ff", factory, keccak256(abi.encodePacked(address(token0), address(token1))), pairCodeHash))
                )
            );

        (uint256 amountFrom, ) = antiqueBox.withdraw(fromToken, address(this), address(pair), 0, shareFrom);

        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();
        uint256 amountTo;
        if (toToken > fromToken) {
            amountTo = getAmountOut(amountFrom, reserve0, reserve1);
            pair.swap(0, amountTo, address(antiqueBox), new bytes(0));
        } else {
            amountTo = getAmountOut(amountFrom, reserve1, reserve0);
            pair.swap(amountTo, 0, address(antiqueBox), new bytes(0));
        }
        (, shareReturned) = antiqueBox.deposit(toToken, address(antiqueBox), recipient, amountTo, 0);
        extraShare = shareReturned.sub(shareToMin);
    }

    // Swaps to an exact amount, from a flexible input amount
    /// @notice Calculates the amount of token 'from' needed to complete the swap (amountFrom),
    /// this should be less than or equal to amountFromMax.
    /// Withdraws 'amountFrom' of token 'from' from the AntiqueBox account for this swapper.
    /// Swaps it for exactly 'exactAmountTo' of token 'to'.
    /// Transfers the swapped tokens of 'to' into the AntiqueBox using a plain ERC20 transfer.
    /// Transfers allocated, but unused 'from' tokens within the AntiqueBox to 'refundTo' (amountFromMax - amountFrom).
    /// Returns the amount of 'from' tokens withdrawn from AntiqueBox (amountFrom).
    /// (The AntiqueBox skim function will be used by the caller to get the swapped funds).
    function swapExact(
        IERC20 fromToken,
        IERC20 toToken,
        address recipient,
        address refundTo,
        uint256 shareFromSupplied,
        uint256 shareToExact
    ) public returns (uint256 shareUsed, uint256 shareReturned) {
        IUniswapV2Pair pair;
        {
            (IERC20 token0, IERC20 token1) = fromToken < toToken ? (fromToken, toToken) : (toToken, fromToken);
            pair = IUniswapV2Pair(
                uint256(
                    keccak256(abi.encodePacked(hex"ff", factory, keccak256(abi.encodePacked(address(token0), address(token1))), pairCodeHash))
                )
            );
        }
        (uint256 reserve0, uint256 reserve1, ) = pair.getReserves();

        uint256 amountToExact = antiqueBox.toAmount(toToken, shareToExact, true);

        uint256 amountFrom;
        if (toToken > fromToken) {
            amountFrom = getAmountIn(amountToExact, reserve0, reserve1);
            (, shareUsed) = antiqueBox.withdraw(fromToken, address(this), address(pair), amountFrom, 0);
            pair.swap(0, amountToExact, address(antiqueBox), "");
        } else {
            amountFrom = getAmountIn(amountToExact, reserve1, reserve0);
            (, shareUsed) = antiqueBox.withdraw(fromToken, address(this), address(pair), amountFrom, 0);
            pair.swap(amountToExact, 0, address(antiqueBox), "");
        }
        antiqueBox.deposit(toToken, address(antiqueBox), recipient, 0, shareToExact);
        shareReturned = shareFromSupplied.sub(shareUsed);
        if (shareReturned > 0) {
            antiqueBox.transfer(fromToken, address(this), refundTo, shareReturned);
        }
    }
}

{
  "optimizer": {
    "enabled": true,
    "runs": 999999
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
  "libraries": {}
}