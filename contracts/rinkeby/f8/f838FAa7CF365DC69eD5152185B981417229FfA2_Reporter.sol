// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "./ITellor.sol";

contract Reporter {
    ITellor oracle;

    constructor() {}

    function changeTellorContract(address _tContract) external {
        oracle = ITellor(_tContract);
    }

    function getNewCurrentVariables()
        external
        view
        returns (
            bytes32 _challenge,
            uint256[5] memory _requestIds,
            uint256 _diff,
            uint256 _tip
        )
    {
        return oracle.getNewCurrentVariables();
    }

    function submitMiningSolution(
        string calldata _nonce,
        uint256[5] calldata _requestIds,
        uint256[5] calldata _values
    ) external {
        oracle.submitMiningSolution(_nonce, _requestIds, _values);
    }

    function didMine(bytes32 _challenge, address _miner)
        external
        view
        returns (bool)
    {
        return oracle.didMine(_challenge, _miner);
    }

    function getLastNewValue() external view returns (uint256, bool) {
        return oracle.getLastNewValue();
    }

    function getUintVar(bytes32 _data) external view returns (uint256) {}

    function getStakerInfo(address _staker)
        external
        view
        returns (uint256, uint256)
    {
        return oracle.getStakerInfo(_staker);
    }

    function balanceOf(address _user) external view returns (uint256) {
        return oracle.balanceOf(_user);
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

/** 
 @author Tellor Inc.
 @title ITellor
 @dev  This contract holds the interface for all Tellor functions
**/
interface ITellor {
    /*Events*/
    event NewTellorAddress(address _newTellor);
    event NewDispute(
        uint256 indexed _disputeId,
        uint256 indexed _requestId,
        uint256 _timestamp,
        address _miner
    );
    event Voted(
        uint256 indexed _disputeID,
        bool _position,
        address indexed _voter,
        uint256 indexed _voteWeight
    );
    event DisputeVoteTallied(
        uint256 indexed _disputeID,
        int256 _result,
        address indexed _reportedMiner,
        address _reportingParty,
        bool _passed
    );
    event TipAdded(
        address indexed _sender,
        uint256 indexed _requestId,
        uint256 _tip,
        uint256 _totalTips
    );
    event NewChallenge(
        bytes32 indexed _currentChallenge,
        uint256[5] _currentRequestId,
        uint256 _difficulty,
        uint256 _totalTips
    );
    event NewValue(
        uint256[5] _requestId,
        uint256 _time,
        uint256[5] _value,
        uint256 _totalTips,
        bytes32 indexed _currentChallenge
    );
    event NonceSubmitted(
        address indexed _miner,
        string _nonce,
        uint256[5] _requestId,
        uint256[5] _value,
        bytes32 indexed _currentChallenge,
        uint256 _slot
    );
    event NewStake(address indexed _sender); //Emits upon new staker
    event StakeWithdrawn(address indexed _sender); //Emits when a staker is now no longer staked
    event StakeWithdrawRequested(address indexed _sender); //Emits when a staker begins the 7 day withdraw period
    event Approval(
        address indexed _owner,
        address indexed _spender,
        uint256 _value
    );
    event Transfer(address indexed _from, address indexed _to, uint256 _value); //ERC20 Transfer Event

    /*Functions -- master*/
    function changeDeity(address _newDeity) external;

    function changeOwner(address _newOwner) external;

    function changeTellorContract(address _tellorContract) external;

    /*Functions -- Extension*/
    function depositStake() external;

    function requestStakingWithdraw() external;

    function tallyVotes(uint256 _disputeId) external;

    function updateMinDisputeFee() external;

    function updateTellor(uint256 _disputeId) external;

    function withdrawStake() external;

    /*Functions -- Tellor*/
    function addTip(uint256 _requestId, uint256 _tip) external;

    function changeMigrator(address _migrator) external;

    function migrate() external;

    function migrateFor(
        address _destination,
        uint256 _amount,
        bool _bypass
    ) external;

    function migrateForBatch(
        address[] calldata _destination,
        uint256[] calldata _amount
    ) external;

    function migrateFrom(
        address _origin,
        address _destination,
        uint256 _amount,
        bool _bypass
    ) external;

    function migrateFromBatch(
        address[] calldata _origin,
        address[] calldata _destination,
        uint256[] calldata _amount
    ) external;

    function submitMiningSolution(
        string calldata _nonce,
        uint256[5] calldata _requestIds,
        uint256[5] calldata _values
    ) external;

    /*Functions -- TellorGetters*/
    function didMine(bytes32 _challenge, address _miner)
        external
        view
        returns (bool);

    function didVote(uint256 _disputeId, address _address)
        external
        view
        returns (bool);

    function getAddressVars(bytes32 _data) external view returns (address);

    function getAllDisputeVars(uint256 _disputeId)
        external
        view
        returns (
            bytes32,
            bool,
            bool,
            bool,
            address,
            address,
            address,
            uint256[9] memory,
            int256
        );

    function getDisputeIdByDisputeHash(bytes32 _hash)
        external
        view
        returns (uint256);

    function getDisputeUintVars(uint256 _disputeId, bytes32 _data)
        external
        view
        returns (uint256);

    function getLastNewValue() external view returns (uint256, bool);

    function getLastNewValueById(uint256 _requestId)
        external
        view
        returns (uint256, bool);

    function getMinedBlockNum(uint256 _requestId, uint256 _timestamp)
        external
        view
        returns (uint256);

    function getMinersByRequestIdAndTimestamp(
        uint256 _requestId,
        uint256 _timestamp
    ) external view returns (address[5] memory);

    function getNewValueCountbyRequestId(uint256 _requestId)
        external
        view
        returns (uint256);

    function getRequestIdByRequestQIndex(uint256 _index)
        external
        view
        returns (uint256);

    function getRequestIdByTimestamp(uint256 _timestamp)
        external
        view
        returns (uint256);

    function getRequestQ() external view returns (uint256[51] memory);

    function getRequestUintVars(uint256 _requestId, bytes32 _data)
        external
        view
        returns (uint256);

    function getRequestVars(uint256 _requestId)
        external
        view
        returns (uint256, uint256);

    function getStakerInfo(address _staker)
        external
        view
        returns (uint256, uint256);

    function getSubmissionsByTimestamp(uint256 _requestId, uint256 _timestamp)
        external
        view
        returns (uint256[5] memory);

    function getTimestampbyRequestIDandIndex(uint256 _requestID, uint256 _index)
        external
        view
        returns (uint256);

    function getUintVar(bytes32 _data) external view returns (uint256);

    function isInDispute(uint256 _requestId, uint256 _timestamp)
        external
        view
        returns (bool);

    function retrieveData(uint256 _requestId, uint256 _timestamp)
        external
        view
        returns (uint256);

    function totalSupply() external view returns (uint256);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function getNewCurrentVariables()
        external
        view
        returns (
            bytes32 _challenge,
            uint256[5] memory _requestIds,
            uint256 _difficulty,
            uint256 _tip
        );

    function getNewVariablesOnDeck()
        external
        view
        returns (uint256[5] memory idsOnDeck, uint256[5] memory tipsOnDeck);

    function getTopRequestIDs()
        external
        view
        returns (uint256[5] memory _requestIds);

    /*Functions -- TellorStake*/
    function beginDispute(
        uint256 _requestId,
        uint256 _timestamp,
        uint256 _minerIndex
    ) external;

    function proposeFork(address _propNewTellorAddress) external;

    function unlockDisputeFee(uint256 _disputeId) external;

    function verify() external returns (uint256);

    function vote(uint256 _disputeId, bool _supportsDispute) external;

    /*Functions -- TellorTransfer*/
    function approve(address _spender, uint256 _amount) external returns (bool);

    function allowance(address _user, address _spender)
        external
        view
        returns (uint256);

    function allowedToTrade(address _user, uint256 _amount)
        external
        view
        returns (bool);

    function balanceOf(address _user) external view returns (uint256);

    function balanceOfAt(address _user, uint256 _blockNumber)
        external
        view
        returns (uint256);

    function transfer(address _to, uint256 _amount) external returns (bool);

    function transferFrom(
        address _from,
        address _to,
        uint256 _amount
    ) external returns (bool);

    //Test Functions
    function theLazyCoon(address _address, uint256 _amount) external;

    function testSubmitMiningSolution(
        string calldata _nonce,
        uint256[5] calldata _requestId,
        uint256[5] calldata _value
    ) external;

    function manuallySetDifficulty(uint256 _diff) external;

    function testgetMax5(uint256[51] memory requests)
        external
        view
        returns (uint256[5] memory _max, uint256[5] memory _index);
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
  },
  "libraries": {}
}