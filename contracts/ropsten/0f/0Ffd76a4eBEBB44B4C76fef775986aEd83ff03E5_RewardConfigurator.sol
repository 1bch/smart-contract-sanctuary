// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../tools/upgradeability/VersionedInitializable.sol';

import '../access/interfaces/IMarketAccessController.sol';
import '../access/MarketAccessBitmask.sol';
import '../tools/Errors.sol';
import './interfaces/IRewardConfigurator.sol';
import './interfaces/IRewardController.sol';
import './interfaces/IManagedRewardController.sol';
import './interfaces/IManagedRewardPool.sol';
import './interfaces/IInitializableRewardToken.sol';
import './interfaces/IInitializableRewardPool.sol';
import '../tools/upgradeability/ProxyAdmin.sol';
import '../interfaces/IRewardedToken.sol';
import './pools/TeamRewardPool.sol';
import '../tools/upgradeability/IProxy.sol';

contract RewardConfigurator is
  MarketAccessBitmask(IMarketAccessController(address(0))),
  VersionedInitializable,
  IRewardConfigurator
{
  uint256 private constant CONFIGURATOR_REVISION = 1;

  function getRevision() internal pure virtual override returns (uint256) {
    return CONFIGURATOR_REVISION;
  }

  ProxyAdmin internal immutable _proxies;
  mapping(string => address) _namedPools;

  constructor() {
    _proxies = new ProxyAdmin();
  }

  // This initializer is invoked by AccessController.setAddressAsImpl
  function initialize(address addressesProvider) external initializer(CONFIGURATOR_REVISION) {
    _remoteAcl = IMarketAccessController(addressesProvider);
  }

  function getDefaultController() public view returns (IManagedRewardController) {
    address ctl = _remoteAcl.getAddress(AccessFlags.REWARD_CONTROLLER);
    require(ctl != address(0), 'incomplete configuration');
    return IManagedRewardController(ctl);
  }

  function list() public view returns (address[] memory pools) {
    uint256 ignoreMask;
    (pools, ignoreMask) = IUntypedRewardControllerPools(address(getDefaultController())).getPools();

    for (uint256 i = 0; ignoreMask > 0 && i < pools.length; i++) {
      if (ignoreMask & 1 != 0) {
        pools[i] = address(0);
      }
      ignoreMask >>= 1;
    }
    return pools;
  }

  function batchInitRewardPools(PoolInitData[] calldata entries) external onlyRewardAdmin {
    IManagedRewardController ctl = getDefaultController();

    for (uint256 i = 0; i < entries.length; i++) {
      PoolInitData calldata entry = entries[i];

      IInitializableRewardPool.InitData memory params =
        IInitializableRewardPool.InitData(
          ctl,
          entry.poolName,
          entry.initialRate,
          entry.baselinePercentage
        );

      address pool =
        address(
          _remoteAcl.createProxy(
            address(_proxies),
            entry.impl,
            abi.encodeWithSelector(IInitializableRewardPool.initialize.selector, params)
          )
        );

      ctl.addRewardPool(IManagedRewardPool(pool));

      if (entry.boostFactor > 0) {
        IManagedRewardBooster(address(ctl)).setBoostFactor(pool, entry.boostFactor);
      }
      if (entry.provider != address(0)) {
        IManagedRewardPool(pool).addRewardProvider(entry.provider, entry.provider);
        IRewardedToken(entry.provider).setIncentivesController(pool);
      }

      emit RewardPoolInitialized(pool, entry.provider, entry);
    }
  }

  function addNamedRewardPools(
    IManagedRewardPool[] calldata pools,
    string[] calldata names,
    uint32[] calldata boostFactors
  ) external onlyRewardAdmin {
    require(pools.length >= names.length);
    require(pools.length >= boostFactors.length);

    IManagedRewardController ctl = getDefaultController();

    for (uint256 i = 0; i < names.length; i++) {
      IManagedRewardPool pool = pools[i];
      if (pool != IManagedRewardPool(address(0))) {
        ctl.addRewardPool(pool);
      }
      if (i < names.length && bytes(names[i]).length > 0) {
        _namedPools[names[i]] = address(pool);
      }
      if (i < boostFactors.length && boostFactors[i] > 0) {
        IManagedRewardBooster(address(ctl)).setBoostFactor(address(pool), boostFactors[i]);
      }
    }
  }

  function getNamedRewardPools(string[] calldata names)
    external
    view
    returns (address[] memory pools)
  {
    pools = new address[](names.length);
    for (uint256 i = 0; i < names.length; i++) {
      pools[i] = _namedPools[names[i]];
    }
    return pools;
  }

  function implementationOf(address token) external view returns (address) {
    return _proxies.getProxyImplementation(IProxy(token));
  }

  function updateRewardPool(PoolUpdateData calldata input) external onlyRewardAdmin {
    IInitializableRewardPool.InitData memory params =
      IInitializableRewardPool(input.pool).initializedWith();
    _proxies.upgradeAndCall(
      IProxy(input.pool),
      input.impl,
      abi.encodeWithSelector(IInitializableRewardPool.initialize.selector, params)
    );
    emit RewardPoolUpgraded(input.pool, input.impl);
  }

  function buildRewardPoolInitData(
    string calldata poolName,
    uint256 initialRate,
    uint16 baselinePercentage
  ) external view returns (bytes memory) {
    IInitializableRewardPool.InitData memory data =
      IInitializableRewardPool.InitData(
        getDefaultController(),
        poolName,
        initialRate,
        baselinePercentage
      );
    return abi.encodeWithSelector(IInitializableRewardPool.initialize.selector, data);
  }

  function buildRewardTokenInitData(
    string calldata name,
    string calldata symbol,
    uint8 decimals
  ) external view returns (bytes memory) {
    IInitializableRewardToken.InitData memory data =
      IInitializableRewardToken.InitData(_remoteAcl, name, symbol, decimals);
    return abi.encodeWithSelector(IInitializableRewardToken.initialize.selector, data);
  }

  function configureRewardBoost(
    IManagedRewardPool boostPool,
    bool updateRate,
    address excessTarget,
    bool mintExcess
  ) external onlyRewardAdmin {
    IManagedRewardBooster booster = IManagedRewardBooster(address(getDefaultController()));

    booster.setUpdateBoostPoolRate(updateRate);
    booster.addRewardPool(boostPool);
    booster.setBoostPool(address(boostPool));
    booster.setBoostExcessTarget(excessTarget, mintExcess);
  }

  function configureTeamRewardPool(
    TeamRewardPool pool,
    string calldata name,
    uint32 unlockedAt,
    address[] calldata members,
    uint16[] calldata memberShares
  ) external onlyRewardAdmin {
    IManagedRewardController ctl = getDefaultController();
    ctl.addRewardPool(pool);
    _namedPools[name] = address(pool);

    if (unlockedAt > 0) {
      pool.setUnlockedAt(unlockedAt);
    }
    if (members.length > 0) {
      pool.updateTeamMembers(members, memberShares);
    }
  }

  function setRates(IManagedRewardPool[] calldata pools, uint256[] calldata rates)
    external
    onlyRewardRateAdmin
  {
    require(pools.length == rates.length);

    for (uint256 i = 0; i < pools.length; i++) {
      pools[i].setRate(rates[i]);
    }
  }

  function setBaselinePercentages(IManagedRewardPool[] calldata pools, uint16[] calldata pcts)
    external
    onlyRewardRateAdmin
  {
    require(pools.length == pcts.length);

    for (uint256 i = 0; i < pools.length; i++) {
      pools[i].setBaselinePercentage(pcts[i]);
    }
  }

  function getPoolTotals(bool excludeBoost)
    external
    view
    returns (
      uint256 totalBaselinePercentage,
      uint256 totalRate,
      uint256 activePoolCount,
      uint256 poolCount,
      uint256 listCount
    )
  {
    IManagedRewardController ctl = getDefaultController();
    (IManagedRewardPool[] memory pools, uint256 ignoreMask) = ctl.getPools();

    listCount = pools.length;

    if (excludeBoost) {
      (, uint256 mask) = IManagedRewardBooster(address(ctl)).getBoostPool();
      if (mask != 0) {
        poolCount++;
        ignoreMask |= mask;
      }
    }

    for (uint256 i = 0; i < pools.length; i++) {
      if (ignoreMask & 1 == 0 && pools[i] != IManagedRewardPool(address(0))) {
        activePoolCount++;
        (bool ok, uint16 pct) = pools[i].getBaselinePercentage();
        if (ok) {
          totalBaselinePercentage += uint256(pct);
        }
        totalRate += pools[i].getRate();
      }
      ignoreMask >>= 1;
    }
    poolCount += activePoolCount;
  }
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

/**
 * @title VersionedInitializable
 *
 * @dev Helper contract to implement versioned initializer functions. To use it, replace
 * the constructor with a function that has the `initializer` or `initializerRunAlways` modifier.
 * The revision number should be defined as a private constant, returned by getRevision() and used by initializer() modifier.
 *
 * ATTN: There is a built-in protection from implementation self-destruct exploits. This protection
 * prevents initializers from being called on an implementation inself, but only on proxied contracts.
 * To override this protection, call _unsafeResetVersionedInitializers() from a constructor.
 *
 * WARNING: Unlike constructors, initializer functions must be manually
 * invoked. This applies both to deploying an initializable contract, as well
 * as extending an initializable contract via inheritance.
 *
 * ATTN: When used with inheritance, parent initializers with `initializer` modifier are prevented by calling twice,
 * but can only be called in child-to-parent sequence.
 *
 * WARNING: When used with inheritance, parent initializers with `initializerRunAlways` modifier
 * are NOT protected from multiple calls by another initializer.
 */
abstract contract VersionedInitializable {
  uint256 private constant BLOCK_REVISION = type(uint256).max;
  // This revision number is applied to implementations
  uint256 private constant IMPL_REVISION = BLOCK_REVISION - 1;

  /// @dev Indicates that the contract has been initialized. The default value blocks initializers from being called on an implementation.
  uint256 private lastInitializedRevision = IMPL_REVISION;

  /// @dev Indicates that the contract is in the process of being initialized.
  uint256 private lastInitializingRevision = 0;

  /**
   * @dev There is a built-in protection from self-destruct of implementation exploits. This protection
   * prevents initializers from being called on an implementation inself, but only on proxied contracts.
   * Function _unsafeResetVersionedInitializers() can be called from a constructor to disable this protection.
   * It must be called before any initializers, otherwise it will fail.
   */
  function _unsafeResetVersionedInitializers() internal {
    require(isConstructor(), 'only for constructor');

    if (lastInitializedRevision == IMPL_REVISION) {
      lastInitializedRevision = 0;
    } else {
      require(lastInitializedRevision == 0, 'can only be called before initializer(s)');
    }
  }

  /// @dev Modifier to use in the initializer function of a contract.
  modifier initializer(uint256 localRevision) {
    (uint256 topRevision, bool initializing, bool skip) = _preInitializer(localRevision);

    if (!skip) {
      lastInitializingRevision = localRevision;
      _;
      lastInitializedRevision = localRevision;
    }

    if (!initializing) {
      lastInitializedRevision = topRevision;
      lastInitializingRevision = 0;
    }
  }

  modifier initializerRunAlways(uint256 localRevision) {
    (uint256 topRevision, bool initializing, bool skip) = _preInitializer(localRevision);

    if (!skip) {
      lastInitializingRevision = localRevision;
    }
    _;
    if (!skip) {
      lastInitializedRevision = localRevision;
    }

    if (!initializing) {
      lastInitializedRevision = topRevision;
      lastInitializingRevision = 0;
    }
  }

  function _preInitializer(uint256 localRevision)
    private
    returns (
      uint256 topRevision,
      bool initializing,
      bool skip
    )
  {
    topRevision = getRevision();
    require(topRevision < IMPL_REVISION, 'invalid contract revision');

    require(localRevision > 0, 'incorrect initializer revision');
    require(localRevision <= topRevision, 'inconsistent contract revision');

    if (lastInitializedRevision < IMPL_REVISION) {
      // normal initialization
      initializing = lastInitializingRevision > 0 && lastInitializedRevision < topRevision;
      require(
        initializing || isConstructor() || topRevision > lastInitializedRevision,
        'already initialized'
      );
    } else {
      // by default, initialization of implementation is only allowed inside a constructor
      require(lastInitializedRevision == IMPL_REVISION && isConstructor(), 'initializer blocked');

      // enable normal use of initializers inside a constructor
      lastInitializedRevision = 0;
      // but make sure to block initializers afterwards
      topRevision = BLOCK_REVISION;

      initializing = lastInitializingRevision > 0;
    }

    if (initializing) {
      require(lastInitializingRevision > localRevision, 'incorrect order of initializers');
    }

    if (localRevision <= lastInitializedRevision) {
      // prevent calling of parent's initializer when it was called before
      if (initializing) {
        // Can't set zero yet, as it is not a top-level call, otherwise `initializing` will become false.
        // Further calls will fail with the `incorrect order` assertion above.
        lastInitializingRevision = 1;
      }
      return (topRevision, initializing, true);
    }
    return (topRevision, initializing, false);
  }

  function isRevisionInitialized(uint256 localRevision) internal view returns (bool) {
    return lastInitializedRevision >= localRevision;
  }

  function REVISION() public pure returns (uint256) {
    return getRevision();
  }

  /**
   * @dev returns the revision number (< type(uint256).max - 1) of the contract.
   * The number should be defined as a private constant.
   **/
  function getRevision() internal pure virtual returns (uint256);

  /// @dev Returns true if and only if the function is running in the constructor
  function isConstructor() private view returns (bool) {
    uint256 cs;
    //solium-disable-next-line
    assembly {
      cs := extcodesize(address())
    }
    return cs == 0;
  }

  // Reserved storage space to allow for layout changes in the future.
  uint256[4] private ______gap;
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

import '../tools/Errors.sol';
import './interfaces/IMarketAccessController.sol';
import './AccessHelper.sol';
import './AccessFlags.sol';

abstract contract MarketAccessBitmask {
  using AccessHelper for IMarketAccessController;
  IMarketAccessController internal _remoteAcl;

  constructor(IMarketAccessController remoteAcl) {
    _remoteAcl = remoteAcl;
  }

  function _getRemoteAcl(address addr) internal view returns (uint256) {
    return _remoteAcl.getAcl(addr);
  }

  function hasRemoteAcl() internal view returns (bool) {
    return _remoteAcl != IMarketAccessController(address(0));
  }

  function acl_hasAnyOf(address subject, uint256 flags) internal view returns (bool) {
    return _remoteAcl.hasAnyOf(subject, flags);
  }

  function acl_requireAnyOf(
    address subject,
    uint256 flags,
    string memory text
  ) internal view {
    require(_remoteAcl.hasAnyOf(subject, flags), text);
  }

  modifier aclHas(uint256 flags) virtual {
    acl_requireAnyOf(msg.sender, flags, Errors.TXT_ACCESS_RESTRICTED);
    _;
  }

  modifier aclAnyOf(uint256 flags) {
    acl_requireAnyOf(msg.sender, flags, Errors.TXT_ACCESS_RESTRICTED);
    _;
  }

  modifier onlyPoolAdmin {
    acl_requireAnyOf(msg.sender, AccessFlags.POOL_ADMIN, Errors.CALLER_NOT_POOL_ADMIN);
    _;
  }

  modifier onlyEmergencyAdmin {
    acl_requireAnyOf(msg.sender, AccessFlags.EMERGENCY_ADMIN, Errors.CALLER_NOT_EMERGENCY_ADMIN);
    _;
  }

  modifier onlySweepAdmin {
    acl_requireAnyOf(msg.sender, AccessFlags.SWEEP_ADMIN, Errors.CT_CALLER_MUST_BE_SWEEP_ADMIN);
    _;
  }

  modifier onlyRewardAdmin {
    acl_requireAnyOf(
      msg.sender,
      AccessFlags.REWARD_CONFIG_ADMIN,
      Errors.CT_CALLER_MUST_BE_REWARD_ADMIN
    );
    _;
  }

  modifier onlyRewardConfiguratorOrAdmin {
    acl_requireAnyOf(
      msg.sender,
      AccessFlags.REWARD_CONFIG_ADMIN | AccessFlags.REWARD_CONFIGURATOR,
      Errors.CT_CALLER_MUST_BE_REWARD_ADMIN
    );
    _;
  }

  modifier onlyRewardRateAdmin {
    acl_requireAnyOf(
      msg.sender,
      AccessFlags.REWARD_RATE_ADMIN,
      Errors.CT_CALLER_MUST_BE_REWARD_RATE_ADMIN
    );
    _;
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

interface IRewardConfigurator {
  struct PoolInitData {
    address provider;
    address impl;
    string poolName;
    uint256 initialRate;
    uint32 boostFactor;
    uint16 baselinePercentage;
  }

  struct PoolUpdateData {
    address pool;
    address impl;
  }

  event RewardPoolInitialized(address indexed pool, address indexed provider, PoolInitData data);

  event RewardPoolUpgraded(address indexed pool, address impl);
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

import '../../interfaces/IRewardMinter.sol';
import '../../interfaces/IEmergencyAccess.sol';
import '../../access/interfaces/IMarketAccessController.sol';
import './IManagedRewardPool.sol';
import './IRewardController.sol';

interface IManagedRewardController is IEmergencyAccess, IRewardController {
  function updateBaseline(uint256 baseline) external returns (uint256 totalRate);

  function addRewardPool(IManagedRewardPool) external;

  function removeRewardPool(IManagedRewardPool) external;

  function setRewardMinter(IRewardMinter) external;

  function getPools() external view returns (IManagedRewardPool[] memory, uint256 ignoreMask);

  event RewardsAllocated(address indexed user, uint256 amount, address indexed fromPool);
  event RewardsClaimed(address indexed user, address indexed to, uint256 amount);

  event BaselineUpdated(uint256 baseline, uint256 totalRate, uint256 mask);
  event RewardPoolAdded(address indexed pool, uint256 mask);
  event RewardPoolRemoved(address indexed pool, uint256 mask);
  event RewardMinterSet(address minter);
}

interface IManagedRewardBooster is IManagedRewardController {
  function setBoostFactor(address pool, uint32 pctFactor) external;

  function setUpdateBoostPoolRate(bool) external;

  function setBoostPool(address) external;

  function getBoostPool() external view returns (address pool, uint256 mask);

  function setBoostExcessTarget(address target, bool mintExcess) external;

  event BoostFactorSet(address indexed pool, uint256 mask, uint32 pctFactor);
}

interface IUntypedRewardControllerPools {
  function getPools() external view returns (address[] memory, uint256 ignoreMask);
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

import '../../access/interfaces/IMarketAccessController.sol';

interface IInitializableRewardToken {
  struct InitData {
    IMarketAccessController remoteAcl;
    string name;
    string symbol;
    uint8 decimals;
  }

  function initialize(InitData memory) external;
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IRewardController.sol';

interface IInitializableRewardPool {
  struct InitData {
    IRewardController controller;
    string poolName;
    uint256 initialRate;
    uint16 baselinePercentage;
  }

  function initialize(InitData calldata) external;

  function initializedWith() external view returns (InitData memory);
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IProxy.sol';
import './ProxyAdminBase.sol';
import '../Errors.sol';

/// @dev This contract meant to be assigned as the admin of a {IProxy}. Adopted from the OpenZeppelin
contract ProxyAdmin is ProxyAdminBase {
  address private immutable _owner;

  constructor() {
    _owner = msg.sender;
  }

  /// @dev Returns the address of the current owner.
  function owner() public view returns (address) {
    return _owner;
  }

  /// @dev Throws if called by any account other than the owner.
  modifier onlyOwner() {
    require(_owner == msg.sender, Errors.TXT_CALLER_NOT_PROXY_OWNER);
    _;
  }

  /// @dev Returns the current implementation of `proxy`.
  function getProxyImplementation(IProxy proxy) public view virtual returns (address) {
    return _getProxyImplementation(proxy);
  }

  /// @dev Upgrades `proxy` to `implementation` and calls a function on the new implementation.
  function upgradeAndCall(
    IProxy proxy,
    address implementation,
    bytes memory data
  ) public payable virtual onlyOwner {
    proxy.upgradeToAndCall{value: msg.value}(implementation, data);
  }
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface IRewardedToken {
  function setIncentivesController(address) external;

  function getIncentivesController() external view returns (address);
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import '../../tools/math/PercentageMath.sol';
import '../../tools/Errors.sol';
import '../interfaces/IRewardController.sol';
import '../calcs/CalcLinearUnweightedReward.sol';
import './ControlledRewardPool.sol';

contract TeamRewardPool is ControlledRewardPool, CalcLinearUnweightedReward {
  using PercentageMath for uint256;

  address private _teamManager;
  uint32 private _lockupTill;
  uint16 private _totalShare;

  constructor(
    IRewardController controller,
    uint256 initialRate,
    uint16 baselinePercentage,
    address teamManager
  ) ControlledRewardPool(controller, initialRate, baselinePercentage) {
    _teamManager = teamManager;
  }

  function _onlyTeamManagerOrConfigurator() private view {
    require(
      msg.sender == _teamManager || _controller.isConfigAdmin(msg.sender),
      Errors.CT_CALLER_MUST_BE_TEAM_MANAGER
    );
  }

  function getPoolName() public pure override returns (string memory) {
    return 'TeamPool';
  }

  modifier onlyTeamManagerOrConfigurator {
    _onlyTeamManagerOrConfigurator();
    _;
  }

  function internalGetRate() internal view override returns (uint256) {
    return super.getLinearRate();
  }

  function internalSetRate(uint256 newRate) internal override {
    super.setLinearRate(newRate);
  }

  function internalGetReward(address holder, uint256) internal override returns (uint256, uint32) {
    if (!isUnlocked(getCurrentTick())) {
      return (0, 0);
    }
    return doGetReward(holder);
  }

  function internalCalcReward(address holder, uint32 at)
    internal
    view
    override
    returns (uint256, uint32)
  {
    if (!isUnlocked(at)) {
      return (0, 0);
    }
    return doCalcRewardAt(holder, at);
  }

  function internalCalcRateAndReward(
    RewardEntry memory entry,
    uint256 lastAccumRate,
    uint32 currentBlock
  )
    internal
    view
    override
    returns (
      uint256 rate,
      uint256 allocated,
      uint32 since
    )
  {
    (rate, allocated, since) = super.internalCalcRateAndReward(entry, lastAccumRate, currentBlock);
    allocated = (allocated + PercentageMath.HALF_ONE) / PercentageMath.ONE;
    return (rate, allocated, since);
  }

  function addRewardProvider(address, address) external view override onlyConfigAdmin {
    revert('UNSUPPORTED');
  }

  function removeRewardProvider(address) external override onlyConfigAdmin {}

  function getAllocatedShares() external view returns (uint16) {
    return _totalShare;
  }

  function isUnlocked(uint32 at) public view returns (bool) {
    return _lockupTill > 0 && _lockupTill < at;
  }

  function updateTeamMembers(address[] calldata members, uint16[] calldata memberSharePct)
    external
    onlyTeamManagerOrConfigurator
  {
    require(members.length == memberSharePct.length);
    for (uint256 i = 0; i < members.length; i++) {
      _updateTeamMember(members[i], memberSharePct[i]);
    }
  }

  function updateTeamMember(address member, uint16 memberSharePct)
    external
    onlyTeamManagerOrConfigurator
  {
    _updateTeamMember(member, memberSharePct);
  }

  function _updateTeamMember(address member, uint16 memberSharePct) private {
    require(member != address(0), 'member is required');
    require(memberSharePct <= PercentageMath.ONE, 'invalid share percentage');

    uint256 oldSharePct = getRewardEntry(member).rewardBase;
    uint256 newTotalShare = uint256(_totalShare) + memberSharePct - oldSharePct;
    require(newTotalShare <= PercentageMath.ONE, 'team total share exceeds 100%');
    _totalShare = uint16(newTotalShare);

    (uint256 allocated, uint32 since, AllocationMode mode) =
      doUpdateReward(member, oldSharePct, memberSharePct);

    require(
      allocated == 0 || isUnlocked(getCurrentTick()),
      'member share can not be changed during lockup'
    );

    internalAllocateReward(member, allocated, since, mode);
  }

  function removeTeamMember(address member) external onlyTeamManagerOrConfigurator {
    require(member != address(0), 'member is required');

    uint256 lastShare = internalRemoveReward(member);
    if (lastShare < _totalShare) {
      _totalShare -= uint16(lastShare);
    } else {
      _totalShare = 0;
    }
    internalAllocateReward(member, 0, 0, AllocationMode.UnsetPull);
  }

  function setTeamManager(address member) external onlyTeamManagerOrConfigurator {
    _teamManager = member;
  }

  function getTeamManager() external view returns (address) {
    return _teamManager;
  }

  function setUnlockedAt(uint32 at) external onlyConfigAdmin {
    require(at > 0, 'unlockAt is required');
    require(_lockupTill == 0 || _lockupTill >= getCurrentTick(), 'lockup is finished');
    _lockupTill = at;
  }

  function getUnlockedAt() external view returns (uint32) {
    return _lockupTill;
  }

  function getCurrentTick() internal view override returns (uint32) {
    return uint32(block.timestamp);
  }
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface IProxy {
  function upgradeToAndCall(address newImplementation, bytes calldata data) external payable;
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

interface IRewardMinter {
  /// @dev mints a reward
  function mintReward(
    address holder,
    uint256 amount,
    bool serviceAccount
  ) external;
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

interface IEmergencyAccess {
  function setPaused(bool paused) external;

  function isPaused() external view returns (bool);

  event EmergencyPaused(address indexed by, bool paused);
}

// SPDX-License-Identifier: agpl-3.0
pragma solidity ^0.8.4;

import './IProxy.sol';

abstract contract ProxyAdminBase {
  /// @dev Returns the current implementation of an owned `proxy`.
  function _getProxyImplementation(IProxy proxy) internal view returns (address) {
    // We need to manually run the static call since the getter cannot be flagged as view
    // bytes4(keccak256('implementation()')) == 0x5c60da1b
    (bool success, bytes memory returndata) = address(proxy).staticcall(hex'5c60da1b');
    require(success);
    return abi.decode(returndata, (address));
  }
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

import './CalcLinearRateReward.sol';

abstract contract CalcLinearUnweightedReward is CalcLinearRateReward {
  uint256 private _accumRate;

  function internalRateUpdated(
    uint256 lastRate,
    uint32 lastAt,
    uint32 at
  ) internal override {
    _accumRate += lastRate * (at - lastAt);
  }

  function internalCalcRateAndReward(
    RewardEntry memory entry,
    uint256 lastAccumRate,
    uint32 at
  )
    internal
    view
    virtual
    override
    returns (
      uint256 adjRate,
      uint256 allocated,
      uint32 since
    )
  {
    (uint256 rate, uint32 updatedAt) = getRateAndUpdatedAt();

    adjRate = _accumRate + (rate * (at - updatedAt));
    allocated = uint256(entry.rewardBase) * (adjRate - lastAccumRate);

    return (adjRate, allocated, entry.claimedAt);
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

import '../interfaces/IRewardController.sol';

abstract contract CalcLinearRateReward {
  mapping(address => RewardEntry) private _rewards;
  uint256 private _rate;
  uint32 private _rateUpdatedAt;

  mapping(address => uint256) private _accumRates;

  struct RewardEntry {
    uint224 rewardBase;
    uint32 claimedAt;
  }

  function setLinearRate(uint256 rate) internal {
    setLinearRateAt(rate, getCurrentTick());
  }

  function setLinearRateAt(uint256 rate, uint32 at) internal {
    if (_rate == rate) {
      return;
    }

    uint32 prevTick = _rateUpdatedAt;
    if (at != prevTick) {
      uint256 prevRate = _rate;
      internalMarkRateUpdate(at);
      _rate = rate;
      internalRateUpdated(prevRate, prevTick, at);
    }
  }

  function doSyncRateAt(uint32 at) internal {
    uint32 prevTick = _rateUpdatedAt;
    if (at != prevTick) {
      internalMarkRateUpdate(at);
      internalRateUpdated(_rate, prevTick, at);
    }
  }

  function getCurrentTick() internal view virtual returns (uint32);

  function internalRateUpdated(
    uint256 lastRate,
    uint32 lastAt,
    uint32 at
  ) internal virtual;

  function internalMarkRateUpdate(uint32 currentTick) internal {
    require(currentTick >= _rateUpdatedAt, 'retroactive update');
    _rateUpdatedAt = currentTick;
  }

  function getLinearRate() internal view virtual returns (uint256) {
    return _rate;
  }

  function getRateAndUpdatedAt() internal view virtual returns (uint256, uint32) {
    return (_rate, _rateUpdatedAt);
  }

  function getRateUpdatedAt() internal view returns (uint32) {
    return _rateUpdatedAt;
  }

  function internalCalcRateAndReward(
    RewardEntry memory entry,
    uint256 lastAccumRate,
    uint32 currentTick
  )
    internal
    view
    virtual
    returns (
      uint256 rate,
      uint256 allocated,
      uint32 since
    );

  function getRewardEntry(address holder) internal view returns (RewardEntry memory) {
    return _rewards[holder];
  }

  function doUpdateReward(
    address holder,
    uint256 oldBalance,
    uint256 newBalance
  )
    internal
    virtual
    returns (
      uint256 allocated,
      uint32 since,
      AllocationMode mode
    )
  {
    require(newBalance <= type(uint224).max, 'balance is too high');

    RewardEntry memory entry = _rewards[holder];

    if (newBalance == 0) {
      mode = AllocationMode.UnsetPull;
    } else if (entry.claimedAt == 0) {
      mode = AllocationMode.SetPull;
    } else {
      mode = AllocationMode.Push;
    }

    newBalance = internalCalcBalance(entry, oldBalance, newBalance);
    require(newBalance <= type(uint224).max, 'balance is too high');

    uint32 currentTick = getCurrentTick();

    uint256 adjRate;
    (adjRate, allocated, since) = internalCalcRateAndReward(
      entry,
      _accumRates[holder],
      currentTick
    );

    _accumRates[holder] = adjRate;
    _rewards[holder] = RewardEntry(uint224(newBalance), currentTick);
    return (allocated, since, mode);
  }

  function internalCalcBalance(
    RewardEntry memory entry,
    uint256 oldBalance,
    uint256 newBalance
  ) internal pure virtual returns (uint256) {
    entry;
    oldBalance;
    return newBalance;
  }

  function internalRemoveReward(address holder) internal virtual returns (uint256 rewardBase) {
    rewardBase = _rewards[holder].rewardBase;
    if (rewardBase == 0 && _rewards[holder].claimedAt == 0) {
      return 0;
    }
    delete (_rewards[holder]);
    return rewardBase;
  }

  function doGetReward(address holder) internal virtual returns (uint256, uint32) {
    return doGetRewardAt(holder, getCurrentTick());
  }

  function doGetRewardAt(address holder, uint32 currentTick)
    internal
    virtual
    returns (uint256, uint32)
  {
    if (_rewards[holder].rewardBase == 0) {
      return (0, 0);
    }

    (uint256 adjRate, uint256 allocated, uint32 since) =
      internalCalcRateAndReward(_rewards[holder], _accumRates[holder], currentTick);

    _accumRates[holder] = adjRate;
    _rewards[holder].claimedAt = currentTick;
    return (allocated, since);
  }

  function doCalcReward(address holder) internal view virtual returns (uint256, uint32) {
    return doCalcRewardAt(holder, getCurrentTick());
  }

  function doCalcRewardAt(address holder, uint32 currentTick)
    internal
    view
    virtual
    returns (uint256, uint32)
  {
    if (_rewards[holder].rewardBase == 0) {
      return (0, 0);
    }

    (, uint256 allocated, uint32 since) =
      internalCalcRateAndReward(_rewards[holder], _accumRates[holder], currentTick);
    return (allocated, since);
  }
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