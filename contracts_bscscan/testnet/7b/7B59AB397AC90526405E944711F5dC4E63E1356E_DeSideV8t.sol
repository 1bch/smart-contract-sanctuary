// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../libs/token/ERC20/utils/SafeERC20.sol";
import "../libs/token/ERC20/IERC20.sol";

contract DeSideV8t {
  using SafeERC20 for IERC20;

  address constant private BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;

  struct TokenInfo {
    bytes4 tokenInFunctionId;
    mapping(uint256 => bytes4) toChainFunctionId;
    mapping(uint256 => IERC20) toChainToken;
  }
  struct Transaction {
    bytes4 executeFunctionId;
    IERC20 sendToken; 
    IERC20 receiveToken;
    uint256 amount;
  }

  // uint256 public nonce;

  // mapping(address => mapping(IERC20 => uint256)) private userBalance;
  // ----- user => -------- fromChainId => ---- toChainId 
  mapping(address => mapping(uint256 => mapping(uint256 => Transaction[]))) private userTransactions;
  mapping(address => mapping(IERC20 => uint256)) private userTokenBalance;
  mapping(IERC20 => uint256) private bridgeTokenBalance;

  mapping(IERC20 => TokenInfo) private tokenInfo;

  mapping(bytes32 => bytes32) public commitments;

  event TransferTo(
    address indexed user, 
    uint256 indexed fromChainId, 
    uint256 indexed toChainId, 
    IERC20 sendToken, 
    IERC20 receiveToken, 
    uint256 amount
  );
  
  function setTokenInfo(
    IERC20 _token, 
    bytes4 _tokenInFunctionId, 
    uint256 _toChainId, 
    bytes4 _toChainFunctionId, 
    IERC20 _toChainToken
  )
    external
  {
    tokenInfo[_token].tokenInFunctionId = _tokenInFunctionId;
    tokenInfo[_token].toChainFunctionId[_toChainId] = _toChainFunctionId;
    tokenInfo[_token].toChainToken[_toChainId] = _toChainToken;
  }
  function tokenInTransferTo(
    uint256 _toChainId, 
    IERC20 _token, 
    uint256 _amount
  ) 
    external 
    permittedTokenInFunctionId(_token)
  {
    //approve-->
    uint256 balanceBefore = _token.balanceOf(address(this));
    _token.safeTransferFrom(msg.sender, address(this), _amount);
    _amount = _token.balanceOf(address(this)) - balanceBefore;
    userTokenBalance[msg.sender][_token] += _amount;
    // solhint-disable-next-line avoid-low-level-calls
    (bool success, ) =  address(this).call(
      abi.encodeWithSelector(tokenInfo[_token].tokenInFunctionId,msg.sender,_token,_amount));
    require(success, "Call tokenInFunctionId failed");
    Transaction[] storage transactions = userTransactions[msg.sender][block.chainid][_toChainId];
    Transaction memory transaction = Transaction({
      executeFunctionId: tokenInfo[_token].toChainFunctionId[_toChainId],
      sendToken: _token,
      receiveToken: tokenInfo[_token].toChainToken[_toChainId],
      amount: _amount
    });
    transactions.push(transaction);
    emit TransferTo(
      msg.sender, 
      block.chainid, 
      _toChainId, 
      _token, 
      tokenInfo[_token].toChainToken[_toChainId], 
      _amount);
  }
  function withdraw(IERC20 _token, uint256 _amount) external {
    _token.safeTransfer(msg.sender, _amount);
  }
  function fulfill(
    bytes32 _requestId, 
    address _user,
    uint256 _fromChainId,
    uint256 _toChainId, 
    uint256 _txIndex, 
    bytes4 _executeFunctionId,
    IERC20 _sendToken,
    IERC20 _receiveToken,
    uint256 _amount
  ) 
    external 
    returns (bool success, bytes memory result)
  {
    bytes32 paramsHash = keccak256(abi.encode(_fromChainId, _toChainId, _txIndex));
    require(commitments[_requestId] == paramsHash, "Params do not match request ID");
    delete commitments[_requestId];
    Transaction[] storage transactions = userTransactions[_user][_fromChainId][_toChainId];
    require(transactions.length == _txIndex, "Transactions index out of order");
    Transaction memory transaction = Transaction({
      executeFunctionId: _executeFunctionId,
      sendToken: _sendToken,
      receiveToken: _receiveToken,
      amount: _amount
    });
    transactions.push(transaction);
    // solhint-disable-next-line avoid-low-level-calls
    return address(this).delegatecall(
      abi.encodeWithSelector(
      transaction.executeFunctionId,
      _user,
      _fromChainId,
      _toChainId,
      _txIndex));
  }
  function transferTokenToUser(
    address _user, 
    IERC20 _token, 
    uint256 _amount
  ) 
    external 
  {
    userTokenBalance[_user][_token] -= _amount;
    _token.safeTransfer(_user, _amount);
  }
  function mintTokenToUser(
    address _user, 
    IERC20 _token, 
    uint256 _amount
  ) 
    external 
  {
    userTokenBalance[_user][_token] -= _amount;
    _token.mint(_user, _amount);
  }
  function tokenInBridge(
    address _user,
    IERC20 _token, 
    uint256 _amount
  ) 
    external 
    permittedTokenInBridge(_token)
    onlyContractCall()
  {
    userTokenBalance[_user][_token] -= _amount;
    bridgeTokenBalance[_token] += _amount;
  }
  function tokenInBurn(
    address _user,
    IERC20 _token, 
    uint256 _amount
  ) 
    external 
    permittedTokenInBurn(_token)
    onlyContractCall()
  {
    userTokenBalance[_user][_token] -= _amount;
    _token.burn(_amount);
  }
  function tokenInBurnToBurnAddr(
    address _user,
    IERC20 _token, 
    uint256 _amount
  ) 
    external 
    permittedTokenInBurnToBurnAddr(_token)
    onlyContractCall()
  {
    userTokenBalance[_user][_token] -= _amount;
    _token.safeTransfer(BURN_ADDRESS, _amount);
  }
  function getUserTransaction(
    address _user, 
    uint256 _fromChainId, 
    uint256 _toChainId, 
    uint256 _txIndex
  ) 
    external 
    view 
    returns (Transaction memory) 
  {
    return userTransactions[_user][_fromChainId][_toChainId][_txIndex];
  }
  function getUserTransactionsLength(
    address _user, 
    uint256 _fromChainId, 
    uint256 _chainId
  )
    external 
    view 
    returns (uint256 length) 
  {
    return userTransactions[_user][_fromChainId][_chainId].length;
  }
  function getTokenInfo(
    IERC20 _token, 
    uint256 _toChainId
  )
    external 
    view 
    returns (
      bytes4 tokenInFunctionId, 
      bytes4 toChainFunctionId, 
      IERC20 toChainToken
    ) 
  {
    return (
      tokenInfo[_token].tokenInFunctionId,
      tokenInfo[_token].toChainFunctionId[_toChainId],
      tokenInfo[_token].toChainToken[_toChainId]
    );
  }
  modifier permittedTokenInFunctionId(IERC20  _token) {
    require(
      tokenInfo[_token].tokenInFunctionId == this.tokenInBurn.selector ||
      tokenInfo[_token].tokenInFunctionId == this.tokenInBurnToBurnAddr.selector ||
      tokenInfo[_token].tokenInFunctionId == this.tokenInBurn.selector,
       "Must use whitelisted functions"
    );
    _;
  }
  modifier permittedTokenInBridge(IERC20 _token) {
    require(
      tokenInfo[_token].tokenInFunctionId == this.tokenInBurn.selector, 
      "Burn function Not Permitted"
    );
    _;
  }
  modifier permittedTokenInBurn(IERC20 _token) {
    require(
      tokenInfo[_token].tokenInFunctionId == this.tokenInBurn.selector, 
      "Burn function Not Permitted"
    );
    _;
  }
  modifier permittedTokenInBurnToBurnAddr(IERC20 _token) {
    require(
      tokenInfo[_token].tokenInFunctionId == this.tokenInBurnToBurnAddr.selector, 
      "Burn function Not Permitted"
    );
    _;
  }
  modifier onlyContractCall() {
    require(msg.sender == address(this), "Only call form this contract");
    _;
  }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// Add Mint and Burn function
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

    function mint(address to, uint256 amount) external;

    function burn(uint256 amount) external;

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

{
  "remappings": [],
  "optimizer": {
    "enabled": false,
    "runs": 200
  },
  "evmVersion": "berlin",
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