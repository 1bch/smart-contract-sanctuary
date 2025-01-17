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
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
        uint256 c = a - b;

        return c;
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
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
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
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
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
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b > 0, errorMessage);
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
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
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
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
        require(b != 0, errorMessage);
        return a % b;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity >=0.6.0 <0.8.0;

import "../../GSN/Context.sol";
import "./IERC20.sol";
import "../../math/SafeMath.sol";

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
 * We have followed general OpenZeppelin guidelines: functions revert instead
 * of returning `false` on failure. This behavior is nonetheless conventional
 * and does not conflict with the expectations of ERC20 applications.
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
contract ERC20 is Context, IERC20 {
    using SafeMath for uint256;

    mapping (address => uint256) private _balances;

    mapping (address => mapping (address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    /**
     * @dev Sets the values for {name} and {symbol}, initializes {decimals} with
     * a default value of 18.
     *
     * To select a different value for {decimals}, use {_setupDecimals}.
     *
     * All three of these values are immutable: they can only be set once during
     * construction.
     */
    constructor (string memory name_, string memory symbol_) public {
        _name = name_;
        _symbol = symbol_;
        _decimals = 18;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless {_setupDecimals} is
     * called.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view returns (uint8) {
        return _decimals;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view override returns (uint256) {
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
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
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
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
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
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
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
    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
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

        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
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
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Sets {decimals} to a value other than the default one of 18.
     *
     * WARNING: This function should only be called from the constructor. Most
     * applications that interact with token contracts will not expect
     * {decimals} to ever change, and may work incorrectly if it does.
     */
    function _setupDecimals(uint8 decimals_) internal {
        _decimals = decimals_;
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual { }
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

pragma solidity 0.6.12;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/math/SafeMath.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts/token/ERC20/SafeERC20.sol";
import "@openzeppelin/contracts/GSN/Context.sol";

import "./VaultToken.sol";

import "./interfaces/IManager.sol";
import "./interfaces/IController.sol";
import "./interfaces/IConverter.sol";
import "./interfaces/IVault.sol";
import "./interfaces/ExtendedIERC20.sol";

/**
 * @title Vault
 * @notice The vault is where users deposit and withdraw
 * like-kind assets that have been added by governance.
 */
contract Vault is VaultToken, IVault {
    using Address for address;
    using SafeMath for uint256;
    using SafeERC20 for IERC20;

    uint256 public constant MAX = 10000;

    IManager public immutable override manager;

    // Strategist-updated variables
    address public override gauge;
    uint256 public min;
    uint256 public totalDepositCap;

    event Deposit(address indexed account, uint256 amount);
    event Withdraw(address indexed account, uint256 amount);
    event Earn(address indexed token, uint256 amount);

    /**
     * @param _name The name of the vault token for depositors
     * @param _symbol The symbol of the vault token for depositors
     * @param _manager The address of the vault manager contract
     */
    constructor(
        string memory _name,
        string memory _symbol,
        address _manager
    )
        public
        VaultToken(_name, _symbol)
    {
        manager = IManager(_manager);
        min = 9500;
        totalDepositCap = 10000000 ether;
    }

    /**
     * STRATEGIST-ONLY FUNCTIONS
     */

    /**
     * @notice Sets the value of this vault's gauge
     * @dev Allow to be unset with the zero address
     * @param _gauge The address of the gauge
     */
    function setGauge(
        address _gauge
    )
        external
        notHalted
        onlyStrategist
    {
        gauge = _gauge;
    }

    /**
     * @notice Sets the value for min
     * @dev min is the minimum percent of funds to keep small withdrawals cheap
     * @param _min The new min value
     */
    function setMin(
        uint256 _min
    )
        external
        notHalted
        onlyStrategist
    {
        require(_min <= MAX, "!_min");
        min = _min;
    }

    /**
     * @notice Sets the value for the totalDepositCap
     * @dev totalDepositCap is the maximum amount of value that can be deposited
     * to the metavault at a time
     * @param _totalDepositCap The new totalDepositCap value
     */
    function setTotalDepositCap(
        uint256 _totalDepositCap
    )
        external
        notHalted
        onlyStrategist
    {
        totalDepositCap = _totalDepositCap;
    }

    /**
     * HARVESTER-ONLY FUNCTIONS
     */

    /**
     * @notice Sends accrued 3CRV tokens on the metavault to the controller to be deposited to strategies
     */
    function earn(
        address _token,
        address _strategy
    )
        external
        override
        checkToken(_token)
        notHalted
        onlyHarvester
    {
        require(manager.allowedStrategies(_strategy), "!_strategy");
        IController _controller = IController(manager.controllers(address(this)));
        if (_controller.investEnabled()) {
            uint256 _balance = available(_token);
            IERC20(_token).safeTransfer(address(_controller), _balance);
            _controller.earn(_strategy, _token, _balance);
            emit Earn(_token, _balance);
        }
    }

    /**
     * USER-FACING FUNCTIONS
     */

    /**
     * @notice Deposits the given token into the vault
     * @param _token The address of the token
     * @param _amount The amount of tokens to deposit
     */
     function deposit(
        address _token,
        uint256 _amount
     )
        public
        override
        checkToken(_token)
        notHalted
        returns (uint256 _shares)
    {
        require(_amount > 0, "!_amount");

        uint256 _balance = balance();

        uint256 _before = IERC20(_token).balanceOf(address(this));
        IERC20(_token).safeTransferFrom(msg.sender, address(this), _amount);
        _amount = IERC20(_token).balanceOf(address(this)).sub(_before);

        if (_amount > 0) {
            _amount = _normalizeDecimals(_token, _amount);

            if (totalSupply() > 0) {
                _amount = (_amount.mul(totalSupply())).div(_balance);
            }

            _shares = _shares.add(_amount);
        }

        if (_shares > 0) {
            _mint(msg.sender, _shares);
            require(totalSupply() <= totalDepositCap, ">totalDepositCap");
            emit Deposit(msg.sender, _shares);
        }
    }

    /**
     * @notice Deposits multiple tokens simultaneously to the vault
     * @dev Users must approve the vault to spend their stablecoin
     * @param _tokens The addresses of each token being deposited
     * @param _amounts The amounts of each token being deposited
     */
    function depositMultiple(
        address[] calldata _tokens,
        uint256[] calldata _amounts
    )
        external
        override
        notHalted
        returns (uint256 _shares)
    {
        require(_tokens.length == _amounts.length, "!length");

        for (uint8 i; i < _amounts.length; i++) {
            _shares = _shares.add(deposit(_tokens[i], _amounts[i]));
        }
    }

    /**
     * @notice Withdraws an amount of shares to a given output token
     * @param _shares The amount of shares to withdraw
     * @param _output The address of the token to receive
     */
    function withdraw(
        uint256 _shares,
        address _output
    )
        public
        override
        checkToken(_output)
    {
        uint256 _amount = (balance().mul(_shares)).div(totalSupply());
        _burn(msg.sender, _shares);

        uint256 _withdrawalProtectionFee = manager.withdrawalProtectionFee();
        if (_withdrawalProtectionFee > 0) {
            uint256 _withdrawalProtection = _amount.mul(_withdrawalProtectionFee).div(MAX);
            _amount = _amount.sub(_withdrawalProtection);
        }

        uint256 _balance = IERC20(_output).balanceOf(address(this));
        if (_balance < _amount) {
            IController _controller = IController(manager.controllers(address(this)));
            uint256 _toWithdraw = _amount.sub(_balance);
            if (_controller.strategies() > 0) {
                _controller.withdraw(_output, _toWithdraw);
            }
            uint256 _after = IERC20(_output).balanceOf(address(this));
            uint256 _diff = _after.sub(_balance);
            if (_diff < _toWithdraw) {
                _amount = _balance.add(_diff);
            }
        }

        IERC20(_output).safeTransfer(msg.sender, _amount);
        emit Withdraw(msg.sender, _amount);
    }

    /**
     * @notice Withdraw the entire balance for an account
     * @param _output The address of the desired token to receive
     */
    function withdrawAll(
        address _output
    )
        external
        override
    {
        withdraw(balanceOf(msg.sender), _output);
    }

    /**
     * VIEWS
     */

    /**
     * @notice Returns the amount of tokens available to be sent to strategies
     * @dev Custom logic in here for how much the vault allows to be borrowed
     * @dev Sets minimum required on-hand to keep small withdrawals cheap
     * @param _token The address of the token
     */
    function available(
        address _token
    )
        public
        view
        override
        returns (uint256)
    {
        return IERC20(_token).balanceOf(address(this)).mul(min).div(MAX);
    }

    /**
     * @notice Returns the total balance of the vault, including strategies
     */
    function balance()
        public
        view
        override
        returns (uint256 _balance)
    {
        return balanceOfThis().add(IController(manager.controllers(address(this))).balanceOf());
    }

    /**
     * @notice Returns the balance of allowed tokens present on the vault only
     */
    function balanceOfThis()
        public
        view
        returns (uint256 _balance)
    {
        address[] memory _tokens = manager.getTokens(address(this));
        for (uint8 i; i < _tokens.length; i++) {
            address _token = _tokens[i];
            _balance = _balance.add(_normalizeDecimals(_token, IERC20(_token).balanceOf(address(this))));
        }
    }

    /**
     * @notice Returns the rate of vault shares
     */
    function getPricePerFullShare()
        external
        view
        override
        returns (uint256)
    {
        if (totalSupply() > 0) {
            return balance().mul(1e18).div(totalSupply());
        } else {
            return balance();
        }
    }

    /**
     * @notice Returns an array of the tokens for this vault
     */
    function getTokens()
        external
        view
        override
        returns (address[] memory)
    {
        return manager.getTokens(address(this));
    }

    /**
     * @notice Returns the fee for withdrawing the given amount
     * @param _amount The amount to withdraw
     */
    function withdrawFee(
        uint256 _amount
    )
        external
        view
        override
        returns (uint256)
    {
        return manager.withdrawalProtectionFee().mul(_amount).div(MAX);
    }

    function _normalizeDecimals(
        address _token,
        uint256 _amount
    )
        internal
        view
        returns (uint256)
    {
        uint256 _decimals = uint256(ExtendedIERC20(_token).decimals());
        if (_decimals < 18) {
            _amount = _amount.mul(10**(18-_decimals));
        }
        return _amount;
    }

    function _checkToken(
        address _token
    )
        private
        view
        returns (bool)
    {
        return manager.allowedTokens(_token) && manager.vaults(_token) == address(this);
    }

    /**
     * MODIFIERS
     */

    modifier checkToken(address _token) {
        require(_checkToken(_token), "!_token");
        _;
    }

    modifier notHalted() {
        require(!manager.halted(), "halted");
        _;
    }

    modifier onlyHarvester() {
        require(msg.sender == manager.harvester(), "!harvester");
        _;
    }

    modifier onlyStrategist() {
        require(msg.sender == manager.strategist(), "!strategist");
        _;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "../vendor/LinkToken/token/LinkERC20.sol";
import "../vendor/LinkToken/ERC677Token.sol";

/**
 * @notice Vault Token
 * @dev Contract has been copied from:
 * https://github.com/smartcontractkit/LinkToken/blob/master/contracts/v0.6/LinkToken.sol
 * with modification made to specify name and symbol, deploys with 0 total supply
 */
contract VaultToken is LinkERC20, ERC677Token {

    constructor(
        string memory _name,
        string memory _symbol
    )
        public
        ERC20(_name, _symbol)
    // solhint-disable-next-line no-empty-blocks
    {}

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
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
    function _transfer(address sender, address recipient, uint256 amount)
        internal
        override
        virtual
        validAddress(recipient)
    {
        super._transfer(sender, recipient, amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner`s tokens.
     *
     * This is internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(address owner, address spender, uint256 amount)
        internal
        override
        virtual
        validAddress(spender)
    {
        super._approve(owner, spender, amount);
    }


    // MODIFIERS

    modifier validAddress(address _recipient) {
        require(_recipient != address(this), "!validAddress");
        _;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

interface ExtendedIERC20 {
    function decimals() external view returns (uint8);
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
}

// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./IManager.sol";

interface IController {
    function balanceOf() external view returns (uint256);
    function converter(address _vault) external view returns (address);
    function earn(address _strategy, address _token, uint256 _amount) external;
    function investEnabled() external view returns (bool);
    function harvestStrategy(address _strategy, uint256 _estimatedWETH, uint256 _estimatedYAXIS) external;
    function manager() external view returns (IManager);
    function strategies() external view returns (uint256);
    function withdraw(address _token, uint256 _amount) external;
    function withdrawAll(address _strategy, address _convert) external;
}

// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./IManager.sol";

interface IConverter {
    function manager() external view returns (IManager);
    function convert(
        address _input,
        address _output,
        uint256 _inputAmount,
        uint256 _estimatedOutput
    ) external returns (uint256 _outputAmount);
    function expected(
        address _input,
        address _output,
        uint256 _inputAmount
    ) external view returns (uint256 _outputAmount);
}

// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

interface IManager {
    function addToken(address, address) external;
    function allowedControllers(address) external view returns (bool);
    function allowedConverters(address) external view returns (bool);
    function allowedStrategies(address) external view returns (bool);
    function allowedTokens(address) external view returns (bool);
    function allowedVaults(address) external view returns (bool);
    function controllers(address) external view returns (address);
    function getHarvestFeeInfo() external view returns (address, address, uint256);
    function getTokens(address) external view returns (address[] memory);
    function governance() external view returns (address);
    function halted() external view returns (bool);
    function harvester() external view returns (address);
    function insuranceFee() external view returns (uint256);
    function insurancePool() external view returns (address);
    function insurancePoolFee() external view returns (uint256);
    function pendingStrategist() external view returns (address);
    function removeToken(address, address) external;
    function stakingPool() external view returns (address);
    function stakingPoolShareFee() external view returns (uint256);
    function strategist() external view returns (address);
    function tokens(address, uint256) external view returns (address);
    function treasury() external view returns (address);
    function treasuryFee() external view returns (uint256);
    function vaults(address) external view returns (address);
    function withdrawalProtectionFee() external view returns (uint256);
    function yaxis() external view returns (address);
}

// SPDX-License-Identifier: MIT

pragma solidity 0.6.12;

import "./IManager.sol";

interface IVault {
    function available(address _token) external view returns (uint256);
    function balance() external view returns (uint256);
    function deposit(address _token, uint256 _amount) external returns (uint256);
    function depositMultiple(address[] calldata _tokens, uint256[] calldata _amount) external returns (uint256);
    function earn(address _token, address _strategy) external;
    function gauge() external returns (address);
    function getPricePerFullShare() external view returns (uint256);
    function getTokens() external view returns (address[] memory);
    function manager() external view returns (IManager);
    function withdraw(uint256 _amount, address _output) external;
    function withdrawAll(address _output) external;
    function withdrawFee(uint256 _amount) external view returns (uint256);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import "./token/ERC677.sol";
import "./token/ERC677Receiver.sol";

abstract contract ERC677Token is ERC20, ERC677 {
  /**
   * @dev transfer token to a contract address with additional data if the recipient is a contact.
   * @param _to The address to transfer to.
   * @param _value The amount to be transferred.
   * @param _data The extra data to be passed to the receiving contract.
   */
  function transferAndCall(address _to, uint _value, bytes memory _data)
    public
    override
    virtual
    returns (bool success)
  {
    super.transfer(_to, _value);
    emit Transfer(msg.sender, _to, _value, _data);
    if (isContract(_to)) {
      contractFallback(_to, _value, _data);
    }
    return true;
  }


  // PRIVATE

  function contractFallback(address _to, uint _value, bytes memory _data)
    private
  {
    ERC677Receiver receiver = ERC677Receiver(_to);
    receiver.onTokenTransfer(msg.sender, _value, _data);
  }

  function isContract(address _addr)
    private
    view
    returns (bool hasCode)
  {
    uint length;
    assembly { length := extcodesize(_addr) }
    return length > 0;
  }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

abstract contract ERC677 is IERC20 {
  function transferAndCall(address to, uint value, bytes memory data) public virtual returns (bool success);

  event Transfer(address indexed from, address indexed to, uint value, bytes data);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

abstract contract ERC677Receiver {
  function onTokenTransfer(address _sender, uint _value, bytes memory _data) public virtual;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.6.0;

import "@openzeppelin/contracts/token/ERC20/ERC20.sol";

abstract contract LinkERC20 is ERC20 {
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
  function increaseApproval(address spender, uint256 addedValue) public virtual returns (bool) {
    return super.increaseAllowance(spender, addedValue);
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
  function decreaseApproval(address spender, uint256 subtractedValue) public virtual returns (bool) {
    return super.decreaseAllowance(spender, subtractedValue);
  }
}

{
  "evmVersion": "istanbul",
  "libraries": {},
  "metadata": {
    "bytecodeHash": "ipfs",
    "useLiteralContent": true
  },
  "optimizer": {
    "enabled": true,
    "runs": 200
  },
  "remappings": [],
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