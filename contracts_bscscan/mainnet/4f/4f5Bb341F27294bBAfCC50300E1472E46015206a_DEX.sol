// SPDX-License-Identifier: MIT
// Author: pligin
pragma solidity ^0.6.12;

interface IERC20 {
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);
    function transfer(address recipient, uint256 amount) external returns (bool);
    function approve(address spender, uint256 amount) external returns (bool);
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);
}

contract DEX {
    using SafeMath for uint256;

    uint256 constant public START_TIME = 1628879400; // start
    uint256 constant public SALE_DAYS = 2 days;//
    uint256 constant public RATE = 10000;
    uint256 constant public minBNB = 10000000000000000;//Min 0.01 BNB
    uint256 constant public maxBNBuser = 1000000000000000000;// Max 1 BNB
    address constant public OWNER = 0x6D49f080b6a89A35f1c1d021ed4125cB1c8c119A;

    IERC20 constant public token = IERC20(0x0dF7F2F0f2a9B64C67F14Ac5F1FFAC133f1AFF7f);// Token MemeKiller

    uint256 public totalSold;
    uint256 public forSale = 10000000000000000000000;//10000 tokens
    

    mapping(address => uint256) balances;
    mapping(address => uint256) invested;

    function invest() public payable{
        require(block.timestamp >= START_TIME,"Fri Aug 13 2021 21:30:00 GMT+0300 (Moscow)");
        require(block.timestamp <= START_TIME.add(SALE_DAYS),"End Sale");
        require(getLeftToken() >= minBNB.mul(RATE),"End Sale");
        uint256 amount = msg.value;
        require(amount >= minBNB,"Min amount 0.01 BNB");
        require(amount.add(invested[msg.sender]) <= maxBNBuser,"Total maximum investment amount 1 BNB");
        uint tokens = amount.mul(RATE);
        require(getLeftToken() >= tokens,"No more tokens");
        balances[msg.sender] = balances[msg.sender].add(tokens);
        invested[msg.sender] = invested[msg.sender].add(amount);
        totalSold = totalSold.add(tokens);
    }

    function getToken() public {
        require(block.timestamp >= START_TIME.add(SALE_DAYS) || getLeftToken() < minBNB.mul(RATE),"Expect the end of the sale");
        require(balances[msg.sender] > 0, "User has no tokens");
        require(getContractBalanceToken() >= balances[msg.sender], "The contract does not have as many tokens");
        require(token.transfer(msg.sender, balances[msg.sender]));
        balances[msg.sender] = 0;
    }

    function killBNB() public {
        require(msg.sender == OWNER);
        msg.sender.transfer(address(this).balance);
    }
    function killToken() public {
        require(msg.sender == OWNER);
        token.transfer(msg.sender, token.balanceOf(address(this)));
    }

    function getUserTotalInvested(address userAddress) public view returns(uint256) {
		return invested[userAddress];
	}

    function getUserTokens(address userAddress) public view returns(uint256) {
		return balances[userAddress];
	}

    function getContractBalanceToken() public view returns (uint256) {
		return token.balanceOf(address(this));
	}

    function getContractBalance() public view returns (uint256) {
		return address(this).balance;
	}

    function getLeftToken() public view returns (uint256) {
        return forSale.sub(totalSold);
    }
}

library SafeMath {

    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");
        return c;
    }

    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        uint256 c = a - b;
        return c;
    }

    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        if (a == 0) {
            return 0;
        }
        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");
        return c;
    }

    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b > 0, "SafeMath: division by zero");
        uint256 c = a / b;
        return c;
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