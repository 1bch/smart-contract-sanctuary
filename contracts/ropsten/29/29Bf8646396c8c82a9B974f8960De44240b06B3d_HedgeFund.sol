// SPDX-License-Identifier: MIT

pragma solidity ^0.6.12;

import "./Libs/SafeMath.sol";
import "./Libs/Ownable.sol";

contract HedgeFund is Ownable {

    using SafeMath for uint256;

    mapping (address => bool) public isDepositor;

    mapping (address => uint256) public amountDeposit;
    mapping (address => uint256) public amountDepositorEarned;

    mapping(uint256 => uint256) public levelPrice;
    mapping (address => uint256) public levelOfDepositor;
    uint256 public constant LAST_LEVEL = 12;

    mapping (address => bool) public hasSponsor;
    mapping (address => address) public sponsorOfDepositor;
    mapping (address => uint256) public feeFromRecruiters;
    mapping (address => uint256) public depositTime;

    uint256 public lastTimestampEthSentToInstitution;

    uint256 public lastTimestampProfitReceived;

    address public manager;

    address payable public institutionWallet;

    uint256 public totalEthDeposited;

    uint256 public currentEthDeposited;

    uint256 public totalEthSentToInstitution;

    uint256 public totalEthPendingSubscription;
    uint256 public totalEthPendingWithdrawal;
    uint256 public totalSharesPendingRedemption;

    // event ProcessedDividendTracker(
    //     uint256 iterations,
    //     uint256 claims,
    //     uint256 lastProcessedIndex,
    //     bool indexed automatic,
    //     uint256 gas,
    //     address indexed processor
    // );
    bool private unlocked = true;
    modifier lock() {
        require(unlocked == true, 'TotemSwap: LOCKED');
        unlocked = false;
        _;
        unlocked = true;
    }

    event Deposit(address depositer, uint256 amount, uint256 timestamp);

    modifier onlyManager() {
        require(manager == _msgSender(), "Ownable: caller is not the manager");
        _;
    }

    constructor() public{
        manager = _msgSender();
        levelPrice[1] = 0.025 ether;
        for (uint256 i = 2; i <= LAST_LEVEL; i++) {
            levelPrice[i] = levelPrice[i-1] * 2;
        }
    }

    function setManager(address _manager) external onlyManager() {
        require(_manager != address(0), "Zero address can not be a manager.");
        manager = _manager;
    }

    function setInstitutionWallet(address payable _wallet) external onlyManager() {
        require(_wallet != address(0), "Zero address!");
        institutionWallet = _wallet;
    }

    function deposit(uint256 level) public payable {
        // require(msg.value >= 1 ether,"Amount should be greater than 1 Ether");
        require(msg.value == levelPrice[level], "invalid price");
        require(level > 0 && level <= LAST_LEVEL, "invalid level number");

        totalEthDeposited = totalEthDeposited.add(msg.value);
        currentEthDeposited = currentEthDeposited.add(msg.value);
        
        isDepositor[msg.sender] = true;
        amountDeposit[msg.sender] = amountDeposit[msg.sender].add(msg.value);
        depositTime[msg.sender] = block.timestamp;
        levelOfDepositor[msg.sender] = level;


        emit Deposit(msg.sender, msg.value, block.timestamp);
    }

    function upgradeLevel() public payable {
        require(isDepositor[msg.sender], "Please deposit before upgrading the level.");
        uint256 currentLevel = levelOfDepositor[msg.sender];
        require(currentLevel + 1 <= LAST_LEVEL, "next level invalid");
        require(msg.value == levelPrice[currentLevel + 1], "invalid price");

        totalEthDeposited = totalEthDeposited.add(msg.value);
        currentEthDeposited = currentEthDeposited.add(msg.value);
        amountDeposit[msg.sender] = amountDeposit[msg.sender].add(msg.value);
        depositTime[msg.sender] = block.timestamp;
        levelOfDepositor[msg.sender] = currentLevel + 1;
    }

    function sendFundsToInstitution() public onlyManager() {
        require(currentEthDeposited > 1 ether, "Funds not enought to send to institution.");
        require(address(this).balance >= currentEthDeposited, "Insufficient balance to send to institution.");
        require(institutionWallet != address(0), "No institutional wallet set up.");
        institutionWallet.transfer(currentEthDeposited);
        totalEthSentToInstitution = totalEthSentToInstitution.add(currentEthDeposited);
        currentEthDeposited = 0;
        lastTimestampEthSentToInstitution = block.timestamp;
    }

    function calculateReweard(address account) public view returns (uint256, uint256) {
        require(totalEthSentToInstitution > 0, "No funds have been transferred to the institutional wallet.");
        require(depositTime[account] < lastTimestampEthSentToInstitution && depositTime[account] < lastTimestampProfitReceived, "You don't have profit yet.");
        uint256 profit = totalEthPendingSubscription.mul(amountDeposit[account]).div(totalEthSentToInstitution);
        profit = profit.add(feeFromRecruiters[account]);
        
        uint256 feeToSponsor;
        if (hasSponsor[account]){
            feeToSponsor = profit.mul(2).div(10);
            profit = profit.sub(feeToSponsor);
            // feeFromRecruiters[sponsor] = feeFromRecruiters[sponsor].add(feeToSponsor);
        }

        if (profit < amountDepositorEarned[account]) {
            return (0, 0);
        }
        else {
            profit = profit.sub(amountDepositorEarned[account]);    
        }
        
        return (profit, feeToSponsor);
    }

    function claim() external lock {
        address claimer = msg.sender;
        require(isDepositor[claimer], "You must deposit first to earn profit.");
        uint256 earnedToDeposit = amountDepositorEarned[claimer].div(amountDeposit[claimer]);
        require(earnedToDeposit < 2, "You already have earned 200% of your deposit. Please upgrade your potfolio.");

        (uint256 profit, uint256 feeToSponsor) = calculateReweard(claimer);

        require(profit > 0, "No profit for your account");

        feeFromRecruiters[claimer] = 0;

        if (feeToSponsor > 0){
            address sponsor = sponsorOfDepositor[claimer];
            feeFromRecruiters[sponsor] = feeFromRecruiters[sponsor].add(feeToSponsor);
        }

        profit = profit.sub(amountDepositorEarned[claimer]);
        (bool success, /* bytes memory data */) = payable(claimer).call{value: profit, gas: 30000}("");
        // bool success = payable(claimer).transfer(profit);
        
        if (success) {
            amountDepositorEarned[claimer] = amountDepositorEarned[claimer].add(profit);
        }


    }

    function withdraw() external onlyManager {
        payable(manager).transfer(address(this).balance);
    }

    receive() external payable {
        totalEthPendingSubscription = msg.value;
        lastTimestampProfitReceived = block.timestamp;
    }
   
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

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
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

pragma solidity ^0.6.2;

// SPDX-License-Identifier: MIT License

import "./Context.sol";

contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () public {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(_owner == _msgSender(), "Ownable: caller is not the owner");
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
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.6.2;

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