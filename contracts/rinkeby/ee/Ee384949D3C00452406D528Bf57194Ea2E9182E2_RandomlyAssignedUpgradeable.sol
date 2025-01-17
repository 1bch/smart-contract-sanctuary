// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "./WithLimitedSupplyUpgradeable.sol";
import "./IRandomlyAssignedUpgradeable.sol";

/// @author 1001.digital
/// @title Randomly assign tokenIDs from a given set of tokens.
contract RandomlyAssignedUpgradeable is
    WithLimitedSupplyUpgradeable,
    IRandomlyAssignedUpgradeable
{
    // Used for random index assignment
    mapping(uint256 => uint256) private tokenMatrix;

    // The initial token ID
    uint256 private startFrom;

    function initialize(uint256 _maxSupply, uint256 _startFrom)
        public
        initializer
    {
        __RandomlyAssigned_init(_maxSupply, _startFrom);
    }

    // @param _maxSupply how many tokens this collection should hold
    // @param _startFrom the tokenID with which to start counting
    function __RandomlyAssigned_init(uint256 _maxSupply, uint256 _startFrom)
        internal
        initializer
    {
        __WithLimitedSupply_init(_maxSupply);
        __RandomlyAssigned_init_unchain(_startFrom);
    }

    function __RandomlyAssigned_init_unchain(uint256 _startFrom)
        internal
        initializer
    {
        startFrom = _startFrom;
    }

    /// Get the next token ID
    /// @dev Randomly gets a new token ID and keeps track of the ones that are still available.
    /// @return the next token ID
    function _nextToken()
        internal
        override
        ensureAvailability
        returns (uint256)
    {
        uint256 maxIndex = maxSupply() - tokenCount();
        uint256 random = uint256(
            keccak256(
                abi.encodePacked(
                    msg.sender,
                    block.coinbase,
                    block.difficulty,
                    block.gaslimit,
                    block.timestamp
                )
            )
        ) % maxIndex;

        uint256 value = 0;
        if (tokenMatrix[random] == 0) {
            // If this matrix position is empty, set the value to the generated random number.
            value = random;
        } else {
            // Otherwise, use the previously stored number from the matrix.
            value = tokenMatrix[random];
        }

        // If the last available tokenID is still unused...
        if (tokenMatrix[maxIndex - 1] == 0) {
            // ...store that ID in the current matrix position.
            tokenMatrix[random] = maxIndex - 1;
        } else {
            // ...otherwise copy over the stored number to the current matrix position.
            tokenMatrix[random] = tokenMatrix[maxIndex - 1];
        }

        // Increment counts
        super._nextToken();

        return value + startFrom;
    }

    function nextTokenId() public override returns (uint256) {
        return _nextToken();
    }

    function getMaxSupply() public view override returns (uint256) {
        return maxSupply();
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import "../../../openzeppelin-contracts-upgradeable/contracts/utils/CountersUpgradeable.sol";
import "../../../openzeppelin-contracts-upgradeable/contracts/proxy/utils/Initializable.sol";

/// @author 1001.digital
/// @title A token tracker that limits the token supply and increments token IDs on each new mint.
abstract contract WithLimitedSupplyUpgradeable is Initializable {
    using CountersUpgradeable for CountersUpgradeable.Counter;

    // Keeps track of how many we have minted
    CountersUpgradeable.Counter private _tokenCount;

    /// @dev The maximum count of tokens this token tracker will hold.
    uint256 private _maxSupply;

    // @param maxSupply_ how many tokens this collection should hold
    function __WithLimitedSupply_init(uint256 maxSupply_) internal initializer {
        __WithLimitedSupply_init_unchained(maxSupply_);
    }

    function __WithLimitedSupply_init_unchained(uint256 maxSupply_)
        internal
        initializer
    {
        _maxSupply = maxSupply_;
    }

    /// @dev Get the max Supply
    /// @return the maximum token count
    function maxSupply() public view returns (uint256) {
        return _maxSupply;
    }

    /// @dev Get the current token count
    /// @return the created token count
    function tokenCount() public view returns (uint256) {
        return _tokenCount.current();
    }

    /// @dev Check whether tokens are still available
    /// @return the available token count
    function availableTokenCount() public view returns (uint256) {
        return maxSupply() - tokenCount();
    }

    /// @dev Increment the token count and fetch the latest count
    /// @return the next token id
    function _nextToken()
        internal
        virtual
        ensureAvailability
        returns (uint256)
    {
        uint256 token = _tokenCount.current();

        _tokenCount.increment();

        return token;
    }

    /// @dev Check whether another token is still available
    modifier ensureAvailability() {
        require(availableTokenCount() > 0, "No more tokens available");
        _;
    }

    /// @param amount Check whether number of tokens are still available
    /// @dev Check whether tokens are still available
    modifier ensureAvailabilityFor(uint256 amount) {
        require(
            availableTokenCount() >= amount,
            "Requested number of tokens not available"
        );
        _;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IRandomlyAssignedUpgradeable {
    function nextTokenId() external returns (uint256 tokenId);

    function getMaxSupply() external returns (uint256 maxSupply);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title Counters
 * @author Matt Condon (@shrugs)
 * @dev Provides counters that can only be incremented, decremented or reset. This can be used e.g. to track the number
 * of elements in a mapping, issuing ERC721 ids, or counting request ids.
 *
 * Include with `using Counters for Counters.Counter;`
 */
library CountersUpgradeable {
    struct Counter {
        // This variable should never be directly accessed by users of the library: interactions must be restricted to
        // the library's function. As of Solidity v0.5.2, this cannot be enforced, though there is a proposal to add
        // this feature: see https://github.com/ethereum/solidity/issues/4637
        uint256 _value; // default: 0
    }

    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    function increment(Counter storage counter) internal {
        unchecked {
            counter._value += 1;
        }
    }

    function decrement(Counter storage counter) internal {
        uint256 value = counter._value;
        require(value > 0, "Counter: decrement overflow");
        unchecked {
            counter._value = value - 1;
        }
    }

    function reset(Counter storage counter) internal {
        counter._value = 0;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since a proxied contract can't have a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 */
abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     */
    bool private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Modifier to protect an initializer function from being invoked twice.
     */
    modifier initializer() {
        require(
            _initializing || !_initialized,
            "Initializable: contract is already initialized"
        );

        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }

        _;

        if (isTopLevelCall) {
            _initializing = false;
        }
    }
}

{
  "optimizer": {
    "enabled": true,
    "runs": 150
  },
  "outputSelection": {
    "*": {
      "*": [
        "evm.bytecode",
        "evm.deployedBytecode",
        "devdoc",
        "userdoc",
        "metadata",
        "abi"
      ]
    }
  },
  "libraries": {}
}