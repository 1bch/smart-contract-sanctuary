// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.4;

import {VaultToken} from "./VaultToken.sol";
import {Clones} from "../oz/proxy/Clones.sol";
import {ReentrancyGuard} from "../oz/security/ReentrancyGuard.sol";

contract Factory is ReentrancyGuard {

    error Unauthorized();
    error Invalid();
    error TooHighFee();
    error ContractCreationFailed();
    error ZeroAddress();

    /// @notice Protocol-level fees for deposits represented with two decimals of precision up to 50% (5000)
    uint16 public depositFee;
    /// @notice Protocol-level fees for performance (sell calls) with two decimals of precision up to 50% (5000)
    uint16 public performanceFee;
    /// @notice Protocol-level fees for withdrawals represented with two decimals of precision up to 50% (5000)
    uint16 public withdrawalFee;
    /// @notice Current implementation of the VaultToken
    address public currentImplementation;
    /// @notice Address of the Gamma AddressBook
    address public immutable addressBook;
    /// @notice Address of the admin
    address public admin;
    /// @notice Address of the airswap exchange
    address public immutable airswapExchange;

    event NewVaultToken(address indexed manager, address indexed asset, address indexed vaultToken);
    event DepositFeeModified(uint16 newFee);
    event PerformanceFeeModified(uint16 newFee);
    event WithdrawalFeeModified(uint16 newFee);
    event ImplementationChanged(address newImplementation);
    event AdminChanged(address newAdmin);

    constructor(
        address _exchange,
        address _addressBook,
        address _currentImplementation,
        address _admin,
        uint16 _depositFee,
        uint16 _performanceFee,
        uint16 _withdrawalFee
    ) {
        require(_exchange != address(0) || _addressBook != address(0) || _admin != address(0), "0 address");
        require(_depositFee <= 5000 && _performanceFee <= 5000 && _withdrawalFee <= 5000, "too high fee");

        currentImplementation = _currentImplementation;
        airswapExchange = _exchange;
        addressBook = _addressBook;
        admin = _admin;
        
        depositFee = _depositFee;
        performanceFee = _performanceFee;
        withdrawalFee = _withdrawalFee;
    }

    modifier onlyAdmin {
        _onlyAdmin();
        _;
    }

    function changeDepositFee(uint16 _newFee) external nonReentrant() onlyAdmin {
        if(_newFee > 5000)
            revert TooHighFee();

        depositFee = _newFee;

        emit DepositFeeModified(_newFee);
    }

    function changePerformanceFee(uint16 _newFee) external nonReentrant() onlyAdmin {
        if(_newFee > 5000)
            revert TooHighFee();

        performanceFee = _newFee;

        emit PerformanceFeeModified(_newFee);
    }
    
    function changeWithdrawalFee(uint16 _newFee) external nonReentrant() onlyAdmin {
        if(_newFee > 5000)
            revert TooHighFee();

        withdrawalFee = _newFee;

        emit WithdrawalFeeModified(_newFee);
    }
    
    function changeCurrentImplementation(address _newImplementation) external nonReentrant() onlyAdmin {
        if(_newImplementation == address(0))
            revert ZeroAddress();
            
        currentImplementation = _newImplementation;

        emit ImplementationChanged(_newImplementation);
    }

    function changeAdmin(address _newAdmin) external nonReentrant() onlyAdmin {
        if(_newAdmin == address(0))
            revert ZeroAddress();

        admin = _newAdmin;

        emit AdminChanged(_newAdmin);
    }

    /// @notice Deploys a new vault token
    /// @dev Deploys a new vault token under the given parameters for the caller
    /// @param _name name of the vault token
    /// @param _symbol symbol of the vault token
    /// @param _asset address of the asset token (what the vault is denominated in)
    /// @param _withdrawalWindowLength length of the withdrawal window
    /// @param _maximumAssets max AUM denominated in the asset token
    function deployNewVaultToken(
        string memory _name,
        string memory _symbol,
        address _asset,
        uint256 _withdrawalWindowLength,
        uint256 _maximumAssets
    ) external nonReentrant() {
        if(_asset == address(0) || currentImplementation == address(0))
            revert ZeroAddress();
        
        VaultToken vToken = VaultToken(Clones.clone(currentImplementation));

        vToken.initialize(
            _name,
            _symbol,
            _asset,
            msg.sender,
            addressBook,
            address(this),
            _withdrawalWindowLength,
            _maximumAssets
        );

        emit NewVaultToken(msg.sender, _asset, address(vToken));
    }

    function _onlyAdmin() internal view {
        if(msg.sender != admin)
            revert Unauthorized();
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuard {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    constructor() {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev https://eips.ethereum.org/EIPS/eip-1167[EIP 1167] is a standard for
 * deploying minimal proxy contracts, also known as "clones".
 *
 * > To simply and cheaply clone contract functionality in an immutable way, this standard specifies
 * > a minimal bytecode implementation that delegates all calls to a known, fixed address.
 *
 * The library includes functions to deploy a proxy using either `create` (traditional deployment) or `create2`
 * (salted deterministic deployment). It also includes functions to predict the addresses of clones deployed using the
 * deterministic method.
 *
 * _Available since v3.4._
 */
library Clones {
    /**
     * @dev Deploys and returns the address of a clone that mimics the behaviour of `implementation`.
     *
     * This function uses the create opcode, which should never revert.
     */
    function clone(address implementation) internal returns (address instance) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create(0, ptr, 0x37)
        }
        require(instance != address(0), "ERC1167: create failed");
    }

    /**
     * @dev Deploys and returns the address of a clone that mimics the behaviour of `implementation`.
     *
     * This function uses the create2 opcode and a `salt` to deterministically deploy
     * the clone. Using the same `implementation` and `salt` multiple time will revert, since
     * the clones cannot be deployed twice at the same address.
     */
    function cloneDeterministic(address implementation, bytes32 salt) internal returns (address instance) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000)
            instance := create2(0, ptr, 0x37, salt)
        }
        require(instance != address(0), "ERC1167: create2 failed");
    }

    /**
     * @dev Computes the address of a clone deployed using {Clones-cloneDeterministic}.
     */
    function predictDeterministicAddress(
        address implementation,
        bytes32 salt,
        address deployer
    ) internal pure returns (address predicted) {
        assembly {
            let ptr := mload(0x40)
            mstore(ptr, 0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000)
            mstore(add(ptr, 0x14), shl(0x60, implementation))
            mstore(add(ptr, 0x28), 0x5af43d82803e903d91602b57fd5bf3ff00000000000000000000000000000000)
            mstore(add(ptr, 0x38), shl(0x60, deployer))
            mstore(add(ptr, 0x4c), salt)
            mstore(add(ptr, 0x6c), keccak256(ptr, 0x37))
            predicted := keccak256(add(ptr, 0x37), 0x55)
        }
    }

    /**
     * @dev Computes the address of a clone deployed using {Clones-cloneDeterministic}.
     */
    function predictDeterministicAddress(address implementation, bytes32 salt)
        internal
        view
        returns (address predicted)
    {
        return predictDeterministicAddress(implementation, salt, address(this));
    }
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.4;

import {IFactory} from "./interfaces/IFactory.sol";
import {ISwap, Types} from "./airswap/interfaces/ISwap.sol";
import {IAddressBook} from "./gamma/interfaces/IAddressBook.sol";
import {Actions, GammaTypes, IController} from "./gamma/interfaces/IController.sol";
import {OtokenInterface} from "./gamma/interfaces/OtokenInterface.sol";
import {ERC20Upgradeable} from "../oz/token/ERC20/ERC20Upgradeable.sol";
import {ERC20, IERC20} from "../oz/token/ERC20/ERC20.sol";
import {SafeERC20} from "../oz/token/ERC20/utils/SafeERC20.sol";
import {PausableUpgradeable} from "../oz/security/PausableUpgradeable.sol";
import {ReentrancyGuardUpgradeable} from "../oz/security/ReentrancyGuardUpgradeable.sol";

contract VaultToken is ERC20Upgradeable, PausableUpgradeable, ReentrancyGuardUpgradeable {
    using SafeERC20 for IERC20;

    error Unauthorized();
    error Unauthorized_COUNTERPARTY_DID_NOT_SIGN();
    error Invalid();
    error NotEnoughFunds();
    error NotEnoughFunds_ReserveViolation();
    error NotEnoughFunds_ObligatedFees();
    error MaximumFundsReached();
    error RatioAlreadyDefined();
    error WithdrawalWindowNotActive();
    error WithdrawalWindowActive();
    error oTokenNotCleared();
    error SettlementNotReady();
    error ClosedPermanently();

    /// @notice Time in which the withdrawal window expires
    uint256 public withdrawalWindowExpires;
    /// @notice Length of time where the withdrawal window is active
    uint256 public withdrawalWindowLength;
    /// @notice Amount of collateral for the address already used for collateral
    uint256 public collateralAmount;
    /// @notice Current active vault
    uint256 private currentVaultId;
    /// @notice Maximum funds
    uint256 public maximumAssets;
    /// @notice Obligated fees to the manager
    uint256 public obligatedFees;
    /// @notice Deposit fee
    uint16 public depositFee;
    /// @notice Take profit fee
    uint16 public withdrawalFee;
    /// @notice Performance fee (taken when options are sold)
    uint16 public performanceFee;
    /// @notice Withdrawal reserve percentage
    uint16 public withdrawalReserve;
    /// @notice Current reserves
    uint256 public currentReserves;
    /// @notice Address of the current oToken
    address public oToken;
    /// @notice Address of the AddressBook
    IAddressBook private addressBook;
    /// @notice Address of the underlying asset to trade
    address public asset;
    /// @notice Address of the manager (admin)
    address public manager;
    /// @notice Address of the factory
    IFactory public factory;
    /// @notice Determines if the vault is closed permanently
    bool public closedPermanently;

    event Deposit(uint256 assetDeposited, uint256 vaultTokensMinted);
    event Withdrawal(uint256 assetWithdrew, uint256 vaultTokensBurned);
    event WithdrawalWindowActivated(uint256 closesAfter);
    event OptionsMinted(uint256 collateralDeposited, address indexed newOtoken, uint256 vaultId);
    event OptionsBurned(uint256 oTokensBurned);
    event OptionsSold(uint256 amountSold, uint256 premiumReceived);
    event ReservesEstablished(uint256 allocatedReserves);
    event MaximumAssetsModified(uint256 newAUM);
    event DepositFeeModified(uint16 newFee);
    event WithdrawalFeeModified(uint16 newFee);
    event PerformanceFeeModified(uint16 newFee);
    event WithdrawalReserveModified(uint16 newReserve);

    modifier onlyManager {
        _onlyManager();
        _;
    }
    modifier withdrawalWindowCheck(bool _revertIfClosed) {
        _withdrawalWindowCheck(_revertIfClosed);
        _;
    }
    modifier ifNotClosed {
        _ifNotClosed();
        _;
    }

    function initialize(
        string memory _name,
        string memory _symbol,
        address _asset,
        address _manager,
        address _addressBook,
        address _factory,
        uint256 _withdrawalWindowLength,
        uint256 _maximumAssets
    ) external initializer {
        __ERC20_init_unchained(_name, _symbol);
        asset = _asset;
        manager = _manager;
        addressBook = IAddressBook(_addressBook);
        factory = IFactory(_factory);
        withdrawalWindowLength = _withdrawalWindowLength;
        maximumAssets = _maximumAssets;
    }

    /// @notice For emergency use
    /// @dev Stops all activities on the vault (or reactivates them)
    /// @param _pause true to pause the vault, false to unpause the vault
    function emergency(bool _pause) external ifNotClosed onlyManager {
        if(_pause)
            super._pause();
        else
            super._unpause();
    }

    /// @notice Changes the maximum allowed deposits under management
    /// @dev Changes the maximumAssets to the new amount
    /// @param _newValue new maximumAssets value
    function adjustTheMaximumAssets(uint256 _newValue) external ifNotClosed onlyManager nonReentrant() whenNotPaused() {
        if(_newValue < collateralAmount + IERC20(asset).balanceOf(address(this)))
            revert Invalid();

        maximumAssets = _newValue;

        emit MaximumAssetsModified(_newValue);
    }

    /// @notice Changes the deposit fee
    /// @dev Changes the depositFee with two decimals of precision up to 50.00% (5000)
    /// @param _newValue new depositFee with two decimals of precision
    function adjustDepositFee(uint16 _newValue) external ifNotClosed onlyManager nonReentrant() whenNotPaused() {
        if(_newValue > 5000)
            revert Invalid();

        depositFee = _newValue;

        emit DepositFeeModified(_newValue);
    }

    /// @notice Changes the withdrawal fee
    /// @dev Changes the withdrawalFee with two decimals of precision up to 50.00% (5000)
    /// @param _newValue new withdrawalFee with two decimals of precision
    function adjustWithdrawalFee(uint16 _newValue) external ifNotClosed onlyManager nonReentrant() whenNotPaused() {
        if(_newValue > 5000)
            revert Invalid();

        withdrawalFee = _newValue;

        emit WithdrawalFeeModified(_newValue);
    }
    
    /// @notice Changes the performance fee
    /// @dev Changes the performanceFee with two decimals of precision up to 50.00% (5000)
    /// @param _newValue new performanceFee with two decimals of precision
    function adjustPerformanceFee(uint16 _newValue) external ifNotClosed onlyManager nonReentrant() whenNotPaused() {
        if(_newValue > 5000)
            revert Invalid();
            
        performanceFee = _newValue;
        
        emit PerformanceFeeModified(_newValue);
    }

    /// @notice Changes the withdrawal reserve percentage
    /// @dev Changes the withdrawalReserve with two decimals of precision up to 50.00% (5000)
    /// @param _newValue new withdrawalReserve with two decimals of precision
    function adjustWithdrawalReserve(uint16 _newValue) external ifNotClosed onlyManager nonReentrant() whenNotPaused() {
        if(_newValue > 5000)
            revert Invalid();

        withdrawalReserve = _newValue;

        emit WithdrawalReserveModified(_newValue);
    }

    /// @notice Changes the withdrawal window length
    /// @dev Changes the withdrawalWindowLength
    /// @param _newValue new withdrawalWindowLength period
    function adjustWithdrawalWindowLength(uint256 _newValue) external ifNotClosed onlyManager nonReentrant() whenNotPaused() {
        withdrawalWindowLength = _newValue;
    }

    /// @notice Allows the manager to collect fees
    /// @dev Transfers all of the obligatedFees to the manager and sets it to zero
    function sweepFees() external ifNotClosed onlyManager nonReentrant() whenNotPaused() {
        IERC20(asset).safeTransfer(msg.sender, obligatedFees);
        obligatedFees = 0;
    }

    /// @notice Allows the manager to disperse obligatedFees to the depositors
    /// @dev Transfers _amount to the vault and deducts against obligatedFees
    function disperseFees(uint256 _amount) external ifNotClosed onlyManager nonReentrant() whenNotPaused() {
        if(_amount > obligatedFees)
            revert NotEnoughFunds_ObligatedFees();

        obligatedFees -= _amount;
    }

    function closeVaultPermanently() external ifNotClosed onlyManager nonReentrant() whenNotPaused() {
        if(oToken != address(0))
            revert oTokenNotCleared();

        closedPermanently = true;
        currentReserves = IERC20(asset).balanceOf(address(this));
    }
    
    /// @notice Deposit assets and receive vault tokens to represent a share
    /// @dev Deposits an amount of assets specified then mints vault tokens to the msg.sender
    /// @param _amount amount to deposit of ASSET
    function deposit(uint256 _amount) external ifNotClosed nonReentrant() whenNotPaused() {
        if(_amount == 0)
            revert Invalid();
        
        uint256 adjustedBal = collateralAmount + IERC20(asset).balanceOf(address(this)) - obligatedFees;
            
        if(adjustedBal + _amount > maximumAssets)
            revert MaximumFundsReached();

        uint256 vaultMint;
        uint256 protocolFees;
        uint256 vaultFees;

        // Calculate protocol-level fees
        if(factory.depositFee() != 0) {
            protocolFees = _percentMultiply(_amount, factory.depositFee());
        }

        // Calculate vault-level fees
        if(depositFee != 0) {
            vaultFees = _percentMultiply(_amount, depositFee);
        }

        // Check if the total supply is zero
        if(totalSupply() == 0) {
            vaultMint = _normalize(_amount - protocolFees - vaultFees, ERC20(asset).decimals(), decimals());
            withdrawalWindowExpires = block.timestamp + withdrawalWindowLength;
        } else {
            vaultMint = totalSupply() * (_amount - protocolFees - vaultFees) / (adjustedBal);
        }

        obligatedFees += vaultFees;

        if(vaultMint == 0) // Safety check for rounding errors
            revert Invalid();

        IERC20(asset).safeTransferFrom(msg.sender, address(this), _amount);
        if(protocolFees > 0)
            IERC20(asset).safeTransfer(factory.admin(), protocolFees);
        _mint(msg.sender, vaultMint);

        emit Deposit(_amount, vaultMint);
    }

    /// @notice Redeem vault tokens for assets
    /// @dev Burns vault tokens in redemption for the assets to msg.sender
    /// @param _amount amount of VAULT TOKENS to burn
    function withdraw(uint256 _amount) external nonReentrant() whenNotPaused() {
        if(_amount == 0)
            revert Invalid();

        uint256 assetAmount = _amount * (IERC20(asset).balanceOf(address(this)) + collateralAmount - obligatedFees) / totalSupply();
        uint256 protocolFee;
        uint256 vaultFee;
        
        if(factory.withdrawalFee() > 0) {
            protocolFee = _percentMultiply(_amount, factory.withdrawalFee());
            IERC20(asset).safeTransfer(factory.admin(), protocolFee);
        }
        if(withdrawalFee > 0) {
            vaultFee = _percentMultiply(_amount, withdrawalFee);
            obligatedFees += vaultFee;
        }

        assetAmount -= (protocolFee + vaultFee);

        // Safety check
        if(assetAmount == 0)
            revert Invalid();

        // (Reserve) safety check
        if(assetAmount > currentReserves && _withdrawalWindowCheck(false) && oToken != address(0))
            revert NotEnoughFunds_ReserveViolation();

        if(_withdrawalWindowCheck(false) && oToken != address(0))
            currentReserves -= assetAmount;

        IERC20(asset).safeTransfer(msg.sender, assetAmount); // Vault Token Amount to Burn * Balance of Vault for Asset  / Total Vault Token Supply
        _burn(address(msg.sender), _amount);

        emit Withdrawal(assetAmount, _amount);
    }

    /// @notice Allows anyone to call it in the event the withdrawal window is closed, but no action has occurred within 1 day
    /// @dev Reopens the withdrawal window for a minimum of one day, whichever is greater
    function reactivateWithdrawalWindow() external ifNotClosed nonReentrant() whenNotPaused() {
        if(block.timestamp < withdrawalWindowExpires + 1 days)
            revert Invalid();
        
        if(withdrawalWindowLength > 1 days)
            withdrawalWindowExpires = block.timestamp + withdrawalWindowLength;
        else
            withdrawalWindowExpires = block.timestamp + 1 days;

        emit WithdrawalWindowActivated(withdrawalWindowExpires);
    }

    /// @notice Write options for an _amount of asset for the specified oToken
    /// @dev Allows the manager to write options for an x 
    /// @param _amount amount of the asset to deposit as collateral
    /// @param _oToken address of the oToken
    function writeOptions(uint256 _amount, address _oToken) external ifNotClosed onlyManager nonReentrant() whenNotPaused() {
        _writeOptions(_amount, _oToken);
    }

    /// @notice Write options for a _percentage of the current balance of the vault
    /// @dev Uses percentage of the vault instead of a specific number (helpful for multi-sigs)
    /// @param _percentage A uint16 representing up to 10000 (100.00%) with two decimals of precision for the amount of asset tokens to write
    /// @param _oToken address of the oToken
    function writeOptions(uint16 _percentage, address _oToken) external ifNotClosed onlyManager nonReentrant() whenNotPaused() {
        if(_percentage > 10000)
            revert Invalid();

        if(_percentage > _percentage - withdrawalReserve)
            _percentage -= withdrawalReserve;
        
        _writeOptions(
            _percentMultiply(
                IERC20(asset).balanceOf(address(this)) - currentReserves - obligatedFees, _percentage
            ),
            _oToken
        );
    }

    /// @notice Burns away the oTokens to redeem the asset collateral
    /// @dev Operation to burn away the oTOkens in redemption of the asset collateral
    /// @param _amount Amount of options to burn
    function burnOptions(uint256 _amount) external ifNotClosed onlyManager nonReentrant() whenNotPaused() {
        if(!_withdrawalWindowCheck(false))
            revert WithdrawalWindowActive();
        if(_amount > IERC20(oToken).balanceOf(address(this)))
            revert Invalid();

        Actions.ActionArgs[] memory actions = new Actions.ActionArgs[](2);
        uint256 normalizedAmount;
        
        if(OtokenInterface(oToken).isPut()) {
            normalizedAmount = _normalize(_amount * OtokenInterface(oToken).strikePrice(), 14, ERC20(asset).decimals());
        } else {
           normalizedAmount = _normalize(_amount, 8, 18);
        }

        actions[0] = Actions.ActionArgs(
            Actions.ActionType.BurnShortOption,
            address(this),
            address(this),
            oToken,
            currentVaultId,
            _amount,
            0,
            ""
        );
        actions[1] = Actions.ActionArgs(
            Actions.ActionType.WithdrawCollateral,
            address(this),
            address(this),
            asset,
            currentVaultId,
            normalizedAmount,
            0,
            ""
        );

        IController controller = IController(addressBook.getController());

        controller.operate(actions);
        collateralAmount -= normalizedAmount;

        if(collateralAmount == 0 && IERC20(oToken).balanceOf(address(this)) == 0) {
            // Withdrawal window reopens
            withdrawalWindowExpires = block.timestamp + withdrawalWindowLength;
            oToken = address(0);

            emit WithdrawalWindowActivated(withdrawalWindowExpires);
        }

        emit OptionsBurned(_amount);
    }

    /// @notice Operation to sell options to an EXISTING order on AirSwap (via off-chain signature)
    /// @dev Sells options via AirSwap that exists by the counterparty grabbed off-chain
    /// @param _order AirSwap order details
    function sellOptions(Types.Order memory _order) external ifNotClosed onlyManager nonReentrant() whenNotPaused() {
        _sellOptions(_order);
    }

    /// @notice Operation to both write AND sell options
    /// @dev Operation that can handle both the `writeOptions()` and `sellOptions()` at the same time
    /// @param _amount Amount of the asset token to collateralize the option
    /// @param _oToken Address of the oToken to write with
    /// @param _order AirSwap order
    function writeAndSellOptions(
        uint256 _amount,
        address _oToken,
        Types.Order memory _order
    ) external onlyManager nonReentrant() whenNotPaused() {
        _writeOptions(
            _amount,
            _oToken
        );
        _sellOptions(
            _order
        );
    }

    /// @notice Operation to both write AND sell options
    /// @dev Operation that can handle both the `writeOptions()` and `sellOptions()` at the same time
    /// @param _percentage Percentage of the available asset tokens to write and sell
    /// @param _oToken Address of the oToken to write with
    /// @param _order AirSwap order
    function writeAndSellOptions(
        uint16 _percentage,
        address _oToken,
        Types.Order memory _order
    ) external ifNotClosed onlyManager nonReentrant() whenNotPaused() {
        if(_percentage > _percentage - withdrawalReserve)
            _percentage -= withdrawalReserve;

        _writeOptions(
            _percentMultiply(
                IERC20(asset).balanceOf(address(this)) - obligatedFees,
                _percentage
            ),
            _oToken
        );
        _sellOptions(_order);
    }

    /// @notice Operation to settle the vault
    /// @dev Settles the currently open vault and opens the withdrawal window
    function settleVault() external ifNotClosed onlyManager nonReentrant() whenNotPaused() {
        if(!_withdrawalWindowCheck(false))
            revert WithdrawalWindowActive();

        IController controller = IController(addressBook.getController());

        // Check if ready to settle otherwise revert
        if(!controller.isSettlementAllowed(oToken))
            revert SettlementNotReady();

        // Settle the vault if ready
        Actions.ActionArgs[] memory action = new Actions.ActionArgs[](1);
        action[0] = Actions.ActionArgs(
            Actions.ActionType.SettleVault,
            address(this),
            address(this),
            address(0),
            currentVaultId,
            IERC20(oToken).balanceOf(address(this)),
            0,
            ""
        );

        controller.operate(action);

        // Withdrawal window opens
        withdrawalWindowExpires = block.timestamp + withdrawalWindowLength;
        collateralAmount = 0;
        oToken = address(0);
        currentReserves = 0;
        
        emit WithdrawalWindowActivated(withdrawalWindowExpires);
    }

    function _writeOptions(uint256 _amount, address _oToken) internal {
        if(!_withdrawalWindowCheck(false))
            revert WithdrawalWindowActive();
        if(_amount == 0 || _oToken == address(0))
            revert Invalid();
        if(_amount > IERC20(asset).balanceOf(address(this)) - obligatedFees)
            revert NotEnoughFunds();
        if(_oToken != oToken && oToken != address(0))
            revert oTokenNotCleared();

        // Calculate reserves if not already done
        if(oToken == address(0))
            _calculateAndSetReserves();

        // Check if the _amount exceeds the reserves
        if(_amount > IERC20(asset).balanceOf(address(this)) - obligatedFees - currentReserves)
            revert NotEnoughFunds_ReserveViolation();

        Actions.ActionArgs[] memory actions;
        GammaTypes.Vault memory vault;

        IController controller = IController(addressBook.getController());

        // Check if the vault is even open and open if no vault is open
        vault = controller.getVault(address(this), currentVaultId);
        if(
            vault.shortOtokens.length == 0 &&
            vault.collateralAssets.length == 0
        ) {
            actions = new Actions.ActionArgs[](3);
            currentVaultId = controller.getAccountVaultCounter(address(this)) + 1;

            actions[0] = Actions.ActionArgs(
                Actions.ActionType.OpenVault,
                address(this),
                address(this),
                address(0),
                currentVaultId,
                0,
                0,
                ""
            );
            
        } else {
            actions = new Actions.ActionArgs[](2);
        }

        // Deposit _amount of asset to the vault
        actions[actions.length - 2] = Actions.ActionArgs(
                Actions.ActionType.DepositCollateral,
                address(this),
                address(this),
                asset,
                currentVaultId,
                _amount,
                0,
                ""
            );
        // Determine the amount of options to write
        uint256 oTokensToWrite;

        if(OtokenInterface(_oToken).isPut()) {
            oTokensToWrite = _normalize(_amount, ERC20(asset).decimals(), 14) / OtokenInterface(_oToken).strikePrice();
        } else {
            oTokensToWrite = _normalize(_amount, ERC20(asset).decimals(), 8);
        }

        // Write options
        actions[actions.length - 1] = Actions.ActionArgs(
                Actions.ActionType.MintShortOption,
                address(this),
                address(this),
                _oToken,
                currentVaultId,
                oTokensToWrite,
                0,
                ""
            );
        // Approve the tokens to be moved
        IERC20(asset).approve(addressBook.getMarginPool(), _amount);
        
        // Submit the operations to the controller contract
        controller.operate(actions);

        collateralAmount += _amount;
        if(oToken != _oToken)
            oToken = _oToken;

        emit OptionsMinted(_amount, oToken, controller.getAccountVaultCounter(address(this)));
    }

    function _sellOptions(Types.Order memory _order) internal {
        if(!_withdrawalWindowCheck(false))
            revert WithdrawalWindowActive();
        if(_order.sender.amount > IERC20(oToken).balanceOf(address(this)) || oToken == address(0))
            revert Invalid();

        // Approve
        IERC20(oToken).approve(factory.airswapExchange(), _order.sender.amount);

        // Submit the order
        ISwap(factory.airswapExchange()).swap(_order);

        // Fee calculation
        obligatedFees += _percentMultiply(_order.signer.amount, performanceFee);
        IERC20(asset).transfer(address(factory), _percentMultiply(_order.signer.amount, factory.performanceFee()));

        emit OptionsSold(_order.sender.amount, _order.signer.amount);
    }

    function _calculateAndSetReserves() internal {
        currentReserves = _percentMultiply(IERC20(asset).balanceOf(address(this)) - obligatedFees, withdrawalReserve);
    }

    function _onlyManager() internal view {
        if(msg.sender != manager)
            revert Unauthorized();
    }
    
    function _normalize(
        uint256 _valueToNormalize,
        uint256 _valueDecimal,
        uint256 _normalDecimals
    ) internal pure returns (uint256) {
        int256 decimalDiff = int256(_valueDecimal) - int256(_normalDecimals);

        if(decimalDiff > 0) {
            return _valueToNormalize / (10**uint256(decimalDiff));
        } else if(decimalDiff < 0) {
            return _valueToNormalize * 10**uint256(-decimalDiff);
        } else {
            return _valueToNormalize;
        }
    }

    function _withdrawalWindowCheck(bool _revertIfClosed) internal view returns(bool isActive) {
        if(block.timestamp > withdrawalWindowExpires && _revertIfClosed)
            revert WithdrawalWindowNotActive();
        
        return block.timestamp > withdrawalWindowExpires;
    }

    function _ifNotClosed() internal view {
        if(closedPermanently)
            revert ClosedPermanently();
    }

    function _percentMultiply(uint256 _subtotal, uint16 _fee) internal pure returns(uint256) {
        return _subtotal * _fee / 10000;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "../proxy/utils/Initializable.sol";

/**
 * @dev Contract module that helps prevent reentrant calls to a function.
 *
 * Inheriting from `ReentrancyGuard` will make the {nonReentrant} modifier
 * available, which can be applied to functions to make sure there are no nested
 * (reentrant) calls to them.
 *
 * Note that because there is a single `nonReentrant` guard, functions marked as
 * `nonReentrant` may not call one another. This can be worked around by making
 * those functions `private`, and then adding `external` `nonReentrant` entry
 * points to them.
 *
 * TIP: If you would like to learn more about reentrancy and alternative ways
 * to protect against it, check out our blog post
 * https://blog.openzeppelin.com/reentrancy-after-istanbul/[Reentrancy After Istanbul].
 */
abstract contract ReentrancyGuardUpgradeable is Initializable {
    // Booleans are more expensive than uint256 or any type that takes up a full
    // word because each write operation emits an extra SLOAD to first read the
    // slot's contents, replace the bits taken up by the boolean, and then write
    // back. This is the compiler's defense against contract upgrades and
    // pointer aliasing, and it cannot be disabled.

    // The values being non-zero value makes deployment a bit more expensive,
    // but in exchange the refund on every call to nonReentrant will be lower in
    // amount. Since refunds are capped to a percentage of the total
    // transaction's gas, it is best to keep them low in cases like this one, to
    // increase the likelihood of the full refund coming into effect.
    uint256 private constant _NOT_ENTERED = 1;
    uint256 private constant _ENTERED = 2;

    uint256 private _status;

    function __ReentrancyGuard_init() internal initializer {
        __ReentrancyGuard_init_unchained();
    }

    function __ReentrancyGuard_init_unchained() internal initializer {
        _status = _NOT_ENTERED;
    }

    /**
     * @dev Prevents a contract from calling itself, directly or indirectly.
     * Calling a `nonReentrant` function from another `nonReentrant`
     * function is not supported. It is possible to prevent this from happening
     * by making the `nonReentrant` function external, and make it call a
     * `private` function that does the actual work.
     */
    modifier nonReentrant() {
        // On the first call to nonReentrant, _notEntered will be true
        require(_status != _ENTERED, "ReentrancyGuard: reentrant call");

        // Any calls to nonReentrant after this point will fail
        _status = _ENTERED;

        _;

        // By storing the original value once again, a refund is triggered (see
        // https://eips.ethereum.org/EIPS/eip-2200)
        _status = _NOT_ENTERED;
    }
    uint256[49] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/ContextUpgradeable.sol";
import "../proxy/utils/Initializable.sol";

/**
 * @dev Contract module which allows children to implement an emergency stop
 * mechanism that can be triggered by an authorized account.
 *
 * This module is used through inheritance. It will make available the
 * modifiers `whenNotPaused` and `whenPaused`, which can be applied to
 * the functions of your contract. Note that they will not be pausable by
 * simply including this module, only once the modifiers are put in place.
 */
abstract contract PausableUpgradeable is Initializable, ContextUpgradeable {
    /**
     * @dev Emitted when the pause is triggered by `account`.
     */
    event Paused(address account);

    /**
     * @dev Emitted when the pause is lifted by `account`.
     */
    event Unpaused(address account);

    bool private _paused;

    /**
     * @dev Initializes the contract in unpaused state.
     */
    function __Pausable_init() internal initializer {
        __Context_init_unchained();
        __Pausable_init_unchained();
    }

    function __Pausable_init_unchained() internal initializer {
        _paused = false;
    }

    /**
     * @dev Returns true if the contract is paused, and false otherwise.
     */
    function paused() public view virtual returns (bool) {
        return _paused;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is not paused.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    modifier whenNotPaused() {
        require(!paused(), "Pausable: paused");
        _;
    }

    /**
     * @dev Modifier to make a function callable only when the contract is paused.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    modifier whenPaused() {
        require(paused(), "Pausable: not paused");
        _;
    }

    /**
     * @dev Triggers stopped state.
     *
     * Requirements:
     *
     * - The contract must not be paused.
     */
    function _pause() internal virtual whenNotPaused {
        _paused = true;
        emit Paused(_msgSender());
    }

    /**
     * @dev Returns to normal state.
     *
     * Requirements:
     *
     * - The contract must be paused.
     */
    function _unpause() internal virtual whenPaused {
        _paused = false;
        emit Unpaused(_msgSender());
    }
    uint256[49] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC20.sol";
import "../../../utils/Address.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20 {
    using Address for address;

    function safeTransfer(
        IERC20 token,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(
        IERC20 token,
        address from,
        address to,
        uint256 value
    ) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        require(
            (value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(
        IERC20 token,
        address spender,
        uint256 value
    ) internal {
        unchecked {
            uint256 oldAllowance = token.allowance(address(this), spender);
            require(oldAllowance >= value, "SafeERC20: decreased allowance below zero");
            uint256 newAllowance = oldAllowance - value;
            _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
        }
    }

    /**
     * @dev Imitates a Solidity high-level call (i.e. a regular function call to a contract), relaxing the requirement
     * on the return value: the return value is optional (but if data is returned, it must not be false).
     * @param token The token targeted by the call.
     * @param data The call data (encoded using abi.encode or one of its variants).
     */
    function _callOptionalReturn(IERC20 token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) {
            // Return data is optional
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20.sol";
import "./extensions/IERC20Metadata.sol";
import "../../utils/Context.sol";

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin guidelines: functions revert instead
 * of returning `false` on failure. This behavior is nonetheless conventional
 * and does not conflict with the expectations of ERC20 applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20 is Context, IERC20, IERC20Metadata {
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    constructor(string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `sender` to `recipient`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);

        _afterTokenTransfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * has been transferred to `to`.
     * - when `from` is zero, `amount` tokens have been minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens have been burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC20Upgradeable.sol";
import "./extensions/IERC20MetadataUpgradeable.sol";
import "../../utils/ContextUpgradeable.sol";
import "../../proxy/utils/Initializable.sol";

/**
 * @dev Implementation of the {IERC20} interface.
 *
 * This implementation is agnostic to the way tokens are created. This means
 * that a supply mechanism has to be added in a derived contract using {_mint}.
 * For a generic mechanism see {ERC20PresetMinterPauser}.
 *
 * TIP: For a detailed writeup see our guide
 * https://forum.zeppelin.solutions/t/how-to-implement-erc20-supply-mechanisms/226[How
 * to implement supply mechanisms].
 *
 * We have followed general OpenZeppelin guidelines: functions revert instead
 * of returning `false` on failure. This behavior is nonetheless conventional
 * and does not conflict with the expectations of ERC20 applications.
 *
 * Additionally, an {Approval} event is emitted on calls to {transferFrom}.
 * This allows applications to reconstruct the allowance for all accounts just
 * by listening to said events. Other implementations of the EIP may not emit
 * these events, as it isn't required by the specification.
 *
 * Finally, the non-standard {decreaseAllowance} and {increaseAllowance}
 * functions have been added to mitigate the well-known issues around setting
 * allowances. See {IERC20-approve}.
 */
contract ERC20Upgradeable is Initializable, ContextUpgradeable, IERC20Upgradeable, IERC20MetadataUpgradeable {
    mapping(address => uint256) private _balances;

    mapping(address => mapping(address => uint256)) private _allowances;

    uint256 private _totalSupply;

    string private _name;
    string private _symbol;

    /**
     * @dev Sets the values for {name} and {symbol}.
     *
     * The default value of {decimals} is 18. To select a different value for
     * {decimals} you should overload it.
     *
     * All two of these values are immutable: they can only be set once during
     * construction.
     */
    function __ERC20_init(string memory name_, string memory symbol_) internal initializer {
        __Context_init_unchained();
        __ERC20_init_unchained(name_, symbol_);
    }

    function __ERC20_init_unchained(string memory name_, string memory symbol_) internal initializer {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless this function is
     * overridden;
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view virtual override returns (uint8) {
        return 18;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view virtual override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view virtual override returns (uint256) {
        return _balances[account];
    }

    /**
     * @dev See {IERC20-transfer}.
     *
     * Requirements:
     *
     * - `recipient` cannot be the zero address.
     * - the caller must have a balance of at least `amount`.
     */
    function transfer(address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(_msgSender(), recipient, amount);
        return true;
    }

    /**
     * @dev See {IERC20-allowance}.
     */
    function allowance(address owner, address spender) public view virtual override returns (uint256) {
        return _allowances[owner][spender];
    }

    /**
     * @dev See {IERC20-approve}.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function approve(address spender, uint256 amount) public virtual override returns (bool) {
        _approve(_msgSender(), spender, amount);
        return true;
    }

    /**
     * @dev See {IERC20-transferFrom}.
     *
     * Emits an {Approval} event indicating the updated allowance. This is not
     * required by the EIP. See the note at the beginning of {ERC20}.
     *
     * Requirements:
     *
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);

        uint256 currentAllowance = _allowances[sender][_msgSender()];
        require(currentAllowance >= amount, "ERC20: transfer amount exceeds allowance");
        unchecked {
            _approve(sender, _msgSender(), currentAllowance - amount);
        }

        return true;
    }

    /**
     * @dev Atomically increases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     */
    function increaseAllowance(address spender, uint256 addedValue) public virtual returns (bool) {
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender] + addedValue);
        return true;
    }

    /**
     * @dev Atomically decreases the allowance granted to `spender` by the caller.
     *
     * This is an alternative to {approve} that can be used as a mitigation for
     * problems described in {IERC20-approve}.
     *
     * Emits an {Approval} event indicating the updated allowance.
     *
     * Requirements:
     *
     * - `spender` cannot be the zero address.
     * - `spender` must have allowance for the caller of at least
     * `subtractedValue`.
     */
    function decreaseAllowance(address spender, uint256 subtractedValue) public virtual returns (bool) {
        uint256 currentAllowance = _allowances[_msgSender()][spender];
        require(currentAllowance >= subtractedValue, "ERC20: decreased allowance below zero");
        unchecked {
            _approve(_msgSender(), spender, currentAllowance - subtractedValue);
        }

        return true;
    }

    /**
     * @dev Moves `amount` of tokens from `sender` to `recipient`.
     *
     * This internal function is equivalent to {transfer}, and can be used to
     * e.g. implement automatic token fees, slashing mechanisms, etc.
     *
     * Emits a {Transfer} event.
     *
     * Requirements:
     *
     * - `sender` cannot be the zero address.
     * - `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     */
    function _transfer(
        address sender,
        address recipient,
        uint256 amount
    ) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        uint256 senderBalance = _balances[sender];
        require(senderBalance >= amount, "ERC20: transfer amount exceeds balance");
        unchecked {
            _balances[sender] = senderBalance - amount;
        }
        _balances[recipient] += amount;

        emit Transfer(sender, recipient, amount);

        _afterTokenTransfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");

        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply += amount;
        _balances[account] += amount;
        emit Transfer(address(0), account, amount);

        _afterTokenTransfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements:
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        uint256 accountBalance = _balances[account];
        require(accountBalance >= amount, "ERC20: burn amount exceeds balance");
        unchecked {
            _balances[account] = accountBalance - amount;
        }
        _totalSupply -= amount;

        emit Transfer(account, address(0), amount);

        _afterTokenTransfer(account, address(0), amount);
    }

    /**
     * @dev Sets `amount` as the allowance of `spender` over the `owner` s tokens.
     *
     * This internal function is equivalent to `approve`, and can be used to
     * e.g. set automatic allowances for certain subsystems, etc.
     *
     * Emits an {Approval} event.
     *
     * Requirements:
     *
     * - `owner` cannot be the zero address.
     * - `spender` cannot be the zero address.
     */
    function _approve(
        address owner,
        address spender,
        uint256 amount
    ) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}

    /**
     * @dev Hook that is called after any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * has been transferred to `to`.
     * - when `from` is zero, `amount` tokens have been minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens have been burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _afterTokenTransfer(
        address from,
        address to,
        uint256 amount
    ) internal virtual {}
    uint256[45] private __gap;
}

// SPDX-License-Identifier: UNLICENSED
// SOURCE: https://github.com/opynfinance/GammaProtocol/blob/2fce44f04300aa5b79187269728aae3a736b4684/contracts/interfaces/OtokenInterface.sol
pragma solidity =0.8.4;

interface OtokenInterface {
    function addressBook() external view returns (address);

    function underlyingAsset() external view returns (address);

    function strikeAsset() external view returns (address);

    function collateralAsset() external view returns (address);

    function strikePrice() external view returns (uint256);

    function expiryTimestamp() external view returns (uint256);

    function isPut() external view returns (bool);

    function init(
        address _addressBook,
        address _underlyingAsset,
        address _strikeAsset,
        address _collateralAsset,
        uint256 _strikePrice,
        uint256 _expiry,
        bool _isPut
    ) external;

    function getOtokenDetails()
        external
        view
        returns (
            address,
            address,
            address,
            uint256,
            uint256,
            bool
        );

    function mintOtoken(address account, uint256 amount) external;

    function burnOtoken(address account, uint256 amount) external;
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.4;

library GammaTypes {
     // vault is a struct of 6 arrays that describe a position a user has, a user can have multiple vaults.
    struct Vault {
        // addresses of oTokens a user has shorted (i.e. written) against this vault
        address[] shortOtokens;
        // addresses of oTokens a user has bought and deposited in this vault
        // user can be long oTokens without opening a vault (e.g. by buying on a DEX)
        // generally, long oTokens will be 'deposited' in vaults to act as collateral in order to write oTokens against (i.e. in spreads)
        address[] longOtokens;
        // addresses of other ERC-20s a user has deposited as collateral in this vault
        address[] collateralAssets;
        // quantity of oTokens minted/written for each oToken address in shortOtokens
        uint256[] shortAmounts;
        // quantity of oTokens owned and held in the vault for each oToken address in longOtokens
        uint256[] longAmounts;
        // quantity of ERC-20 deposited as collateral in the vault for each ERC-20 address in collateralAssets
        uint256[] collateralAmounts;
    }
}

library Actions {
    // possible actions that can be performed
    enum ActionType {
        OpenVault,
        MintShortOption,
        BurnShortOption,
        DepositLongOption,
        WithdrawLongOption,
        DepositCollateral,
        WithdrawCollateral,
        SettleVault,
        Redeem,
        Call,
        Liquidate
    }

    struct ActionArgs {
        // type of action that is being performed on the system
        ActionType actionType;
        // address of the account owner
        address owner;
        // address which we move assets from or to (depending on the action type)
        address secondAddress;
        // asset that is to be transfered
        address asset;
        // index of the vault that is to be modified (if any)
        uint256 vaultId;
        // amount of asset that is to be transfered
        uint256 amount;
        // each vault can hold multiple short / long / collateral assets but we are restricting the scope to only 1 of each in this version
        // in future versions this would be the index of the short / long / collateral asset that needs to be modified
        uint256 index;
        // any other data that needs to be passed in for arbitrary function calls
        bytes data;
    }

    struct RedeemArgs {
        // address to which we pay out the oToken proceeds
        address receiver;
        // oToken that is to be redeemed
        address otoken;
        // amount of oTokens that is to be redeemed
        uint256 amount;
    }
}

interface IController {

    function getVault(address _owner, uint256 _vaultId) external view returns(GammaTypes.Vault memory);

    function getAccountVaultCounter(address _accountOwner) external view returns(uint256);

    function operate(Actions.ActionArgs[] memory _actions) external;

    function isSettlementAllowed(address _oToken) external view returns(bool);

}

// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.4;

interface IAddressBook {
    function getController() external view returns(address);
    function getMarginPool() external view returns(address);
}

// SPDX-License-Identifier: Apache-2.0
// SOURCE: https://github.com/airswap/airswap-protocols/blob/master/source/swap/contracts/interfaces/ISwap.sol
pragma solidity =0.8.4;
pragma experimental ABIEncoderV2;

import "../types/Types.sol";
import "../transfers/TransferHandlerRegistry.sol";

interface ISwap {
  event Swap(
    uint256 indexed nonce,
    uint256 timestamp,
    address indexed signerWallet,
    uint256 signerAmount,
    uint256 signerId,
    address signerToken,
    address indexed senderWallet,
    uint256 senderAmount,
    uint256 senderId,
    address senderToken,
    address affiliateWallet,
    uint256 affiliateAmount,
    uint256 affiliateId,
    address affiliateToken
  );

  event Cancel(uint256 indexed nonce, address indexed signerWallet);

  event CancelUpTo(uint256 indexed nonce, address indexed signerWallet);

  event AuthorizeSender(
    address indexed authorizerAddress,
    address indexed authorizedSender
  );

  event AuthorizeSigner(
    address indexed authorizerAddress,
    address indexed authorizedSigner
  );

  event RevokeSender(
    address indexed authorizerAddress,
    address indexed revokedSender
  );

  event RevokeSigner(
    address indexed authorizerAddress,
    address indexed revokedSigner
  );

  /**
   * @notice Atomic Token Swap
   * @param order Types.Order
   */
  function swap(Types.Order calldata order) external;

  /**
   * @notice Cancel one or more open orders by nonce
   * @param nonces uint256[]
   */
  function cancel(uint256[] calldata nonces) external;

  /**
   * @notice Cancels all orders below a nonce value
   * @dev These orders can be made active by reducing the minimum nonce
   * @param minimumNonce uint256
   */
  function cancelUpTo(uint256 minimumNonce) external;

  /**
   * @notice Authorize a delegated sender
   * @param authorizedSender address
   */
  function authorizeSender(address authorizedSender) external;

  /**
   * @notice Authorize a delegated signer
   * @param authorizedSigner address
   */
  function authorizeSigner(address authorizedSigner) external;

  /**
   * @notice Revoke an authorization
   * @param authorizedSender address
   */
  function revokeSender(address authorizedSender) external;

  /**
   * @notice Revoke an authorization
   * @param authorizedSigner address
   */
  function revokeSigner(address authorizedSigner) external;

  function senderAuthorizations(address, address) external view returns (bool);

  function signerAuthorizations(address, address) external view returns (bool);

  function signerNonceStatus(address, uint256) external view returns (bytes1);

  function signerMinimumNonce(address) external view returns (uint256);

  function registry() external view returns (TransferHandlerRegistry);
}

// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.4;

interface IFactory {
    function admin() external view returns(address);
    function airswapExchange() external view returns(address);
    function depositFee() external view returns(uint16);
    function performanceFee() external view returns(uint16);
    function withdrawalFee() external view returns(uint16);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Collection of functions related to the address type
 */
library Address {
    /**
     * @dev Returns true if `account` is a contract.
     *
     * [IMPORTANT]
     * ====
     * It is unsafe to assume that an address for which this function returns
     * false is an externally-owned account (EOA) and not a contract.
     *
     * Among others, `isContract` will return false for the following
     * types of addresses:
     *
     *  - an externally-owned account
     *  - a contract in construction
     *  - an address where a contract will be created
     *  - an address where a contract lived, but was destroyed
     * ====
     */
    function isContract(address account) internal view returns (bool) {
        // This method relies on extcodesize, which returns 0 for contracts in
        // construction, since the code is only stored at the end of the
        // constructor execution.

        uint256 size;
        assembly {
            size := extcodesize(account)
        }
        return size > 0;
    }

    /**
     * @dev Replacement for Solidity's `transfer`: sends `amount` wei to
     * `recipient`, forwarding all available gas and reverting on errors.
     *
     * https://eips.ethereum.org/EIPS/eip-1884[EIP1884] increases the gas cost
     * of certain opcodes, possibly making contracts go over the 2300 gas limit
     * imposed by `transfer`, making them unable to receive funds via
     * `transfer`. {sendValue} removes this limitation.
     *
     * https://diligence.consensys.net/posts/2019/09/stop-using-soliditys-transfer-now/[Learn more].
     *
     * IMPORTANT: because control is transferred to `recipient`, care must be
     * taken to not create reentrancy vulnerabilities. Consider using
     * {ReentrancyGuard} or the
     * https://solidity.readthedocs.io/en/v0.5.11/security-considerations.html#use-the-checks-effects-interactions-pattern[checks-effects-interactions pattern].
     */
    function sendValue(address payable recipient, uint256 amount) internal {
        require(address(this).balance >= amount, "Address: insufficient balance");

        (bool success, ) = recipient.call{value: amount}("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain `call` is an unsafe replacement for a function call: use this
     * function instead.
     *
     * If `target` reverts with a revert reason, it is bubbled up by this
     * function (like regular Solidity function calls).
     *
     * Returns the raw returned data. To convert to the expected return value,
     * use https://solidity.readthedocs.io/en/latest/units-and-global-variables.html?highlight=abi.decode#abi-encoding-and-decoding-functions[`abi.decode`].
     *
     * Requirements:
     *
     * - `target` must be a contract.
     * - calling `target` with `data` must not revert.
     *
     * _Available since v3.1._
     */
    function functionCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionCall(target, data, "Address: low-level call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`], but with
     * `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, 0, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but also transferring `value` wei to `target`.
     *
     * Requirements:
     *
     * - the calling contract must have an ETH balance of at least `value`.
     * - the called Solidity function must be `payable`.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value
    ) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(
        address target,
        bytes memory data,
        uint256 value,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        (bool success, bytes memory returndata) = target.call{value: value}(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(address target, bytes memory data) internal view returns (bytes memory) {
        return functionStaticCall(target, data, "Address: low-level static call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a static call.
     *
     * _Available since v3.3._
     */
    function functionStaticCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(address target, bytes memory data) internal returns (bytes memory) {
        return functionDelegateCall(target, data, "Address: low-level delegate call failed");
    }

    /**
     * @dev Same as {xref-Address-functionCall-address-bytes-string-}[`functionCall`],
     * but performing a delegate call.
     *
     * _Available since v3.4._
     */
    function functionDelegateCall(
        address target,
        bytes memory data,
        string memory errorMessage
    ) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        (bool success, bytes memory returndata) = target.delegatecall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(
        bool success,
        bytes memory returndata,
        string memory errorMessage
    ) private pure returns (bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                assembly {
                    let returndata_size := mload(returndata)
                    revert(add(32, returndata), returndata_size)
                }
            } else {
                revert(errorMessage);
            }
        }
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
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

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

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev This is a base contract to aid in writing upgradeable contracts, or any kind of contract that will be deployed
 * behind a proxy. Since a proxied contract can't have a constructor, it's common to move constructor logic to an
 * external initializer function, usually called `initialize`. It then becomes necessary to protect this initializer
 * function so it can only be called once. The {initializer} modifier provided by this contract will have this effect.
 *
 * TIP: To avoid leaving the proxy in an uninitialized state, the initializer function should be called as early as
 * possible by providing the encoded function call as the `_data` argument to {ERC1967Proxy-constructor}.
 *
 * CAUTION: When used with inheritance, manual care must be taken to not invoke a parent initializer twice, or to ensure
 * that all initializers are idempotent. This is not verified automatically as constructors are by Solidity.
 */
abstract contract Initializable {
    /**
     * @dev Indicates that the contract has been initialized.
     */
    bool private _initialized;

    /**
     * @dev Indicates that the contract is in the process of being initialized.
     */
    bool private _initializing;

    /**
     * @dev Modifier to protect an initializer function from being invoked twice.
     */
    modifier initializer() {
        require(_initializing || !_initialized, "Initializable: contract is already initialized");

        bool isTopLevelCall = !_initializing;
        if (isTopLevelCall) {
            _initializing = true;
            _initialized = true;
        }

        _;

        if (isTopLevelCall) {
            _initializing = false;
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "../proxy/utils/Initializable.sol";

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract ContextUpgradeable is Initializable {
    function __Context_init() internal initializer {
        __Context_init_unchained();
    }

    function __Context_init_unchained() internal initializer {
    }
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
    uint256[50] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC20Upgradeable.sol";

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20MetadataUpgradeable is IERC20Upgradeable {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IERC20Upgradeable {
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
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) external returns (bool);

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

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC20.sol";

/**
 * @dev Interface for the optional metadata functions from the ERC20 standard.
 *
 * _Available since v4.1._
 */
interface IERC20Metadata is IERC20 {
    /**
     * @dev Returns the name of the token.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the symbol of the token.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the decimals places of the token.
     */
    function decimals() external view returns (uint8);
}

// SPDX-License-Identifier: Apache-2.0
pragma solidity =0.8.4;

import "../interfaces/ITransferHandler.sol";
import "../../../oz/access/Ownable.sol";

/**
 * @title TransferHandlerRegistry: holds registry of contract to
 * facilitate token transfers
 */
contract TransferHandlerRegistry is Ownable {
  // Mapping of bytes4 to contract interface type
  mapping(bytes4 => ITransferHandler) public transferHandlers;

  /**
   * @notice Contract Events
   */
  event AddTransferHandler(bytes4 kind, address contractAddress);

  /**
   * @notice Adds handler to mapping
   * @param kind bytes4 Key value that defines a token type
   * @param transferHandler ITransferHandler
   */
  function addTransferHandler(bytes4 kind, ITransferHandler transferHandler)
    external
    onlyOwner
  {
    require(
      address(transferHandlers[kind]) == address(0),
      "HANDLER_EXISTS_FOR_KIND"
    );
    transferHandlers[kind] = transferHandler;
    emit AddTransferHandler(kind, address(transferHandler));
  }
}

// SPDX-License-Identifier: Apache-2.0
// SOURCE: https://github.com/airswap/airswap-protocols/blob/master/source/types/contracts/Types.sol
pragma solidity =0.8.4;
pragma experimental ABIEncoderV2;

/**
 * @title Types: Library of Swap Protocol Types and Hashes
 */
library Types {
  struct Order {
    uint256 nonce; // Unique per order and should be sequential
    uint256 expiry; // Expiry in seconds since 1 January 1970
    Party signer; // Party to the trade that sets terms
    Party sender; // Party to the trade that accepts terms
    Party affiliate; // Party compensated for facilitating (optional)
    Signature signature; // Signature of the order
  }

  struct Party {
    bytes4 kind; // Interface ID of the token
    address wallet; // Wallet address of the party
    address token; // Contract address of the token
    uint256 amount; // Amount for ERC-20 or ERC-1155
    uint256 id; // ID for ERC-721 or ERC-1155
  }

  struct Signature {
    address signatory; // Address of the wallet used to sign
    address validator; // Address of the intended swap contract
    bytes1 version; // EIP-191 signature version
    uint8 v; // `v` value of an ECDSA signature
    bytes32 r; // `r` value of an ECDSA signature
    bytes32 s; // `s` value of an ECDSA signature
  }

  bytes internal constant EIP191_HEADER = "\x19\x01";

  bytes32 internal constant DOMAIN_TYPEHASH =
    keccak256(
      abi.encodePacked(
        "EIP712Domain(",
        "string name,",
        "string version,",
        "address verifyingContract",
        ")"
      )
    );

  bytes32 internal constant ORDER_TYPEHASH =
    keccak256(
      abi.encodePacked(
        "Order(",
        "uint256 nonce,",
        "uint256 expiry,",
        "Party signer,",
        "Party sender,",
        "Party affiliate",
        ")",
        "Party(",
        "bytes4 kind,",
        "address wallet,",
        "address token,",
        "uint256 amount,",
        "uint256 id",
        ")"
      )
    );

  bytes32 internal constant PARTY_TYPEHASH =
    keccak256(
      abi.encodePacked(
        "Party(",
        "bytes4 kind,",
        "address wallet,",
        "address token,",
        "uint256 amount,",
        "uint256 id",
        ")"
      )
    );

  /**
   * @notice Hash an order into bytes32
   * @dev EIP-191 header and domain separator included
   * @param order Order The order to be hashed
   * @param domainSeparator bytes32
   * @return bytes32 A keccak256 abi.encodePacked value
   */
  function hashOrder(Order calldata order, bytes32 domainSeparator)
    external
    pure
    returns (bytes32)
  {
    return
      keccak256(
        abi.encodePacked(
          EIP191_HEADER,
          domainSeparator,
          keccak256(
            abi.encode(
              ORDER_TYPEHASH,
              order.nonce,
              order.expiry,
              keccak256(
                abi.encode(
                  PARTY_TYPEHASH,
                  order.signer.kind,
                  order.signer.wallet,
                  order.signer.token,
                  order.signer.amount,
                  order.signer.id
                )
              ),
              keccak256(
                abi.encode(
                  PARTY_TYPEHASH,
                  order.sender.kind,
                  order.sender.wallet,
                  order.sender.token,
                  order.sender.amount,
                  order.sender.id
                )
              ),
              keccak256(
                abi.encode(
                  PARTY_TYPEHASH,
                  order.affiliate.kind,
                  order.affiliate.wallet,
                  order.affiliate.token,
                  order.affiliate.amount,
                  order.affiliate.id
                )
              )
            )
          )
        )
      );
  }

  /**
   * @notice Hash domain parameters into bytes32
   * @dev Used for signature validation (EIP-712)
   * @param name bytes
   * @param version bytes
   * @param verifyingContract address
   * @return bytes32 returns a keccak256 abi.encodePacked value
   */
  function hashDomain(
    bytes calldata name,
    bytes calldata version,
    address verifyingContract
  ) external pure returns (bytes32) {
    return
      keccak256(
        abi.encode(
          DOMAIN_TYPEHASH,
          keccak256(name),
          keccak256(version),
          verifyingContract
        )
      );
  }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/Context.sol";

/**
 * @dev Contract module which provides a basic access control mechanism, where
 * there is an account (an owner) that can be granted exclusive access to
 * specific functions.
 *
 * By default, the owner account will be the one that deploys the contract. This
 * can later be changed with {transferOwnership}.
 *
 * This module is used through inheritance. It will make available the modifier
 * `onlyOwner`, which can be applied to your functions to restrict their use to
 * the owner.
 */
abstract contract Ownable is Context {
    address private _owner;

    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Initializes the contract setting the deployer as the initial owner.
     */
    constructor() {
        _setOwner(_msgSender());
    }

    /**
     * @dev Returns the address of the current owner.
     */
    function owner() public view virtual returns (address) {
        return _owner;
    }

    /**
     * @dev Throws if called by any account other than the owner.
     */
    modifier onlyOwner() {
        require(owner() == _msgSender(), "Ownable: caller is not the owner");
        _;
    }

    /**
     * @dev Leaves the contract without owner. It will not be possible to call
     * `onlyOwner` functions anymore. Can only be called by the current owner.
     *
     * NOTE: Renouncing ownership will leave the contract without an owner,
     * thereby removing any functionality that is only available to the owner.
     */
    function renounceOwnership() public virtual onlyOwner {
        _setOwner(address(0));
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        _setOwner(newOwner);
    }

    function _setOwner(address newOwner) private {
        address oldOwner = _owner;
        _owner = newOwner;
        emit OwnershipTransferred(oldOwner, newOwner);
    }
}

// SPDX-License-Identifier: Apache-2.0
// SOURCE: https://github.com/airswap/airswap-protocols/blob/master/source/transfers/contracts/interfaces/ITransferHandler.sol
pragma solidity =0.8.4;

/**
 * @title ITransferHandler: interface for token transfers
 */
interface ITransferHandler {
  /**
   * @notice Function to wrap token transfer for different token types
   * @param from address Wallet address to transfer from
   * @param to address Wallet address to transfer to
   * @param amount uint256 Amount for ERC-20
   * @param id token ID for ERC-721
   * @param token address Contract address of token
   * @return bool on success of the token transfer
   */
  function transferTokens(
    address from,
    address to,
    uint256 amount,
    uint256 id,
    address token
  ) external returns (bool);
}

{
  "optimizer": {
    "enabled": true,
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