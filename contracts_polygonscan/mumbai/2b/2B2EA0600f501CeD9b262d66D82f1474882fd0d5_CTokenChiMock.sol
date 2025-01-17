// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.0;
import "./ISourceMock.sol";


contract CTokenChiMock is ISourceMock {
    uint public exchangeRateStored;
    uint counter;

    function set(uint chi) external override {
        exchangeRateStored = chi;
    }

    function exchangeRateCurrent() public returns (uint) {
        counter++;
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
    "runs": 1500
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