// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "@openzeppelin/contracts/access/Ownable.sol";
import "../interfaces/IIVProvider.sol";

/**
 * @title IVProvider
 * @author Pods Finance
 * @notice Storage of implied volatility oracles
 */
contract IVProvider is IIVProvider, Ownable {
    mapping(address => IVData) private _answers;

    mapping(address => uint256) private _lastIds;

    address public updater;

    modifier isUpdater() {
        require(msg.sender == updater, "IVProvider: sender must be an updater");
        _;
    }

    function getIV(address option)
        external
        override
        view
        returns (
            uint256,
            uint256,
            uint256,
            uint8
        )
    {
        IVData memory data = _answers[option];
        return (data.roundId, data.updatedAt, data.answer, data.decimals);
    }

    function updateIV(
        address option,
        uint256 answer,
        uint8 decimals
    ) external override isUpdater {
        uint256 lastRoundId = _lastIds[option];
        uint256 roundId = ++lastRoundId;

        _lastIds[option] = roundId;
        _answers[option] = IVData(roundId, block.timestamp, answer, decimals);

        emit UpdatedIV(option, roundId, block.timestamp, answer, decimals);
    }

    function setUpdater(address _updater) external override onlyOwner {
        updater = _updater;
        emit UpdaterSet(msg.sender, updater);
    }
}

pragma solidity ^0.6.0;

import "../GSN/Context.sol";
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
contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor () internal {
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

// SPDX-License-Identifier: agpl-3.0

pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

interface IIVProvider {
    struct IVData {
        uint256 roundId;
        uint256 updatedAt;
        uint256 answer;
        uint8 decimals;
    }

    event UpdatedIV(address indexed option, uint256 roundId, uint256 updatedAt, uint256 answer, uint8 decimals);
    event UpdaterSet(address indexed admin, address indexed updater);

    function getIV(address option)
        external
        view
        returns (
            uint256 roundId,
            uint256 updatedAt,
            uint256 answer,
            uint8 decimals
        );

    function updateIV(
        address option,
        uint256 answer,
        uint8 decimals
    ) external;

    function setUpdater(address updater) external;
}

pragma solidity ^0.6.0;

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
contract Context {
    // Empty internal constructor, to prevent people from mistakenly deploying
    // an instance of this contract, which should be used via inheritance.
    constructor () internal { }

    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

{
  "optimizer": {
    "enabled": true,
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