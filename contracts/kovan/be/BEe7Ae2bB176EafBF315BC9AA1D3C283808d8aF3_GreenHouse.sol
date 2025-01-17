// SPDX-License-Identifier: MIT
pragma solidity ^0.8.7;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title GreenHouse staking contract
 * @dev A stakable smart contract that stores ERC20 token.
 */
contract GreenHouse is Ownable {
    // Staking ERC20 token
    IERC20 public token;

    // All Users Stakes
    uint256 public allStakes = 0;
    uint256 public everStakedUsersCount = 0;

    // Bonus and Monthly Reward Pools
    uint256 public bonusRewardPool = 0;  // Bonus Reward Pool 
    uint256 public monthlyRewardPool = 0;  // Monthly Reward Pool
    mapping(address => uint256) public referralRewards;

    // Users stakes, withdrawals and users that has staked at least once
    mapping(address => uint256) internal _stakes;
    mapping(address => uint256) internal _withdrawals;
    mapping(address => bool) internal _hasStaked;

    // Reward calculation magic
    uint256 constant internal _magnitude = 2**128;
    uint256 internal _magnifiedRewardPerStake = 0; 
    mapping(address => int256) internal _magnifiedRewardCorrections;

    // Staking and Unstaking fees
    uint256 constant internal _feeAllUsersStakedPermille = 700;
    uint256 constant internal _feeBonusPoolPermille = 100;
    uint256 constant internal _feePlatformWalletPermille = 100;
    uint256 constant internal _feeReferalPermille = 50;
    uint256 constant internal _feePartnerWalletPermille = 50;

    // Monthly Pool distribution and timer
    uint256 constant internal _monthlyPoolDistributeAllUsersPercent = 50;
    uint256 constant internal _monthlyPoolTimer = 2592000; // 30 days
    uint256 internal _monthlyPoolLastDistributedAt;

    // Bonus Pool distribution 
    uint256 constant internal _bonusPoolDistributeAllUsersPercent = 40;
    uint256 constant internal _bonusPoolDistributeLeaderboardPercent = 40;

    // Bonus Pool Leaderboard queue
    mapping(uint256 => address) internal _bonusPoolLeaderboard;
    uint256 internal _bonusPoolLeaderboardFirst = 1;
    uint256 internal _bonusPoolLeaderboardLast = 0;
    uint256 constant internal _bonusPoolLeaderboardMaxUsersCount = 10;
    uint256 constant internal _bonusPoolMinStakeToQualify = 1000;

    // Bonus Timer settings
    uint256 internal _bonusPoolTimer;
    uint256 internal _bonusPoolLastQualifiedStakeAt;
    uint256 constant internal _bonusPoolNewStakeholderTimerAddition = 900;   // 15 minutes
    uint256 constant internal _bonusPoolTimerInitial = 21600; // 6 hours

    // Platform Team wallets
    address[] internal _platformWallets;
    // Partner wallet
    address   internal _partnerWallet;

    event Staked(address indexed sender, uint256 amount, address indexed referrer);
    event Unstaked(address indexed sender, uint256 amount);
    event RewardWithdrawn(address indexed sender, uint256 amount);
    event Restaked(address indexed sender, uint256 amount);
    event BonusRewardPoolDistributed();
    event MonthlyRewardPoolDistributed();

    /// @param token_ A ERC20 token to use in this contract
    /// @param partnerWallet A Partner's wallet to reward
    /// @param platformWallets List of Platform Team's wallets
    constructor(
        address token_, 
        address partnerWallet, 
        address[] memory platformWallets
    ) Ownable() {
        token = IERC20(token_);

        _platformWallets = platformWallets;
        _partnerWallet = partnerWallet;

        _bonusPoolLastQualifiedStakeAt = block.timestamp;
        _bonusPoolTimer = _bonusPoolTimerInitial;

        _monthlyPoolLastDistributedAt = block.timestamp;
    }

    // External functions 

    function stake(uint256 amount, address referrer) external {
        require(amount != 0, "GreenHouse: staking amount could not be zero");

        bool success = token.transferFrom(msg.sender, address(this), amount);
        require(success, "GreenHouse: staking token transfer failed");

        if (!_hasStaked[msg.sender]) {
            _hasStaked[msg.sender] = true;
            everStakedUsersCount++;
            if (amount >= _bonusPoolMinStakeToQualify) {
                _bonusPoolProcessNewStakeholder(msg.sender);
            }
        }

        _processStake(amount, referrer);
        emit Staked(msg.sender, amount, referrer);
    }

    function unstake(uint256 amount) external {
        require(amount != 0, "GreenHouse: unstaking amount could not be zero");
        require(_stakes[msg.sender] >= amount, "GreenHouse: insufficient amount to unstake");

        (uint256 net, uint256 fee) = _applyFeesAndDistributeRewards(amount, address(0));
        _stakes[msg.sender] -= amount;

        bool success = token.transfer(msg.sender, net);
        require(success, "GreenHouse: unstaking token transfer failed");

        _magnifiedRewardCorrections[msg.sender] += int256(_magnifiedRewardPerStake * amount);
        _rewardAllUsersStaked(fee);
        allStakes -= amount;

        emit Unstaked(msg.sender, amount);
    }

    function restake() external {
        uint256 withdrawable = withdrawableRewardOf(msg.sender);
        require(withdrawable > 0, "GreenHouse: nothing to restake");

        _processStake(withdrawable, address(0));
        emit Restaked(msg.sender, withdrawable);
    }

    function withdrawReward() external {
        uint256 withdrawable = withdrawableRewardOf(msg.sender);
        require(withdrawable > 0, "GreenHouse: nothing to withdraw");
        bool success = token.transfer(msg.sender, withdrawable);
        require(success, "GreenHouse: withdrawal token transfer failed");
        _withdrawals[msg.sender] += withdrawable;

        emit RewardWithdrawn(msg.sender, withdrawable);
    }

    function distributeMonthlyRewardPool() external {
        require(monthlyRewardPoolCountdown() == 0, "GreenHouse: monthly pool timer's still on");

        uint256 amountToDistribute = (monthlyRewardPool * _monthlyPoolDistributeAllUsersPercent) / 100;
        require(amountToDistribute != 0, "GreenHouse: monthly pool is empty");
        _rewardAllUsersStaked(amountToDistribute);
        monthlyRewardPool -= amountToDistribute;

        emit MonthlyRewardPoolDistributed();
    }

    function distributeBonusRewardPool() external {
        require(bonusRewardPoolCountdown() == 0, "GreenHouse: bonus pool timer's still on");
        require(bonusRewardPool != 0, "GreenHouse: bonus pool is empty");

        uint256 amountToDistributeAllUsers = (bonusRewardPool * _bonusPoolDistributeAllUsersPercent) / 100;
        _rewardAllUsersStaked(amountToDistributeAllUsers);

        uint256 leaderboardUsersCount = _bonusPoolLeaderboardUsersCount();
        require(leaderboardUsersCount != 0, "GreenHouse: leaderboard is empty");

        uint256 amountToDistributeLeaderboard = (bonusRewardPool * _bonusPoolDistributeLeaderboardPercent) / 100;
        uint256 amountToDistributePerLeader = amountToDistributeLeaderboard / leaderboardUsersCount;

        require(amountToDistributePerLeader > 0, "GreenHouse: nothing to reward leaderboard");
        for (uint256 i = _bonusPoolLeaderboardFirst; i <= _bonusPoolLeaderboardLast; ++i) {
            bool success = token.transfer(_bonusPoolLeaderboard[i], amountToDistributePerLeader);
            require(success, "GreenHouse: failed to transfer bonus pool reward");
        }

        _bonusPoolTimer = _bonusPoolTimerInitial;  // reset bonus pool timer
        bonusRewardPool -= amountToDistributeAllUsers + amountToDistributeLeaderboard;

        emit BonusRewardPoolDistributed();
    }

    function bonusPoolLeaderboard() external view returns(address[] memory) {
        uint256 leaderboardUsersCount = _bonusPoolLeaderboardUsersCount();
        address[] memory leaderboard = new address[](leaderboardUsersCount);
        for (uint256 i = 0; i < leaderboardUsersCount; ++i) {
            leaderboard[i] = _bonusPoolLeaderboard[i + _bonusPoolLeaderboardFirst];
        }
        return leaderboard;
    }


    // External functions only owner

    function setPartnerWallet(address address_) external onlyOwner {
        _partnerWallet = address_;
    }

    function setPlatformWallets(address[] memory addresses) external onlyOwner {
        _platformWallets = addresses;
    }


    // Public view functions 

    function stakeOf(address stakeholder) public view returns(uint256) {
        return _stakes[stakeholder];
    }

    function accumulativeRewardOf(address stakeholder) public view returns(uint256) {
        return uint256(int256(stakeOf(stakeholder) * _magnifiedRewardPerStake) 
                       + _magnifiedRewardCorrections[stakeholder]) / _magnitude;
    }

    function withdrawnRewardOf(address stakeholder) public view returns(uint256) {
        return _withdrawals[stakeholder];
    }

    function withdrawableRewardOf(address stakeholder) public view returns(uint256) {
        return accumulativeRewardOf(stakeholder) - withdrawnRewardOf(stakeholder);
    }

    function bonusRewardPoolCountdown() public view returns(uint256) {
        uint256 timeSinceLastQualifiedStake = block.timestamp - _bonusPoolLastQualifiedStakeAt;
        if (timeSinceLastQualifiedStake >= _bonusPoolTimer) return 0;
        return _bonusPoolTimer - timeSinceLastQualifiedStake;
    }

    function monthlyRewardPoolCountdown() public view returns(uint256) {
        uint256 timeSinceLastDistributed = block.timestamp - _monthlyPoolLastDistributedAt;
        if (timeSinceLastDistributed >= _monthlyPoolTimer) return 0;
        return _monthlyPoolTimer - timeSinceLastDistributed;
    }

    // internal functions

    /**
     @notice Adds new qualified staker to the Bonus Pool Leaderboard's queue
             and update Bonus Pool Timer
     @param stakeholder The address of a stakeholder
     */
    function _bonusPoolProcessNewStakeholder(address stakeholder) internal {
        _bonusPoolLeaderboardLast += 1;
        _bonusPoolLeaderboard[_bonusPoolLeaderboardLast] = stakeholder;
        _bonusPoolTimer += _bonusPoolNewStakeholderTimerAddition;

        if (_bonusPoolLeaderboardUsersCount() > _bonusPoolLeaderboardMaxUsersCount) {
            delete _bonusPoolLeaderboard[_bonusPoolLeaderboardFirst];
            _bonusPoolLeaderboardFirst += 1;
        }
    }

    function _bonusPoolLeaderboardUsersCount() internal view returns(uint256) {
        return _bonusPoolLeaderboardLast + 1 - _bonusPoolLeaderboardFirst;
    }

    function _transferRewardPartner(uint256 amount) internal {
        bool success = token.transfer(_partnerWallet, amount);
        require(success, "GreenHouse: failed to transfer reward to partner wallet");
    }

    function _transferRewardPlatform(uint256 amount) internal {
        uint256 perWallet = amount / _platformWallets.length;
        for (uint256 i = 0; i != _platformWallets.length; ++i) {
            bool success = token.transfer(_platformWallets[i], perWallet);
            require(success, "GreenHouse: failed to transfer reward to platform wallet");
        }
    }

    function _rewardAllUsersStaked(uint256 amount) internal {
        _magnifiedRewardPerStake += (_magnitude * amount) / allStakes;
    }

    function _transferRewardReferral(uint256 amount, address referrer) internal {
        bool success = token.transfer(referrer, amount);
        require(success, "GreenHouse: failed to transfer referal reward");
        referralRewards[referrer] += amount;
    }

    function _rewardBonusPool(uint256 amount) internal {
        bonusRewardPool += amount;
    }

    function _rewardMonthlyPool(uint256 amount) internal {
        monthlyRewardPool += amount;
    }

    function _applyFeesAndDistributeRewards(uint256 amount, address referrer) 
        internal
        returns(uint256, uint256) 
    {
        uint256 fee = (amount * _feeAllUsersStakedPermille) / 10000;

        uint256 feeBonusPool = (amount * _feeBonusPoolPermille) / 10000;
        uint256 feePartnerWallet = (amount * _feePartnerWalletPermille) / 10000;
        uint256 feeReferral = (amount * _feeReferalPermille) / 10000;
        uint256 feePlatformWallet = (amount * _feePlatformWalletPermille) / 10000;

        _rewardBonusPool(feeBonusPool);
        _transferRewardPartner(feePartnerWallet);
        _transferRewardPlatform(feePlatformWallet);
        if (referrer == address(0)) _rewardMonthlyPool(feeReferral);
        else _transferRewardReferral(feeReferral, referrer);

        uint256 net = (amount 
                       - fee
                       - feeBonusPool 
                       - feePartnerWallet
                       - feePlatformWallet 
                       - feeReferral);

        return (net, fee);
    }

    function _processStake(uint256 amount, address referrer) internal {
        (uint256 net, uint256 fee) = _applyFeesAndDistributeRewards(amount, referrer);
        _stakes[msg.sender] += net;
        _hasStaked[msg.sender] = true;

        allStakes += net;
        _magnifiedRewardCorrections[msg.sender] -= int256(_magnifiedRewardPerStake * net);
        _rewardAllUsersStaked(fee);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./extensions/IERC20Metadata.sol";
import "../../utils/Context.sol";

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin Contracts guidelines: functions revert
 * instead returning `false` on failure. This behavior is nonetheless
 * conventional and does not conflict with the expectations of ERC20
 * applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5.05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `sender` to `recipient`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);

        _afterTokenTransfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * has been transferred to `to`.
     * - when `from` is zero, `amount` tokens have been minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens have been burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}

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

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
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

{
  "optimizer": {
    "enabled": false,
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
  },
  "libraries": {}
}