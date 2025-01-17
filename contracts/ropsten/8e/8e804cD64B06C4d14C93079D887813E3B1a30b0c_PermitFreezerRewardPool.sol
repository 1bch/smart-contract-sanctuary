// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../dependencies/openzeppelin/contracts/SafeMath.sol';
import '../../tools/Errors.sol';
import '../interfaces/IRewardController.sol';
import '../calcs/CalcLinearFreezer.sol';
import './BasePermitRewardPool.sol';

contract PermitFreezerRewardPool is BasePermitRewardPool, CalcLinearFreezer {
  uint256 private _rewardLimit;

  constructor(
    IRewardController controller,
    uint256 rewardLimit,
    uint32 meltDownAt,
    string memory rewardPoolName
  ) BasePermitRewardPool(controller, 0, NO_BASELINE, rewardPoolName) {
    _rewardLimit = rewardLimit;
    internalSetMeltDownAt(meltDownAt);
  }

  function getClaimTypeHash() internal pure override returns (bytes32) {
    return
      keccak256(
        'ClaimReward(address provider,address spender,uint256 value,uint256 nonce,uint256 deadline)'
      );
  }

  function setFreezePercentage(uint16 freezePortion) external onlyConfigAdmin {
    internalSetFreezePercentage(freezePortion);
  }

  function setMeltDownAt(uint32 at) external onlyConfigAdmin {
    internalSetMeltDownAt(at);
  }

  function availableReward() public view override returns (uint256) {
    return _rewardLimit;
  }

  function claimRewardByPermit(
    address provider,
    address spender,
    uint256 value,
    uint256 deadline,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) external notPaused {
    uint256 currentValidNonce = _nonces[spender];

    bytes32 encodedHash =
      keccak256(abi.encode(CLAIM_TYPEHASH, provider, spender, value, currentValidNonce, deadline));

    doClaimRewardByPermit(
      provider,
      spender,
      spender,
      value,
      deadline,
      encodedHash,
      currentValidNonce,
      v,
      r,
      s
    );
  }

  function internalCheckNonce(uint256 currentValidNonce, uint256 deadline)
    internal
    view
    override
    returns (uint256)
  {
    require(block.timestamp <= deadline, 'INVALID_EXPIRATION');
    return currentValidNonce + 1;
  }

  function internalGetReward(address holder, uint256)
    internal
    override
    returns (uint256 allocated, uint32)
  {
    (allocated, ) = doClaimByPull(holder, 0, 0);
    return (allocated, uint32(block.timestamp));
  }

  function internalCalcReward(address holder, uint32 at)
    internal
    view
    override
    returns (uint256 allocated, uint32)
  {
    (allocated, ) = doCalcByPull(holder, 0, 0, at, false);
    return (allocated, uint32(block.timestamp));
  }

  function internalPushReward(
    address holder,
    uint256 allocated,
    uint32 since
  ) internal override {
    AllocationMode mode;
    (allocated, since, mode) = doAllocatedByPush(holder, allocated, since);

    if (allocated == 0 && mode == AllocationMode.Push) {
      return;
    }
    internalAllocateReward(holder, allocated, since, mode);
  }

  function internalUpdateFunds(uint256 value) internal override {
    _rewardLimit = SafeMath.sub(_rewardLimit, value, Errors.VL_INSUFFICIENT_REWARD_AVAILABLE);
  }

  function internalSetBaselinePercentage(uint16) internal pure override {
    revert('UNSUPPORTED');
  }

  function internalSetRate(uint256 rate) internal pure override {
    if (rate != 0) {
      revert('UNSUPPORTED');
    }
  }

  function internalGetRate() internal pure override returns (uint256) {
    return 0;
  }
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

/// @dev Replacement of SafeMath to use with solc 0.8
library SafeMath {
  function add(uint256 a, uint256 b) internal pure returns (uint256) {
    return a + b;
  }

  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    return a - b;
  }

  function sub(
    uint256 a,
    uint256 b,
    string memory errorMessage
  ) internal pure returns (uint256) {
    require(b <= a, errorMessage);
    unchecked {
      return a - b;
    }
  }

  function mul(uint256 a, uint256 b) internal pure returns (uint256) {
    return a * b;
  }

  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    return a / b;
  }

  function mod(uint256 a, uint256 b) internal pure returns (uint256) {
    return a % b;
  }
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

/**
 * @title Errors library
 * @author Aave
 * @notice Defines the error messages emitted by the different contracts of the Aave protocol
 * @dev Error messages prefix glossary:
 *  - VL = ValidationLogic
 *  - MATH = Math libraries
 *  - CT = Common errors between tokens (DepositToken, VariableDebtToken and StableDebtToken)
 *  - AT = DepositToken
 *  - SDT = StableDebtToken
 *  - VDT = VariableDebtToken
 *  - LP = LendingPool
 *  - LPAPR = AddressesProviderRegistry
 *  - LPC = LendingPoolConfiguration
 *  - RL = ReserveLogic
 *  - LPCM = LendingPoolExtension
 *  - ST = Stake
 */
library Errors {
  //contract specific errors
  string public constant VL_INVALID_AMOUNT = '1'; // Amount must be greater than 0
  string public constant VL_NO_ACTIVE_RESERVE = '2'; // Action requires an active reserve
  string public constant VL_RESERVE_FROZEN = '3'; // Action cannot be performed because the reserve is frozen
  string public constant VL_CURRENT_AVAILABLE_LIQUIDITY_NOT_ENOUGH = '4'; // The current liquidity is not enough
  string public constant VL_NOT_ENOUGH_AVAILABLE_USER_BALANCE = '5'; // User cannot withdraw more than the available balance
  string public constant VL_TRANSFER_NOT_ALLOWED = '6'; // Transfer cannot be allowed.
  string public constant VL_BORROWING_NOT_ENABLED = '7'; // Borrowing is not enabled
  string public constant VL_INVALID_INTEREST_RATE_MODE_SELECTED = '8'; // Invalid interest rate mode selected
  string public constant VL_COLLATERAL_BALANCE_IS_0 = '9'; // The collateral balance is 0
  string public constant VL_HEALTH_FACTOR_LOWER_THAN_LIQUIDATION_THRESHOLD = '10'; // Health factor is lesser than the liquidation threshold
  string public constant VL_COLLATERAL_CANNOT_COVER_NEW_BORROW = '11'; // There is not enough collateral to cover a new borrow
  string public constant VL_STABLE_BORROWING_NOT_ENABLED = '12'; // stable borrowing not enabled
  string public constant VL_COLLATERAL_SAME_AS_BORROWING_CURRENCY = '13'; // collateral is (mostly) the same currency that is being borrowed
  string public constant VL_AMOUNT_BIGGER_THAN_MAX_LOAN_SIZE_STABLE = '14'; // The requested amount is greater than the max loan size in stable rate mode
  string public constant VL_NO_DEBT_OF_SELECTED_TYPE = '15'; // for repayment of stable debt, the user needs to have stable debt, otherwise, he needs to have variable debt
  string public constant VL_NO_EXPLICIT_AMOUNT_TO_REPAY_ON_BEHALF = '16'; // To repay on behalf of an user an explicit amount to repay is needed
  string public constant VL_NO_STABLE_RATE_LOAN_IN_RESERVE = '17'; // User does not have a stable rate loan in progress on this reserve
  string public constant VL_NO_VARIABLE_RATE_LOAN_IN_RESERVE = '18'; // User does not have a variable rate loan in progress on this reserve
  string public constant VL_UNDERLYING_BALANCE_NOT_GREATER_THAN_0 = '19'; // The underlying balance needs to be greater than 0
  string public constant VL_DEPOSIT_ALREADY_IN_USE = '20'; // User deposit is already being used as collateral
  string public constant LP_NOT_ENOUGH_STABLE_BORROW_BALANCE = '21'; // User does not have any stable rate loan for this reserve
  string public constant LP_INTEREST_RATE_REBALANCE_CONDITIONS_NOT_MET = '22'; // Interest rate rebalance conditions were not met
  //  string public constant LP_LIQUIDATION_CALL_FAILED = '23'; // Liquidation call failed
  string public constant LP_NOT_ENOUGH_LIQUIDITY_TO_BORROW = '24'; // There is not enough liquidity available to borrow
  string public constant LP_REQUESTED_AMOUNT_TOO_SMALL = '25'; // The requested amount is too small for a FlashLoan.
  string public constant LP_INCONSISTENT_PROTOCOL_ACTUAL_BALANCE = '26'; // The actual balance of the protocol is inconsistent
  string public constant LP_CALLER_NOT_LENDING_POOL_CONFIGURATOR = '27'; // The caller of the function is not the lending pool configurator
  string public constant LP_INCONSISTENT_FLASHLOAN_PARAMS = '28';
  string public constant CT_CALLER_MUST_BE_LENDING_POOL = '29'; // The caller of this function must be a lending pool
  string public constant CT_CANNOT_GIVE_ALLOWANCE_TO_HIMSELF = '30'; // User cannot give allowance to himself
  string public constant CT_TRANSFER_AMOUNT_NOT_GT_0 = '31'; // Transferred amount needs to be greater than zero
  string public constant RL_RESERVE_ALREADY_INITIALIZED = '32'; // Reserve has already been initialized
  string public constant CALLER_NOT_POOL_ADMIN = '33'; // The caller must be the pool admin
  string public constant LPC_RESERVE_LIQUIDITY_NOT_0 = '34'; // The liquidity of the reserve needs to be 0
  string public constant LPC_INVALID_ATOKEN_POOL_ADDRESS = '35'; // The liquidity of the reserve needs to be 0
  string public constant LPC_INVALID_STABLE_DEBT_TOKEN_POOL_ADDRESS = '36'; // The liquidity of the reserve needs to be 0
  string public constant LPC_INVALID_VARIABLE_DEBT_TOKEN_POOL_ADDRESS = '37'; // The liquidity of the reserve needs to be 0
  string public constant LPC_INVALID_STABLE_DEBT_TOKEN_UNDERLYING_ADDRESS = '38'; // The liquidity of the reserve needs to be 0
  string public constant LPC_INVALID_VARIABLE_DEBT_TOKEN_UNDERLYING_ADDRESS = '39'; // The liquidity of the reserve needs to be 0
  string public constant LPC_INVALID_ADDRESSES_PROVIDER_ID = '40'; // The liquidity of the reserve needs to be 0
  string public constant LPAPR_PROVIDER_NOT_REGISTERED = '41'; // Provider is not registered
  string public constant LPCM_HEALTH_FACTOR_NOT_BELOW_THRESHOLD = '42'; // Health factor is not below the threshold
  string public constant LPCM_COLLATERAL_CANNOT_BE_LIQUIDATED = '43'; // The collateral chosen cannot be liquidated
  string public constant LPCM_SPECIFIED_CURRENCY_NOT_BORROWED_BY_USER = '44'; // User did not borrow the specified currency
  string public constant LPCM_NOT_ENOUGH_LIQUIDITY_TO_LIQUIDATE = '45'; // There isn't enough liquidity available to liquidate
  //  string public constant LPCM_NO_ERRORS = '46'; // No errors
  string public constant LP_INVALID_FLASHLOAN_MODE = '47'; //Invalid flashloan mode selected
  string public constant MATH_MULTIPLICATION_OVERFLOW = '48';
  string public constant MATH_ADDITION_OVERFLOW = '49';
  string public constant MATH_DIVISION_BY_ZERO = '50';
  string public constant RL_LIQUIDITY_INDEX_OVERFLOW = '51'; //  Liquidity index overflows uint128
  string public constant RL_VARIABLE_BORROW_INDEX_OVERFLOW = '52'; //  Variable borrow index overflows uint128
  string public constant RL_LIQUIDITY_RATE_OVERFLOW = '53'; //  Liquidity rate overflows uint128
  string public constant RL_VARIABLE_BORROW_RATE_OVERFLOW = '54'; //  Variable borrow rate overflows uint128
  string public constant RL_STABLE_BORROW_RATE_OVERFLOW = '55'; //  Stable borrow rate overflows uint128
  string public constant CT_INVALID_MINT_AMOUNT = '56'; //invalid amount to mint
  string public constant LP_FAILED_REPAY_WITH_COLLATERAL = '57';
  string public constant CT_INVALID_BURN_AMOUNT = '58'; //invalid amount to burn
  string public constant BORROW_ALLOWANCE_NOT_ENOUGH = '59'; // User borrows on behalf, but allowance are too small
  string public constant LP_FAILED_COLLATERAL_SWAP = '60';
  string public constant LP_INVALID_EQUAL_ASSETS_TO_SWAP = '61';
  string public constant LP_REENTRANCY_NOT_ALLOWED = '62';
  string public constant LP_CALLER_MUST_BE_AN_ATOKEN = '63';
  string public constant LP_IS_PAUSED = '64'; // Pool is paused
  string public constant LP_NO_MORE_RESERVES_ALLOWED = '65';
  string public constant LP_INVALID_FLASH_LOAN_EXECUTOR_RETURN = '66';
  string public constant RC_INVALID_LTV = '67';
  string public constant RC_INVALID_LIQ_THRESHOLD = '68';
  string public constant RC_INVALID_LIQ_BONUS = '69';
  string public constant RC_INVALID_DECIMALS = '70';
  string public constant RC_INVALID_RESERVE_FACTOR = '71';
  string public constant LPAPR_INVALID_ADDRESSES_PROVIDER_ID = '72';
  string public constant VL_INCONSISTENT_FLASHLOAN_PARAMS = '73';
  string public constant LP_INCONSISTENT_PARAMS_LENGTH = '74';
  string public constant LPC_INVALID_CONFIGURATION = '75'; // Invalid risk parameters for the reserve
  string public constant CALLER_NOT_EMERGENCY_ADMIN = '76'; // The caller must be the emergency admin
  string public constant UL_INVALID_INDEX = '77';
  string public constant VL_CONTRACT_REQUIRED = '78';
  string public constant SDT_STABLE_DEBT_OVERFLOW = '79';
  string public constant SDT_BURN_EXCEEDS_BALANCE = '80';
  string public constant CT_CALLER_MUST_BE_REWARD_ADMIN = '81'; // The caller of this function must be a reward admin
  string public constant LP_INVALID_PERCENTAGE = '82'; // Percentage can't be more than 100%
  string public constant LP_IS_NOT_TRUSTED_FLASHLOAN = '83';
  string public constant CT_CALLER_MUST_BE_SWEEP_ADMIN = '84';
  string public constant LP_TOO_MANY_NESTED_CALLS = '85';
  string public constant LP_RESTRICTED_FEATURE = '86';
  string public constant LP_TOO_MANY_FLASHLOAN_CALLS = '87';

  string public constant CT_CALLER_MUST_BE_REWARD_RATE_ADMIN = '89';
  string public constant CT_CALLER_MUST_BE_REWARD_CONTROLLER = '90';
  string public constant RW_REWARD_PAUSED = '91';
  string public constant CT_CALLER_MUST_BE_TEAM_MANAGER = '92';

  string public constant STK_REDEEM_PAUSED = '93';
  string public constant STK_INSUFFICIENT_COOLDOWN = '94';
  string public constant STK_UNSTAKE_WINDOW_FINISHED = '95';
  string public constant STK_INVALID_BALANCE_ON_COOLDOWN = '96';
  string public constant STK_EXCESSIVE_SLASH_PCT = '97';
  string public constant STK_EXCESSIVE_COOLDOWN_PERIOD = '98';
  string public constant STK_WRONG_UNSTAKE_PERIOD = '98';

  string public constant VL_INSUFFICIENT_REWARD_AVAILABLE = '99';

  string public constant TXT_OWNABLE_CALLER_NOT_OWNER = 'Ownable: caller is not the owner';
  string public constant TXT_CALLER_NOT_PROXY_OWNER = 'ProxyOwner: caller is not the owner';
  string public constant TXT_ACCESS_RESTRICTED = 'RESTRICTED';
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../access/interfaces/IMarketAccessController.sol';

enum AllocationMode {Push, SetPull, UnsetPull}

interface IRewardController {
  function allocatedByPool(
    address holder,
    uint256 allocated,
    uint32 since,
    AllocationMode mode
  ) external;

  function isRateAdmin(address) external view returns (bool);

  function isConfigAdmin(address) external view returns (bool);

  function isEmergencyAdmin(address) external view returns (bool);

  function getAccessController() external view returns (IMarketAccessController);
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../tools/math/PercentageMath.sol';
import {AllocationMode} from '../interfaces/IRewardController.sol';

abstract contract CalcLinearFreezer {
  using PercentageMath for uint256;

  struct FrozenReward {
    uint224 frozenReward;
    uint32 lastUpdatedAt;
  }

  mapping(address => FrozenReward) private _frozenRewards;
  uint32 private _meltdownAt;
  uint16 private _unfrozenPortion;

  function internalSetFreezePercentage(uint16 freezePortion) internal {
    _unfrozenPortion = PercentageMath.ONE - freezePortion;
  }

  function getFreezePercentage() public view returns (uint16) {
    return PercentageMath.ONE - _unfrozenPortion;
  }

  function internalSetMeltDownAt(uint32 at) internal {
    require(_meltdownAt == 0 || _meltdownAt > block.timestamp);
    _meltdownAt = at;
  }

  function getMeltDownAt() public view returns (uint32) {
    return _meltdownAt;
  }

  function doAllocatedByPush(
    address holder,
    uint256 allocated,
    uint32 since
  )
    internal
    returns (
      uint256,
      uint32,
      AllocationMode
    )
  {
    uint256 frozenBefore = _frozenRewards[holder].frozenReward;

    (allocated, ) = internalApplyAllocated(holder, allocated, since, uint32(block.timestamp));

    AllocationMode mode = AllocationMode.Push;
    if (_frozenRewards[holder].frozenReward > 0) {
      if (frozenBefore == 0) {
        mode = AllocationMode.SetPull;
      }
    } else if (frozenBefore > 0) {
      mode = AllocationMode.UnsetPull;
    }

    return (allocated, uint32(block.timestamp), mode);
  }

  function doAllocatedByPool(
    address holder,
    uint256 allocated,
    uint32 since
  ) internal returns (uint256) {
    (allocated, ) = internalApplyAllocated(holder, allocated, since, uint32(block.timestamp));
    return allocated;
  }

  function doClaimByPull(
    address holder,
    uint256 allocated,
    uint32 since
  ) internal returns (uint256 claimableAmount, uint256 delayedAmount) {
    return internalApplyAllocated(holder, allocated, since, uint32(block.timestamp));
  }

  enum FrozenRewardState {NotRead, Read, Updated, Remove}

  function internalCalcAllocated(
    address holder,
    uint256 allocated,
    uint32 since,
    uint32 current,
    bool incremental
  )
    private
    view
    returns (
      uint256 amount,
      uint256 frozenReward,
      FrozenRewardState state
    )
  {
    if (_meltdownAt > 0 && _meltdownAt <= current) {
      if (incremental) {
        return (allocated, 0, FrozenRewardState.NotRead);
      }
      frozenReward = _frozenRewards[holder].frozenReward;
      if (frozenReward == 0) {
        return (allocated, 0, FrozenRewardState.Read);
      }
      allocated = allocated + frozenReward;
      return (allocated, 0, FrozenRewardState.Remove);
    }

    if (_unfrozenPortion < PercentageMath.ONE) {
      amount = allocated.percentMul(_unfrozenPortion);
      allocated -= amount;
    } else {
      amount = allocated;
      allocated = 0;
    }

    if (_meltdownAt > 0) {
      if (allocated > 0 && since != 0 && since < current) {
        // portion of the allocated was already unfreezed
        uint256 unfrozen = calcUnfrozenDuringEmmission(allocated, since, current);
        if (unfrozen > 0) {
          amount += unfrozen;
          allocated -= unfrozen;
        }
      }

      if (!incremental) {
        frozenReward = _frozenRewards[holder].frozenReward;
        state = FrozenRewardState.Read;

        if (frozenReward > 0) {
          uint256 unfrozen =
            calcUnfrozen(frozenReward, _frozenRewards[holder].lastUpdatedAt, current);
          if (unfrozen > 0) {
            amount += unfrozen;
            frozenReward -= unfrozen;
            state = FrozenRewardState.Updated;
          }
        }
      }
    }

    if (allocated > 0) {
      if (state == FrozenRewardState.NotRead && !incremental) {
        frozenReward = _frozenRewards[holder].frozenReward;
      }
      frozenReward += allocated;
      require(frozenReward <= type(uint224).max, 'reward is too high');
      state = FrozenRewardState.Updated;
    }

    return (amount, frozenReward, state);
  }

  function internalApplyAllocated(
    address holder,
    uint256 allocated,
    uint32 since,
    uint32 current
  ) private returns (uint256, uint256) {
    uint256 frozenBefore = _frozenRewards[holder].frozenReward;

    (uint256 amount, uint256 frozenReward, FrozenRewardState state) =
      internalCalcAllocated(holder, allocated, since, current, false);

    if (state == FrozenRewardState.Updated) {
      // was updated
      _frozenRewards[holder].frozenReward = uint224(frozenReward);
      _frozenRewards[holder].lastUpdatedAt = current;
    } else if (state == FrozenRewardState.Remove) {
      delete (_frozenRewards[holder]);
    }

    if (frozenBefore < frozenReward) {
      frozenReward = frozenReward - frozenBefore;
    } else {
      frozenReward = 0;
    }

    return (amount, frozenReward);
  }

  function calcUnfrozen(
    uint256 frozenReward,
    uint32 lastUpdatedAt,
    uint32 current
  ) private view returns (uint256) {
    return (frozenReward * (current - lastUpdatedAt)) / (_meltdownAt - lastUpdatedAt);
  }

  function calcUnfrozenDuringEmmission(
    uint256 emittedReward,
    uint32 lastUpdatedAt,
    uint32 current
  ) private view returns (uint256) {
    return (emittedReward * ((current - lastUpdatedAt + 1) >> 1)) / (_meltdownAt - lastUpdatedAt);
  }

  function doCalcByPull(
    address holder,
    uint256 allocated,
    uint32 since,
    uint32 at,
    bool incremental
  ) internal view returns (uint256 claimableAmount, uint256 frozenReward) {
    uint256 frozenBefore = _frozenRewards[holder].frozenReward;

    (claimableAmount, frozenReward, ) = internalCalcAllocated(
      holder,
      allocated,
      since,
      at,
      incremental
    );

    if (frozenBefore < frozenReward) {
      frozenReward = frozenReward - frozenBefore;
    } else {
      frozenReward = 0;
    }

    return (claimableAmount, frozenReward);
  }
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../interfaces/IRewardController.sol';
import './ControlledRewardPool.sol';

abstract contract BasePermitRewardPool is ControlledRewardPool {
  bytes public constant EIP712_REVISION = bytes('1');
  bytes32 public DOMAIN_SEPARATOR;
  bytes32 internal constant EIP712_DOMAIN =
    keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)');
  bytes32 public CLAIM_TYPEHASH;

  /// @dev spender => next valid nonce to submit with permit()
  mapping(address => uint256) public _nonces;

  string private _rewardPoolName;

  mapping(address => bool) private _providers;

  constructor(
    IRewardController controller,
    uint256 initialRate,
    uint16 baselinePercentage,
    string memory rewardPoolName
  ) ControlledRewardPool(controller, initialRate, baselinePercentage) {
    _rewardPoolName = rewardPoolName;

    _initializeDomainSeparator();
  }

  function _initialize(
    IRewardController controller,
    uint256 initialRate,
    uint16 baselinePercentage,
    string memory rewardPoolName
  ) internal {
    _rewardPoolName = rewardPoolName;
    _initializeDomainSeparator();
    super._initialize(controller, initialRate, baselinePercentage);
  }

  function _initializeDomainSeparator() internal {
    uint256 chainId;

    //solium-disable-next-line
    assembly {
      chainId := chainid()
    }

    DOMAIN_SEPARATOR = keccak256(
      abi.encode(
        EIP712_DOMAIN,
        keccak256(bytes(_rewardPoolName)),
        keccak256(EIP712_REVISION),
        chainId,
        address(this)
      )
    );
    CLAIM_TYPEHASH = getClaimTypeHash();
  }

  function getPoolName() public view override returns (string memory) {
    return _rewardPoolName;
  }

  function availableReward() public view virtual returns (uint256);

  function getClaimTypeHash() internal pure virtual returns (bytes32);

  function addRewardProvider(address provider, address token) external override onlyConfigAdmin {
    require(provider != address(0), 'provider is required');
    require(token == address(0), 'token is unsupported');
    _providers[provider] = true;
    emit ProviderAdded(provider, token);
  }

  function removeRewardProvider(address provider) external override onlyConfigAdmin {
    delete (_providers[provider]);
    emit ProviderRemoved(provider);
  }

  function doClaimRewardByPermit(
    address provider,
    address spender,
    address to,
    uint256 value,
    uint256 at,
    bytes32 encodedHash,
    uint256 currentValidNonce,
    uint8 v,
    bytes32 r,
    bytes32 s
  ) internal {
    require(provider != address(0) && _providers[provider], 'INVALID_PROVIDER');

    bytes32 digest = keccak256(abi.encodePacked('\x19\x01', DOMAIN_SEPARATOR, encodedHash));
    require(provider == ecrecover(digest, v, r, s), 'INVALID_SIGNATURE');

    _nonces[spender] = internalCheckNonce(currentValidNonce, at);

    if (value == 0) {
      return;
    }

    internalUpdateFunds(value);
    internalPushReward(to, value, uint32(block.timestamp));
  }

  function internalUpdateFunds(uint256 value) internal virtual;

  function internalCheckNonce(uint256 nonce, uint256 at) internal virtual returns (uint256);

  function internalPushReward(
    address holder,
    uint256 allocated,
    uint32 since
  ) internal virtual {
    internalAllocateReward(holder, allocated, since, AllocationMode.Push);
  }
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IAccessController.sol';

/// @dev Main registry of addresses part of or connected to the protocol, including permissioned roles. Also acts a proxy factory.
interface IMarketAccessController is IAccessController {
  function getMarketId() external view returns (string memory);

  function getLendingPool() external view returns (address);

  function isPoolAdmin(address) external view returns (bool);

  function getPriceOracle() external view returns (address);

  function getLendingRateOracle() external view returns (address);
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IRemoteAccessBitmask.sol';
import '../../tools/upgradeability/IProxy.sol';

/// @dev Main registry of permissions and addresses
interface IAccessController is IRemoteAccessBitmask {
  function getAddress(uint256 id) external view returns (address);

  function createProxy(
    address admin,
    address impl,
    bytes calldata params
  ) external returns (IProxy);
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface IRemoteAccessBitmask {
  /**
   * @dev Returns access flags granted to the given address and limited by the filterMask. filterMask == 0 has a special meaning.
   * @param addr an to get access perfmissions for
   * @param filterMask limits a subset of flags to be checked. NB! When filterMask == 0 then zero is returned no flags granted, or an unspecified non-zero value otherwise.
   * @return Access flags currently granted
   */
  function queryAccessControlMask(address addr, uint256 filterMask) external view returns (uint256);
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface IProxy {
  function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../Errors.sol';

/// @dev Percentages are defined in basis points. The precision is indicated by ONE. Operations are rounded half up.
library PercentageMath {
  uint16 constant BP = 1; // basis point
  uint16 constant PCT = 100 * BP; // basis points per percentage point
  uint16 constant ONE = 100 * PCT; // basis points per 1 (100%)
  uint16 constant HALF_ONE = ONE / 2;
  // deprecated
  uint256 constant PERCENTAGE_FACTOR = ONE; //percentage plus two decimals

  /**
   * @dev Executes a percentage multiplication
   * @param value The value of which the percentage needs to be calculated
   * @param factor Basis points of the value to be calculated
   * @return The percentage of value
   **/
  function percentMul(uint256 value, uint256 factor) internal pure returns (uint256) {
    if (value == 0 || factor == 0) {
      return 0;
    }

    require(value <= (type(uint256).max - HALF_ONE) / factor, Errors.MATH_MULTIPLICATION_OVERFLOW);

    return (value * factor + HALF_ONE) / ONE;
  }

  /**
   * @dev Executes a percentage division
   * @param value The value of which the percentage needs to be calculated
   * @param factor Basis points of the value to be calculated
   * @return The value divided the percentage
   **/
  function percentDiv(uint256 value, uint256 factor) internal pure returns (uint256) {
    require(factor != 0, Errors.MATH_DIVISION_BY_ZERO);
    uint256 halfFactor = factor >> 1;

    require(value <= (type(uint256).max - halfFactor) / ONE, Errors.MATH_MULTIPLICATION_OVERFLOW);

    return (value * ONE + halfFactor) / factor;
  }

  function percentOf(uint256 value, uint256 base) internal pure returns (uint256) {
    require(base != 0, Errors.MATH_DIVISION_BY_ZERO);
    if (value == 0) {
      return 0;
    }

    require(value <= (type(uint256).max - HALF_ONE) / ONE, Errors.MATH_MULTIPLICATION_OVERFLOW);

    return (value * ONE + (base >> 1)) / base;
  }
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../tools/math/PercentageMath.sol';
import '../interfaces/IRewardController.sol';
import '../interfaces/IManagedRewardPool.sol';
import '../../access/AccessFlags.sol';
import '../../access/AccessHelper.sol';
import '../../tools/Errors.sol';

abstract contract ControlledRewardPool is IManagedRewardPool {
  using PercentageMath for uint256;

  uint16 internal constant NO_BASELINE = type(uint16).max;

  IRewardController internal _controller;

  uint256 private _pausedRate;
  uint16 private _baselinePercentage;
  bool private _paused;

  constructor(
    IRewardController controller,
    uint256 initialRate,
    uint16 baselinePercentage
  ) {
    _initialize(controller, initialRate, baselinePercentage);
  }

  function _initialize(
    IRewardController controller,
    uint256 initialRate,
    uint16 baselinePercentage
  ) internal virtual {
    require(address(controller) != address(0), 'controller is required');
    _controller = controller;

    if (baselinePercentage == NO_BASELINE || (initialRate != 0 && baselinePercentage == 0)) {
      _baselinePercentage = NO_BASELINE;
      emit BaselineDisabled();
    } else if (baselinePercentage > 0) {
      internalSetBaselinePercentage(baselinePercentage);
    }

    if (initialRate > 0) {
      _setRate(initialRate);
    }
  }

  function getPoolName() public view virtual override returns (string memory) {
    return '';
  }

  function updateBaseline(uint256 baseline)
    external
    virtual
    override
    onlyController
    returns (bool hasBaseline, uint256 appliedRate)
  {
    if (_baselinePercentage == NO_BASELINE) {
      return (false, internalGetRate());
    }
    appliedRate = baseline.percentMul(_baselinePercentage);
    _setRate(appliedRate);
    return (true, appliedRate);
  }

  function disableBaseline() external override onlyRateAdmin {
    _baselinePercentage = NO_BASELINE;
    emit BaselineDisabled();
  }

  function disableRewardPool() external override onlyRateAdmin {
    _baselinePercentage = NO_BASELINE;
    _pausedRate = 0;
    internalSetRate(0);
    emit BaselineDisabled();
    emit RateUpdated(0);
  }

  function setBaselinePercentage(uint16 factor) external override onlyRateAdmin {
    internalSetBaselinePercentage(factor);
  }

  function getBaselinePercentage() external view override returns (bool, uint16) {
    if (_baselinePercentage == NO_BASELINE) {
      return (false, 0);
    }
    return (true, _baselinePercentage);
  }

  function internalGetBaselinePercentage() internal view returns (uint16) {
    return _baselinePercentage;
  }

  function internalSetBaselinePercentage(uint16 factor) internal virtual {
    require(factor <= PercentageMath.ONE, 'illegal value');
    _baselinePercentage = factor;
    emit BaselineFactorUpdated(factor);
  }

  function setRate(uint256 rate) external override onlyRateAdmin {
    _setRate(rate);
  }

  function _setRate(uint256 rate) internal {
    if (isPaused()) {
      _pausedRate = rate;
      return;
    }
    internalSetRate(rate);
    emit RateUpdated(rate);
  }

  function getRate() external view override returns (uint256) {
    return internalGetRate();
  }

  function internalGetRate() internal view virtual returns (uint256);

  function internalSetRate(uint256 rate) internal virtual;

  function setPaused(bool paused) public override onlyEmergencyAdmin {
    if (_paused != paused) {
      _paused = paused;
      internalPause(paused);
    }
    emit EmergencyPaused(msg.sender, paused);
  }

  function isPaused() public view override returns (bool) {
    return _paused;
  }

  function internalPause(bool paused) internal virtual {
    if (paused) {
      _pausedRate = internalGetRate();
      internalSetRate(0);
      return;
    }
    internalSetRate(_pausedRate);
  }

  function getRewardController() public view override returns (address) {
    return address(_controller);
  }

  function claimRewardFor(address holder, uint256 limit)
    external
    override
    onlyController
    returns (uint256, uint32)
  {
    return internalGetReward(holder, limit);
  }

  function calcRewardFor(address holder, uint32 at)
    external
    view
    override
    returns (uint256, uint32)
  {
    require(at >= uint32(block.timestamp));
    return internalCalcReward(holder, at);
  }

  function internalAllocateReward(
    address holder,
    uint256 allocated,
    uint32 since,
    AllocationMode mode
  ) internal {
    _controller.allocatedByPool(holder, allocated, since, mode);
  }

  function internalGetReward(address holder, uint256 limit)
    internal
    virtual
    returns (uint256, uint32);

  function internalCalcReward(address holder, uint32 at)
    internal
    view
    virtual
    returns (uint256, uint32);

  function attachedToRewardController() external override onlyController {
    internalAttachedToRewardController();
  }

  function internalAttachedToRewardController() internal virtual {}

  function isController(address addr) internal view virtual returns (bool) {
    return address(_controller) == addr;
  }

  function _onlyController() private view {
    require(isController(msg.sender), Errors.CT_CALLER_MUST_BE_REWARD_CONTROLLER);
  }

  modifier onlyController() {
    _onlyController();
    _;
  }

  function _onlyConfigAdmin() private view {
    require(_controller.isConfigAdmin(msg.sender), Errors.CT_CALLER_MUST_BE_REWARD_ADMIN);
  }

  modifier onlyConfigAdmin() {
    _onlyConfigAdmin();
    _;
  }

  function _onlyRateAdmin() private view {
    require(_controller.isRateAdmin(msg.sender), Errors.CT_CALLER_MUST_BE_REWARD_RATE_ADMIN);
  }

  modifier onlyRateAdmin() {
    _onlyRateAdmin();
    _;
  }

  function _onlyEmergencyAdmin() private view {
    require(_controller.isEmergencyAdmin(msg.sender), Errors.CALLER_NOT_EMERGENCY_ADMIN);
  }

  modifier onlyEmergencyAdmin() {
    _onlyEmergencyAdmin();
    _;
  }

  function _onlyRefAdmin() private view {
    require(
      AccessHelper.hasAnyOf(
        _controller.getAccessController(),
        msg.sender,
        AccessFlags.REFERRAL_ADMIN
      ),
      'only referral admin is allowed'
    );
  }

  modifier onlyRefAdmin() {
    _onlyRefAdmin();
    _;
  }

  function _notPaused() private view {
    require(!_paused, Errors.RW_REWARD_PAUSED);
  }

  modifier notPaused() {
    _notPaused();
    _;
  }
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../interfaces/IEmergencyAccess.sol';

interface IManagedRewardPool is IEmergencyAccess {
  function updateBaseline(uint256) external returns (bool hasBaseline, uint256 appliedRate);

  function setBaselinePercentage(uint16) external;

  function getBaselinePercentage() external view returns (bool, uint16);

  function disableBaseline() external;

  function disableRewardPool() external;

  function getRate() external view returns (uint256);

  function setRate(uint256) external;

  function getPoolName() external view returns (string memory);

  function claimRewardFor(address holder, uint256 limit)
    external
    returns (uint256 amount, uint32 since);

  function calcRewardFor(address holder, uint32 at)
    external
    view
    returns (uint256 amount, uint32 since);

  function addRewardProvider(address provider, address token) external;

  function removeRewardProvider(address provider) external;

  function getRewardController() external view returns (address);

  function attachedToRewardController() external;

  event RateUpdated(uint256 rate);
  event BaselineFactorUpdated(uint16);
  event BaselineDisabled();
  event ProviderAdded(address provider, address token);
  event ProviderRemoved(address provider);
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

library AccessFlags {
  // roles that can be assigned to multiple addresses - use range [0..15]
  uint256 public constant EMERGENCY_ADMIN = 1 << 0;
  uint256 public constant POOL_ADMIN = 1 << 1;
  uint256 public constant TREASURY_ADMIN = 1 << 2;
  uint256 public constant REWARD_CONFIG_ADMIN = 1 << 3;
  uint256 public constant REWARD_RATE_ADMIN = 1 << 4;
  uint256 public constant STAKE_ADMIN = 1 << 5;
  uint256 public constant REFERRAL_ADMIN = 1 << 6;
  uint256 public constant LENDING_RATE_ADMIN = 1 << 7;
  uint256 public constant SWEEP_ADMIN = 1 << 8;
  uint256 public constant ORACLE_ADMIN = 1 << 9;

  uint256 public constant ROLES = (uint256(1) << 16) - 1;

  // singletons - use range [16..64] - can ONLY be assigned to a single address
  uint256 public constant SINGLETONS = ((uint256(1) << 64) - 1) & ~ROLES;

  // proxied singletons
  uint256 public constant LENDING_POOL = 1 << 16;
  uint256 public constant LENDING_POOL_CONFIGURATOR = 1 << 17;
  uint256 public constant LIQUIDITY_CONTROLLER = 1 << 18;
  uint256 public constant TREASURY = 1 << 19;
  uint256 public constant REWARD_TOKEN = 1 << 20;
  uint256 public constant REWARD_STAKE_TOKEN = 1 << 21;
  uint256 public constant REWARD_CONTROLLER = 1 << 22;
  uint256 public constant REWARD_CONFIGURATOR = 1 << 23;
  uint256 public constant STAKE_CONFIGURATOR = 1 << 24;
  uint256 public constant REFERRAL_REGISTRY = 1 << 25;

  uint256 public constant PROXIES = ((uint256(1) << 26) - 1) & ~ROLES;

  // non-proxied singletons, numbered down from 31 (as JS has problems with bitmasks over 31 bits)
  uint256 public constant WETH_GATEWAY = 1 << 27;
  uint256 public constant DATA_HELPER = 1 << 28;
  uint256 public constant PRICE_ORACLE = 1 << 29;
  uint256 public constant LENDING_RATE_ORACLE = 1 << 30;

  // any other roles - use range [64..]
  // these roles can be assigned to multiple addresses

  uint256 public constant REWARD_MINT = 1 << 64;
  uint256 public constant REWARD_BURN = 1 << 65;

  uint256 public constant TRUSTED_FLASHLOAN = 1 << 66;
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './interfaces/IRemoteAccessBitmask.sol';

/// @dev Helper/wrapper around IRemoteAccessBitmask
library AccessHelper {
  function getAcl(IRemoteAccessBitmask remote, address subject) internal view returns (uint256) {
    return remote.queryAccessControlMask(subject, ~uint256(0));
  }

  function queryAcl(
    IRemoteAccessBitmask remote,
    address subject,
    uint256 filterMask
  ) internal view returns (uint256) {
    return remote.queryAccessControlMask(subject, filterMask);
  }

  function hasAnyOf(
    IRemoteAccessBitmask remote,
    address subject,
    uint256 flags
  ) internal view returns (bool) {
    uint256 found = queryAcl(remote, subject, flags);
    return found & flags != 0;
  }

  function hasAny(IRemoteAccessBitmask remote, address subject) internal view returns (bool) {
    return remote.queryAccessControlMask(subject, 0) != 0;
  }

  function hasNone(IRemoteAccessBitmask remote, address subject) internal view returns (bool) {
    return remote.queryAccessControlMask(subject, 0) == 0;
  }
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface IEmergencyAccess {
  function setPaused(bool paused) external;

  function isPaused() external view returns (bool);

  event EmergencyPaused(address indexed by, bool paused);
}

{
  "optimizer": {
    "enabled": true,
    "runs": 200
  },
  "evmVersion": "istanbul",
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