// SPDX-License-Identifier: MIT
pragma solidity >=0.4.22 <0.9.0;

interface IERC1155 {
  function safeTransferFrom(address from,address to,uint256 id,uint256 amount,bytes calldata data) external;
  function balanceOf(address account, uint256 id) external view returns (uint256);
}

contract MKBoxesBatchSend {

  IERC1155 constant public tmk = IERC1155(0xd119648D817122BB7885ed02Fc1350942c3991eC);

  function batchSend(address[] memory accounts, uint256[] memory ids) public {
    require(accounts.length == ids.length,"Wrong data");
    uint256 count = accounts.length;
    for(uint256 i = 0;i<count;i++){
      if(tmk.balanceOf(msg.sender, ids[i]) >= 1){
        tmk.safeTransferFrom(msg.sender,accounts[i],ids[i],1,"");
      }
    }
  }

  function batchSendWithAmounts(address[] memory accounts, uint256[] memory ids,uint256[] memory amounts) public {
    require(accounts.length == ids.length && accounts.length == amounts.length,"Wrong data");
    uint256 count = accounts.length;
    for(uint256 i = 0;i<count;i++){
      if(tmk.balanceOf(msg.sender, ids[i]) >= amounts[i]){
        tmk.safeTransferFrom(msg.sender,accounts[i],ids[i],amounts[i],"");
      }
    }
  }

  function sendOneToAll(address[] memory accounts, uint256 id) public {
    uint256 count = accounts.length;
    require(tmk.balanceOf(msg.sender, id) >= count,"You don't have that many tokens");
    for(uint256 i = 0;i<count;i++){
      tmk.safeTransferFrom(msg.sender,accounts[i],id,1,"");
    }
  }

  function sendOneToAllWithAmounts(address[] memory accounts,uint256[] memory amounts, uint256 id) public {
    require(accounts.length == amounts.length,"Wrong data");
    uint256 count = accounts.length;
    for(uint256 i = 0;i<count;i++){
      if(tmk.balanceOf(msg.sender, id) >= amounts[i]){
        tmk.safeTransferFrom(msg.sender,accounts[i],id,amounts[i],"");
      }
    }
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