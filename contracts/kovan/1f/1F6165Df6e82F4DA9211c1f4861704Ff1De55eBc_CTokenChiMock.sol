// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "./ISourceMock.sol";


contract CTokenChiMock is ISourceMock {
    uint public exchangeRateStored;

    function set(uint chi) external override {
        exchangeRateStored = chi;
    }

    function exchangeRateCurrent() public returns (uint) {
        return exchangeRateStored;
    }
}

// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;

interface ISourceMock {
    function set(uint) external;
}

{
  "optimizer": {
    "enabled": true,
    "runs": 5000
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
  "metadata": {
    "useLiteralContent": true
  },
  "libraries": {}
}