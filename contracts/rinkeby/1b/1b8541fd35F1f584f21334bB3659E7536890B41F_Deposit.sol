// SPDX-License-Identifier: MIT
pragma solidity >=0.4.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

contract Deposit {
    address public owner;

    mapping(address => mapping(address => uint256)) public tokensDeposits;
    mapping(address => uint256) public ethDeposits;
    mapping(address => bool) public allowedTokens;

    constructor() {
        owner = msg.sender;
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    event Deposited(address indexed payee, uint256 weiAmount);
    event Withdrawn(address indexed payee, uint256 weiAmount);

    function updateToken(address token, bool isAllowed) external onlyOwner {
        allowedTokens[token] = isAllowed;
    }

    function deposit() external payable {
        ethDeposits[msg.sender] += msg.value;
        emit Deposited(msg.sender, msg.value);
    }

    function withdraw(uint256 amount, address to) external {
        require(ethDeposits[msg.sender] >= amount, "Not enought eth balance");
        ethDeposits[msg.sender] -= amount;
        (bool success, ) = to.call{value: amount}("");
        require(success, "Withdraw failure");
        emit Withdrawn(msg.sender, amount);
    }

    function depositToken(address token, uint256 amount) external {
        require(allowedTokens[token], "Token is not allowed for deposit");

        uint256 balanceBefore = IERC20(token).balanceOf(address(this));

        bool success = IERC20(token).transferFrom(
            msg.sender,
            address(this),
            amount
        );
        require(success, "Deposit failure");

        uint256 balanceAfter = IERC20(token).balanceOf(address(this));

        require(balanceAfter >= balanceBefore, "token transfer owerflow");
        tokensDeposits[msg.sender][token] += balanceAfter - balanceBefore;
    }

    function withdrawToken(
        address token,
        uint256 amount,
        address to
    ) external {
        require(
            tokensDeposits[msg.sender][token] >= amount,
            "Not enought token balance"
        );
        tokensDeposits[msg.sender][token] -= amount;
        bool success = IERC20(token).transfer(to, amount);
        require(success, "Withdraw failure");
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

{
  "remappings": [],
  "optimizer": {
    "enabled": false,
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