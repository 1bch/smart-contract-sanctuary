// SPDX-License-Identifier: UNLICENSED
pragma solidity 0.8.0;

contract MockGelatoGasPriceOracle {
    uint256 public gasPrice;

    constructor(uint256 _gasPrice) {
        gasPrice = _gasPrice;
    }

    function setGasPrice(uint256 _newGasPrice) external {
        gasPrice = _newGasPrice;
    }

    function latestAnswer() external view returns (int256) {
        return int256(gasPrice);
    }
}

{
  "evmVersion": "istanbul",
  "libraries": {},
  "metadata": {
    "bytecodeHash": "ipfs",
    "useLiteralContent": true
  },
  "optimizer": {
    "enabled": true,
    "runs": 200
  },
  "remappings": [],
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