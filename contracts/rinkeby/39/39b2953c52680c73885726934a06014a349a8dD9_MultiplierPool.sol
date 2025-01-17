// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/utils/Pausable.sol";
import "synthetix/contracts/interfaces/IStakingRewards.sol";

import "../interfaces/multiplier/IMultiStake.sol";

import "./MultiplierMath.sol";
import "./FundablePool.sol";

/**
 * @title Multiplier Pool for Float Protocol
 * @dev The Multiplier Pool provides `rewardTokens` for `stakeTokens` with a
 * token-over-time distribution, with the function being equal to their
 * "stake-seconds" divided by the global "stake-seconds".
 * This is designed to align token distribution with long term stakers.
 * The longer the hold, the higher the proportion of the pool; and the higher
 * the multiplier.
 *
 * THIS DOES NOT WORK WITH FEE TOKENS / REBASING TOKENS - Use Token Geyser V2 instead.
 *
 * This contract was only possible due to a number of existing
 * open-source contracts including:
 * - The original [Synthetix rewards contract](https://etherscan.io/address/0xDCB6A51eA3CA5d3Fd898Fd6564757c7aAeC3ca92#code) developed by k06a
 * - Ampleforth's Token Geyser [V1](https://github.com/ampleforth/token-geyser) and [V2](https://github.com/ampleforth/token-geyser-v2)
 * - [GYSR.io Token Geyser](https://github.com/gysr-io/core)
 * - [Alchemist's Aludel](https://github.com/alchemistcoin/alchemist/tree/main/contracts/aludel)
 */
contract MultiplierPool is
  IMultiStake,
  AccessControl,
  MultiplierMath,
  FundablePool
{
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  /* ========== CONSTANTS ========== */
  bytes32 public constant RECOVER_ROLE = keccak256("RECOVER_ROLE");
  bytes32 public constant ADJUSTER_ROLE = keccak256("ADJUSTER_ROLE");

  /* ========== STATE VARIABLES ========== */
  IERC20 public immutable stakeToken;

  IBonusScaling.BonusScaling public bonusScaling;

  uint256 public hardLockPeriod;

  uint256 public lastUpdateTime;

  /// @dev {cached} total staked
  uint256 internal _totalStaked;

  /// @dev {cached} total staked seconds
  uint256 internal _totalStakeSeconds;

  struct UserData {
    // [eD] {cached} total stake from individual stakes
    uint256 totalStake;
    Stake[] stakes;
  }

  mapping(address => UserData) internal _users;

  /* ========== CONSTRUCTOR ========== */

  /**
   * @notice Construct a new MultiplierPool
   * @param _admin The default role controller
   * @param _funder The reward distributor
   * @param _rewardToken The reward token to distribute
   * @param _stakingToken The staking token used to qualify for rewards
   * @param _bonusScaling The starting bonus scaling amount
   * @param _hardLockPeriod The period for a hard lock to apply (no unstake)
   */
  constructor(
    address _admin,
    address _funder,
    address _rewardToken,
    address _stakingToken,
    IBonusScaling.BonusScaling memory _bonusScaling,
    uint256 _hardLockPeriod
  ) FundablePool(_funder, _rewardToken) {
    stakeToken = IERC20(_stakingToken);
    bonusScaling = _bonusScaling;
    hardLockPeriod = _hardLockPeriod;

    _setupRole(DEFAULT_ADMIN_ROLE, _admin);
    _setupRole(ADJUSTER_ROLE, _admin);
    _setupRole(RECOVER_ROLE, _admin);
  }

  /* ========== EVENTS ========== */

  event Staked(address indexed user, uint256 amount);
  event Withdrawn(address indexed user, uint256 amount);
  event Recovered(address token, uint256 amount);

  /* ========== VIEWS ========== */

  /**
   * @notice The total reward producing staked supply (total quantity to distribute)
   */
  function totalSupply() public view virtual returns (uint256) {
    return _totalStaked;
  }

  function getUserData(address user)
    external
    view
    returns (UserData memory userData)
  {
    return _users[user];
  }

  function getFutureTotalStakeSeconds(uint256 timestamp)
    public
    view
    returns (uint256 totalStakeSeconds)
  {
    totalStakeSeconds = calculateTotalStakeSeconds(
      _totalStaked,
      _totalStakeSeconds,
      lastUpdateTime,
      timestamp
    );
  }

  /**
   * @notice The total staked balance of the staker.
   */
  function balanceOf(address staker) public view virtual returns (uint256) {
    return _users[staker].totalStake;
  }

  function earned(address staker) public view virtual returns (uint256) {
    UnstakeOutput memory out =
      simulateUnstake(
        _users[staker].stakes,
        balanceOf(staker),
        getFutureTotalStakeSeconds(block.timestamp),
        unlockedRewardAmount(),
        block.timestamp,
        bonusScaling
      );
    return out.rewardDue;
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /**
   * @notice Stakes `amount` tokens from `msg.sender`
   *
   * Emits a {Staked} event.
   * Can emit a {RewardsUnlocked} event if additional rewards are now available.
   */
  function stake(uint256 amount) external virtual {
    _update();
    _stakeFor(msg.sender, msg.sender, amount);
  }

  /**
   * @notice Stakes `amount` tokens from `msg.sender` on behalf of `staker`
   *
   * Emits a {Staked} event.
   * Can emit a {RewardsUnlocked} event if additional rewards are now available.
   */
  function stakeFor(address staker, uint256 amount) external virtual {
    _update();
    _stakeFor(msg.sender, staker, amount);
  }

  /**
   * @notice Withdraw an `amount` from the pool including any rewards due for that stake
   *
   * Emits a {Withdrawn} event.
   * Can emit a {RewardsPaid} event if due rewards.
   * Can emit a {RewardsUnlocked} event if additional rewards are now available.
   */
  function withdraw(uint256 amount) external virtual {
    _update();
    _unstake(msg.sender, amount);
  }

  /**
   * @notice Exit the pool, taking any rewards due and any staked tokens
   *
   * Emits a {Withdrawn} event.
   * Can emit a {RewardsPaid} event if due rewards.
   * Can emit a {RewardsUnlocked} event if additional rewards are now available.
   */
  function exit() external virtual {
    _update();
    _unstake(msg.sender, balanceOf(msg.sender));
  }

  /**
   * @notice Retrieve any rewards due to `msg.sender`
   *
   * Can emit a {RewardsPaid} event if due rewards.
   * Can emit a {RewardsUnlocked} event if additional rewards are now available.
   *
   * Requirements:
   * - `msg.sender` must have some tokens staked
   */
  function getReward() external virtual {
    _update();
    address staker = msg.sender;
    uint256 totalStake = balanceOf(staker);
    uint256 reward = _unstakeAccounting(staker, totalStake);
    _stakeAccounting(staker, totalStake);

    if (reward != 0) {
      _distributeRewards(staker, reward);
    }
  }

  /**
   * @dev Stakes `amount` tokens from `payer` to `staker`, increasing the total supply.
   *
   * Emits a {Staked} event.
   *
   * Requirements:
   * - `staker` cannot be zero address.
   * - `payer` must have at least `amount` tokens
   * - `payer` must approve this contract for at least `amount`
   */
  function _stakeFor(
    address payer,
    address staker,
    uint256 amount
  ) internal virtual {
    require(staker != address(0), "MultiplierPool/ZeroAddressS");
    require(amount != 0, "MultiplierPool/NoAmount");

    _beforeStake(payer, staker, amount);

    _stakeAccounting(staker, amount);

    emit Staked(staker, amount);
    stakeToken.safeTransferFrom(payer, address(this), amount);
  }

  /**
   * @dev Withdraws `amount` tokens from `staker`, reducing the total supply.
   *
   * Emits a {Withdrawn} event.
   *
   * Requirements:
   * - `staker` cannot be zero address.
   * - `staker` must have at least `amount` staked.
   */
  function _unstake(address staker, uint256 amount) internal virtual {
    // Sense check input
    require(staker != address(0), "MultiplierPool/ZeroAddressW");
    require(amount != 0, "MultiplierPool/NoAmount");

    _beforeWithdraw(staker, amount);

    uint256 reward = _unstakeAccounting(staker, amount);

    if (reward != 0) {
      _distributeRewards(staker, reward);
    }

    emit Withdrawn(staker, amount);
    stakeToken.safeTransfer(staker, amount);
  }

  /**
   * @dev Performs necessary accounting for unstake operation
   * Assumes:
   * - `staker` is a valid address
   * - `amount` is non-zero
   * - `_update` has been called (and hence `_totalStakeSeconds` / `lockedRewardAmount` / `lastUpdateTime`)
   * - `rewardDue` will be transfered to `staker` after accounting
   * - `amount` will be transfered back to `staker` after accounting
   * - `Withdraw` / `RewardsPaid` will be emitted
   *
   * State:
   * - `_users[staker].stakes` will remove entries necessary to cover amount
   * - `_users[staker].totalStake` will be decreased
   * - `_totalStaked` will be reduced by amount
   * - `_totalStakeSeconds` will be reduced by unstaked stake seconds
   * @param staker Staker address to unstake from
   * @param amount Stake Tokens to be unstaked
   */
  function _unstakeAccounting(address staker, uint256 amount)
    internal
    virtual
    returns (uint256 rewardDue)
  {
    // Fetch User storage reference
    UserData storage userData = _users[staker];

    require(userData.totalStake >= amount, "MultiplierPool/ExceedsStake");
    // {cached} value would be de-synced
    assert(_totalStaked >= amount);

    UnstakeOutput memory out =
      simulateUnstake(
        userData.stakes,
        amount,
        getFutureTotalStakeSeconds(block.timestamp),
        unlockedRewardAmount(),
        block.timestamp,
        bonusScaling
      );

    // Update storage data
    if (out.newStakesCount == 0) {
      delete userData.stakes;
    } else {
      // Remove all fully unstaked amounts
      while (userData.stakes.length > out.newStakesCount) {
        userData.stakes.pop();
      }

      if (out.lastStakeAmount != 0) {
        userData.stakes[out.newStakesCount.sub(1)].amount = out.lastStakeAmount;
      }
    }

    // Update {cached} totals
    userData.totalStake = userData.totalStake.sub(amount);
    _totalStaked = _totalStaked.sub(amount);
    _totalStakeSeconds = out.newTotalStakeSeconds;

    // Calculate rewards
    rewardDue = out.rewardDue;
  }

  /**
   * @dev Performs necessary accounting for stake operation
   * Assumes:
   * - `staker` is a valid address
   * - `amount` is non-zero
   * - `_update` has been called (and hence `_totalStakeSeconds` / `lockedRewardAmount` / `lastUpdateTime` are modified)
   * - `amount` has been transfered to the contract
   *
   * State:
   * - `_users[staker].stakes` will add a new entry for amount
   * - `_users[staker].totalStake` will be increased
   * - `_totalStaked` will be increased by amount
   * @param staker Staker address to stake for
   * @param amount Stake tokens to be staked
   */
  function _stakeAccounting(address staker, uint256 amount) internal {
    UserData storage userData = _users[staker];

    // Add new stake entry
    userData.stakes.push(Stake(amount, block.timestamp));

    // Update {cached} totals
    _totalStaked = _totalStaked.add(amount);
    userData.totalStake = userData.totalStake.add(amount);
  }

  /**
   * @dev Updates the Pool to:
   * - Releases token rewards for the current timestamp
   * - Updates the `_totalStakeSeconds` for the entire `_totalStake`
   * - Set `lastUpdateTime` to be block.timestamp
   */
  function _update() internal {
    _unlockRewards();

    _totalStakeSeconds = _totalStakeSeconds.add(
      calculateStakeSeconds(_totalStaked, lastUpdateTime, block.timestamp)
    );
    lastUpdateTime = block.timestamp;
  }

  /* ========== RESTRICTED FUNCTIONS ========== */

  /* ----- FUNDER_ROLE ----- */

  /**
   * @notice Fund pool by locking up reward tokens for future distribution
   * @param amount number of reward tokens to lock up as funding
   * @param duration period (seconds) over which funding will be unlocked
   * @param start time (seconds) at which funding begins to unlock
   */
  function fund(
    uint256 amount,
    uint256 duration,
    uint256 start
  ) external onlyFunder {
    _update();
    _fund(amount, duration, start);
  }

  /**
   * @notice Clean a pool by expiring old rewards
   */
  function clean() external onlyFunder {
    _cleanRewardSchedules();
  }

  /* ----- ADJUSTER_ROLE ----- */
  /**
   * @notice Modify the bonus scaling once started
   * @dev Adjusters should be timelocked.
   * @param _bonusScaling Bonus Scaling parameters (min, max, period)
   */
  function modifyBonusScaling(BonusScaling memory _bonusScaling) external {
    require(hasRole(ADJUSTER_ROLE, msg.sender), "MultiplierPool/AdjusterRole");
    bonusScaling = _bonusScaling;
  }

  /**
   * @notice Modify the hard lock (allows release after a set period)
   * @dev Adjusters should be timelocked.
   * @param _hardLockPeriod [seconds] length of time to refuse release of staked funds
   */
  function modifyHardLock(uint256 _hardLockPeriod) external {
    require(hasRole(ADJUSTER_ROLE, msg.sender), "MultiplierPool/AdjusterRole");
    hardLockPeriod = _hardLockPeriod;
  }

  /* ----- RECOVER_ROLE ----- */

  /**
   * @notice Provide accidental token retrieval.
   * @dev Sourced from synthetix/contracts/StakingRewards.sol
   */
  function recoverERC20(address tokenAddress, uint256 tokenAmount) external {
    require(hasRole(RECOVER_ROLE, msg.sender), "MultiplierPool/RecoverRole");
    require(
      tokenAddress != address(stakeToken),
      "MultiplierPool/NoRecoveryOfStake"
    );
    require(
      tokenAddress != address(rewardToken),
      "MultiplierPool/NoRecoveryOfReward"
    );

    emit Recovered(tokenAddress, tokenAmount);

    IERC20(tokenAddress).safeTransfer(msg.sender, tokenAmount);
  }

  /* ========== HOOKS ========== */

  /**
   * @dev Hook that is called before any staking of tokens.
   *
   * Calling conditions:
   *
   * - `amount` of `payer`'s tokens will be staked into the pool
   * - `staker` can withdraw.
   * N.B. this is not called on claiming rewards
   */
  function _beforeStake(
    address payer,
    address staker,
    uint256 amount
  ) internal virtual {}

  /**
   * @dev Hook that is called before any withdrawal of tokens.
   *
   * Calling conditions:
   *
   * - `amount` of ``from``'s tokens will be withdrawn into the pool
   * N.B. this is not called on claiming rewards
   */
  function _beforeWithdraw(address from, uint256) internal virtual {
    // Check hard lock - was the last stake > hardLockPeriod
    Stake[] memory userStakes = _users[from].stakes;
    Stake memory lastStake = userStakes[userStakes.length.sub(1)];
    require(
      lastStake.timestamp.add(hardLockPeriod) <= block.timestamp,
      "MultiplierPool/HardLockNotPassed"
    );
  }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "../utils/EnumerableSet.sol";
import "../utils/Address.sol";
import "../utils/Context.sol";

/**
 * @dev Contract module that allows children to implement role-based access
 * control mechanisms.
 *
 * Roles are referred to by their `bytes32` identifier. These should be exposed
 * in the external API and be unique. The best way to achieve this is by
 * using `public constant` hash digests:
 *
 * ```
 * bytes32 public constant MY_ROLE = keccak256("MY_ROLE");
 * ```
 *
 * Roles can be used to represent a set of permissions. To restrict access to a
 * function call, use {hasRole}:
 *
 * ```
 * function foo() public {
 *     require(hasRole(MY_ROLE, msg.sender));
 *     ...
 * }
 * ```
 *
 * Roles can be granted and revoked dynamically via the {grantRole} and
 * {revokeRole} functions. Each role has an associated admin role, and only
 * accounts that have a role's admin role can call {grantRole} and {revokeRole}.
 *
 * By default, the admin role for all roles is `DEFAULT_ADMIN_ROLE`, which means
 * that only accounts with this role will be able to grant or revoke other
 * roles. More complex role relationships can be created by using
 * {_setRoleAdmin}.
 *
 * WARNING: The `DEFAULT_ADMIN_ROLE` is also its own admin: it has permission to
 * grant and revoke this role. Extra precautions should be taken to secure
 * accounts that have been granted it.
 */
abstract contract AccessControl is Context {
    using EnumerableSet for EnumerableSet.AddressSet;
    using Address for address;

    struct RoleData {
        EnumerableSet.AddressSet members;
        bytes32 adminRole;
    }

    mapping (bytes32 => RoleData) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`
     *
     * `DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
     * {RoleAdminChanged} not being emitted signaling this.
     *
     * _Available since v3.1._
     */
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /**
     * @dev Emitted when `account` is granted `role`.
     *
     * `sender` is the account that originated the contract call, an admin role
     * bearer except when using {_setupRole}.
     */
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Emitted when `account` is revoked `role`.
     *
     * `sender` is the account that originated the contract call:
     *   - if using `revokeRole`, it is the admin role bearer
     *   - if using `renounceRole`, it is the role bearer (i.e. `account`)
     */
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) public view returns (bool) {
        return _roles[role].members.contains(account);
    }

    /**
     * @dev Returns the number of accounts that have `role`. Can be used
     * together with {getRoleMember} to enumerate all bearers of a role.
     */
    function getRoleMemberCount(bytes32 role) public view returns (uint256) {
        return _roles[role].members.length();
    }

    /**
     * @dev Returns one of the accounts that have `role`. `index` must be a
     * value between 0 and {getRoleMemberCount}, non-inclusive.
     *
     * Role bearers are not sorted in any particular way, and their ordering may
     * change at any point.
     *
     * WARNING: When using {getRoleMember} and {getRoleMemberCount}, make sure
     * you perform all queries on the same block. See the following
     * https://forum.openzeppelin.com/t/iterating-over-elements-on-enumerableset-in-openzeppelin-contracts/2296[forum post]
     * for more information.
     */
    function getRoleMember(bytes32 role, uint256 index) public view returns (address) {
        return _roles[role].members.at(index);
    }

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) public view returns (bytes32) {
        return _roles[role].adminRole;
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function grantRole(bytes32 role, address account) public virtual {
        require(hasRole(_roles[role].adminRole, _msgSender()), "AccessControl: sender must be an admin to grant");

        _grantRole(role, account);
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function revokeRole(bytes32 role, address account) public virtual {
        require(hasRole(_roles[role].adminRole, _msgSender()), "AccessControl: sender must be an admin to revoke");

        _revokeRole(role, account);
    }

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been granted `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`.
     */
    function renounceRole(bytes32 role, address account) public virtual {
        require(account == _msgSender(), "AccessControl: can only renounce roles for self");

        _revokeRole(role, account);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event. Note that unlike {grantRole}, this function doesn't perform any
     * checks on the calling account.
     *
     * [WARNING]
     * ====
     * This function should only be called from the constructor when setting
     * up the initial roles for the system.
     *
     * Using this function in any other way is effectively circumventing the admin
     * system imposed by {AccessControl}.
     * ====
     */
    function _setupRole(bytes32 role, address account) internal virtual {
        _grantRole(role, account);
    }

    /**
     * @dev Sets `adminRole` as ``role``'s admin role.
     *
     * Emits a {RoleAdminChanged} event.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        emit RoleAdminChanged(role, _roles[role].adminRole, adminRole);
        _roles[role].adminRole = adminRole;
    }

    function _grantRole(bytes32 role, address account) private {
        if (_roles[role].members.add(account)) {
            emit RoleGranted(role, account, _msgSender());
        }
    }

    function _revokeRole(bytes32 role, address account) private {
        if (_roles[role].members.remove(account)) {
            emit RoleRevoked(role, account, _msgSender());
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow, so we distribute
        return (a / 2) + (b / 2) + ((a % 2 + b % 2) / 2);
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

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./IERC20.sol";
import "../../math/SafeMath.sol";
import "../../utils/Address.sol";

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
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value, "SafeERC20: decreased allowance below zero");
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
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
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "./Context.sol";

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract Pausable is Context {
    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    constructor () internal {
        _paused = false;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
}

pragma solidity >=0.4.24;


// https://docs.synthetix.io/contracts/source/interfaces/istakingrewards
interface IStakingRewards {
    // Views
    function lastTimeRewardApplicable() external view returns (uint256);

    function rewardPerToken() external view returns (uint256);

    function earned(address account) external view returns (uint256);

    function getRewardForDuration() external view returns (uint256);

    function totalSupply() external view returns (uint256);

    function balanceOf(address account) external view returns (uint256);

    // Mutative

    function stake(uint256 amount) external;

    function withdraw(uint256 amount) external;

    function getReward() external;

    function exit() external;
}

// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

interface IMultiStake {
  struct Stake {
    // [e18] Staked token amount
    uint256 amount;
    // [seconds] block timestamp at point of stake
    uint256 timestamp;
  }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.7.6;

import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "../../external-lib/SafeDecimalMath.sol";

import "../interfaces/multiplier/IMultiStake.sol";
import "../interfaces/multiplier/IBonusScaling.sol";

contract MultiplierMath is IBonusScaling, IMultiStake {
  using SafeMath for uint256;
  using SafeDecimalMath for uint256;

  struct UnstakeOutput {
    // [e18] amount left staked in last stake array
    uint256 lastStakeAmount;
    // [e18] number of stakes left
    uint256 newStakesCount;
    // [e18] stake seconds
    uint256 rawStakeSeconds;
    // [e18] bonus weighted stake seconds
    uint256 bonusWeightedStakeSeconds;
    // [e18] reward tokens due
    uint256 rewardDue;
    // [e18] total stake seconds adjusting for new unstaking
    uint256 newTotalStakeSeconds;
  }

  /**
   * @notice Calculate accrued stake seconds given a period
   * @param amount [eD] token amount
   * @param start [seconds] epoch timestamp
   * @param end [seconds] epoch timestamp up to
   * @return stakeSeconds accrued stake seconds
   */
  function calculateStakeSeconds(
    uint256 amount,
    uint256 start,
    uint256 end
  ) internal pure returns (uint256 stakeSeconds) {
    uint256 duration = end.sub(start);
    stakeSeconds = duration.mul(amount);
    return stakeSeconds;
  }

  /**
   * @dev Calculate the time bonus
   * @param bs BonusScaling used to calculate time bonus
   * @param duration length of time staked for
   * @return bonus [e18] fixed point fraction, UNIT = +100%
   */
  function timeBonus(BonusScaling memory bs, uint256 duration)
    internal
    pure
    returns (uint256 bonus)
  {
    if (duration >= bs.period) {
      return bs.max;
    }

    uint256 bonusScale = bs.max.sub(bs.min);
    uint256 bonusAddition = bonusScale.mul(duration).div(bs.period);
    bonus = bs.min.add(bonusAddition);
  }

  /**
   * @dev Calculate total stake seconds
   */
  function calculateTotalStakeSeconds(
    uint256 cachedTotalStakeAmount,
    uint256 cachedTotalStakeSeconds,
    uint256 lastUpdateTimestamp,
    uint256 timestamp
  ) internal pure returns (uint256 totalStakeSeconds) {
    if (timestamp == lastUpdateTimestamp) return cachedTotalStakeSeconds;

    uint256 additionalStakeSeconds =
      calculateStakeSeconds(
        cachedTotalStakeAmount,
        lastUpdateTimestamp,
        timestamp
      );

    totalStakeSeconds = cachedTotalStakeSeconds.add(additionalStakeSeconds);
  }

  /**
   * @dev Calculates reward from a given set of stakes
   * - Should check for total stake before calling
   * @param stakes Set of stakes
   */
  function simulateUnstake(
    Stake[] memory stakes,
    uint256 amountToUnstake,
    uint256 totalStakeSeconds,
    uint256 unlockedRewardAmount,
    uint256 timestamp,
    BonusScaling memory bs
  ) internal pure returns (UnstakeOutput memory out) {
    uint256 stakesToDrop = 0;
    while (amountToUnstake > 0) {
      uint256 targetIndex = stakes.length.sub(stakesToDrop).sub(1);
      Stake memory lastStake = stakes[targetIndex];

      uint256 currentAmount;
      if (lastStake.amount > amountToUnstake) {
        // set current amount to remaining unstake amount
        currentAmount = amountToUnstake;
        // amount of last stake is reduced
        out.lastStakeAmount = lastStake.amount.sub(amountToUnstake);
      } else {
        // set current amount to amount of last stake
        currentAmount = lastStake.amount;
        // add to stakes to drop
        stakesToDrop += 1;
      }

      amountToUnstake = amountToUnstake.sub(currentAmount);

      // Calculate staked seconds from amount
      uint256 stakeSeconds =
        calculateStakeSeconds(currentAmount, lastStake.timestamp, timestamp);

      // [e18] fixed point time bonus, 100% + X%
      uint256 bonus =
        SafeDecimalMath.UNIT.add(
          timeBonus(bs, timestamp.sub(lastStake.timestamp))
        );

      out.rawStakeSeconds = out.rawStakeSeconds.add(stakeSeconds);
      out.bonusWeightedStakeSeconds = out.bonusWeightedStakeSeconds.add(
        stakeSeconds.multiplyDecimal(bonus)
      );
    }

    // Update virtual caches
    out.newTotalStakeSeconds = totalStakeSeconds.sub(out.rawStakeSeconds);

    //              M_time * h
    // R = K *  ------------------
    //          H - h + M_time * h
    //
    // R - rewards due
    // K - total unlocked rewards
    // M_time - bonus related to time
    // h - user stake seconds
    // H - total stake seconds
    // H-h - new total stake seconds
    // R = 0 if H = 0
    if (totalStakeSeconds != 0) {
      out.rewardDue = unlockedRewardAmount
        .mul(out.bonusWeightedStakeSeconds)
        .div(out.newTotalStakeSeconds.add(out.bonusWeightedStakeSeconds));
    }

    return
      UnstakeOutput(
        out.lastStakeAmount,
        stakes.length.sub(stakesToDrop),
        out.rawStakeSeconds,
        out.bonusWeightedStakeSeconds,
        out.rewardDue,
        out.newTotalStakeSeconds
      );
  }
}

// SPDX-License-Identifier: GPL-3.0-only
pragma solidity =0.7.6;
pragma abicoder v2;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/math/Math.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";

abstract contract FundablePool is AccessControl {
  using SafeMath for uint256;
  using SafeERC20 for IERC20;

  struct RewardSchedule {
    // [eR] Amount of reward token contributed. (immutable)
    uint256 amount;
    // [seconds] Duration of funding round (immutable)
    uint256 duration;
    // [seconds] Epoch timestamp for start time (immutable)
    uint256 start;
    // [eR] Amount still locked
    uint256 amountLocked;
    // [seconds] Last updated epoch timestamp
    uint256 updated;
  }

  /* ========== CONSTANTS ========== */
  bytes32 public constant FUNDER_ROLE = keccak256("FUNDER_ROLE");

  /* ========== STATE VARIABLES ========== */
  IERC20 public immutable rewardToken;

  /// @notice [eR] {cached} total reward amount <=> rewardToken.balanceOf
  uint256 public totalRewardAmount;

  /// @notice [eR] {cached} locked reward amount
  uint256 public lockedRewardAmount;

  /// @dev All non-expired reward schedules
  RewardSchedule[] internal _rewardSchedules;

  /* ========== CONSTRUCTOR ========== */
  /**
   * @notice Construct a new FundablePool
   */
  constructor(address _funder, address _rewardToken) {
    rewardToken = IERC20(_rewardToken);
    _setupRole(FUNDER_ROLE, _funder);
  }

  /* ========== EVENTS ========== */
  event RewardsFunded(uint256 amount, uint256 start, uint256 duration);
  event RewardsUnlocked(uint256 amount);
  event RewardsPaid(address indexed user, uint256 reward);
  event RewardsExpired(uint256 amount, uint256 start);

  /* ========== MODIFIERS ========== */

  modifier onlyFunder() {
    require(hasRole(FUNDER_ROLE, msg.sender), "FundablePool/OnlyFunder");
    _;
  }

  /* ========== VIEWS ========== */

  /**
   * @notice All active/pending reward schedules
   */
  function rewardSchedules() external view returns (RewardSchedule[] memory) {
    return _rewardSchedules;
  }

  /**
   * @notice Rewards that are unlocked
   */
  function unlockedRewardAmount() public view returns (uint256) {
    return totalRewardAmount.sub(lockedRewardAmount);
  }

  /**
   * @notice Rewards that are pending unlock (will be unlocked on next update)
   */
  function pendingRewardAmount(uint256 timestamp)
    external
    view
    returns (uint256 unlockedRewards)
  {
    for (uint256 i = 0; i < _rewardSchedules.length; i++) {
      unlockedRewards = unlockedRewards.add(unlockable(i, timestamp));
    }
  }

  /**
   * @notice Compute the number of unlockable rewards for the given RewardSchedule
   * @param idx index of RewardSchedule
   * @return the number of unlockable rewards
   */
  function unlockable(uint256 idx, uint256 timestamp)
    public
    view
    returns (uint256)
  {
    RewardSchedule memory rs = _rewardSchedules[idx];

    // If still to start, then 0 unlocked
    if (timestamp <= rs.start) {
      return 0;
    }
    // If all used of rs used up, there is 0 left to unlock
    if (rs.amountLocked == 0) {
      return 0;
    }

    // if there is dust left, use it up.
    if (timestamp >= rs.start.add(rs.duration)) {
      return rs.amountLocked;
    }

    // N.B. rs.update >= rs.start;
    // => rs.start <= timeElapsed < rs.start + rs.duration
    uint256 timeElapsed = timestamp.sub(rs.updated);
    return timeElapsed.mul(rs.amount).div(rs.duration);
  }

  /* ========== MUTATIVE FUNCTIONS ========== */

  /* ========== RESTRICTED FUNCTIONS ========== */

  /* ----- Funder ----- */

  /**
   * @notice Fund pool using locked up reward tokens for future distribution
   * @dev Assumes: onlyFunder
   * @param amount number of reward tokens to lock up as funding
   * @param duration period (seconds) over which funding will be unlocked
   * @param start time (seconds) at which funding begins to unlock
   */
  function _fund(
    uint256 amount,
    uint256 duration,
    uint256 start
  ) internal {
    require(duration != 0, "FundablePool/ZeroDuration");
    require(start >= block.timestamp, "FundablePool/HistoricFund");

    uint256 allowed =
      rewardToken.balanceOf(address(this)).sub(totalRewardAmount);

    require(allowed >= amount, "FundablePool/InsufficentBalance");

    // Update {cached} values
    totalRewardAmount = totalRewardAmount.add(amount);
    lockedRewardAmount = lockedRewardAmount.add(amount);

    // create new funding
    _rewardSchedules.push(
      RewardSchedule({
        amount: amount,
        amountLocked: amount,
        updated: start,
        start: start,
        duration: duration
      })
    );

    emit RewardsFunded(amount, start, duration);
  }

  /**
   * @notice Clean up stale reward schedules
   * @dev Assumes: onlyFunder
   */
  function _cleanRewardSchedules() internal {
    // check for stale reward schedules to expire
    uint256 removed = 0;
    // Gas will hit cap before this becomes an overflow problem
    uint256 originalSize = _rewardSchedules.length;
    for (uint256 i = 0; i < originalSize; i++) {
      uint256 idx = i - removed;
      RewardSchedule storage funding = _rewardSchedules[idx];

      if (
        unlockable(idx, block.timestamp) == 0 &&
        block.timestamp >= funding.start.add(funding.duration)
      ) {
        emit RewardsExpired(funding.amount, funding.start);

        // remove at idx by copying last element here, then popping off last
        // (we don't care about order)
        _rewardSchedules[idx] = _rewardSchedules[_rewardSchedules.length - 1];
        _rewardSchedules.pop();
        removed++;
      }
    }
  }

  /* ========== INTERNAL FUNCTIONS ========== */

  /**
   * @dev Unlocks reward tokens based on funding schedules
   * @return unlockedRewards number of rewards unlocked
   */
  function _unlockRewards() internal returns (uint256 unlockedRewards) {
    // get unlockable rewards for each funding schedule
    for (uint256 i = 0; i < _rewardSchedules.length; i++) {
      uint256 unlockableRewardAtIdx = unlockable(i, block.timestamp);
      RewardSchedule storage funding = _rewardSchedules[i];
      if (unlockableRewardAtIdx != 0) {
        funding.amountLocked = funding.amountLocked.sub(unlockableRewardAtIdx);
        funding.updated = block.timestamp;
        unlockedRewards = unlockedRewards.add(unlockableRewardAtIdx);
      }
    }

    if (unlockedRewards != 0) {
      // Update {cached} lockedRewardAmount
      lockedRewardAmount = lockedRewardAmount.sub(unlockedRewards);
      emit RewardsUnlocked(unlockedRewards);
    }
  }

  /**
   * @dev Distribute reward tokens to user
   *
   * Assumptions:
   * - `user` deserves this amount
   *
   * @param user address of user receiving reward
   * @param amount number of reward tokens to be distributed
   */
  function _distributeRewards(address user, uint256 amount) internal {
    assert(amount <= totalRewardAmount);

    // update {cached} totalRewardAmount
    totalRewardAmount = totalRewardAmount.sub(amount);

    rewardToken.safeTransfer(user, amount);
    emit RewardsPaid(user, amount);
  }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

/**
 * @dev Library for managing
 * https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of primitive
 * types.
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableSet for EnumerableSet.AddressSet;
 *
 *     // Declare a set state variable
 *     EnumerableSet.AddressSet private mySet;
 * }
 * ```
 *
 * As of v3.3.0, sets of type `bytes32` (`Bytes32Set`), `address` (`AddressSet`)
 * and `uint256` (`UintSet`) are supported.
 */
library EnumerableSet {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Set type with
    // bytes32 values.
    // The Set implementation uses private functions, and user-facing
    // implementations (such as AddressSet) are just wrappers around the
    // underlying Set.
    // This means that we can only create new EnumerableSets for types that fit
    // in bytes32.

    struct Set {
        // Storage of set values
        bytes32[] _values;

        // Position of the value in the `values` array, plus 1 because index 0
        // means a value is not in the set.
        mapping (bytes32 => uint256) _indexes;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set._indexes[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function _remove(Set storage set, bytes32 value) private returns (bool) {
        // We read and store the value's index to prevent multiple reads from the same storage slot
        uint256 valueIndex = set._indexes[value];

        if (valueIndex != 0) { // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;

            // When the value to delete is the last one, the swap operation is unnecessary. However, since this occurs
            // so rarely, we still do the swap anyway to avoid the gas cost of adding an 'if' statement.

            bytes32 lastvalue = set._values[lastIndex];

            // Move the last value to the index where the value to delete is
            set._values[toDeleteIndex] = lastvalue;
            // Update the index for the moved value
            set._indexes[lastvalue] = toDeleteIndex + 1; // All indexes are 1-based

            // Delete the slot where the moved value was stored
            set._values.pop();

            // Delete the index for the deleted slot
            delete set._indexes[value];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._indexes[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        require(set._values.length > index, "EnumerableSet: index out of bounds");
        return set._values[index];
    }

    // Bytes32Set

    struct Bytes32Set {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _add(set._inner, value);
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _remove(set._inner, value);
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        return _contains(set._inner, value);
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(Bytes32Set storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
        return _at(set._inner, index);
    }

    // AddressSet

    struct AddressSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(AddressSet storage set, address value) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return address(uint160(uint256(_at(set._inner, index))));
    }


    // UintSet

    struct UintSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(UintSet storage set, uint256 value) internal returns (bool) {
        return _add(set._inner, bytes32(value));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(UintSet storage set, uint256 value) internal returns (bool) {
        return _remove(set._inner, bytes32(value));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(UintSet storage set, uint256 value) internal view returns (bool) {
        return _contains(set._inner, bytes32(value));
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function length(UintSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(UintSet storage set, uint256 index) internal view returns (uint256) {
        return uint256(_at(set._inner, index));
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

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

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

pragma solidity ^0.7.6;

import "@openzeppelin/contracts/math/SafeMath.sol";

// https://docs.synthetix.io/contracts/source/libraries/safedecimalmath
library SafeDecimalMath {
  using SafeMath for uint256;

  /* Number of decimal places in the representations. */
  uint8 public constant decimals = 18;
  uint8 public constant highPrecisionDecimals = 27;

  /* The number representing 1.0. */
  uint256 public constant UNIT = 10**uint256(decimals);

  /* The number representing 1.0 for higher fidelity numbers. */
  uint256 public constant PRECISE_UNIT = 10**uint256(highPrecisionDecimals);
  uint256 private constant UNIT_TO_HIGH_PRECISION_CONVERSION_FACTOR =
    10**uint256(highPrecisionDecimals - decimals);

  /**
   * @return Provides an interface to UNIT.
   */
  function unit() external pure returns (uint256) {
    return UNIT;
  }

  /**
   * @return Provides an interface to PRECISE_UNIT.
   */
  function preciseUnit() external pure returns (uint256) {
    return PRECISE_UNIT;
  }

  /**
   * @return The result of multiplying x and y, interpreting the operands as fixed-point
   * decimals.
   *
   * @dev A unit factor is divided out after the product of x and y is evaluated,
   * so that product must be less than 2**256. As this is an integer division,
   * the internal division always rounds down. This helps save on gas. Rounding
   * is more expensive on gas.
   */
  function multiplyDecimal(uint256 x, uint256 y)
    internal
    pure
    returns (uint256)
  {
    /* Divide by UNIT to remove the extra factor introduced by the product. */
    return x.mul(y) / UNIT;
  }

  /**
   * @return The result of safely multiplying x and y, interpreting the operands
   * as fixed-point decimals of the specified precision unit.
   *
   * @dev The operands should be in the form of a the specified unit factor which will be
   * divided out after the product of x and y is evaluated, so that product must be
   * less than 2**256.
   *
   * Unlike multiplyDecimal, this function rounds the result to the nearest increment.
   * Rounding is useful when you need to retain fidelity for small decimal numbers
   * (eg. small fractions or percentages).
   */
  function _multiplyDecimalRound(
    uint256 x,
    uint256 y,
    uint256 precisionUnit
  ) private pure returns (uint256) {
    /* Divide by UNIT to remove the extra factor introduced by the product. */
    uint256 quotientTimesTen = x.mul(y) / (precisionUnit / 10);

    if (quotientTimesTen % 10 >= 5) {
      quotientTimesTen += 10;
    }

    return quotientTimesTen / 10;
  }

  /**
   * @return The result of safely multiplying x and y, interpreting the operands
   * as fixed-point decimals of a precise unit.
   *
   * @dev The operands should be in the precise unit factor which will be
   * divided out after the product of x and y is evaluated, so that product must be
   * less than 2**256.
   *
   * Unlike multiplyDecimal, this function rounds the result to the nearest increment.
   * Rounding is useful when you need to retain fidelity for small decimal numbers
   * (eg. small fractions or percentages).
   */
  function multiplyDecimalRoundPrecise(uint256 x, uint256 y)
    internal
    pure
    returns (uint256)
  {
    return _multiplyDecimalRound(x, y, PRECISE_UNIT);
  }

  /**
   * @return The result of safely multiplying x and y, interpreting the operands
   * as fixed-point decimals of a standard unit.
   *
   * @dev The operands should be in the standard unit factor which will be
   * divided out after the product of x and y is evaluated, so that product must be
   * less than 2**256.
   *
   * Unlike multiplyDecimal, this function rounds the result to the nearest increment.
   * Rounding is useful when you need to retain fidelity for small decimal numbers
   * (eg. small fractions or percentages).
   */
  function multiplyDecimalRound(uint256 x, uint256 y)
    internal
    pure
    returns (uint256)
  {
    return _multiplyDecimalRound(x, y, UNIT);
  }

  /**
   * @return The result of safely dividing x and y. The return value is a high
   * precision decimal.
   *
   * @dev y is divided after the product of x and the standard precision unit
   * is evaluated, so the product of x and UNIT must be less than 2**256. As
   * this is an integer division, the result is always rounded down.
   * This helps save on gas. Rounding is more expensive on gas.
   */
  function divideDecimal(uint256 x, uint256 y) internal pure returns (uint256) {
    /* Reintroduce the UNIT factor that will be divided out by y. */
    return x.mul(UNIT).div(y);
  }

  /**
   * @return The result of safely dividing x and y. The return value is as a rounded
   * decimal in the precision unit specified in the parameter.
   *
   * @dev y is divided after the product of x and the specified precision unit
   * is evaluated, so the product of x and the specified precision unit must
   * be less than 2**256. The result is rounded to the nearest increment.
   */
  function _divideDecimalRound(
    uint256 x,
    uint256 y,
    uint256 precisionUnit
  ) private pure returns (uint256) {
    uint256 resultTimesTen = x.mul(precisionUnit * 10).div(y);

    if (resultTimesTen % 10 >= 5) {
      resultTimesTen += 10;
    }

    return resultTimesTen / 10;
  }

  /**
   * @return The result of safely dividing x and y. The return value is as a rounded
   * standard precision decimal.
   *
   * @dev y is divided after the product of x and the standard precision unit
   * is evaluated, so the product of x and the standard precision unit must
   * be less than 2**256. The result is rounded to the nearest increment.
   */
  function divideDecimalRound(uint256 x, uint256 y)
    internal
    pure
    returns (uint256)
  {
    return _divideDecimalRound(x, y, UNIT);
  }

  /**
   * @return The result of safely dividing x and y. The return value is as a rounded
   * high precision decimal.
   *
   * @dev y is divided after the product of x and the high precision unit
   * is evaluated, so the product of x and the high precision unit must
   * be less than 2**256. The result is rounded to the nearest increment.
   */
  function divideDecimalRoundPrecise(uint256 x, uint256 y)
    internal
    pure
    returns (uint256)
  {
    return _divideDecimalRound(x, y, PRECISE_UNIT);
  }

  /**
   * @dev Convert a standard decimal representation to a high precision one.
   */
  function decimalToPreciseDecimal(uint256 i) internal pure returns (uint256) {
    return i.mul(UNIT_TO_HIGH_PRECISION_CONVERSION_FACTOR);
  }

  /**
   * @dev Convert a high precision decimal to a standard decimal representation.
   */
  function preciseDecimalToDecimal(uint256 i) internal pure returns (uint256) {
    uint256 quotientTimesTen =
      i / (UNIT_TO_HIGH_PRECISION_CONVERSION_FACTOR / 10);

    if (quotientTimesTen % 10 >= 5) {
      quotientTimesTen += 10;
    }

    return quotientTimesTen / 10;
  }
}

// SPDX-License-Identifier: MIT
pragma solidity =0.7.6;

interface IBonusScaling {
  /**
   * Scale staked seconds according to multiplier
   */
  struct BonusScaling {
    // [e18] Minimum bonus amount
    uint256 min;
    // [e18] Maximum bonus amount
    uint256 max;
    // [seconds] Period over which to apply bonus scaling
    uint256 period;
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
  "metadata": {
    "bytecodeHash": "none",
    "useLiteralContent": true
  },
  "libraries": {}
}