pragma solidity ^0.5.16;

// Inheritance
import "./Owned.sol";
import "./ExternStateToken.sol";
import "./MixinResolver.sol";
import "./interfaces/IPhant.sol";
import "./interfaces/IERC20.sol";

// Internal references
import "./interfaces/ISystemStatus.sol";
import "./interfaces/IFeePool.sol";
import "./interfaces/IIssuer.sol";

contract Phant is Owned, IERC20, ExternStateToken, MixinResolver, IPhant {
    /* ========== STATE VARIABLES ========== */

    // Currency key which identifies this Phant to the Phantom system
    bytes32 public currencyKey;

    uint8 public constant DECIMALS = 18;

    /* ========== ADDRESS RESOLVER CONFIGURATION ========== */

    bytes32 private constant CONTRACT_SYSTEMSTATUS = "SystemStatus";
    bytes32 private constant CONTRACT_ISSUER = "Issuer";
    bytes32 private constant CONTRACT_FEEPOOL = "FeePool";

    /* ========== CONSTRUCTOR ========== */

    constructor(
        address payable _proxy,
        TokenState _tokenState,
        string memory _tokenName,
        string memory _tokenSymbol,
        address _owner,
        bytes32 _currencyKey,
        uint _totalSupply,
        address _resolver
    )
        public
        ExternStateToken(_proxy, _tokenState, _tokenName, _tokenSymbol, _totalSupply, DECIMALS, _owner)
        MixinResolver(_resolver)
    {
        require(_proxy != address(0), "_proxy cannot be 0");
        require(_owner != address(0), "_owner cannot be 0");

        currencyKey = _currencyKey;
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    function transfer(address to, uint value) public optionalProxy returns (bool) {
        _ensureCanTransfer(messageSender, value);

        // transfers to 0x address will be burned
        if (to == address(0)) {
            return _internalBurn(messageSender, value);
        }

        return super._internalTransfer(messageSender, to, value);
    }

    function transferFrom(
        address from,
        address to,
        uint value
    ) public optionalProxy returns (bool) {
        _ensureCanTransfer(from, value);

        return _internalTransferFrom(from, to, value);
    }

    function issue(address account, uint amount) external onlyInternalContracts {
        _internalIssue(account, amount);
    }

    function burn(address account, uint amount) external onlyInternalContracts {
        _internalBurn(account, amount);
    }

    function _internalIssue(address account, uint amount) internal {
        tokenState.setBalanceOf(account, tokenState.balanceOf(account).add(amount));
        totalSupply = totalSupply.add(amount);
        emitTransfer(address(0), account, amount);
        emitIssued(account, amount);
    }

    function _internalBurn(address account, uint amount) internal returns (bool) {
        tokenState.setBalanceOf(account, tokenState.balanceOf(account).sub(amount));
        totalSupply = totalSupply.sub(amount);
        emitTransfer(account, address(0), amount);
        emitBurned(account, amount);

        return true;
    }

    // Allow owner to set the total supply on import.
    function setTotalSupply(uint amount) external optionalProxy_onlyOwner {
        totalSupply = amount;
    }

    /* ========== VIEWS ========== */

    // Note: use public visibility so that it can be invoked in a subclass
    function resolverAddressesRequired() public view returns (bytes32[] memory addresses) {
        addresses = new bytes32[](3);
        addresses[0] = CONTRACT_SYSTEMSTATUS;
        addresses[1] = CONTRACT_ISSUER;
        addresses[2] = CONTRACT_FEEPOOL;
    }

    function systemStatus() internal view returns (ISystemStatus) {
        return ISystemStatus(requireAndGetAddress(CONTRACT_SYSTEMSTATUS));
    }

    function feePool() internal view returns (IFeePool) {
        return IFeePool(requireAndGetAddress(CONTRACT_FEEPOOL));
    }

    function issuer() internal view returns (IIssuer) {
        return IIssuer(requireAndGetAddress(CONTRACT_ISSUER));
    }

    function _ensureCanTransfer(address from, uint value) internal view {
        require(transferablePhants(from) >= value, "Insufficient balance after any settlement owing");
        systemStatus().requirePhantActive(currencyKey);
    }

    function transferablePhants(address account) public view returns (uint) {
        return tokenState.balanceOf(account);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function _internalTransferFrom(
        address from,
        address to,
        uint value
    ) internal returns (bool) {
        // Skip allowance update in case of infinite allowance
        if (tokenState.allowance(from, messageSender) != uint(-1)) {
            // Reduce the allowance by the amount we're transferring.
            // The safeSub call will handle an insufficient allowance.
            tokenState.setAllowance(from, messageSender, tokenState.allowance(from, messageSender).sub(value));
        }

        return super._internalTransfer(from, to, value);
    }

    /* ========== MODIFIERS ========== */

    modifier onlyInternalContracts() {
        bool isFeePool = msg.sender == address(feePool());
        bool isIssuer = msg.sender == address(issuer());

        require(isFeePool || isIssuer, "Only FeePool or Issuer contracts allowed");
        _;
    }

    /* ========== EVENTS ========== */
    event Issued(address indexed account, uint value);
    bytes32 private constant ISSUED_SIG = keccak256("Issued(address,uint256)");

    function emitIssued(address account, uint value) internal {
        proxy._emit(abi.encode(value), 2, ISSUED_SIG, addressToBytes32(account), 0, 0);
    }

    event Burned(address indexed account, uint value);
    bytes32 private constant BURNED_SIG = keccak256("Burned(address,uint256)");

    function emitBurned(address account, uint value) internal {
        proxy._emit(abi.encode(value), 2, BURNED_SIG, addressToBytes32(account), 0, 0);
    }
}

pragma solidity >=0.4.24;

interface ISystemStatus {
    struct Status {
        bool canSuspend;
        bool canResume;
    }

    struct Suspension {
        bool suspended;
        // reason is an integer code,
        // 0 => no reason, 1 => upgrading, 2+ => defined by system usage
        uint248 reason;
    }

    // Views
    function accessControl(bytes32 section, address account) external view returns (bool canSuspend, bool canResume);

    function requireSystemActive() external view;

    function requireIssuanceActive() external view;

    function requirePhantActive(bytes32 currencyKey) external view;

    function requirePhantsActive(bytes32 sourceCurrencyKey, bytes32 destinationCurrencyKey) external view;

    function systemSuspension() external view returns (bool suspended, uint248 reason);

    function issuanceSuspension() external view returns (bool suspended, uint248 reason);

    function phantSuspension(bytes32 currencyKey) external view returns (bool suspended, uint248 reason);

    function getPhantSuspensions(bytes32[] calldata phants)
        external
        view
        returns (bool[] memory suspensions, uint256[] memory reasons);

    // Restricted functions
    function suspendPhant(bytes32 currencyKey, uint256 reason) external;

    function updateAccessControl(
        bytes32 section,
        address account,
        bool canSuspend,
        bool canResume
    ) external;
}

pragma solidity >=0.4.24;

interface IPhant {
    // Views
    function currencyKey() external view returns (bytes32);

    function transferablePhants(address account) external view returns (uint);

    // Restricted: used internally to Phantom
    function burn(address account, uint amount) external;

    function issue(address account, uint amount) external;
}

pragma solidity >=0.4.24;

import "../interfaces/IPhant.sol";

interface IIssuer {
    // Views
    function anyPhantOrPHMRateIsInvalid() external view returns (bool anyRateInvalid);

    function availableCurrencyKeys() external view returns (bytes32[] memory);

    function availablePhantCount() external view returns (uint);

    function availablePhants(uint index) external view returns (IPhant);

    function canBurnPhants(address account) external view returns (bool);

    function collateral(address account) external view returns (uint);

    function collateralisationRatio(address issuer) external view returns (uint);

    function collateralisationRatioAndAnyRatesInvalid(address _issuer)
        external
        view
        returns (uint cratio, bool anyRateIsInvalid);

    function debtBalanceOf(address issuer, bytes32 currencyKey) external view returns (uint debtBalance);

    function issuanceRatio() external view returns (uint);

    function lastIssueEvent(address account) external view returns (uint);

    function maxIssuablePhants(address issuer) external view returns (uint maxIssuable);

    function minimumStakeTime() external view returns (uint);

    function remainingIssuablePhants(address issuer)
        external
        view
        returns (
            uint maxIssuable,
            uint alreadyIssued,
            uint totalSystemDebt
        );

    function phants(bytes32 currencyKey) external view returns (IPhant);

    function getPhants(bytes32[] calldata currencyKeys) external view returns (IPhant[] memory);

    function phantsByAddress(address phantAddress) external view returns (bytes32);

    function totalIssuedPhants(bytes32 currencyKey) external view returns (uint);

    function transferablePHMAndAnyRateIsInvalid(address account, uint balance)
        external
        view
        returns (uint transferable, bool anyRateIsInvalid);

    // Restricted: used internally to Phantetix
    function issuePhants(address from, uint amount) external;

    function issueMaxPhants(address from) external;

    function burnPhants(address from, uint amount) external;

    function burnPhantsToTarget(address from) external;

    function liquidateDelinquentAccount(
        address account,
        uint susdAmount,
        address liquidator
    ) external returns (uint totalRedeemed, uint amountToLiquidate);
}

pragma solidity >=0.4.24;

interface IFeePool {
    // Views

    function feesAvailable(address account) external view returns (uint, uint);

    function feePeriodDuration() external view returns (uint);

    function isFeesClaimable(address account) external view returns (bool);

    function targetThreshold() external view returns (uint);

    function totalRewardsAvailable() external view returns (uint);

    // Mutative Functions
    function claimFees() external returns (bool);

    function closeCurrentFeePeriod() external;

    // Restricted: used internally to Phantom
    function appendAccountIssuanceRecord(
        address account,
        uint lockedAmount,
        uint debtEntryIndex
    ) external;

    function setRewardsToDistribute(uint amount) external;
}

pragma solidity >=0.4.24;

interface IERC20 {
    // ERC20 Optional Views
    function name() external view returns (string memory);

    function symbol() external view returns (string memory);

    function decimals() external view returns (uint8);

    // Views
    function totalSupply() external view returns (uint);

    function balanceOf(address owner) external view returns (uint);

    function allowance(address owner, address spender) external view returns (uint);

    // Mutative functions
    function transfer(address to, uint value) external returns (bool);

    function approve(address spender, uint value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint value
    ) external returns (bool);

    // Events
    event Transfer(address indexed from, address indexed to, uint value);

    event Approval(address indexed owner, address indexed spender, uint value);
}

pragma solidity >=0.4.24;

interface IAddressResolver {
    function getAddress(bytes32 name) external view returns (address);

    function getPhant(bytes32 key) external view returns (address);

    function requireAndGetAddress(bytes32 name, string calldata reason) external view returns (address);
}

pragma solidity ^0.5.16;

// Inheritance
import "./Owned.sol";
import "./State.sol";

contract TokenState is Owned, State {
    /* ERC20 fields. */
    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;

    constructor(address _owner, address _associatedContract) public Owned(_owner) State(_associatedContract) {}

    /* ========== SETTERS ========== */

    /**
     * @notice Set ERC20 allowance.
     * @dev Only the associated contract may call this.
     * @param tokenOwner The authorising party.
     * @param spender The authorised party.
     * @param value The total value the authorised party may spend on the
     * authorising party's behalf.
     */
    function setAllowance(
        address tokenOwner,
        address spender,
        uint value
    ) external onlyAssociatedContract {
        allowance[tokenOwner][spender] = value;
    }

    /**
     * @notice Set the balance in a given account
     * @dev Only the associated contract may call this.
     * @param account The account whose value to set.
     * @param value The new balance of the given account.
     */
    function setBalanceOf(address account, uint value) external onlyAssociatedContract {
        balanceOf[account] = value;
    }
}

pragma solidity ^0.5.16;

// Inheritance
import "./Owned.sol";

contract State is Owned {
    // the address of the contract that can modify variables
    // this can only be changed by the owner of this contract
    address public associatedContract;

    constructor(address _associatedContract) internal {
        // This contract is abstract, and thus cannot be instantiated directly
        require(owner != address(0), "Owner must be set");

        associatedContract = _associatedContract;
        emit AssociatedContractUpdated(_associatedContract);
    }

    /* ========== SETTERS ========== */

    // Change the associated contract to a new address
    function setAssociatedContract(address _associatedContract) external onlyOwner {
        associatedContract = _associatedContract;
        emit AssociatedContractUpdated(_associatedContract);
    }

    /* ========== MODIFIERS ========== */

    modifier onlyAssociatedContract {
        require(msg.sender == associatedContract, "Only the associated contract can perform this action");
        _;
    }

    /* ========== EVENTS ========== */

    event AssociatedContractUpdated(address associatedContract);
}

pragma solidity ^0.5.16;

// Libraries
import "openzeppelin-solidity-2.3.0/contracts/math/SafeMath.sol";

library SafeDecimalMath {
    using SafeMath for uint;

    /* Number of decimal places in the representations. */
    uint8 public constant decimals = 18;
    uint8 public constant highPrecisionDecimals = 27;

    /* The number representing 1.0. */
    uint public constant UNIT = 10**uint(decimals);

    /* The number representing 1.0 for higher fidelity numbers. */
    uint public constant PRECISE_UNIT = 10**uint(highPrecisionDecimals);
    uint private constant UNIT_TO_HIGH_PRECISION_CONVERSION_FACTOR = 10**uint(highPrecisionDecimals - decimals);

    /**
     * @return Provides an interface to UNIT.
     */
    function unit() external pure returns (uint) {
        return UNIT;
    }

    /**
     * @return Provides an interface to PRECISE_UNIT.
     */
    function preciseUnit() external pure returns (uint) {
        return PRECISE_UNIT;
    }

    /**
     * @return The result of multiplying x and y, interpreting the operands as fixed-point
     * decimals.
     *
     * @dev A unit factor is divided out after the product of x and y is evaluated,
     * so that product must be less than 2**256. As this is an integer division,
     * the internal division always rounds down. This helps save on gas. Rounding
     * is more expensive on gas.
     */
    function multiplyDecimal(uint x, uint y) internal pure returns (uint) {
        /* Divide by UNIT to remove the extra factor introduced by the product. */
        return x.mul(y) / UNIT;
    }

    /**
     * @return The result of safely multiplying x and y, interpreting the operands
     * as fixed-point decimals of the specified precision unit.
     *
     * @dev The operands should be in the form of a the specified unit factor which will be
     * divided out after the product of x and y is evaluated, so that product must be
     * less than 2**256.
     *
     * Unlike multiplyDecimal, this function rounds the result to the nearest increment.
     * Rounding is useful when you need to retain fidelity for small decimal numbers
     * (eg. small fractions or percentages).
     */
    function _multiplyDecimalRound(
        uint x,
        uint y,
        uint precisionUnit
    ) private pure returns (uint) {
        /* Divide by UNIT to remove the extra factor introduced by the product. */
        uint quotientTimesTen = x.mul(y) / (precisionUnit / 10);

        if (quotientTimesTen % 10 >= 5) {
            quotientTimesTen += 10;
        }

        return quotientTimesTen / 10;
    }

    /**
     * @return The result of safely multiplying x and y, interpreting the operands
     * as fixed-point decimals of a precise unit.
     *
     * @dev The operands should be in the precise unit factor which will be
     * divided out after the product of x and y is evaluated, so that product must be
     * less than 2**256.
     *
     * Unlike multiplyDecimal, this function rounds the result to the nearest increment.
     * Rounding is useful when you need to retain fidelity for small decimal numbers
     * (eg. small fractions or percentages).
     */
    function multiplyDecimalRoundPrecise(uint x, uint y) internal pure returns (uint) {
        return _multiplyDecimalRound(x, y, PRECISE_UNIT);
    }

    /**
     * @return The result of safely multiplying x and y, interpreting the operands
     * as fixed-point decimals of a standard unit.
     *
     * @dev The operands should be in the standard unit factor which will be
     * divided out after the product of x and y is evaluated, so that product must be
     * less than 2**256.
     *
     * Unlike multiplyDecimal, this function rounds the result to the nearest increment.
     * Rounding is useful when you need to retain fidelity for small decimal numbers
     * (eg. small fractions or percentages).
     */
    function multiplyDecimalRound(uint x, uint y) internal pure returns (uint) {
        return _multiplyDecimalRound(x, y, UNIT);
    }

    /**
     * @return The result of safely dividing x and y. The return value is a high
     * precision decimal.
     *
     * @dev y is divided after the product of x and the standard precision unit
     * is evaluated, so the product of x and UNIT must be less than 2**256. As
     * this is an integer division, the result is always rounded down.
     * This helps save on gas. Rounding is more expensive on gas.
     */
    function divideDecimal(uint x, uint y) internal pure returns (uint) {
        /* Reintroduce the UNIT factor that will be divided out by y. */
        return x.mul(UNIT).div(y);
    }

    /**
     * @return The result of safely dividing x and y. The return value is as a rounded
     * decimal in the precision unit specified in the parameter.
     *
     * @dev y is divided after the product of x and the specified precision unit
     * is evaluated, so the product of x and the specified precision unit must
     * be less than 2**256. The result is rounded to the nearest increment.
     */
    function _divideDecimalRound(
        uint x,
        uint y,
        uint precisionUnit
    ) private pure returns (uint) {
        uint resultTimesTen = x.mul(precisionUnit * 10).div(y);

        if (resultTimesTen % 10 >= 5) {
            resultTimesTen += 10;
        }

        return resultTimesTen / 10;
    }

    /**
     * @return The result of safely dividing x and y. The return value is as a rounded
     * standard precision decimal.
     *
     * @dev y is divided after the product of x and the standard precision unit
     * is evaluated, so the product of x and the standard precision unit must
     * be less than 2**256. The result is rounded to the nearest increment.
     */
    function divideDecimalRound(uint x, uint y) internal pure returns (uint) {
        return _divideDecimalRound(x, y, UNIT);
    }

    /**
     * @return The result of safely dividing x and y. The return value is as a rounded
     * high precision decimal.
     *
     * @dev y is divided after the product of x and the high precision unit
     * is evaluated, so the product of x and the high precision unit must
     * be less than 2**256. The result is rounded to the nearest increment.
     */
    function divideDecimalRoundPrecise(uint x, uint y) internal pure returns (uint) {
        return _divideDecimalRound(x, y, PRECISE_UNIT);
    }

    /**
     * @dev Convert a standard decimal representation to a high precision one.
     */
    function decimalToPreciseDecimal(uint i) internal pure returns (uint) {
        return i.mul(UNIT_TO_HIGH_PRECISION_CONVERSION_FACTOR);
    }

    /**
     * @dev Convert a high precision decimal to a standard decimal representation.
     */
    function preciseDecimalToDecimal(uint i) internal pure returns (uint) {
        uint quotientTimesTen = i / (UNIT_TO_HIGH_PRECISION_CONVERSION_FACTOR / 10);

        if (quotientTimesTen % 10 >= 5) {
            quotientTimesTen += 10;
        }

        return quotientTimesTen / 10;
    }

    // Computes `a - b`, setting the value to 0 if b > a.
    function floorsub(uint a, uint b) internal pure returns (uint) {
        return b >= a ? 0 : a - b;
    }
}

pragma solidity ^0.5.16;

// Inheritance
import "./Owned.sol";

// Internal references
import "./Proxy.sol";

contract Proxyable is Owned {
    // This contract should be treated like an abstract contract

    /* The proxy this contract exists behind. */
    Proxy public proxy;
    Proxy public integrationProxy;

    /* The caller of the proxy, passed through to this contract.
     * Note that every function using this member must apply the onlyProxy or
     * optionalProxy modifiers, otherwise their invocations can use stale values. */
    address public messageSender;

    constructor(address payable _proxy) internal {
        // This contract is abstract, and thus cannot be instantiated directly
        require(owner != address(0), "Owner must be set");

        proxy = Proxy(_proxy);
        emit ProxyUpdated(_proxy);
    }

    function setProxy(address payable _proxy) external onlyOwner {
        proxy = Proxy(_proxy);
        emit ProxyUpdated(_proxy);
    }

    function setIntegrationProxy(address payable _integrationProxy) external onlyOwner {
        integrationProxy = Proxy(_integrationProxy);
    }

    function setMessageSender(address sender) external onlyProxy {
        messageSender = sender;
    }

    modifier onlyProxy {
        _onlyProxy();
        _;
    }

    function _onlyProxy() private view {
        require(Proxy(msg.sender) == proxy || Proxy(msg.sender) == integrationProxy, "Only the proxy can call");
    }

    modifier optionalProxy {
        _optionalProxy();
        _;
    }

    function _optionalProxy() private {
        if (Proxy(msg.sender) != proxy && Proxy(msg.sender) != integrationProxy && messageSender != msg.sender) {
            messageSender = msg.sender;
        }
    }

    modifier optionalProxy_onlyOwner {
        _optionalProxy_onlyOwner();
        _;
    }

    // solhint-disable-next-line func-name-mixedcase
    function _optionalProxy_onlyOwner() private {
        if (Proxy(msg.sender) != proxy && Proxy(msg.sender) != integrationProxy && messageSender != msg.sender) {
            messageSender = msg.sender;
        }
        require(messageSender == owner, "Owner only function");
    }

    event ProxyUpdated(address proxyAddress);
}

pragma solidity ^0.5.16;

// Inheritance
import "./Owned.sol";

// Internal references
import "./Proxyable.sol";

contract Proxy is Owned {
    Proxyable public target;

    constructor(address _owner) public Owned(_owner) {}

    function setTarget(Proxyable _target) external onlyOwner {
        target = _target;
        emit TargetUpdated(_target);
    }

    function _emit(
        bytes calldata callData,
        uint numTopics,
        bytes32 topic1,
        bytes32 topic2,
        bytes32 topic3,
        bytes32 topic4
    ) external onlyTarget {
        uint size = callData.length;
        bytes memory _callData = callData;

        assembly {
            /* The first 32 bytes of callData contain its length (as specified by the abi).
             * Length is assumed to be a uint256 and therefore maximum of 32 bytes
             * in length. It is also leftpadded to be a multiple of 32 bytes.
             * This means moving call_data across 32 bytes guarantees we correctly access
             * the data itself. */
            switch numTopics
                case 0 {
                    log0(add(_callData, 32), size)
                }
                case 1 {
                    log1(add(_callData, 32), size, topic1)
                }
                case 2 {
                    log2(add(_callData, 32), size, topic1, topic2)
                }
                case 3 {
                    log3(add(_callData, 32), size, topic1, topic2, topic3)
                }
                case 4 {
                    log4(add(_callData, 32), size, topic1, topic2, topic3, topic4)
                }
        }
    }

    // solhint-disable no-complex-fallback
    function() external payable {
        // Mutable call setting Proxyable.messageSender as this is using call not delegatecall
        target.setMessageSender(msg.sender);

        assembly {
            let free_ptr := mload(0x40)
            calldatacopy(free_ptr, 0, calldatasize)

            /* We must explicitly forward ether to the underlying contract as well. */
            let result := call(gas, sload(target_slot), callvalue, free_ptr, calldatasize, 0, 0)
            returndatacopy(free_ptr, 0, returndatasize)

            if iszero(result) {
                revert(free_ptr, returndatasize)
            }
            return(free_ptr, returndatasize)
        }
    }

    modifier onlyTarget {
        require(Proxyable(msg.sender) == target, "Must be proxy target");
        _;
    }

    event TargetUpdated(Proxyable newTarget);
}

pragma solidity ^0.5.16;

contract Owned {
    address public owner;
    address public nominatedOwner;

    constructor(address _owner) public {
        require(_owner != address(0), "Owner address cannot be 0");
        owner = _owner;
        emit OwnerChanged(address(0), _owner);
    }

    function nominateNewOwner(address _owner) external onlyOwner {
        nominatedOwner = _owner;
        emit OwnerNominated(_owner);
    }

    function acceptOwnership() external {
        require(msg.sender == nominatedOwner, "You must be nominated before you can accept ownership");
        emit OwnerChanged(owner, nominatedOwner);
        owner = nominatedOwner;
        nominatedOwner = address(0);
    }

    modifier onlyOwner {
        _onlyOwner();
        _;
    }

    function _onlyOwner() private view {
        require(msg.sender == owner, "Only the contract owner may perform this action");
    }

    event OwnerNominated(address newOwner);
    event OwnerChanged(address oldOwner, address newOwner);
}

pragma solidity ^0.5.16;

// Internal references
import "./AddressResolver.sol";

contract MixinResolver {
    AddressResolver public resolver;

    mapping(bytes32 => address) private addressCache;

    constructor(address _resolver) internal {
        resolver = AddressResolver(_resolver);
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function combineArrays(bytes32[] memory first, bytes32[] memory second)
        internal
        pure
        returns (bytes32[] memory combination)
    {
        combination = new bytes32[](first.length + second.length);

        for (uint i = 0; i < first.length; i++) {
            combination[i] = first[i];
        }

        for (uint j = 0; j < second.length; j++) {
            combination[first.length + j] = second[j];
        }
    }

    /* ========== PUBLIC FUNCTIONS ========== */

    // Note: this function is public not external in order for it to be overridden and invoked via super in subclasses
    function resolverAddressesRequired() public view returns (bytes32[] memory addresses) {}

    function rebuildCache() public {
        bytes32[] memory requiredAddresses = resolverAddressesRequired();
        // The resolver must call this function whenver it updates its state
        for (uint i = 0; i < requiredAddresses.length; i++) {
            bytes32 name = requiredAddresses[i];
            // Note: can only be invoked once the resolver has all the targets needed added
            address destination =
                resolver.requireAndGetAddress(name, string(abi.encodePacked("Resolver missing target: ", name)));
            addressCache[name] = destination;
            emit CacheUpdated(name, destination);
        }
    }

    /* ========== VIEWS ========== */

    function isResolverCached() external view returns (bool) {
        bytes32[] memory requiredAddresses = resolverAddressesRequired();
        for (uint i = 0; i < requiredAddresses.length; i++) {
            bytes32 name = requiredAddresses[i];
            // false if our cache is invalid or if the resolver doesn't have the required address
            if (resolver.getAddress(name) != addressCache[name] || addressCache[name] == address(0)) {
                return false;
            }
        }

        return true;
    }

    /* ========== INTERNAL FUNCTIONS ========== */

    function requireAndGetAddress(bytes32 name) internal view returns (address) {
        address _foundAddress = addressCache[name];
        require(_foundAddress != address(0), string(abi.encodePacked("Missing address: ", name)));
        return _foundAddress;
    }

    /* ========== EVENTS ========== */

    event CacheUpdated(bytes32 name, address destination);
}

pragma solidity ^0.5.16;

// Inheritance
import "./Owned.sol";
import "./Proxyable.sol";

// Libraries
import "./SafeDecimalMath.sol";

// Internal references
import "./TokenState.sol";

contract ExternStateToken is Owned, Proxyable {
    using SafeMath for uint;
    using SafeDecimalMath for uint;

    /* ========== STATE VARIABLES ========== */

    /* Stores balances and allowances. */
    TokenState public tokenState;

    /* Other ERC20 fields. */
    string public name;
    string public symbol;
    uint public totalSupply;
    uint8 public decimals;

    constructor(
        address payable _proxy,
        TokenState _tokenState,
        string memory _name,
        string memory _symbol,
        uint _totalSupply,
        uint8 _decimals,
        address _owner
    ) public Owned(_owner) Proxyable(_proxy) {
        tokenState = _tokenState;

        name = _name;
        symbol = _symbol;
        totalSupply = _totalSupply;
        decimals = _decimals;
    }

    /* ========== VIEWS ========== */

    /**
     * @notice Returns the ERC20 allowance of one party to spend on behalf of another.
     * @param owner The party authorising spending of their funds.
     * @param spender The party spending tokenOwner's funds.
     */
    function allowance(address owner, address spender) public view returns (uint) {
        return tokenState.allowance(owner, spender);
    }

    /**
     * @notice Returns the ERC20 token balance of a given account.
     */
    function balanceOf(address account) external view returns (uint) {
        return tokenState.balanceOf(account);
    }

    /* ========== MUTATIVE FUNCTIONS ========== */

    /**
     * @notice Set the address of the TokenState contract.
     * @dev This can be used to "pause" transfer functionality, by pointing the tokenState at 0x000..
     * as balances would be unreachable.
     */
    function setTokenState(TokenState _tokenState) external optionalProxy_onlyOwner {
        tokenState = _tokenState;
        emitTokenStateUpdated(address(_tokenState));
    }

    function _internalTransfer(
        address from,
        address to,
        uint value
    ) internal returns (bool) {
        /* Disallow transfers to irretrievable-addresses. */
        require(to != address(0) && to != address(this) && to != address(proxy), "Cannot transfer to this address");

        // Insufficient balance will be handled by the safe subtraction.
        tokenState.setBalanceOf(from, tokenState.balanceOf(from).sub(value));
        tokenState.setBalanceOf(to, tokenState.balanceOf(to).add(value));

        // Emit a standard ERC20 transfer event
        emitTransfer(from, to, value);

        return true;
    }

    /**
     * @dev Perform an ERC20 token transfer. Designed to be called by transfer functions possessing
     * the onlyProxy or optionalProxy modifiers.
     */
    function _transferByProxy(
        address from,
        address to,
        uint value
    ) internal returns (bool) {
        return _internalTransfer(from, to, value);
    }

    /*
     * @dev Perform an ERC20 token transferFrom. Designed to be called by transferFrom functions
     * possessing the optionalProxy or optionalProxy modifiers.
     */
    function _transferFromByProxy(
        address sender,
        address from,
        address to,
        uint value
    ) internal returns (bool) {
        /* Insufficient allowance will be handled by the safe subtraction. */
        tokenState.setAllowance(from, sender, tokenState.allowance(from, sender).sub(value));
        return _internalTransfer(from, to, value);
    }

    /**
     * @notice Approves spender to transfer on the message sender's behalf.
     */
    function approve(address spender, uint value) public optionalProxy returns (bool) {
        address sender = messageSender;

        tokenState.setAllowance(sender, spender, value);
        emitApproval(sender, spender, value);
        return true;
    }

    /* ========== EVENTS ========== */
    function addressToBytes32(address input) internal pure returns (bytes32) {
        return bytes32(uint256(uint160(input)));
    }

    event Transfer(address indexed from, address indexed to, uint value);
    bytes32 internal constant TRANSFER_SIG = keccak256("Transfer(address,address,uint256)");

    function emitTransfer(
        address from,
        address to,
        uint value
    ) internal {
        proxy._emit(abi.encode(value), 3, TRANSFER_SIG, addressToBytes32(from), addressToBytes32(to), 0);
    }

    event Approval(address indexed owner, address indexed spender, uint value);
    bytes32 internal constant APPROVAL_SIG = keccak256("Approval(address,address,uint256)");

    function emitApproval(
        address owner,
        address spender,
        uint value
    ) internal {
        proxy._emit(abi.encode(value), 3, APPROVAL_SIG, addressToBytes32(owner), addressToBytes32(spender), 0);
    }

    event TokenStateUpdated(address newTokenState);
    bytes32 internal constant TOKENSTATEUPDATED_SIG = keccak256("TokenStateUpdated(address)");

    function emitTokenStateUpdated(address newTokenState) internal {
        proxy._emit(abi.encode(newTokenState), 1, TOKENSTATEUPDATED_SIG, 0, 0, 0);
    }
}

pragma solidity ^0.5.16;

// Inheritance
import "./Owned.sol";
import "./interfaces/IAddressResolver.sol";

// Internal references
import "./interfaces/IIssuer.sol";
import "./MixinResolver.sol";

contract AddressResolver is Owned, IAddressResolver {
    mapping(bytes32 => address) public repository;

    constructor(address _owner) public Owned(_owner) {}

    /* ========== RESTRICTED FUNCTIONS ========== */

    function importAddresses(bytes32[] calldata names, address[] calldata destinations) external onlyOwner {
        require(names.length == destinations.length, "Input lengths must match");

        for (uint i = 0; i < names.length; i++) {
            bytes32 name = names[i];
            address destination = destinations[i];
            repository[name] = destination;
            emit AddressImported(name, destination);
        }
    }

    /* ========= PUBLIC FUNCTIONS ========== */

    function rebuildCaches(MixinResolver[] calldata destinations) external {
        for (uint i = 0; i < destinations.length; i++) {
            destinations[i].rebuildCache();
        }
    }

    /* ========== VIEWS ========== */

    function areAddressesImported(bytes32[] calldata names, address[] calldata destinations) external view returns (bool) {
        for (uint i = 0; i < names.length; i++) {
            if (repository[names[i]] != destinations[i]) {
                return false;
            }
        }
        return true;
    }

    function getAddress(bytes32 name) external view returns (address) {
        return repository[name];
    }

    function requireAndGetAddress(bytes32 name, string calldata reason) external view returns (address) {
        address _foundAddress = repository[name];
        require(_foundAddress != address(0), reason);
        return _foundAddress;
    }

    function getPhant(bytes32 key) external view returns (address) {
        IIssuer issuer = IIssuer(repository["Issuer"]);
        require(address(issuer) != address(0), "Cannot find Issuer address");
        return address(issuer.phants(key));
    }

    /* ========== EVENTS ========== */

    event AddressImported(bytes32 name, address destination);
}

pragma solidity ^0.5.0;

/**
 * @dev Wrappers over Solidity's arithmetic operations with added overflow
 * checks.
 *
 * Arithmetic operations in Solidity wrap on overflow. This can easily result
 * in bugs, because programmers usually assume that an overflow raises an
 * error, which is the standard behavior in high level programming languages.
 * `SafeMath` restores this intuition by reverting the transaction when an
 * operation overflows.
 *
 * Using this library instead of the unchecked operations eliminates an entire
 * class of bugs, so it's recommended to use it always.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        uint256 c = a + b;
        require(c >= a, "SafeMath: addition overflow");

        return c;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b <= a, "SafeMath: subtraction overflow");
        uint256 c = a - b;

        return c;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
        if (a == 0) {
            return 0;
        }

        uint256 c = a * b;
        require(c / a == b, "SafeMath: multiplication overflow");

        return c;
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        // Solidity only automatically asserts when dividing by 0
        require(b > 0, "SafeMath: division by zero");
        uint256 c = a / b;
        // assert(a == b * c + a % b); // There is no case in which this doesn't hold

        return c;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        require(b != 0, "SafeMath: modulo by zero");
        return a % b;
    }
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