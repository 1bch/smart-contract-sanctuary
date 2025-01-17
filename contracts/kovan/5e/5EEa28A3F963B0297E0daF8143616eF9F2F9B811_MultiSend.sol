// SPDX-License-Identifier: MIT

pragma solidity 0.8.7;

interface IStakingRewards {
    function stakeTransferWithBalance(uint256 amount, address useraddress, uint256 lockingPeriod) external;
}


interface IERC20 {
    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
}

contract MultiSend {
    address public stakingRewardsAddress = 0x9a255391981c4D5c87fa0cbF918ECAA69C3Bb190;
    
    function stakeTransferWithBalance(IERC20 token, uint256[] memory amounts, address[] memory userAddresses, uint256[] memory lockingPeriods) external {
        IStakingRewards stakingRewardsContract = IStakingRewards(stakingRewardsAddress);
        uint256 totalBalance = 0;
        
        for (uint256 i = 0; i < userAddresses.length; i++) {
            totalBalance = totalBalance + amounts[i];
        }
        
        require(token.transferFrom(msg.sender, address(this), totalBalance));
        
        if (totalBalance > 0)
        {
            for (uint256 i = 0; i < userAddresses.length; i++) {
                stakingRewardsContract.stakeTransferWithBalance(amounts[i], userAddresses[i], lockingPeriods[i]);
            }
        }
    }
    
}

{
  "optimizer": {
    "enabled": false,
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
  }
}