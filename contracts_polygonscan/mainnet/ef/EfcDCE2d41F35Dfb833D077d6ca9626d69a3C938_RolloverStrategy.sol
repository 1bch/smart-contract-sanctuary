pragma solidity 0.7.6;

import "../Token.sol";
import "../IPool.sol";
import "./IRolloverStrategy.sol";
import "../Math.sol";
import '../libs/complifi/tokens/IERC20Metadata.sol';
import '../repricers/IRepricer.sol';
import '../IDynamicFee.sol';

contract RolloverStrategy is IRolloverStrategy, Num {

    // Using vars to avoid stack do deep error
    struct Vars {
        IERC20 collateralToken;
        IERC20 primaryToken;
        IERC20 complementToken;
        IVault vault;
        IPool pool;
        uint256 primaryTokenBalance;
        uint256 complementTokenBalance;
        uint256 primaryTokenAmount;
        uint256 complementTokenAmount;
    }

    function execute(
        address _poolSettled,
        uint256 _poolAmountIn,
        uint256[] memory _underlyingEndRoundHints,
        address _poolNew
    ) external override {
        Vars memory vars;

        vars.pool = IPool(_poolSettled);
        vars.vault = IVault(vars.pool.derivativeVault());
        require(vars.vault.settleTime() <= block.timestamp, "SETTLED");

        IVault vaultNew = IVault(IPool(_poolNew).derivativeVault());
        require(vars.vault.derivativeSpecification() == vaultNew.derivativeSpecification(), "SPECS");
        require(vaultNew.settleTime() > block.timestamp, "NOT_SETTLED");

        vars.collateralToken = IERC20(vars.vault.collateralToken());

        removeLiquidityOnSettledStateInternal(
            _poolSettled,
            _poolAmountIn,
            [uint256(0), uint256(0)], // minAmountsOut,
            _underlyingEndRoundHints,
            address(this)
        );

        mintAndJoinPoolInternal(
            _poolNew,
            vars.collateralToken.balanceOf(address(this)),
            0, // minPoolAmountOut
            false
        );
    }

    /// @notice Remove settled derivatives from AMM pool redeem for collateral
    /// @dev User provides amount of LP tokens (method applies only when state = Settled)
    function removeLiquidityOnSettledStateInternal(
        address _pool,
        uint256 _poolAmountIn,
        uint256[2] memory _minAmountsOut,
        uint256[] memory _underlyingEndRoundHints,
        address recipient
    ) internal {

        Vars memory vars;
        vars.pool = IPool(_pool);

        vars.vault = IVault(vars.pool.derivativeVault());

        vars.primaryToken = IERC20(vars.vault.primaryToken());
        vars.complementToken = IERC20(vars.vault.complementToken());
        vars.collateralToken = IERC20(vars.vault.collateralToken());

        require(
            vars.pool.transferFrom(msg.sender, address(this), _poolAmountIn),
            "TAKE_POOL"
        );

        // Approve LP tokens for POOL // Not sure if this needed
        require(vars.pool.approve(_pool, _poolAmountIn), "APPROVE");

        // Step 1: Users sends LP tokens, receives (ΔBprim-, ΔBcompl-, ΔC-)
        vars.pool.exitPool(_poolAmountIn, _minAmountsOut);

        vars.primaryTokenAmount = vars.primaryToken.balanceOf(address(this));
        vars.complementTokenAmount = vars.complementToken.balanceOf(address(this));

        vars.primaryToken.approve(address(vars.vault), vars.primaryTokenAmount);
        vars.complementToken.approve(address(vars.vault), vars.complementTokenAmount);

        vars.vault.redeemTo(
            recipient,
            vars.primaryTokenAmount,
            vars.complementTokenAmount,
            _underlyingEndRoundHints
        );
    }

    function mintAndJoinPoolInternal(
        address _pool,
        uint256 _collateralAmount,
        uint256 _minPoolAmountOut,
        bool _shouldTransferCollateral
    ) internal {
        Vars memory vars;
        vars.pool = IPool(_pool);

        vars.vault = IVault(vars.pool.derivativeVault());

        vars.primaryToken = IERC20(vars.vault.primaryToken());
        vars.complementToken = IERC20(vars.vault.complementToken());
        vars.collateralToken = IERC20(vars.vault.collateralToken());

        if(_shouldTransferCollateral) {
            // Transfer collateral tokens from users to Proxy
            require(
                vars.collateralToken.transferFrom(msg.sender, address(this), _collateralAmount),
                "TAKE_COLLATERAL"
            );
        }

        // Approve collateral Tokens for Vault Contract
        vars.collateralToken.approve(address(vars.vault), _collateralAmount);

        // Mint derivatives
        vars.vault.mintTo(address(this), _collateralAmount);

        uint lpTokenSupply = IERC20(address(vars.pool)).totalSupply();
        vars.primaryTokenBalance = vars.pool.getBalance(address(vars.primaryToken));
        vars.complementTokenBalance = vars.pool.getBalance(address(vars.complementToken));
        vars.primaryTokenAmount = vars.primaryToken.balanceOf(address(this));
        vars.complementTokenAmount = vars.complementToken.balanceOf(address(this));

        uint lpTokenMultiplier = 1;
        uint tokenDecimals = uint(IERC20Metadata(address(vars.collateralToken)).decimals());
        if(tokenDecimals > 0 && tokenDecimals < 18) {
            lpTokenMultiplier = 18 - tokenDecimals;
        }

        uint poolAmountOut = min(
            lpTokenSupply * scaleTo(vars.primaryTokenAmount, lpTokenMultiplier) * BONE / scaleTo(vars.primaryTokenBalance, lpTokenMultiplier),
            lpTokenSupply * scaleTo(vars.complementTokenAmount, lpTokenMultiplier) * BONE / scaleTo(vars.complementTokenBalance, lpTokenMultiplier)
        ) / BONE;

        require(poolAmountOut >= _minPoolAmountOut, "MIN_POOL_AMOUNT_OUT");

        vars.primaryToken.approve(_pool, vars.primaryTokenAmount);
        vars.complementToken.approve(_pool, vars.complementTokenAmount);

        uint256[2] memory tokenBalances;
        tokenBalances[0] = vars.primaryTokenAmount;
        tokenBalances[1] = vars.complementTokenAmount;

        vars.pool.joinPool(poolAmountOut, tokenBalances);

        require(vars.pool.transfer(msg.sender, poolAmountOut), "GIVE_POOL");
    }

    function scaleTo(uint256 _amount, uint256 _decimal) internal returns (uint256) {
        return _amount * (10 ** _decimal);
    }
}

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.7.6;

import './Num.sol';

// Highly opinionated token implementation

interface IERC20 {
    function totalSupply() external view returns (uint256);

    function balanceOf(address whom) external view returns (uint256);

    function allowance(address src, address dst) external view returns (uint256);

    function approve(address dst, uint256 amt) external returns (bool);

    function transfer(address dst, uint256 amt) external returns (bool);

    function transferFrom(
        address src,
        address dst,
        uint256 amt
    ) external returns (bool);
}

contract TokenBase is Num {
    mapping(address => uint256) internal _balance;
    mapping(address => mapping(address => uint256)) internal _allowance;
    uint256 internal _totalSupply;

    event Approval(address indexed src, address indexed dst, uint256 amt);
    event Transfer(address indexed src, address indexed dst, uint256 amt);

    function _mint(uint256 amt) internal {
        _balance[address(this)] = add(_balance[address(this)], amt);
        _totalSupply = add(_totalSupply, amt);
        emit Transfer(address(0), address(this), amt);
    }

    function _burn(uint256 amt) internal {
        require(_balance[address(this)] >= amt, 'INSUFFICIENT_BAL');
        _balance[address(this)] = sub(_balance[address(this)], amt);
        _totalSupply = sub(_totalSupply, amt);
        emit Transfer(address(this), address(0), amt);
    }

    function _move(
        address src,
        address dst,
        uint256 amt
    ) internal {
        require(_balance[src] >= amt, 'INSUFFICIENT_BAL');
        _balance[src] = sub(_balance[src], amt);
        _balance[dst] = add(_balance[dst], amt);
        emit Transfer(src, dst, amt);
    }

    function _push(address to, uint256 amt) internal {
        _move(address(this), to, amt);
    }

    function _pull(address from, uint256 amt) internal {
        _move(from, address(this), amt);
    }
}

contract Token is TokenBase, IERC20 {
    string private _name;
    string private _symbol;
    uint8 private constant _decimals = 18;

    function setName(string memory name) internal {
        _name = name;
    }

    function setSymbol(string memory symbol) internal {
        _symbol = symbol;
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

    function allowance(address src, address dst) external view override returns (uint256) {
        return _allowance[src][dst];
    }

    function balanceOf(address whom) external view override returns (uint256) {
        return _balance[whom];
    }

    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    function approve(address dst, uint256 amt) external override returns (bool) {
        _allowance[msg.sender][dst] = amt;
        emit Approval(msg.sender, dst, amt);
        return true;
    }

    function increaseApproval(address dst, uint256 amt) external returns (bool) {
        _allowance[msg.sender][dst] = add(_allowance[msg.sender][dst], amt);
        emit Approval(msg.sender, dst, _allowance[msg.sender][dst]);
        return true;
    }

    function decreaseApproval(address dst, uint256 amt) external returns (bool) {
        uint256 oldValue = _allowance[msg.sender][dst];
        if (amt > oldValue) {
            _allowance[msg.sender][dst] = 0;
        } else {
            _allowance[msg.sender][dst] = sub(oldValue, amt);
        }
        emit Approval(msg.sender, dst, _allowance[msg.sender][dst]);
        return true;
    }

    function transfer(address dst, uint256 amt) external override returns (bool) {
        _move(msg.sender, dst, amt);
        return true;
    }

    function transferFrom(
        address src,
        address dst,
        uint256 amt
    ) external override returns (bool) {
        uint256 oldValue = _allowance[src][msg.sender];
        require(msg.sender == src || amt <= oldValue, 'TOKEN_BAD_CALLER');
        _move(src, dst, amt);
        if (msg.sender != src && oldValue != uint256(-1)) {
            _allowance[src][msg.sender] = sub(oldValue, amt);
            emit Approval(msg.sender, dst, _allowance[src][msg.sender]);
        }
        return true;
    }
}

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.7.6;

import './Token.sol';
import './libs/complifi/IVault.sol';

interface IPool is IERC20 {
    function repricingBlock() external view returns (uint256);

    function controller() external view returns (address);

    function baseFee() external view returns (uint256);

    function feeAmpPrimary() external view returns (uint256);

    function feeAmpComplement() external view returns (uint256);

    function maxFee() external view returns (uint256);

    function pMin() external view returns (uint256);

    function qMin() external view returns (uint256);

    function exposureLimitPrimary() external view returns (uint256);

    function exposureLimitComplement() external view returns (uint256);

    function repricerParam1() external view returns (uint256);

    function repricerParam2() external view returns (uint256);

    function derivativeVault() external view returns (IVault);

    function dynamicFee() external view returns (address);

    function repricer() external view returns (address);

    function isFinalized() external view returns (bool);

    function getNumTokens() external view returns (uint256);

    function getTokens() external view returns (address[2] memory tokens);

    function getLeverage(address token) external view returns (uint256);

    function getBalance(address token) external view returns (uint256);

    function joinPool(uint256 poolAmountOut, uint256[2] calldata maxAmountsIn) external;

    function exitPool(uint256 poolAmountIn, uint256[2] calldata minAmountsOut) external;

    function swapExactAmountIn(
        address tokenIn,
        uint256 tokenAmountIn,
        address tokenOut,
        uint256 minAmountOut
    ) external returns (uint256 tokenAmountOut, uint256 spotPriceAfter);

    function paused() external view returns (bool);

    function swappable() external view returns (bool);
    function setSwappable() external;
}

pragma solidity 0.7.6;

interface IRolloverStrategy {
    function execute(
        address _poolSettled,
        uint256 _poolAmountIn,
        uint256[] memory _underlyingEndRoundHints,
        address _poolNew
    ) external;
}

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.7.6;

import './Num.sol';

contract Math is Const, Num {
    /**********************************************************************************************
    // calcSpotPrice                                                                             //
    // sP = spotPrice                                                                            //
    // bI = tokenBalanceIn                 bI          1                                         //
    // bO = tokenBalanceOut         sP =  ----  *  ----------                                    //
    // sF = swapFee                        bO      ( 1 - sF )                                    //
    **********************************************************************************************/
    function calcSpotPrice(
        uint256 tokenBalanceIn,
        uint256 tokenBalanceOut,
        uint256 swapFee
    ) public pure returns (uint256 spotPrice) {
        uint256 ratio = div(tokenBalanceIn, tokenBalanceOut);
        uint256 scale = div(BONE, sub(BONE, swapFee));
        spotPrice = mul(ratio, scale);
    }

    /**********************************************************************************************
    // calcOutGivenIn                                                                            //
    // aO = tokenAmountOut                                                                       //
    // bO = tokenBalanceOut                                                                      //
    // bI = tokenBalanceIn              /      /            bI             \   \                 //
    // aI = tokenAmountIn    aO = bO * |  1 - | --------------------------  |  |                 //
    // sF = swapFee                     \      \ ( bI + ( aI * ( 1 - sF )) /   /                 //
    **********************************************************************************************/
    function calcOutGivenIn(
        uint256 tokenBalanceIn,
        uint256 tokenBalanceOut,
        uint256 tokenAmountIn,
        uint256 swapFee
    ) public pure returns (uint256 tokenAmountOut) {
        uint256 adjustedIn = sub(BONE, swapFee);
        adjustedIn = mul(tokenAmountIn, adjustedIn);
        uint256 y = div(tokenBalanceIn, add(tokenBalanceIn, adjustedIn));
        uint256 bar = sub(BONE, y);
        tokenAmountOut = mul(tokenBalanceOut, bar);
    }
}

// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

interface IERC20Metadata {
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);
}

// "SPDX-License-Identifier: GNU General Public License v3.0"

pragma solidity 0.7.6;

import '../libs/complifi/IVaultMinimal.sol';

interface IRepricer {
    function isRepricer() external pure returns (bool);

    function symbol() external pure returns (string memory);

    function reprice(
        IVaultMinimal _vault,
        uint256 _pMin,
        int256 _repricerParam1,
        int256 _repricerParam2
    )
        external
        view
        returns (
            int256 estPricePrimary,
            int256 estPriceComplement,
            uint256 estPrice,
            uint256 upperBoundary
        );

    function sqrtWrapped(int256 x) external pure returns (int256);
}

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.7.6;
pragma experimental ABIEncoderV2;

interface IDynamicFee {
    function calc(
        int256[3] calldata _inRecord,
        int256[3] calldata _outRecord,
        int256 _baseFee,
        int256 _feeAmp,
        int256 _maxFee
    ) external pure returns (int256 fee, int256 expStart);
}

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.7.6;

import './Const.sol';

contract Num is Const {

    function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
        c = a + b;
        require(c >= a, 'ADD_OVERFLOW');
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256 c) {
        bool flag;
        (c, flag) = subSign(a, b);
        require(!flag, 'SUB_UNDERFLOW');
    }

    function subSign(uint256 a, uint256 b) internal pure returns (uint256, bool) {
        if (a >= b) {
            return (a - b, false);
        } else {
            return (b - a, true);
        }
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
        uint256 c0 = a * b;
        require(a == 0 || c0 / a == b, 'MUL_OVERFLOW');
        uint256 c1 = c0 + (BONE / 2);
        require(c1 >= c0, 'MUL_OVERFLOW');
        c = c1 / BONE;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256 c) {
        require(b != 0, 'DIV_ZERO');
        uint256 c0 = a * BONE;
        require(a == 0 || c0 / a == BONE, 'DIV_INTERNAL'); // mul overflow
        uint256 c1 = c0 + (b / 2);
        require(c1 >= c0, 'DIV_INTERNAL'); //  add require
        c = c1 / b;
    }

    function min(uint256 first, uint256 second) internal pure returns (uint256) {
        if (first < second) {
            return first;
        }
        return second;
    }
}

// This program is free software: you can redistribute it and/or modify
// it under the terms of the GNU General Public License as published by
// the Free Software Foundation, either version 3 of the License, or
// (at your option) any later version.

// This program is distributed in the hope that it will be useful,
// but WITHOUT ANY WARRANTY; without even the implied warranty of
// MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
// GNU General Public License for more details.

// You should have received a copy of the GNU General Public License
// along with this program.  If not, see <http://www.gnu.org/licenses/>.

pragma solidity 0.7.6;

contract Const {
    uint256 public constant BONE = 10**18;
    int256 public constant iBONE = int256(BONE);

    uint256 public constant MIN_POW_BASE = 1 wei;
    uint256 public constant MAX_POW_BASE = (2 * BONE) - 1 wei;
    uint256 public constant POW_PRECISION = BONE / 10**10;
}

// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "./IDerivativeSpecification.sol";

/// @title Derivative implementation Vault
/// @notice A smart contract that references derivative specification and enables users to mint and redeem the derivative
interface IVault {
    enum State { Created, Live, Settled }

    /// @notice start of live period
    function liveTime() external view returns (uint256);

    /// @notice end of live period
    function settleTime() external view returns (uint256);

    /// @notice redeem function can only be called after the end of the Live period + delay
    function settlementDelay() external view returns (uint256);

    /// @notice underlying value at the start of live period
    function underlyingStarts(uint256 index) external view returns (int256);

    /// @notice underlying value at the end of live period
    function underlyingEnds(uint256 index) external view returns (int256);

    /// @notice primary token conversion rate multiplied by 10 ^ 12
    function primaryConversion() external view returns (uint256);

    /// @notice complement token conversion rate multiplied by 10 ^ 12
    function complementConversion() external view returns (uint256);

    /// @notice protocol fee multiplied by 10 ^ 12
    function protocolFee() external view returns (uint256);

    /// @notice limit on author fee multiplied by 10 ^ 12
    function authorFeeLimit() external view returns (uint256);

    // @notice protocol's fee receiving wallet
    function feeWallet() external view returns (address);

    // @notice current state of the vault
    function state() external view returns (State);

    // @notice derivative specification address
    function derivativeSpecification()
        external
        view
        returns (IDerivativeSpecification);

    // @notice collateral token address
    function collateralToken() external view returns (address);

    // @notice oracle address
    function oracles(uint256 index) external view returns (address);

    function oracleIterators(uint256 index) external view returns (address);

    // @notice collateral split address
    function collateralSplit() external view returns (address);

    // @notice derivative's token builder strategy address
    function tokenBuilder() external view returns (address);

    function feeLogger() external view returns (address);

    // @notice primary token address
    function primaryToken() external view returns (address);

    // @notice complement token address
    function complementToken() external view returns (address);

    /// @notice Switch to Settled state if appropriate time threshold is passed and
    /// set underlyingStarts value and set underlyingEnds value,
    /// calculate primaryConversion and complementConversion params
    /// @dev Reverts if underlyingStart or underlyingEnd are not available
    /// Vault cannot settle when it paused
    function settle(uint256[] calldata _underlyingEndRoundHints) external;

    function mintTo(address _recipient, uint256 _collateralAmount) external;

    /// @notice Mints primary and complement derivative tokens
    /// @dev Checks and switches to the right state and does nothing if vault is not in Live state
    function mint(uint256 _collateralAmount) external;

    /// @notice Refund equal amounts of derivative tokens for collateral at any time
    function refund(uint256 _tokenAmount) external;

    function refundTo(address _recipient, uint256 _tokenAmount) external;

    function redeemTo(
        address _recipient,
        uint256 _primaryTokenAmount,
        uint256 _complementTokenAmount,
        uint256[] calldata _underlyingEndRoundHints
    ) external;

    /// @notice Redeems unequal amounts previously calculated conversions if the vault is in Settled state
    function redeem(
        uint256 _primaryTokenAmount,
        uint256 _complementTokenAmount,
        uint256[] calldata _underlyingEndRoundHints
    ) external;
}

// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

/// @title Derivative Specification interface
/// @notice Immutable collection of derivative attributes
/// @dev Created by the derivative's author and published to the DerivativeSpecificationRegistry
interface IDerivativeSpecification {
    /// @notice Proof of a derivative specification
    /// @dev Verifies that contract is a derivative specification
    /// @return true if contract is a derivative specification
    function isDerivativeSpecification() external pure returns (bool);

    /// @notice Set of oracles that are relied upon to measure changes in the state of the world
    /// between the start and the end of the Live period
    /// @dev Should be resolved through OracleRegistry contract
    /// @return oracle symbols
    function oracleSymbols() external view returns (bytes32[] memory);

    /// @notice Algorithm that, for the type of oracle used by the derivative,
    /// finds the value closest to a given timestamp
    /// @dev Should be resolved through OracleIteratorRegistry contract
    /// @return oracle iterator symbols
    function oracleIteratorSymbols() external view returns (bytes32[] memory);

    /// @notice Type of collateral that users submit to mint the derivative
    /// @dev Should be resolved through CollateralTokenRegistry contract
    /// @return collateral token symbol
    function collateralTokenSymbol() external view returns (bytes32);

    /// @notice Mapping from the change in the underlying variable (as defined by the oracle)
    /// and the initial collateral split to the final collateral split
    /// @dev Should be resolved through CollateralSplitRegistry contract
    /// @return collateral split symbol
    function collateralSplitSymbol() external view returns (bytes32);

    /// @notice Lifecycle parameter that define the length of the derivative's Live period.
    /// @dev Set in seconds
    /// @return live period value
    function livePeriod() external view returns (uint256);

    /// @notice Parameter that determines starting nominal value of primary asset
    /// @dev Units of collateral theoretically swappable for 1 unit of primary asset
    /// @return primary nominal value
    function primaryNominalValue() external view returns (uint256);

    /// @notice Parameter that determines starting nominal value of complement asset
    /// @dev Units of collateral theoretically swappable for 1 unit of complement asset
    /// @return complement nominal value
    function complementNominalValue() external view returns (uint256);

    /// @notice Minting fee rate due to the author of the derivative specification.
    /// @dev Percentage fee multiplied by 10 ^ 12
    /// @return author fee
    function authorFee() external view returns (uint256);

    /// @notice Symbol of the derivative
    /// @dev Should be resolved through DerivativeSpecificationRegistry contract
    /// @return derivative specification symbol
    function symbol() external view returns (string memory);

    /// @notice Return optional long name of the derivative
    /// @dev Isn't used directly in the protocol
    /// @return long name
    function name() external view returns (string memory);

    /// @notice Optional URI to the derivative specs
    /// @dev Isn't used directly in the protocol
    /// @return URI to the derivative specs
    function baseURI() external view returns (string memory);

    /// @notice Derivative spec author
    /// @dev Used to set and receive author's fee
    /// @return address of the author
    function author() external view returns (address);
}

// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

import "./IDerivativeSpecificationMinimal.sol";

interface IVaultMinimal {

    function settleTime() external view returns (uint256);

    function derivativeSpecification()
    external
    view
    returns (IDerivativeSpecificationMinimal);

    function collateralToken() external view returns (address);

    function primaryToken() external view returns (address);

    function complementToken() external view returns (address);

    function underlyingStarts(uint256 index) external view returns (int256);

    function oracles(uint256 index) external view returns (address);
}

// "SPDX-License-Identifier: GPL-3.0-or-later"

pragma solidity 0.7.6;

interface IDerivativeSpecificationMinimal {

    function primaryNominalValue() external view returns (uint256);

    function complementNominalValue() external view returns (uint256);

    function symbol() external view returns (string memory);

    function name() external view returns (string memory);
}

{
  "optimizer": {
    "enabled": true,
    "runs": 1000000
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