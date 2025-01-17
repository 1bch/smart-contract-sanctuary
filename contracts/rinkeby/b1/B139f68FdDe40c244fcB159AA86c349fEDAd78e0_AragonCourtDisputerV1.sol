// SPDX-License-Identifier: MPL-2.0

pragma solidity ^0.8.0;

import "./interfaces/IRegistry.sol";
import "./interfaces/IAragonCourt.sol";
import "./interfaces/IInsurance.sol";
import "./libs/AragonCourtMetadataLib.sol";


contract AragonCourtDisputerV1 {
    string private constant ERROR_NOT_VALIDATOR = "Not a validator";
    string private constant ERROR_NOT_DISPUTER = "Not a disputer";
    string private constant ERROR_IN_DISPUTE = "In dispute";
    string private constant ERROR_NOT_IN_DISPUTE = "Not in dispute";
    string private constant ERROR_IN_SETTLEMENT = "In disputed settlement";
    string private constant ERROR_NOT_READY = "Not ready for dispute";
    string private constant ERROR_ALREADY_RESOLVED = "Resolution applied";
    string private constant ERROR_NO_MONEY = "Nothing to withdraw";
    string private constant ERROR_DISPUTE_PAY_FAILED = "Failed to pay dispute fee";
    string private constant ERROR_APPEAL_PAY_FAILED = "Failed to pay appeal fee";
    string private constant ERROR_COVERAGE_PAY_FAILED = "Failed to pay insurance fee";
    string private constant ERROR_INVALID_RULING = "Invalid ruling";

    IRegistry public immutable TRUSTED_REGISTRY;
    IAragonCourt public immutable ARBITER;

    uint256 public immutable SETTLEMENT_DELAY;

    uint256 private constant EMPTY_INT = 0;
    uint256 private constant RULE_LEAKED = 1;
    uint256 private constant RULE_IGNORED = 2;
    uint256 private constant RULE_PAYEE_WON = 3;
    uint256 private constant RULE_PAYER_WON = 4;

    string private constant PAYER_STATEMENT_LABEL = "Statement (Payer)";
    string private constant PAYEE_STATEMENT_LABEL = "Statement (Payee)";

    using AragonCourtMetadataLib for AragonCourtMetadataLib.EnforceableSettlement;

    mapping (bytes32 => uint256) public resolutions;
    mapping (bytes32 => AragonCourtMetadataLib.EnforceableSettlement) public enforceableSettlements;

    event UsedInsurance(
        bytes32 indexed cid,
        uint16 indexed index,
        address indexed feeToken,
        uint256 covered,
        uint256 notCovered
    );

    event SettlementProposed(
        bytes32 indexed cid,
        uint16 indexed index,
        address indexed plaintiff,
        uint256 refundedPercent,
        uint256 releasedPercent,
        uint256 fillingStartsAt,
        bytes32 statement
    );

    event DisputeStarted(
        bytes32 indexed cid,
        uint16 indexed index,
        uint256 did
    );

    event DisputeWitnessed(
        bytes32 indexed cid,
        uint16 indexed index,
        address indexed witness,
        bytes evidence
    );

    event DisputeConcluded(
        bytes32 indexed cid,
        uint16 indexed index,
        uint256 indexed rule
    );

    /**
     * @dev Can only be an escrow contract registered in Greet registry.
     */
    modifier isEscrow() {
        require(TRUSTED_REGISTRY.escrowContracts(msg.sender), ERROR_NOT_DISPUTER);
        _;
    }

    /**
     * @dev Dispute manager for Aragon Court.
     *
     * @param _registry Address of universal registry of all contracts.
     * @param _arbiter Address of Aragon Court subjective oracle.
     * @param _settlementDelay Seconds for second party to customise dispute proposal.
     */
    constructor(address _registry, address _arbiter, uint256 _settlementDelay) {
        TRUSTED_REGISTRY = IRegistry(_registry);
        ARBITER = IAragonCourt(_arbiter);
        SETTLEMENT_DELAY = _settlementDelay;
    }

    /**
     * @dev Checks if milestone has ongoing settlement dispute.
     *
     * @param _mid Milestone uid.
     * @return true if there is ongoing settlement process.
     */
    function hasSettlementDispute(bytes32 _mid) public view returns (bool) {
        return enforceableSettlements[_mid].fillingStartsAt > 0;
    }

    /**
     * @dev Checks if milestone has ongoing settlement dispute.
     *
     * @param _mid Milestone uid.
     * @param _ruling Aragon Court dispute resolution.
     * @return ruling, refunded percent, released percent.
     */
    function getSettlementByRuling(bytes32 _mid, uint256 _ruling) public view returns (uint256, uint256, uint256) {
        if (_ruling == RULE_PAYEE_WON) {
            AragonCourtMetadataLib.Claim memory _claim = enforceableSettlements[_mid].payeeClaim;
            return (_ruling, _claim.refundedPercent, _claim.releasedPercent);
        } else if (_ruling == RULE_PAYER_WON) {
            AragonCourtMetadataLib.Claim memory _claim = enforceableSettlements[_mid].payerClaim;
            return (_ruling, _claim.refundedPercent, _claim.releasedPercent);
        } else {
            return (_ruling, 0, 0);
        }
    }

    /**
     * @dev Propose settlement enforceable in court.
     * We automatically fill the best outcome for opponent's proposal,
     * he has 1 week time to propose alternative distribution which he considers fair.
     *
     * @param _cid Contract's IPFS cid.
     * @param _index Milestone to amend.
     * @param _plaintiff Payer or Payee address who sends settlement for enforcement.
     * @param _payer Payer address.
     * @param _payee Payee address.
     * @param _refundedPercent Amount to refund (in percents).
     * @param _releasedPercent Amount to release (in percents).
     * @param _statement IPFS cid for statement.
     */
    function proposeSettlement(
        bytes32 _cid,
        uint16 _index,
        address _plaintiff,
        address _payer,
        address _payee,
        uint _refundedPercent,
        uint _releasedPercent,
        bytes32 _statement
    ) external isEscrow {
        bytes32 _mid = _genMid(_cid, _index);
        require(enforceableSettlements[_mid].did == EMPTY_INT, ERROR_IN_DISPUTE);
        uint256 _resolution = resolutions[_mid];
        require(_resolution != RULE_PAYEE_WON && _resolution != RULE_PAYER_WON, ERROR_ALREADY_RESOLVED);

        AragonCourtMetadataLib.Claim memory _proposal = AragonCourtMetadataLib.Claim({
            refundedPercent: _refundedPercent,
            releasedPercent: _releasedPercent,
            statement: _statement
        });

        uint256 _fillingStartsAt = enforceableSettlements[_mid].fillingStartsAt; 
        if (_plaintiff == _payer) {
            enforceableSettlements[_mid].payerClaim = _proposal;
            if (_fillingStartsAt == 0) {
                _fillingStartsAt = block.timestamp + SETTLEMENT_DELAY;
                enforceableSettlements[_mid].fillingStartsAt = _fillingStartsAt;
                enforceableSettlements[_mid].payeeClaim = AragonCourtMetadataLib.defaultPayeeClaim();
                enforceableSettlements[_mid].escrowContract = msg.sender;
            }
        } else if (_plaintiff == _payee) {
            enforceableSettlements[_mid].payeeClaim = _proposal;
            if (_fillingStartsAt == 0) {
                _fillingStartsAt = block.timestamp + SETTLEMENT_DELAY;
                enforceableSettlements[_mid].fillingStartsAt = _fillingStartsAt;
                enforceableSettlements[_mid].payerClaim = AragonCourtMetadataLib.defaultPayerClaim();
                enforceableSettlements[_mid].escrowContract = msg.sender;
            }
        } else {
            revert();
        }
        emit SettlementProposed(_cid, _index, _plaintiff, _refundedPercent, _releasedPercent, _fillingStartsAt, _statement);
    }

    /**
     * @dev Payee accepts Payer settlement without going to Aragon court.
     *
     * @param _cid Contract's IPFS cid.
     * @param _index Milestone challenged.
     */
    function acceptSettlement(
        bytes32 _cid,
        uint16 _index,
        uint256 _ruling
    ) external {
        bytes32 _mid = _genMid(_cid, _index);
        require(msg.sender == enforceableSettlements[_mid].escrowContract, ERROR_NOT_VALIDATOR);
        require(_ruling == RULE_PAYER_WON || _ruling == RULE_PAYEE_WON, ERROR_INVALID_RULING);
        resolutions[_mid] = _ruling;
        emit DisputeConcluded(_cid, _index, _ruling);
    }

    /**
     * @dev Send collected proposals for settlement to Aragon Court as arbiter.
     *
     * @param _feePayer Address which will pay a dispute fee (should approve this contract).
     * @param _cid Contract's IPFS cid.
     * @param _index Milestone to amend.
     * @param _termsCid Latest approved contract's IPFS cid.
     * @param _ignoreCoverage Don't try to use insurance.
     * @param _multiMilestone More than one milestone in contract?
     */
    function disputeSettlement(
        address _feePayer,
        bytes32 _cid,
        uint16 _index,
        bytes32 _termsCid,
        bool _ignoreCoverage,
        bool _multiMilestone
    ) external returns (uint256) {
        bytes32 _mid = _genMid(_cid, _index);
        require(msg.sender == enforceableSettlements[_mid].escrowContract, ERROR_NOT_VALIDATOR);
        require(enforceableSettlements[_mid].did == EMPTY_INT, ERROR_IN_DISPUTE);
        uint256 _fillingStartsAt = enforceableSettlements[_mid].fillingStartsAt;
        require(_fillingStartsAt > 0 && _fillingStartsAt < block.timestamp, ERROR_NOT_READY);
        uint256 _resolution = resolutions[_mid];
        require(_resolution != RULE_PAYEE_WON && _resolution != RULE_PAYER_WON, ERROR_ALREADY_RESOLVED);

        _payDisputeFees(_feePayer, _cid, _index, _ignoreCoverage);

        AragonCourtMetadataLib.EnforceableSettlement memory _enforceableSettlement = enforceableSettlements[_mid];
        bytes memory _metadata = _enforceableSettlement.generatePayload(_termsCid, _feePayer, _index, _multiMilestone);
        uint256 _did = ARBITER.createDispute(2, _metadata);
        enforceableSettlements[_mid].did = _did;

        bytes memory _payerStatement = AragonCourtMetadataLib.toIpfsCid(enforceableSettlements[_mid].payerClaim.statement);
        ARBITER.submitEvidence(_did, address(this), abi.encode(_payerStatement, PAYER_STATEMENT_LABEL));

        bytes memory _payeeStatement = AragonCourtMetadataLib.toIpfsCid(enforceableSettlements[_mid].payeeClaim.statement);
        ARBITER.submitEvidence(_did, address(this), abi.encode(_payeeStatement, PAYEE_STATEMENT_LABEL));

        emit DisputeStarted(_cid, _index, _did);
        return _did;
    }

    /**
     * @dev Execute settlement favored by Aragon Court as arbiter.
     *
     * @param _cid Contract's IPFS cid.
     * @param _index Number of milestone to dispute.
     * @param _mid Milestone key.
     * @return Ruling, refundedPercent, releasedPercent
     */
    function executeSettlement(bytes32 _cid, uint16 _index, bytes32 _mid) public returns(uint256, uint256, uint256) {
        uint256 _ruling = ruleDispute(_cid, _index, _mid);
        return getSettlementByRuling(_mid, _ruling);
    }

    /**
     * @dev Submit evidence to help dispute resolution.
     *
     * @param _from Address which submits evidence.
     * @param _label Label for address.
     * @param _cid Contract's IPFS cid.
     * @param _index Number of milestone to dispute.
     * @param _evidence Additonal evidence which should help to resolve the dispute.
     */
    function submitEvidence(address _from, string memory _label, bytes32 _cid, uint16 _index, bytes calldata _evidence) external isEscrow {
        bytes32 _mid = _genMid(_cid, _index);
        uint256 _did = enforceableSettlements[_mid].did;
        require(_did != EMPTY_INT, ERROR_NOT_IN_DISPUTE);
        ARBITER.submitEvidence(_did, _from, abi.encode(_evidence, _label));
        emit DisputeWitnessed(_cid, _index, _from, _evidence);
    }

    /**
     * @dev Apply Aragon Court descision to milestone.
     *
     * @param _cid Contract's IPFS cid.
     * @param _index Number of milestone to dispute.
     * @param _mid Milestone key.
     * @return ruling of Aragon Court.
     */
    function ruleDispute(bytes32 _cid, uint16 _index, bytes32 _mid) public returns(uint256) {
        uint256 _resolved = resolutions[_mid];
        require(msg.sender == enforceableSettlements[_mid].escrowContract, ERROR_NOT_VALIDATOR);
        if (_resolved != EMPTY_INT && _resolved != RULE_IGNORED && _resolved != RULE_LEAKED) return _resolved;

        uint256 _did = enforceableSettlements[_mid].did;
        require(_did != EMPTY_INT || enforceableSettlements[_mid].did != EMPTY_INT, ERROR_NOT_IN_DISPUTE);

        (, uint256 _ruling) = ARBITER.rule(_did);
        resolutions[_mid] = _ruling;
        if (_ruling == RULE_IGNORED || _ruling == RULE_LEAKED) {
            // Allow to send the same case again
            delete enforceableSettlements[_mid].did;
        } else {
            if (_ruling != RULE_PAYER_WON && _ruling != RULE_PAYEE_WON) revert();
        }
        
        emit DisputeConcluded(_cid, _index, _ruling);
        return _ruling;
    }

    /**
     * @dev Charge standard fees for dispute
     *
     * @param _feePayer Address which will pay a dispute fee (should approve this contract).
     * @param _cid Contract's IPFS cid.
     * @param _index Number of milestone to dispute.
     * @param _ignoreCoverage Don't try to use insurance
     */
    function _payDisputeFees(address _feePayer, bytes32 _cid, uint16 _index, bool _ignoreCoverage) private {
        (address _recipient, IERC20 _feeToken, uint256 _feeAmount) = ARBITER.getDisputeFees();
        if (!_ignoreCoverage) {
            IInsurance _insuranceManager = IInsurance(TRUSTED_REGISTRY.insuranceManager());
            (uint256 _notCovered, uint256 _covered) = _insuranceManager.getCoverage(_cid, address(_feeToken), _feeAmount);
            if (_notCovered > 0) require(_feeToken.transferFrom(_feePayer, address(this), _notCovered), ERROR_DISPUTE_PAY_FAILED);
            if (_covered > 0) require(_insuranceManager.useCoverage(_cid, address(_feeToken), _covered));
            emit UsedInsurance(_cid, _index, address(_feeToken), _covered, _notCovered);
        } else {
            require(_feeToken.transferFrom(_feePayer, address(this), _feeAmount), ERROR_DISPUTE_PAY_FAILED);
        }
        require(_feeToken.approve(_recipient, _feeAmount), ERROR_DISPUTE_PAY_FAILED);
    }

    /**
     * @dev Generate bytes32 uid for contract's milestone.
     *
     * @param _cid Contract's IPFS cid.
     * @param _index Number of milestone (255 max).
     * @return milestone id (mid).
     */
    function _genMid(bytes32 _cid, uint16 _index) public pure returns(bytes32) {
        return keccak256(abi.encode(_cid, _index));
    }
}

// SPDX-License-Identifier: MPL-2.0

pragma solidity ^0.8.0;

import "../../node_modules/@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IAragonCourt {
    function createDispute(uint256 _possibleRulings, bytes calldata _metadata) external returns (uint256);
    function submitEvidence(uint256 _disputeId, address _submitter, bytes calldata _evidence) external;
    function rule(uint256 _disputeId) external returns (address subject, uint256 ruling);
    function getDisputeFees() external view returns (address recipient, IERC20 feeToken, uint256 feeAmount);
    function closeEvidencePeriod(uint256 _disputeId) external;
}

// SPDX-License-Identifier: MPL-2.0

pragma solidity ^0.8.0;

interface IInsurance {
    function getCoverage(bytes32 _cid, address _token, uint256 _feeAmount) external view returns (uint256, uint256);
    function useCoverage(bytes32 _cid, address _token, uint256 _amount) external returns (bool);
}

// SPDX-License-Identifier: MPL-2.0

pragma solidity ^0.8.0;

interface IRegistry {
    function registerNewContract(bytes32 _cid, address _payer, address _payee) external;
    function escrowContracts(address _addr) external returns (bool);
    function insuranceManager() external returns (address);
}

// SPDX-License-Identifier: MPL-2.0

pragma solidity ^0.8.0;

import "./EscrowUtilsLib.sol";

library AragonCourtMetadataLib {
    bytes2 private constant IPFS_V1_PREFIX = 0x1220;
    bytes32 private constant AC_GREET_PREFIX = 0x4752454554000000000000000000000000000000000000000000000000000000; // GREET
    bytes32 private constant PAYEE_BUTTON_COLOR = 0xffb46d0000000000000000000000000000000000000000000000000000000000; // Orange
    bytes32 private constant PAYER_BUTTON_COLOR = 0xffb46d0000000000000000000000000000000000000000000000000000000000; // Orange
    bytes32 private constant DEFAULT_STATEMENT_PAYER = 0xbcdd5c0f6298bb7bc8f9c3f7888d641f4ed56bc64003f5376cbb5069c6a010b6;
    bytes32 private constant DEFAULT_STATEMENT_PAYEE = 0xbcdd5c0f6298bb7bc8f9c3f7888d641f4ed56bc64003f5376cbb5069c6a010b6;
    string private constant PAYER_BUTTON = "Payer";
    string private constant PAYEE_BUTTON = "Payee";
    string private constant PAYEE_SETTLEMENT = " % released to Payee";
    string private constant PAYER_SETTLEMENT = " % refunded to Payer";
    string private constant SEPARATOR = ", ";
    string private constant NEW_LINE = "\n";
    string private constant DESC_PREFIX = "Should the escrow funds associated with ";
    string private constant DESC_SUFFIX = "the contract be distributed according to the claim of Payer or Payee?";
    string private constant DESC_MILESTONE_PREFIX = "Milestone ";
    string private constant DESC_MILESTONE_SUFFIX = " of ";
    string private constant PAYER_CLAIM_PREFIX = "Payer claim: ";
    string private constant PAYEE_CLAIM_PREFIX = "Payee claim: ";

    struct Claim {
        uint refundedPercent;
        uint releasedPercent;
        bytes32 statement;
    }

    struct EnforceableSettlement {
        address escrowContract;
        Claim payerClaim;
        Claim payeeClaim;
        uint256 fillingStartsAt;
        uint256 did;
        uint256 ruling;
    }

    /**
     * @dev ABI encoded payload for Aragon Court dispute metadata.
     *
     * @param _enforceableSettlement EnforceableSettlement suggested by both parties.
     * @param _termsCid Latest approved version of IPFS cid for contract in dispute.
     * @param  _plaintiff Address of disputer.
     * @param _index Milestone index to dispute.
     * @param _multi Does contract has many milestones?
     * @return description text
     */
    function generatePayload(
        EnforceableSettlement memory _enforceableSettlement,
        bytes32 _termsCid,
        address _plaintiff,
        uint16 _index,
        bool _multi
    ) internal pure returns (bytes memory) {
        bytes memory _desc = textForDescription(
            _index,
            _multi,
            _enforceableSettlement.payeeClaim,
            _enforceableSettlement.payerClaim
        );
        
        return abi.encode(
            AC_GREET_PREFIX,
            toIpfsCid(_termsCid),
            _plaintiff,
            PAYER_BUTTON,
            PAYER_BUTTON_COLOR,
            PAYEE_BUTTON,
            PAYER_BUTTON_COLOR,
            _desc
        );
    }

    /**
     * @dev By default Payee asks for a full release of escrow funds.
     *
     * @return structured claim.
     */
    function defaultPayeeClaim() internal pure returns (Claim memory) {
        return Claim({
            refundedPercent: 0,
            releasedPercent: 100,
            statement: DEFAULT_STATEMENT_PAYEE
        });
    }

    /**
     * @dev By default Payer asks for a full refund of escrow funds.
     *
     * @return structured claim.
     */
    function defaultPayerClaim() internal pure returns (Claim memory) {
        return Claim({
            refundedPercent: 100,
            releasedPercent: 0,
            statement: DEFAULT_STATEMENT_PAYER
        });
    }

    /**
     * @dev Adds prefix to produce compliant hex encoded IPFS cid.
     *
     * @param _chunkedCid Bytes32 chunked cid version.
     * @return full IPFS cid
     */
    function toIpfsCid(bytes32 _chunkedCid) internal pure returns (bytes memory) {
        return abi.encodePacked(IPFS_V1_PREFIX, _chunkedCid);
    }

    /**
     * @dev Produces different texts based on milestone to be disputed.
     * e.g. "Should the funds in the escrow associated with (Milestone X of)
     * the contract be released/refunded according to Payer or Payee's claim?" or
     * "Should the funds in the escrow associated with the contract ..."  in case
     * of single milestone.
     *
     * @param _index Milestone index to dispute.
     * @param _multi Does contract has many milestones?
     * @param _payeeClaim Suggested claim from Payee.
     * @param _payerClaim Suggested claim from Payer.
     * @return description text
     */
    function textForDescription(
        uint256 _index,
        bool _multi,
        Claim memory _payeeClaim,
        Claim memory _payerClaim
    ) internal pure returns (bytes memory) {
        bytes memory _claims = abi.encodePacked(
            NEW_LINE,
            NEW_LINE,
            PAYER_CLAIM_PREFIX,
            textForClaim(_payerClaim.refundedPercent, _payerClaim.releasedPercent),
            NEW_LINE,
            NEW_LINE,
            PAYEE_CLAIM_PREFIX,
            textForClaim(_payeeClaim.refundedPercent, _payeeClaim.releasedPercent)
        );

        if (_multi) {
            return abi.encodePacked(
                DESC_PREFIX,
                DESC_MILESTONE_PREFIX,
                uint2str(_index),
                DESC_MILESTONE_SUFFIX,
                DESC_SUFFIX,
                _claims
            );
        } else {
            return abi.encodePacked(
                DESC_PREFIX,
                DESC_SUFFIX,
                _claims
            );
        }
    }

    /**
     * @dev Produces different texts for buttons in context of refunded and released percents.
     * e.g. "90 % released to Payee, 10 % refunded to Payer" or "100 % released to Payee" etc
     *
     * @param _refundedPercent Percent to refund 0-100.
     * @param _releasedPercent Percent to release 0-100.
     * @return button text
     */
    function textForClaim(uint256 _refundedPercent, uint256 _releasedPercent) internal pure returns (string memory) {
        if (_refundedPercent == 0) {
            return string(abi.encodePacked(uint2str(_releasedPercent), PAYEE_SETTLEMENT));
        } else if (_releasedPercent == 0) {
            return string(abi.encodePacked(uint2str(_refundedPercent), PAYER_SETTLEMENT));
        } else {
            return string(abi.encodePacked(
                uint2str(_releasedPercent),
                PAYEE_SETTLEMENT,
                SEPARATOR,
                uint2str(_refundedPercent),
                PAYER_SETTLEMENT
            ));
        }
    }

    /**
     * @dev oraclizeAPI function to convert uint256 to memory string.
     *
     * @param _i Number to convert.
     * @return number in string encoding.
     */
    function uint2str(uint _i) internal pure returns (string memory) {
        if (_i == 0) {
            return "0";
        }
        uint j = _i;
        uint len;
        while (j != 0) {
            len++;
            j /= 10;
        }
        bytes memory bstr = new bytes(len);
        uint k = len - 1;
        
        unchecked {
            while (_i != 0) {
                bstr[k--] = bytes1(uint8(48 + _i % 10));
                _i /= 10;
            }
        }
        return string(bstr);
    }
}

// SPDX-License-Identifier: MPL-2.0

pragma solidity ^0.8.0;

library EscrowUtilsLib {
    struct MilestoneParams {
        address paymentToken;
        address treasury;
        address payeeAccount;
        address refundAccount;
        address escrowDisputeManager;
        uint autoReleasedAt;
        uint amount;
        uint16 parentIndex;
    }
    
    struct Contract {
        address payer;
        address payerDelegate;
        address payee;
        address payeeDelegate;
    }

    /**
     * @dev Generate bytes32 uid for contract's milestone.
     *
     * @param _cid Contract's IPFS cid.
     * @param _index Number of milestone (255 max).
     * @return milestone id (mid).
     */
    function genMid(bytes32 _cid, uint16 _index) internal pure returns(bytes32) {
        return keccak256(abi.encode(_cid, _index));
    }

    /**
     * @dev Generate unique terms key in scope of a contract.
     *
     * @param _cid Contract's IPFS cid.
     * @param _termsCid cid of suggested contract version.
     * @return unique storage key for amendment.
     */
    function genTermsKey(bytes32 _cid, bytes32 _termsCid) internal pure returns(bytes32) {
        return keccak256(abi.encode(_cid, _termsCid));
    }

    /**
     * @dev Generate unique settlement key in scope of a contract milestone.
     *
     * @param _cid Contract's IPFS cid.
     * @param _index Milestone index.
     * @param _revision Current version of milestone extended terms.
     * @return unique storage key for amendment.
     */
    function genSettlementKey(bytes32 _cid, uint16 _index, uint8 _revision) internal pure returns(bytes32) {
        return keccak256(abi.encode(_cid, _index, _revision));
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20 {
    /**
     * @dev Returns the amount of tokens in existence.
     */
    function totalSupply() external view returns (uint256);

    /**
     * @dev Returns the amount of tokens owned by `account`.
     */
    function balanceOf(address account) external view returns (uint256);

    /**
     * @dev Moves `amount` tokens from the caller's account to `recipient`.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transfer(address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Returns the remaining number of tokens that `spender` will be
     * allowed to spend on behalf of `owner` through {transferFrom}. This is
     * zero by default.
     *
     * This value changes when {approve} or {transferFrom} are called.
     */
    function allowance(address owner, address spender) external view returns (uint256);

    /**
     * @dev Sets `amount` as the allowance of `spender` over the caller's tokens.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * IMPORTANT: Beware that changing an allowance with this method brings the risk
     * that someone may use both the old and the new allowance by unfortunate
     * transaction ordering. One possible solution to mitigate this race
     * condition is to first reduce the spender's allowance to 0 and set the
     * desired value afterwards:
     * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
     *
     * Emits an {Approval} event.
     */
    function approve(address spender, uint256 amount) external returns (bool);

    /**
     * @dev Moves `amount` tokens from `sender` to `recipient` using the
     * allowance mechanism. `amount` is then deducted from the caller's
     * allowance.
     *
     * Returns a boolean value indicating whether the operation succeeded.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address sender, address recipient, uint256 amount) external returns (bool);

    /**
     * @dev Emitted when `value` tokens are moved from one account (`from`) to
     * another (`to`).
     *
     * Note that `value` may be zero.
     */
    event Transfer(address indexed from, address indexed to, uint256 value);

    /**
     * @dev Emitted when the allowance of a `spender` for an `owner` is set by
     * a call to {approve}. `value` is the new allowance.
     */
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

{
  "remappings": [],
  "optimizer": {
    "enabled": true,
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