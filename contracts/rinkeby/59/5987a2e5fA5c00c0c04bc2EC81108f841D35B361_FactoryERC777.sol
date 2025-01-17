// //SPDX-License-Identifier: MIT
// pragma solidity ^0.8.0;

// import "../token/ERC777/ERC777Burnable.sol";
// import "../token/ERC777/ERC777Mintable.sol";

// import "../token/ERC777/ERC777FixedSupply.sol";

// contract FactoryERC777 {
//   ERC777FixedSupply[] private childrenErc777FixedSuplly;
//   ERC777Mintable[] private childrenErc777Mintable;
//   ERC777Burnable[] private childrenErc777Burnable;

//   enum Types {
//     none,
//     erc777,
//     erc777Burnable,
//     erc777Mintable
//   }

//   function createChild(
//     Types types,
//     string memory name,
//     uint8 decimal,
//     string memory symbol,
//     uint256 initialSupply,
//     uint256 cap
//   ) external {
//     if (types == Types.erc777) {
//       ERC777FixedSupply child = new ERC777FixedSupply(
//         name,
//         symbol,
//         decimal,
//         initialSupply,
//         msg.sender
//       );
//       childrenErc777FixedSuplly.push(child);
//     }

//     if (types == Types.erc777Mintable) {
//       ERC777Mintable child = new ERC777Mintable(
//         name,
//         symbol,
//         decimal,
//         initialSupply,
//         cap,
//         msg.sender
//       );
//       childrenErc777Mintable.push(child);
//     }

//     if(types == Types.erc777Burnable) {
//         ERC777Burnable child = new ERC777Burnable(
//         name,
//         symbol,
//         decimal,
//         initialSupply,
//         msg.sender
//       );
//       childrenErc777Burnable.push(child);
//       }
//   }
// }

pragma solidity ^0.8.0;

import '../token/ERC777/ERC777.sol';
import '../token/ERC777/ERC777Mintable.sol';
import './CloneFactory.sol';
import './../libraries/Ownable.sol';

contract FactoryERC777 is CloneFactory, Ownable {
  address private _owner;

  ERC777[] public children;
  address private tokenOwner;
  address masterContract;

  // constructor(address _tokenOwner) {
  //   tokenOwner = _tokenOwner;
  // }

  function setMasterContract(address _masterContract) external onlyOwner {
    masterContract = _masterContract;
  }

  function createERC777(
    uint256 initialSupply,
    string memory tokenName,
    uint8 decimalUnits,
    string memory tokenSymbol
  ) external {
    ERC777 child = ERC777(createClone(masterContract));
    child.initialize(
      _owner,
      initialSupply,
      tokenName,
      decimalUnits,
      tokenSymbol
    );
    children.push(child);
  }

  function getChildren() external view returns (address owner, address token) {
    if (children.length > 0) {
      return (address(_owner), address(children[children.length - 1]));
    }
    return (address(_owner), address(children[0]));
  }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./interfaces/IERC777.sol";
import "./IERC777Recipient.sol";
import "./IERC777Sender.sol";
import "./interfaces/IERC20.sol";
import "./Address.sol";
import "../../libraries/Context.sol";
import "./introspection/IERC1820Registry.sol";

contract ERC777 is Context, IERC777, IERC20 {
  using Address for address;

  IERC1820Registry internal constant _ERC1820_REGISTRY =
    IERC1820Registry(0x1820a4B7618BdE71Dce8cdc73aAB6C95905faD24);

  mapping(address => uint256) public _balances;

  uint256 public _totalSupply;

  string private _name;
  string private _symbol;
  uint8 private _decimal;

  bytes32 private constant _TOKENS_SENDER_INTERFACE_HASH =
    keccak256("ERC777TokensSender");
  bytes32 private constant _TOKENS_RECIPIENT_INTERFACE_HASH =
    keccak256("ERC777TokensRecipient");

  // This isn't ever read from - it's only used to respond to the defaultOperators query.
  address[] private _defaultOperatorsArray;

  // Immutable, but accounts may revoke them (tracked in __revokedDefaultOperators).
  mapping(address => bool) private _defaultOperators;

  // For each account, a mapping of its operators and revoked default operators.
  mapping(address => mapping(address => bool)) private _operators;
  mapping(address => mapping(address => bool)) private _revokedDefaultOperators;

  mapping(address => mapping(address => uint256)) private _allowances;

  constructor(
    string memory name_,
    string memory symbol_,
    address[] memory defaultOperators_,
    uint8 decimal_
  ) {
    _name = name_;
    _symbol = symbol_;
    _decimal = decimal_;

    _defaultOperatorsArray = defaultOperators_;
    for (uint256 i = 0; i < defaultOperators_.length; i++) {
      _defaultOperators[defaultOperators_[i]] = true;
    }

    // register interfaces
    _ERC1820_REGISTRY.setInterfaceImplementer(
      address(this),
      keccak256("ERC777Token"),
      address(this)
    );
    _ERC1820_REGISTRY.setInterfaceImplementer(
      address(this),
      keccak256("ERC20Token"),
      address(this)
    );
  }

  function initialize(
    address owner,
    uint256 initialSupply,
    string memory tokenName,
    uint8 decimalUnits,
    string memory tokenSymbol
  ) public {
    _totalSupply = initialSupply * 10**uint256(decimalUnits);
    _balances[owner] = _totalSupply;
    _name = tokenName;
    _decimal = decimalUnits;
    _symbol = tokenSymbol;
    emit Transfer(address(0), msg.sender, _totalSupply);
  }

  function name() public view virtual override returns (string memory) {
    return _name;
  }

  function symbol() public view virtual override returns (string memory) {
    return _symbol;
  }

  function decimals() public view virtual returns (uint8) {
    return _decimal;
  }

  function granularity() public view virtual override returns (uint256) {
    return 1;
  }

  function totalSupply() public view virtual override returns (uint256) {
    return _totalSupply;
  }

  function balanceOf(address tokenHolder)
    public
    view
    virtual
    override
    returns (uint256)
  {
    return _balances[tokenHolder];
  }

  function send(
    address recipient,
    uint256 amount,
    bytes memory data
  ) public virtual override {
    _send(_msgSender(), recipient, amount, data, "", true);
  }

  function transfer(address recipient, uint256 amount)
    public
    virtual
    returns (bool)
  {
    require(recipient != address(0), "ERC777: transfer to the zero address");

    address from = _msgSender();

    _callTokensToSend(from, from, recipient, amount, "", "");

    _move(from, from, recipient, amount, "", "");

    _callTokensReceived(from, from, recipient, amount, "", "", false);

    return true;
  }

  function isOperatorFor(address operator, address tokenHolder)
    public
    view
    virtual
    override
    returns (bool)
  {
    return
      operator == tokenHolder ||
      (_defaultOperators[operator] &&
        !_revokedDefaultOperators[tokenHolder][operator]) ||
      _operators[tokenHolder][operator];
  }

  function authorizeOperator(address operator) public virtual override {
    require(_msgSender() != operator, "ERC777: authorizing self as operator");

    if (_defaultOperators[operator]) {
      delete _revokedDefaultOperators[_msgSender()][operator];
    } else {
      _operators[_msgSender()][operator] = true;
    }

    emit AuthorizedOperator(operator, _msgSender());
  }

  function revokeOperator(address operator) public virtual override {
    require(operator != _msgSender(), "ERC777: revoking self as operator");

    if (_defaultOperators[operator]) {
      _revokedDefaultOperators[_msgSender()][operator] = true;
    } else {
      delete _operators[_msgSender()][operator];
    }

    emit RevokedOperator(operator, _msgSender());
  }

  function defaultOperators()
    public
    view
    virtual
    override
    returns (address[] memory)
  {
    return _defaultOperatorsArray;
  }

  function operatorSend(
    address sender,
    address recipient,
    uint256 amount,
    bytes memory data,
    bytes memory operatorData
  ) public virtual override {
    require(
      isOperatorFor(_msgSender(), sender),
      "ERC777: caller is not an operator for holder"
    );
    _send(sender, recipient, amount, data, operatorData, true);
  }

  function allowance(address holder, address spender)
    public
    view
    virtual
    returns (uint256)
  {
    return _allowances[holder][spender];
  }

  function approve(address spender, uint256 value)
    public
    virtual
    returns (bool)
  {
    address holder = _msgSender();
    _approve(holder, spender, value);
    return true;
  }

  function transferFrom(
    address holder,
    address recipient,
    uint256 amount
  ) public virtual returns (bool) {
    require(recipient != address(0), "ERC777: transfer to the zero address");
    require(holder != address(0), "ERC777: transfer from the zero address");

    address spender = _msgSender();

    _callTokensToSend(spender, holder, recipient, amount, "", "");

    _move(spender, holder, recipient, amount, "", "");

    uint256 currentAllowance = _allowances[holder][spender];
    require(
      currentAllowance >= amount,
      "ERC777: transfer amount exceeds allowance"
    );
    _approve(holder, spender, currentAllowance - amount);

    _callTokensReceived(spender, holder, recipient, amount, "", "", false);

    return true;
  }

  function _mint(
    address account,
    uint256 amount,
    bytes memory userData,
    bytes memory operatorData
  ) internal virtual {
    _mint(account, amount, userData, operatorData, true);
  }

  function _mint(
    address account,
    uint256 amount,
    bytes memory userData,
    bytes memory operatorData,
    bool requireReceptionAck
  ) internal virtual {
    require(account != address(0), "ERC777: mint to the zero address");

    address operator = _msgSender();

    _beforeTokenTransfer(operator, address(0), account, amount);

    // Update state variables
    _totalSupply += amount;
    _balances[account] += amount;

    _callTokensReceived(
      operator,
      address(0),
      account,
      amount,
      userData,
      operatorData,
      requireReceptionAck
    );

    emit Minted(operator, account, amount, userData, operatorData);
    emit Transfer(address(0), account, amount);
  }

  function _send(
    address from,
    address to,
    uint256 amount,
    bytes memory userData,
    bytes memory operatorData,
    bool requireReceptionAck
  ) internal virtual {
    require(from != address(0), "ERC777: send from the zero address");
    require(to != address(0), "ERC777: send to the zero address");

    address operator = _msgSender();

    _callTokensToSend(operator, from, to, amount, userData, operatorData);

    _move(operator, from, to, amount, userData, operatorData);

    _callTokensReceived(
      operator,
      from,
      to,
      amount,
      userData,
      operatorData,
      requireReceptionAck
    );
  }

  function _burn(
    address from,
    uint256 amount,
    bytes memory data,
    bytes memory operatorData
  ) internal virtual {
    require(from != address(0), "ERC777: burn from the zero address");

    address operator = _msgSender();

    _callTokensToSend(operator, from, address(0), amount, data, operatorData);

    _beforeTokenTransfer(operator, from, address(0), amount);

    // Update state variables
    uint256 fromBalance = _balances[from];
    require(fromBalance >= amount, "ERC777: burn amount exceeds balance");
    unchecked {
      _balances[from] = fromBalance - amount;
    }
    _totalSupply -= amount;

    emit Burned(operator, from, amount, data, operatorData);
    emit Transfer(from, address(0), amount);
  }

  function _move(
    address operator,
    address from,
    address to,
    uint256 amount,
    bytes memory userData,
    bytes memory operatorData
  ) private {
    _beforeTokenTransfer(operator, from, to, amount);

    uint256 fromBalance = _balances[from];
    require(fromBalance >= amount, "ERC777: transfer amount exceeds balance");
    unchecked {
      _balances[from] = fromBalance - amount;
    }
    _balances[to] += amount;

    emit Sent(operator, from, to, amount, userData, operatorData);
    emit Transfer(from, to, amount);
  }

  function _approve(
    address holder,
    address spender,
    uint256 value
  ) internal {
    require(holder != address(0), "ERC777: approve from the zero address");
    require(spender != address(0), "ERC777: approve to the zero address");

    _allowances[holder][spender] = value;
    emit Approval(holder, spender, value);
  }

  function _callTokensToSend(
    address operator,
    address from,
    address to,
    uint256 amount,
    bytes memory userData,
    bytes memory operatorData
  ) private {
    address implementer = _ERC1820_REGISTRY.getInterfaceImplementer(
      from,
      _TOKENS_SENDER_INTERFACE_HASH
    );
    if (implementer != address(0)) {
      IERC777Sender(implementer).tokensToSend(
        operator,
        from,
        to,
        amount,
        userData,
        operatorData
      );
    }
  }

  function _callTokensReceived(
    address operator,
    address from,
    address to,
    uint256 amount,
    bytes memory userData,
    bytes memory operatorData,
    bool requireReceptionAck
  ) private {
    address implementer = _ERC1820_REGISTRY.getInterfaceImplementer(
      to,
      _TOKENS_RECIPIENT_INTERFACE_HASH
    );
    if (implementer != address(0)) {
      IERC777Recipient(implementer).tokensReceived(
        operator,
        from,
        to,
        amount,
        userData,
        operatorData
      );
    } else if (requireReceptionAck) {
      require(
        !to.isContract(),
        "ERC777: token recipient contract has no implementer for ERC777TokensRecipient"
      );
    }
  }

  function _beforeTokenTransfer(
    address operator,
    address from,
    address to,
    uint256 amount
  ) internal virtual {}
}

// // SPDX-License-Identifier: MIT
// pragma solidity ^0.8.0;

// import "./ERC777.sol";

// contract ERC777Mintable is ERC777 {
  
//   uint256 private _cap;

//   constructor(
//     string memory name,
//     string memory symbol,
//     uint8 decimal,
//     uint256 initialSupply,
//     uint256 cap_,
//     address owner
//   ) ERC777(name, symbol, new address[](0), decimal) {
//     _cap = cap_ * 10 ** uint8(decimal);
//     _mint(owner, initialSupply, "", "");
//     _totalSupply = initialSupply * 10**uint8(decimal);
//     _balances[owner] = _totalSupply;
//   }

//   function mint(
//     address account,
//     uint256 amount,
//     bytes memory userData,
//     bytes memory operatorData
//   ) public returns (bool) {
//     _mint(account, amount, userData, operatorData);
//     return true;
//   }

//   function cap() public view virtual returns (uint256) {
//     return _cap;
//   }

//   function _mint(address account, uint256 amount, bytes memory userData, bytes memory operatorData) internal virtual override {
//     require(ERC777.totalSupply() + amount <= cap(), "ERC777Capped: cap exceeded");
//     super._mint(account, amount, userData, operatorData);
//   }
// }

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;



contract CloneFactory {
    function createClone(address target) internal returns (address result) {
        bytes20 targetBytes = bytes20(target);
        assembly {
            let clone := mload(0x40)
            mstore(
                clone,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(clone, 0x14), targetBytes)
            mstore(
                add(clone, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            result := create(0, clone, 0x37)
        }
    }

    function isClone(address target, address query)
        internal
        view
        returns (bool result)
    {
        bytes20 targetBytes = bytes20(target);
        assembly {
            let clone := mload(0x40)
            mstore(
                clone,
                0x363d3d373d3d3d363d7300000000000000000000000000000000000000000000
            )
            mstore(add(clone, 0xa), targetBytes)
            mstore(
                add(clone, 0x1e),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )

            let other := add(clone, 0x40)
            extcodecopy(query, other, 0, 0x2d)
            result := and(
                eq(mload(clone), mload(other)),
                eq(mload(add(clone, 0xd)), mload(add(other, 0xd)))
            )
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import './Context.sol';

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

  event OwnershipTransferred(
    address indexed previousOwner,
    address indexed newOwner
  );

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
    require(owner() == _msgSender(), 'Ownable: caller is not the owner');
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
    require(newOwner != address(0), 'Ownable: new owner is the zero address');
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

interface IERC777 {
  function name() external view returns (string memory);

  function symbol() external view returns (string memory);

  function granularity() external view returns (uint256);

  function totalSupply() external view returns (uint256);

  function balanceOf(address owner) external view returns (uint256);

  function send(
    address recipient,
    uint256 amount,
    bytes calldata data
  ) external;

  function isOperatorFor(address operator, address tokenHolder)
    external
    view
    returns (bool);

  function authorizeOperator(address operator) external;

  function revokeOperator(address operator) external;

  function defaultOperators() external view returns (address[] memory);

  function operatorSend(
    address sender,
    address recipient,
    uint256 amount,
    bytes calldata data,
    bytes calldata operatorData
  ) external;

  event Sent(
    address indexed operator,
    address indexed from,
    address indexed to,
    uint256 amount,
    bytes data,
    bytes operatorData
  );

  event Minted(
    address indexed operator,
    address indexed to,
    uint256 amount,
    bytes data,
    bytes operatorData
  );

  event Burned(
    address indexed operator,
    address indexed from,
    uint256 amount,
    bytes data,
    bytes operatorData
  );

  event AuthorizedOperator(
    address indexed operator,
    address indexed tokenHolder
  );

  event RevokedOperator(address indexed operator, address indexed tokenHolder);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


interface IERC777Recipient {
    function tokensReceived(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;


interface IERC777Sender {
    function tokensToSend(
        address operator,
        address from,
        address to,
        uint256 amount,
        bytes calldata userData,
        bytes calldata operatorData
    ) external;
}

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

interface IERC20 {
  
  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);
}

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

library Address {
  function isContract(address account) internal view returns (bool) {
    uint256 size;
    assembly {
      size := extcodesize(account)
    }
    return size > 0;
  }
}

//SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract Context {
  function _msgSender() internal view virtual returns (address) {
    return msg.sender;
  }

  function _msgData() internal view virtual returns (bytes calldata) {
    return msg.data;
  }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

interface IERC1820Registry {
  function setManager(address account, address newManager) external;

  function getManager(address account) external view returns (address);

  function setInterfaceImplementer(
    address account,
    bytes32 _interfaceHash,
    address implementer
  ) external;

  function getInterfaceImplementer(address account, bytes32 _interfaceHash)
    external
    view
    returns (address);

  function interfaceHash(string calldata interfaceName)
    external
    pure
    returns (bytes32);

  function updateERC165Cache(address account, bytes4 interfaceId) external;

  function implementsERC165Interface(address account, bytes4 interfaceId)
    external
    view
    returns (bool);

  function implementsERC165InterfaceNoCache(address account, bytes4 interfaceId)
    external
    view
    returns (bool);

  event InterfaceImplementerSet(
    address indexed account,
    bytes32 indexed interfaceHash,
    address indexed implementer
  );

  event ManagerChanged(address indexed account, address indexed newManager);
}

{
  "optimizer": {
    "enabled": true,
    "runs": 1
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