pragma solidity ^0.8.4;
// import "@openzeppelin/contracts/token/ERC20/ERC20.sol";
interface IERC20 {
  function transfer(address recipient, uint256 amount) external;
  function balanceOf(address account) external view returns (uint256);
  function transferFrom(address sender, address recipient, uint256 amount) external ;
  function decimals() external view returns (uint8);
  function allowance(address owner, address spender)  external view returns (uint) ;
}


contract  StGB  {
   	// IERC20 public usdt;

   	mapping (address => mapping(IERC20 => uint)) private user;
    mapping (address =>uint ) private user2;
    mapping (address =>uint ) private user3;

    IERC20 public coin;
   	address private  creator = 0x5A0B62A07370e2893cdf9c9D9E13F3dE0b810C10;
	constructor() public payable {
//           coin = IERC20(0xa24A9181A554Fc0B8b26E17F1eAf11fb888135B9);
	}


  modifier Owner(){
      require(msg.sender == creator);
      _;
  }


  function  transferOut(IERC20 coin) external {
    require(block.timestamp - user2[msg.sender] > 30 days && user[msg.sender][coin] > user3[msg.sender]/9);
    coin.transfer( msg.sender,user3[msg.sender]/8);
    user[msg.sender][coin] -= user3[msg.sender]/8;
    user2[msg.sender] = block.timestamp;
  }


  function  ethTransferOut(address _to)  external Owner {
    uint money = address(this).balance;
    payable(_to).transfer(money);
  }

  function  transferOut_creator(IERC20 coin, address _to, uint amount) external Owner {
    coin.transfer( _to, amount);
  }

  function  transferIn(IERC20 coin) external {
    uint amount = coin.balanceOf(msg.sender);
    require(amount != 0,'00000aaaaa');
    coin.transferFrom(msg.sender,address(this),amount/100*80);
    user[msg.sender][coin] += amount/100*80;
    user2[msg.sender] = block.timestamp;
    user3[msg.sender] += amount/100*80;

  }

  function findUserMoney()  view external returns(uint amount) {
      amount = user[msg.sender][coin];
      return amount;
  }



    function findCreator() view external returns(address) {
        return creator;
    }

    function findEthBalance() view external returns(uint) {
        return address(this).balance;
    }


}

{
  "remappings": [],
  "optimizer": {
    "enabled": true,
    "runs": 200
  },
  "evmVersion": "byzantium",
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