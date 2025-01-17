// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "@openzeppelin/contracts/proxy/Clones.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IGSVESmartWrapper.sol";

/**
* @dev interface to allow the burning of gas tokens from an address to save on deployment cost
*/
interface IFreeFromUpTo {
    function freeFromUpTo(address from, uint256 value) external returns (uint256 freed);
}

contract GSVESmartWrapperFactory is Ownable{
    address payable public smartWrapperLocation;
    mapping(address => uint256) private _compatibleGasTokens;
    mapping(uint256 => address) private _reverseTokenMap;
    mapping(address => address) private _deployedWalletAddressLocation;
    mapping(address => uint256) private _freeUpValue;
    address private GSVEToken;
    uint256 private _totalSupportedTokens = 0;

  constructor (address payable _smartWrapperLocation, address _GSVEToken) public {
    smartWrapperLocation = _smartWrapperLocation;
    GSVEToken = _GSVEToken;
  }

    /**
    * @dev add support for trusted gas tokens - those we wrapped
    */
    function addGasToken(address gasToken, uint256 freeUpValue) public onlyOwner{
        _compatibleGasTokens[gasToken] = 1;
        _reverseTokenMap[_totalSupportedTokens] = gasToken;
        _totalSupportedTokens = _totalSupportedTokens + 1;
        _freeUpValue[gasToken] = freeUpValue;
    }

        /**
    * @dev GSVE moddifier that burns supported gas tokens around a function that uses gas
    * the function calculates the optimal number of tokens to burn, based on the token specified
    */
    modifier discountGas(address gasToken) {
        if(gasToken != address(0)){
            require(_compatibleGasTokens[gasToken] == 1, "GSVE: incompatible token");
            uint256 gasStart = gasleft();
            _;
            uint256 gasSpent = 21000 + gasStart - gasleft() + 16 * msg.data.length;
            IFreeFromUpTo(gasToken).freeFromUpTo(msg.sender,  (gasSpent + 16000) / _freeUpValue[gasToken]);
        }
        else{
            _;
        }
    }

    /**
    * @dev return the location of a users deployed wrapper
    */
    function deployedWalletAddressLocation(address creator) public view returns(address){
        return _deployedWalletAddressLocation[creator];
    }

    /**
    * @dev function to check if a gas token is supported by the deployer
    */
    function compatibleGasToken(address gasToken) public view returns(uint256){
        return _compatibleGasTokens[gasToken];
    }

    /**
    * @dev deploys a gsve smart wrapper for the caller
    * the ownership of the wrapper is transfered to the caller
    * a note is made of where the users wrapper is deployed
    * gas tokens can be burned to save on this deployment operation
    * the gas tokens that the deployer supports are enabled in the wrapper before transfering ownership.
    */
  function deployGSVESmartWrapper(address gasToken)  public discountGas(gasToken){
        address contractAddress = Clones.clone(smartWrapperLocation);
        IGSVESmartWrapper(payable(contractAddress)).init(address(this), GSVEToken);

        for(uint256 i = 0; i<_totalSupportedTokens; i++){
            address tokenAddress = _reverseTokenMap[i];
            IGSVESmartWrapper(payable(contractAddress)).addGasToken(tokenAddress, _freeUpValue[tokenAddress]);
        }
        IGSVESmartWrapper(payable(contractAddress)).setInited();
        Ownable(contractAddress).transferOwnership(msg.sender);
        _deployedWalletAddressLocation[msg.sender] = contractAddress;
    }

}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

/**
* @dev interface for v1 gsve smart wrapper
*/
interface  IGSVESmartWrapper{

    receive() external payable;
    
     /**
    * @dev sets the contract as inited
    */
    function setInited() external;

    /**
    * @dev function to enable gas tokens.
    * by default the wrapped tokens are added when the wrapper is deployed
    * using efficiency values based on a known token gas rebate that we store on contract.
    * DANGER: adding unvetted gas tokens that aren't supported by the protocol could be bad!
    */
    function addGasToken(address gasToken, uint256 freeUpValue) external;

    /**
    * @dev checks if the gas token is supported
    */
    function compatibleGasToken(address gasToken) external view returns(uint256);

    /**
    * @dev the wrapTransaction function interacts with other smart contracts on the users behalf
    * this wrapper works for any smart contract
    * as long as the dApp/smart contract the wrapper is interacting with has the correct approvals for balances within this wrapper
    * if the function requires a payment, this is handled too and sent from the wrapper balance.
    */
    function wrapTransaction(bytes calldata data, address contractAddress, uint256 value, address gasToken) external;

    /**
    * @dev function that the user can trigger to withdraw the entire balance of their wrapper back to themselves.
    */
    function withdrawBalance() external;

    /**
    * @dev function that the user can trigger to withdraw an entire token balance from the wrapper to themselves
    */
    function withdrawTokenBalance(address token) external;

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function init (address initialOwner, address _GSVEToken) external;

    /**
     * @dev Returns the address of the current owner.
     */

    function owner() external view returns (address);
    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() external;

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) external;

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
    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
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

pragma solidity ^0.8.0;

/**
 * @dev https://eips.ethereum.org/EIPS/eip-1167[EIP 1167] is a standard for
 * deploying minimal proxy contracts, also known as "clones".
 *
 * > To simply and cheaply clone contract functionality in an immutable way, this standard specifies
 * > a minimal bytecode implementation that delegates all calls to a known, fixed address.
 *
 * The library includes functions to deploy a proxy using either `create` (traditional deployment) or `create2`
 * (salted deterministic deployment). It also includes functions to predict the addresses of clones deployed using the
 * deterministic method.
 *
 * _Available since v3.4._
 */
library Clones {
    /**
     * @dev Deploys and returns the address of a clone that mimics the behaviour of `implementation`.
     *
     * This function uses the create opcode, which should never revert.
     */
    function clone(address implementation) internal returns (address instance) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create(0, ptr, 0x37)
        }
        require(instance != address(0), "ERC1167: create failed");
    }

    /**
     * @dev Deploys and returns the address of a clone that mimics the behaviour of `implementation`.
     *
     * This function uses the create2 opcode and a `salt` to deterministically deploy
     * the clone. Using the same `implementation` and `salt` multiple time will revert, since
     * the clones cannot be deployed twice at the same address.
     */
    function cloneDeterministic(address implementation, bytes32 salt) internal returns (address instance) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create2(0, ptr, 0x37, salt)
        }
        require(instance != address(0), "ERC1167: create2 failed");
    }

    /**
     * @dev Computes the address of a clone deployed using {Clones-cloneDeterministic}.
     */
    function predictDeterministicAddress(address implementation, bytes32 salt, address deployer) internal pure returns (address predicted) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf3ff00000000000000000000000000000000)
            mstore(add(ptr, 0x38), shl(0x60, deployer))
            mstore(add(ptr, 0x4c), salt)
            mstore(add(ptr, 0x6c), keccak256(ptr, 0x37))
            predicted := keccak256(add(ptr, 0x37), 0x55)
        }
    }

    /**
     * @dev Computes the address of a clone deployed using {Clones-cloneDeterministic}.
     */
    function predictDeterministicAddress(address implementation, bytes32 salt) internal view returns (address predicted) {
        return predictDeterministicAddress(implementation, salt, address(this));
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

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

{
  "remappings": [],
  "optimizer": {
    "enabled": true,
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