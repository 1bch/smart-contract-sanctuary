//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.2;

import "@openzeppelin/contracts-upgradeable/access/OwnableUpgradeable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";
import "./PetInfoType.sol";

contract IDetopiaPetNFTToken {
    function mintNewNFT(address to) public returns (uint256) {}
}

contract DetopiaPetDataProvider is OwnableUpgradeable {
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIds;

    uint8 constant PART_COUNT = 11;

    address public pet_nft_address;

    mapping(uint256 => PetInfo) _petInfos;
    mapping(uint256 => PetGenesInfo) _petGenes;

    function initialize(address pet_nft_address_param)
        public
        virtual
        initializer
    {
        __Ownable_init();
        pet_nft_address = pet_nft_address_param;
    }

    function petInfo(uint256 tokenId)
        public
        view
        virtual
        returns (PetInfo memory)
    {
        require(_petInfos[tokenId].existed == 1, "Pet not existed");
        return _petInfos[tokenId];
    }

    function petGenesInfo(uint256 tokenId)
        public
        view
        virtual
        returns (PetGenesPart[] memory)
    {
        require(_petGenes[tokenId].existed == 1, "Pet not existed");
        PetGenesPart[] memory genes = new PetGenesPart[](
            _petGenes[tokenId].gene_count
        );
        for (uint8 i = 0; i < _petGenes[tokenId].gene_count; i++)
            genes[i] = _petGenes[tokenId].genes[i];
        return genes;
    }

    function setPetGenesInfo(uint256 tokenId, PetGenesPart[] calldata genesParts)
        public
        onlyOwner
    {
        require(_petInfos[tokenId].existed == 1, "Pet not existed");
        
        PetGenesInfo storage genesInfo = _petGenes[tokenId];
        uint8 count = 0;
        for (uint i = 0; i < genesParts.length; i++) {
            genesInfo.genes[count++] = genesParts[i];
        }
        genesInfo.gene_count = count;
        genesInfo.existed = 1;
    }

    function totalSupply() public view virtual returns (uint256) {
        return _tokenIds.current();
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/ContextUpgradeable.sol";
import "../proxy/utils/Initializable.sol";

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
abstract contract OwnableUpgradeable is Initializable, ContextUpgradeable {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    function __Ownable_init() internal initializer {
        __Context_init_unchained();
        __Ownable_init_unchained();
    }

    function __Ownable_init_unchained() internal initializer {
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
    uint256[49] private __gap;
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
library Counters {
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

//SPDX-License-Identifier: Unlicense
pragma solidity 0.8.2;

enum PET_CLASS {
    UNKNOWN,
    B,
    A,
    S,
    SR,
    SSR
}

enum PET_TRIBE {
    UNKNOWN,
    NORMAL,
    ELECTRIC,
    WATER,
    FIRE,
    ICE,
    EARTH,
    DARK,
    LIGHT,
    CAT
}

struct PetInfo {
    uint8 existed;
    uint256 token_id;
    PET_CLASS pet_class;
    PET_TRIBE pet_tribe;
    uint16 level;
    string name;
    PetParts parts;
    PetStats stats;
}

struct PetParts {
    uint16 body;
    uint16 eye;
    uint16 eyelid;
    uint16 mouth;
    uint16 hair;
    uint16 left_head;
    uint16 right_head;
    uint16 left_arm;
    uint16 right_arm;
    uint16 left_leg;
    uint16 right_leg;
}

struct PetStats {
    uint16 atk;
    uint16 def;
    uint16 hp;
    uint16 speed;
    uint16 cridmg;
    uint16 crirate;
}

struct PetGenesPart {
    uint16 part_id;
    uint8 rate;
    uint8 part_type;
}

struct PetGenesInfo {
    uint8 existed;
    mapping(uint8 => PetGenesPart) genes;
    uint8 gene_count;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "../proxy/utils/Initializable.sol";

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
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal initializer {
        __Context_init_unchained();
    }

    function __Context_init_unchained() internal initializer {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
    uint256[50] private __gap;
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
        require(_initializing || !_initialized, "Initializable: contract is already initialized");

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