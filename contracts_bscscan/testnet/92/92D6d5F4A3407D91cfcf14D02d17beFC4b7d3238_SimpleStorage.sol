pragma solidity ^0.8.4;

contract SimpleStorage  {
    uint data;

    function updateData(uint _data) external {
        data = _data;
    }

    function readData() external view returns(uint) {
        return data;
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