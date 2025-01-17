// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/access/AccessControlEnumerableUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/extensions/IERC20MetadataUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/utils/SafeERC20Upgradeable.sol";
import "../interfaces/IKernel.sol";
import "../interfaces/IIntegrationMap.sol";
import "../interfaces/IUserPositions.sol";
import "../interfaces/IYieldManager.sol";
import "../interfaces/IWeth9.sol";
import "../interfaces/IUniswapTrader.sol";
import "../interfaces/ISushiSwapTrader.sol";
import "./ModuleMapConsumer.sol";

/// @title Kernel
/// @notice Allows users to deposit/withdraw erc20 tokens
/// @notice Allows a system admin to control which tokens are depositable
contract Kernel is
    Initializable,
    AccessControlEnumerableUpgradeable,
    ModuleMapConsumer,
    IKernel
{
    using SafeERC20Upgradeable for IERC20MetadataUpgradeable;

    bytes32 public constant OWNER_ROLE = keccak256("owner_role");
    bytes32 public constant MANAGER_ROLE = keccak256("manager_role");

    uint256 private lastDeployTimestamp;
    uint256 private lastHarvestYieldTimestamp;
    uint256 private lastProcessYieldTimestamp;
    uint256 private lastDistributeEthTimestamp;
    uint256 private lastLastDistributeEthTimestamp;
    uint256 private lastBiosBuyBackTimestamp;
    uint256 private initializationTimestamp;

    event Deposit(address indexed user, address[] tokens, uint256[] tokenAmounts, uint256 ethAmount);
    event Withdraw(address indexed user, address[] tokens, uint256[] tokenAmounts, uint256 ethAmount);
    event ClaimEthRewards(address indexed user, uint256 ethRewards);
    event ClaimBiosRewards(address indexed user, uint256 biosRewards);
    event WithdrawAllAndClaim(address indexed user, address[] tokens, bool withdrawWethAsEth, uint256[] tokenAmounts, uint256 ethWithdrawn, uint256 ethRewards,uint256 biosRewards);
    event TokenAdded(address indexed token, bool acceptingDeposits, bool acceptingWithdrawals, uint256 biosRewardWeight, uint256 reserveRatioNumerator, uint256[] weightsByIntegrationId);    event TokenDepositsEnabled(address indexed token);
    event TokenDepositsDisabled(address indexed token);
    event TokenWithdrawalsEnabled(address indexed token);
    event TokenWithdrawalsDisabled(address indexed token);
    event TokenRewardWeightUpdated(address indexed token, uint256 biosRewardWeight);
    event TokenReserveRatioNumeratorUpdated(address indexed token, uint256 reserveRatioNumerator, bool rebalance);
    event TokenIntegrationWeightUpdated(address indexed token, address indexed integration, uint256 weight, bool rebalance);
    event GasAccountUpdated(address gasAccount);
    event TreasuryAccountUpdated(address treasuryAccount);
    event IntegrationAdded(address indexed contractAddress, string name, uint256[] weightsByTokenId);
    event SetBiosRewardsDuration(uint32 biosRewardsDuration);
    event SeedBiosRewards(uint256 biosAmount);
    event Deploy();
    event HarvestYield();
    event ProcessYield();
    event DistributeEth();
    event BiosBuyBack();
    event EthDistributionWeightsUpdated(uint32 biosBuyBackEthWeight, uint32 treasuryEthWeight, uint32 protocolFeeEthWeight, uint32 rewardsEthWeight);
    event GasAccountTargetEthBalanceUpdated(uint256 gasAccountTargetEthBalance);

    modifier onlyGasAccount {
        require(msg.sender == IYieldManager(moduleMap.getModuleAddress(Modules.YieldManager)).getGasAccount(), 
            "Kernel::onlyGasAccount: Caller is not gas account");
        _;
    }

    receive() external payable {}

    /// @notice Initializes contract - used as a replacement for a constructor
    /// @param admin_ default administrator, a cold storage address
    /// @param owner_ single owner account, used to manage the managers
    /// @param moduleMap_ Module Map address
    function initialize(address admin_, address owner_, address moduleMap_) external initializer {
        __ModuleMapConsumer_init(moduleMap_);
        __AccessControl_init();

        // make the "admin_" address the default admin role
        _setupRole(DEFAULT_ADMIN_ROLE, admin_);

        // make the "owner_" address the owner of the system
        _setupRole(OWNER_ROLE, owner_);

        // give the "owner_" address the manager role, too
        _setupRole(MANAGER_ROLE, owner_);

        // owners are admins of managers
        _setRoleAdmin(MANAGER_ROLE, OWNER_ROLE);

        initializationTimestamp = block.timestamp;
    }

    /// @param biosRewardsDuration The duration in seconds for a BIOS rewards period to last
    function setBiosRewardsDuration(uint32 biosRewardsDuration) external onlyRole(MANAGER_ROLE) {
        IUserPositions(moduleMap.getModuleAddress(Modules.UserPositions)).setBiosRewardsDuration(biosRewardsDuration);

        emit SetBiosRewardsDuration(biosRewardsDuration);
    }

    /// @param biosAmount The amount of BIOS to add to the rewards
    function seedBiosRewards(uint256 biosAmount) external onlyRole(MANAGER_ROLE) {
        IUserPositions(moduleMap.getModuleAddress(Modules.UserPositions)).seedBiosRewards(msg.sender, biosAmount);

        emit SeedBiosRewards(biosAmount);
    }

    /// @notice This function is used after tokens have been added, and a weight array should be included
    /// @param contractAddress The address of the integration contract
    /// @param name The name of the protocol being integrated to
    /// @param weightsByTokenId The weights of each token for the added integration
    function addIntegration(
        address contractAddress, 
        string memory name, 
        uint256[] memory weightsByTokenId
    ) external onlyRole(MANAGER_ROLE) {
        IIntegrationMap(moduleMap.getModuleAddress(Modules.IntegrationMap))
            .addIntegration(contractAddress, name, weightsByTokenId);

        emit IntegrationAdded(contractAddress, name, weightsByTokenId);
    }

    /// @param tokenAddress The address of the ERC20 token contract
    /// @param acceptingDeposits Whether token deposits are enabled
    /// @param acceptingWithdrawals Whether token withdrawals are enabled
    /// @param biosRewardWeight Token weight for BIOS rewards
    /// @param reserveRatioNumerator Number that gets divided by reserve ratio denominator to get reserve ratio
    /// @param weightsByIntegrationId The weights of each integration for the added token
    function addToken(
        address tokenAddress, 
        bool acceptingDeposits, 
        bool acceptingWithdrawals, 
        uint256 biosRewardWeight, 
        uint256 reserveRatioNumerator, 
        uint256[] memory weightsByIntegrationId
    ) external onlyRole(MANAGER_ROLE) {
        IIntegrationMap(moduleMap.getModuleAddress(Modules.IntegrationMap))
            .addToken(
                tokenAddress, 
                acceptingDeposits, 
                acceptingWithdrawals, 
                biosRewardWeight, 
                reserveRatioNumerator, 
                weightsByIntegrationId
            );
        
        if(IERC20MetadataUpgradeable(tokenAddress).allowance(moduleMap.getModuleAddress(Modules.Kernel), 
            moduleMap.getModuleAddress(Modules.YieldManager)) == 0) {
            IERC20MetadataUpgradeable(tokenAddress)
                .safeApprove(moduleMap.getModuleAddress(Modules.YieldManager), type(uint256).max);
        }

        if(IERC20MetadataUpgradeable(tokenAddress).allowance(moduleMap.getModuleAddress(Modules.Kernel), 
            moduleMap.getModuleAddress(Modules.UserPositions)) == 0) {
            IERC20MetadataUpgradeable(tokenAddress)
                .safeApprove(moduleMap.getModuleAddress(Modules.UserPositions), type(uint256).max);
        }

        emit TokenAdded(tokenAddress, acceptingDeposits, acceptingWithdrawals, biosRewardWeight, reserveRatioNumerator, weightsByIntegrationId);
    }

    /// @param biosBuyBackEthWeight The relative weight of ETH to send to BIOS buy back
    /// @param treasuryEthWeight The relative weight of ETH to send to the treasury
    /// @param protocolFeeEthWeight The relative weight of ETH to send to protocol fee accrual
    /// @param rewardsEthWeight The relative weight of ETH to send to user rewards
    function updateEthDistributionWeights(
        uint32 biosBuyBackEthWeight,
        uint32 treasuryEthWeight,
        uint32 protocolFeeEthWeight,
        uint32 rewardsEthWeight
    ) external onlyRole(MANAGER_ROLE) {
        IYieldManager(moduleMap.getModuleAddress(Modules.YieldManager)).updateEthDistributionWeights(
            biosBuyBackEthWeight,
            treasuryEthWeight,
            protocolFeeEthWeight,
            rewardsEthWeight   
        );

        emit EthDistributionWeightsUpdated(biosBuyBackEthWeight, treasuryEthWeight, protocolFeeEthWeight, rewardsEthWeight);
    }

    /// @notice Gives the UserPositions contract approval to transfer BIOS from Kernel
    function tokenApprovals() external onlyRole(MANAGER_ROLE) {
        IIntegrationMap integrationMap = IIntegrationMap(moduleMap.getModuleAddress(Modules.IntegrationMap));
        IERC20MetadataUpgradeable bios = IERC20MetadataUpgradeable(integrationMap.getBiosTokenAddress());
        IERC20MetadataUpgradeable weth = IERC20MetadataUpgradeable(integrationMap.getWethTokenAddress());

        if(bios.allowance(address(this), moduleMap.getModuleAddress(Modules.UserPositions)) == 0) {
            bios.safeApprove(moduleMap.getModuleAddress(Modules.UserPositions), type(uint256).max);
        }

        if(weth.allowance(address(this), moduleMap.getModuleAddress(Modules.UserPositions)) == 0) {
            weth.safeApprove(moduleMap.getModuleAddress(Modules.UserPositions), type(uint256).max);
        }

        if(weth.allowance(address(this), moduleMap.getModuleAddress(Modules.YieldManager)) == 0) {
            weth.safeApprove(moduleMap.getModuleAddress(Modules.YieldManager), type(uint256).max);
        }
    }

    /// @param tokenAddress The address of the token ERC20 contract
    function enableTokenDeposits(address tokenAddress) external onlyRole(MANAGER_ROLE) {
        IIntegrationMap(moduleMap.getModuleAddress(Modules.IntegrationMap))
            .enableTokenDeposits(tokenAddress);

        emit TokenDepositsEnabled(tokenAddress);
    }

    /// @param tokenAddress The address of the token ERC20 contract
    function disableTokenDeposits(address tokenAddress) external onlyRole(MANAGER_ROLE) {
        IIntegrationMap(moduleMap.getModuleAddress(Modules.IntegrationMap))
            .disableTokenDeposits(tokenAddress);

        emit TokenDepositsDisabled(tokenAddress);
    }

    /// @param tokenAddress The address of the token ERC20 contract
    function enableTokenWithdrawals(address tokenAddress) external onlyRole(MANAGER_ROLE) {
        IIntegrationMap(moduleMap.getModuleAddress(Modules.IntegrationMap))
            .enableTokenWithdrawals(tokenAddress);

        emit TokenWithdrawalsEnabled(tokenAddress);
    }

    /// @param tokenAddress The address of the token ERC20 contract
    function disableTokenWithdrawals(address tokenAddress) external onlyRole(MANAGER_ROLE) {
        IIntegrationMap(moduleMap.getModuleAddress(Modules.IntegrationMap))
            .disableTokenWithdrawals(tokenAddress);

        emit TokenWithdrawalsDisabled(tokenAddress);
    }

    /// @param tokenAddress The address of the token ERC20 contract
    /// @param updatedWeight The updated token BIOS reward weight
    function updateTokenRewardWeight(address tokenAddress, uint256 updatedWeight) external onlyRole(MANAGER_ROLE) {
        IIntegrationMap(moduleMap.getModuleAddress(Modules.IntegrationMap))
            .updateTokenRewardWeight(tokenAddress, updatedWeight);  

        emit TokenRewardWeightUpdated(tokenAddress, updatedWeight);
    }

    /// @param integrationAddress The address of the integration contract
    /// @param tokenAddress the address of the token ERC20 contract
    /// @param updatedWeight The new updated token integration weight
    /// @param rebalance Boolean indicating whether rebalance should be triggered
    function updateTokenIntegrationWeight(
        address integrationAddress, 
        address tokenAddress, 
        uint256 updatedWeight,
        bool rebalance
    ) external onlyRole(MANAGER_ROLE) {
        IIntegrationMap(moduleMap.getModuleAddress(Modules.IntegrationMap))
            .updateTokenIntegrationWeight(integrationAddress, tokenAddress, updatedWeight);

        if(rebalance) {
            IYieldManager(moduleMap.getModuleAddress(Modules.YieldManager)).rebalance();
        }

        emit TokenIntegrationWeightUpdated(tokenAddress, integrationAddress, updatedWeight, rebalance);
    }

    /// @param tokenAddress the address of the token ERC20 contract
    /// @param reserveRatioNumerator Number that gets divided by reserve ratio denominator to get reserve ratio
    /// @param rebalance Boolean indicating whether rebalance should be triggered
    function updateTokenReserveRatioNumerator(
        address tokenAddress, 
        uint256 reserveRatioNumerator, 
        bool rebalance
    ) external onlyRole(MANAGER_ROLE) {
        IIntegrationMap(moduleMap.getModuleAddress(Modules.IntegrationMap))
            .updateTokenReserveRatioNumerator(tokenAddress, reserveRatioNumerator);

        if(rebalance) {
            IYieldManager(moduleMap.getModuleAddress(Modules.YieldManager)).rebalance();
        }

        emit TokenReserveRatioNumeratorUpdated(tokenAddress, reserveRatioNumerator, rebalance);
    }

    /// @param gasAccount The address of the account to send ETH to gas for executing bulk system functions
    function updateGasAccount(address payable gasAccount) external onlyRole(MANAGER_ROLE) {
        IYieldManager(moduleMap.getModuleAddress(Modules.YieldManager)).updateGasAccount(gasAccount);

        emit GasAccountUpdated(gasAccount);
    }

    /// @param treasuryAccount The address of the system treasury account
    function updateTreasuryAccount(address payable treasuryAccount) external onlyRole(MANAGER_ROLE) {
        IYieldManager(moduleMap.getModuleAddress(Modules.YieldManager)).updateTreasuryAccount(treasuryAccount);  

        emit TreasuryAccountUpdated(treasuryAccount);      
    }

    /// @param gasAccountTargetEthBalance The target ETH balance of the gas account
    function updateGasAccountTargetEthBalance(uint256 gasAccountTargetEthBalance) external onlyRole(MANAGER_ROLE) {
        IYieldManager(moduleMap.getModuleAddress(Modules.YieldManager)).updateGasAccountTargetEthBalance(gasAccountTargetEthBalance);

        emit GasAccountTargetEthBalanceUpdated(gasAccountTargetEthBalance);
    }

    /// @notice User is allowed to deposit whitelisted tokens
    /// @param tokens Array of token the token addresses
    /// @param amounts Array of token amounts
    function deposit(
        address[] memory tokens, 
        uint256[] memory amounts
    ) external payable {
        if(msg.value > 0) {
            // Convert ETH to WETH
            address wethAddress = IIntegrationMap(moduleMap.getModuleAddress(Modules.IntegrationMap)).getWethTokenAddress();
            IWeth9(wethAddress).deposit{value: msg.value}();
        }
        
        IUserPositions(moduleMap.getModuleAddress(Modules.UserPositions)).deposit(msg.sender, tokens, amounts, msg.value);

        emit Deposit(msg.sender, tokens, amounts, msg.value);
    }

    /// @notice User is allowed to withdraw tokens
    /// @param tokens Array of token the token addresses
    /// @param amounts Array of token amounts
    /// @param withdrawWethAsEth Boolean indicating whether should receive WETH balance as ETH
    function withdraw(
        address[] memory tokens, 
        uint256[] memory amounts, 
        bool withdrawWethAsEth
    ) external {
        uint256 ethWithdrawn = IUserPositions(moduleMap.getModuleAddress(Modules.UserPositions))
            .withdraw(msg.sender, tokens, amounts, withdrawWethAsEth);

        if (ethWithdrawn > 0) {
            IWeth9(IIntegrationMap(moduleMap.getModuleAddress(Modules.IntegrationMap))
                .getWethTokenAddress()).withdraw(ethWithdrawn);

            payable(msg.sender).transfer(ethWithdrawn);
        }

        emit Withdraw(msg.sender, tokens, amounts, ethWithdrawn);
    }

    /// @notice Allows a user to withdraw entire balances of the specified tokens and claim rewards
    /// @param tokens Array of token address that user is exiting positions from
    /// @param withdrawWethAsEth Boolean indicating whether should receive WETH balance as ETH
    /// @return tokenAmounts The amounts of each token being withdrawn
    /// @return ethWithdrawn The amount of WETH balance being withdrawn as ETH
    /// @return ethClaimed The amount of ETH being claimed from rewards
    /// @return biosClaimed The amount of BIOS being claimed from rewards
    function withdrawAllAndClaim(
        address[] memory tokens,
        bool withdrawWethAsEth
    ) external returns (
        uint256[] memory tokenAmounts,
        uint256 ethWithdrawn,
        uint256 ethClaimed,
        uint256 biosClaimed
    ) {
        (tokenAmounts, ethWithdrawn, ethClaimed, biosClaimed) = 
            IUserPositions(moduleMap.getModuleAddress(Modules.UserPositions))
                .withdrawAllAndClaim(msg.sender, tokens, withdrawWethAsEth);

        if(ethWithdrawn > 0) {
            IWeth9(IIntegrationMap(moduleMap.getModuleAddress(Modules.IntegrationMap))
                .getWethTokenAddress()).withdraw(ethWithdrawn);
        }
        
        if(ethWithdrawn + ethClaimed > 0) {
            payable(msg.sender).transfer(ethWithdrawn + ethClaimed);
        }

        emit WithdrawAllAndClaim(
            msg.sender,
            tokens,
            withdrawWethAsEth,
            tokenAmounts,
            ethWithdrawn,
            ethClaimed,
            biosClaimed
        );
    }

    /// @notice Allows user to claim their BIOS rewards
    /// @return ethClaimed The amount of ETH claimed by the user
    function claimEthRewards() public returns (uint256 ethClaimed) {
        ethClaimed = IUserPositions(moduleMap.getModuleAddress(Modules.UserPositions)).claimEthRewards(msg.sender);

        payable(msg.sender).transfer(ethClaimed);

        emit ClaimEthRewards(msg.sender, ethClaimed);
    }

    /// @notice Allows user to claim their BIOS rewards
    /// @return biosClaimed The amount of BIOS claimed by the user
    function claimBiosRewards() public returns (uint256 biosClaimed) {
        biosClaimed = IUserPositions(moduleMap.getModuleAddress(Modules.UserPositions)).claimBiosRewards(msg.sender);

        emit ClaimBiosRewards(msg.sender, biosClaimed);
    }

    /// @notice Allows user to claim their ETH and BIOS rewards
    /// @return ethClaimed The amount of ETH claimed by the user
    /// @return biosClaimed The amount of BIOS claimed by the user
    function claimAllRewards() external returns (uint256 ethClaimed, uint256 biosClaimed) {
        ethClaimed = claimEthRewards();
        biosClaimed = claimBiosRewards();
    }

    /// @notice Deploys all tokens to all integrations according to configured weights
    function deploy() external onlyGasAccount {
        IYieldManager(moduleMap.getModuleAddress(Modules.YieldManager)).deploy();  
        lastDeployTimestamp = block.timestamp;
        emit Deploy();
    }

    /// @notice Harvests available yield from all tokens and integrations
    function harvestYield() external onlyGasAccount {
        IYieldManager(moduleMap.getModuleAddress(Modules.YieldManager)).harvestYield();
        lastHarvestYieldTimestamp = block.timestamp;
        emit HarvestYield();
    }

    /// @notice Swaps all harvested yield tokens for WETH
    function processYield() external onlyGasAccount {
        IYieldManager(moduleMap.getModuleAddress(Modules.YieldManager)).processYield();
        lastProcessYieldTimestamp = block.timestamp;
        emit ProcessYield();
    }

    /// @notice Distributes WETH to the gas account, BIOS buy back, treasury, protocol fee accrual, and user rewards
    function distributeEth() external onlyGasAccount {
        IYieldManager(moduleMap.getModuleAddress(Modules.YieldManager)).distributeEth();    
        lastLastDistributeEthTimestamp = lastDistributeEthTimestamp;  
        lastDistributeEthTimestamp = block.timestamp;
        emit DistributeEth();
    }

    /// @notice Uses any WETH held in the SushiSwap integration to buy back BIOS which is sent to the Kernel
    function biosBuyBack() external onlyGasAccount {
        IYieldManager(moduleMap.getModuleAddress(Modules.YieldManager)).biosBuyBack();
        lastBiosBuyBackTimestamp = block.timestamp;
        emit BiosBuyBack();
    }

    /// @param account The address of the account to check if they are a manager
    /// @return Bool indicating whether the account is a manger
    function isManager(address account) public view override returns (bool) {
        return hasRole(MANAGER_ROLE, account);
    }

    /// @param account The address of the account to check if they are an owner
    /// @return Bool indicating whether the account is an owner
    function isOwner(address account) public view override returns (bool) {
        return hasRole(OWNER_ROLE, account);
    }   

    /// @return The timestamp the deploy function was last called
    function getLastDeployTimestamp() external view returns (uint256) {
        return lastDeployTimestamp;
    }

    /// @return The timestamp the harvestYield function was last called
    function getLastHarvestYieldTimestamp() external view returns (uint256) {
        return lastHarvestYieldTimestamp;
    }

    /// @return The timestamp the processYield function was last called
    function getLastProcessYieldTimestamp() external view returns (uint256) {
        return lastProcessYieldTimestamp;
    }

    /// @return The timestamp the distributeEth function was last called
    function getLastDistributeEthTimestamp() external view returns (uint256) {
        return lastDistributeEthTimestamp;
    }

    /// @return The timestamp the biosBuyBack function was last called
    function getLastBiosBuyBackTimestamp() external view returns (uint256) {
        return lastBiosBuyBackTimestamp;
    }

    /// @return ethRewardsTimePeriod The number of seconds between the last two ETH payouts
    function getEthRewardsTimePeriod() external view returns (uint256 ethRewardsTimePeriod) {
        if(lastDistributeEthTimestamp > 0) {
            if(lastLastDistributeEthTimestamp > 0) {
                ethRewardsTimePeriod = lastDistributeEthTimestamp - lastLastDistributeEthTimestamp;
            } else {
                ethRewardsTimePeriod = lastDistributeEthTimestamp - initializationTimestamp;
            }
        } else {
            ethRewardsTimePeriod = 0;
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./AccessControlUpgradeable.sol";
import "../utils/structs/EnumerableSetUpgradeable.sol";
import "../proxy/utils/Initializable.sol";

/**
 * @dev External interface of AccessControlEnumerable declared to support ERC165 detection.
 */
interface IAccessControlEnumerableUpgradeable {
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
}

/**
 * @dev Extension of {AccessControl} that allows enumerating the members of each role.
 */
abstract contract AccessControlEnumerableUpgradeable is Initializable, IAccessControlEnumerableUpgradeable, AccessControlUpgradeable {
    function __AccessControlEnumerable_init() internal initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
        __AccessControlEnumerable_init_unchained();
    }

    function __AccessControlEnumerable_init_unchained() internal initializer {
    }
    using EnumerableSetUpgradeable for EnumerableSetUpgradeable.AddressSet;

    mapping (bytes32 => EnumerableSetUpgradeable.AddressSet) private _roleMembers;

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAccessControlEnumerableUpgradeable).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns one of the accounts that have `role`. `index` must be a
     * value between 0 and {getRoleMemberCount}, non-inclusive.
     *
     * Role bearers are not sorted in any particular way, and their ordering may
     * change at any point.
     *
     * WARNING: When using {getRoleMember} and {getRoleMemberCount}, make sure
     * you perform all queries on the same block. See the following
     * https://forum.openzeppelin.com/t/iterating-over-elements-on-enumerableset-in-openzeppelin-contracts/2296[forum post]
     * for more information.
     */
    function getRoleMember(bytes32 role, uint256 index) public view override returns (address) {
        return _roleMembers[role].at(index);
    }

    /**
     * @dev Returns the number of accounts that have `role`. Can be used
     * together with {getRoleMember} to enumerate all bearers of a role.
     */
    function getRoleMemberCount(bytes32 role) public view override returns (uint256) {
        return _roleMembers[role].length();
    }

    /**
     * @dev Overload {grantRole} to track enumerable memberships
     */
    function grantRole(bytes32 role, address account) public virtual override {
        super.grantRole(role, account);
        _roleMembers[role].add(account);
    }

    /**
     * @dev Overload {revokeRole} to track enumerable memberships
     */
    function revokeRole(bytes32 role, address account) public virtual override {
        super.revokeRole(role, account);
        _roleMembers[role].remove(account);
    }

    /**
     * @dev Overload {renounceRole} to track enumerable memberships
     */
    function renounceRole(bytes32 role, address account) public virtual override {
        super.renounceRole(role, account);
        _roleMembers[role].remove(account);
    }

    /**
     * @dev Overload {_setupRole} to track enumerable memberships
     */
    function _setupRole(bytes32 role, address account) internal virtual override {
        super._setupRole(role, account);
        _roleMembers[role].add(account);
    }
    uint256[49] private __gap;
}

// SPDX-License-Identifier: MIT

// solhint-disable-next-line compiler-version
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

import "../IERC20Upgradeable.sol";
import "../../../utils/AddressUpgradeable.sol";

/**
 * @title SafeERC20
 * @dev Wrappers around ERC20 operations that throw on failure (when the token
 * contract returns false). Tokens that return no value (and instead revert or
 * throw on failure) are also supported, non-reverting calls are assumed to be
 * successful.
 * To use this library you can add a `using SafeERC20 for IERC20;` statement to your contract,
 * which allows you to call the safe operations as `token.safeTransfer(...)`, etc.
 */
library SafeERC20Upgradeable {
    using AddressUpgradeable for address;

    function safeTransfer(IERC20Upgradeable token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20Upgradeable token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20Upgradeable token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20Upgradeable token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20Upgradeable token, address spender, uint256 value) internal {
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
    function _callOptionalReturn(IERC20Upgradeable token, bytes memory data) private {
        // We need to perform a low level call here, to bypass Solidity's return data size checking mechanism, since
        // we're implementing it ourselves. We use {Address.functionCall} to perform this call, which verifies that
        // the target address contains contract code and also asserts for success in the low-level call.

        bytes memory returndata = address(token).functionCall(data, "SafeERC20: low-level call failed");
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IKernel {
    /// @param account The address of the account to check if they are a manager
    /// @return Bool indicating whether the account is a manger
    function isManager(address account) external view returns (bool);

    /// @param account The address of the account to check if they are an owner
    /// @return Bool indicating whether the account is an owner
    function isOwner(address account) external view returns (bool);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IIntegrationMap {
    /// @param contractAddress The address of the integration contract
    /// @param name The name of the protocol being integrated to
    /// @param weightsByTokenId The weights of each token for the added integration
    function addIntegration(address contractAddress, string memory name, uint256[] memory weightsByTokenId) external;

    /// @param tokenAddress The address of the ERC20 token contract
    /// @param acceptingDeposits Whether token deposits are enabled
    /// @param acceptingWithdrawals Whether token withdrawals are enabled
    /// @param biosRewardWeight Token weight for BIOS rewards
    /// @param reserveRatioNumerator Number that gets divided by reserve ratio denominator to get reserve ratio
    /// @param weightsByIntegrationId The weights of each integration for the added token
    function addToken(
        address tokenAddress, 
        bool acceptingDeposits, 
        bool acceptingWithdrawals, 
        uint256 biosRewardWeight, 
        uint256 reserveRatioNumerator, 
        uint256[] memory weightsByIntegrationId
    ) external;

    /// @param tokenAddress The address of the token ERC20 contract
    function enableTokenDeposits(address tokenAddress) external;

    /// @param tokenAddress The address of the token ERC20 contract
    function disableTokenDeposits(address tokenAddress) external;

    /// @param tokenAddress The address of the token ERC20 contract
    function enableTokenWithdrawals(address tokenAddress) external;

    /// @param tokenAddress The address of the token ERC20 contract
    function disableTokenWithdrawals(address tokenAddress) external;

    /// @param tokenAddress The address of the token ERC20 contract
    /// @param rewardWeight The updated token BIOS reward weight
    function updateTokenRewardWeight(address tokenAddress, uint256 rewardWeight) external;

    /// @param integrationAddress The address of the integration contract
    /// @param tokenAddress the address of the token ERC20 contract
    /// @param updatedWeight The updated token integration weight
    function updateTokenIntegrationWeight(address integrationAddress, address tokenAddress, uint256 updatedWeight) external;

    /// @param tokenAddress the address of the token ERC20 contract
    /// @param reserveRatioNumerator Number that gets divided by reserve ratio denominator to get reserve ratio
    function updateTokenReserveRatioNumerator(address tokenAddress, uint256 reserveRatioNumerator) external;

    /// @param integrationId The ID of the integration
    /// @return The address of the integration contract
    function getIntegrationAddress(uint256 integrationId) external view returns (address);

    /// @param integrationAddress The address of the integration contract
    /// @return The name of the of the protocol being integrated to
    function getIntegrationName(address integrationAddress) external view returns (string memory);

    /// @return The address of the WETH token
    function getWethTokenAddress() external view returns (address);

    /// @return The address of the BIOS token
    function getBiosTokenAddress() external view returns (address);

    /// @param tokenId The ID of the token
    /// @return The address of the token ERC20 contract
    function getTokenAddress(uint256 tokenId) external view returns (address);

    /// @param tokenAddress The address of the token ERC20 contract
    /// @return The index of the token in the tokens array
    function getTokenId(address tokenAddress) external view returns (uint256);

    /// @param tokenAddress The address of the token ERC20 contract
    /// @return The token BIOS reward weight
    function getTokenBiosRewardWeight(address tokenAddress) external view returns (uint256);

    /// @return rewardWeightSum reward weight of depositable tokens
    function getBiosRewardWeightSum() external view returns (uint256 rewardWeightSum);

    /// @param integrationAddress The address of the integration contract
    /// @param tokenAddress the address of the token ERC20 contract
    /// @return The weight of the specified integration & token combination
    function getTokenIntegrationWeight(address integrationAddress, address tokenAddress) external view returns (uint256);

    /// @param tokenAddress The address of the token ERC20 contract
    /// @return tokenWeightSum The sum of the specified token weights
    function getTokenIntegrationWeightSum(address tokenAddress) external view returns (uint256 tokenWeightSum);

    /// @param tokenAddress The address of the token ERC20 contract
    /// @return bool indicating whether depositing this token is currently enabled
    function getTokenAcceptingDeposits(address tokenAddress) external view returns (bool);

    /// @param tokenAddress The address of the token ERC20 contract
    /// @return bool indicating whether withdrawing this token is currently enabled
    function getTokenAcceptingWithdrawals(address tokenAddress) external view returns (bool);

    // @param tokenAddress The address of the token ERC20 contract
    // @return bool indicating whether the token has been added
    function getIsTokenAdded(address tokenAddress) external view returns (bool);

    // @param integrationAddress The address of the integration contract
    // @return bool indicating whether the integration has been added
    function getIsIntegrationAdded(address tokenAddress) external view returns (bool);

    /// @notice get the length of supported tokens
    /// @return The quantity of tokens added
    function getTokenAddressesLength() external view returns (uint256);

    /// @notice get the length of supported integrations
    /// @return The quantity of integrations added
    function getIntegrationAddressesLength() external view returns (uint256);

    /// @param tokenAddress The address of the token ERC20 contract
    /// @return The value that gets divided by the reserve ratio denominator
    function getTokenReserveRatioNumerator(address tokenAddress) external view returns (uint256);

    /// @return The token reserve ratio denominator
    function getReserveRatioDenominator() external view returns (uint32);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IUserPositions{
    /// @param biosRewardsDuration_ The duration in seconds for a BIOS rewards period to last
    function setBiosRewardsDuration(uint32 biosRewardsDuration_) external;

    /// @param sender The account seeding BIOS rewards
    /// @param biosAmount The amount of BIOS to add to rewards
    function seedBiosRewards(address sender, uint256 biosAmount) external;

    /// @notice Sends all BIOS available in the Kernel to each token BIOS rewards pool based up configured weights
    function increaseBiosRewards() external;

    /// @notice User is allowed to deposit whitelisted tokens
    /// @param depositor Address of the account depositing
    /// @param tokens Array of token the token addresses
    /// @param amounts Array of token amounts
    /// @param ethAmount The amount of ETH sent with the deposit
    function deposit(address depositor, address[] memory tokens, uint256[] memory amounts, uint256 ethAmount) external;

    /// @notice User is allowed to withdraw tokens
    /// @param recipient The address of the user withdrawing
    /// @param tokens Array of token the token addresses
    /// @param amounts Array of token amounts
    /// @param withdrawWethAsEth Boolean indicating whether should receive WETH balance as ETH
    function withdraw(
        address recipient, 
        address[] memory tokens, 
        uint256[] memory amounts, 
        bool withdrawWethAsEth) 
    external returns (
        uint256 ethWithdrawn
    );

    /// @notice Allows a user to withdraw entire balances of the specified tokens and claim rewards
    /// @param recipient The address of the user withdrawing tokens
    /// @param tokens Array of token address that user is exiting positions from
    /// @param withdrawWethAsEth Boolean indicating whether should receive WETH balance as ETH
    /// @return tokenAmounts The amounts of each token being withdrawn
    /// @return ethWithdrawn The amount of ETH being withdrawn
    /// @return ethClaimed The amount of ETH being claimed from rewards
    /// @return biosClaimed The amount of BIOS being claimed from rewards
    function withdrawAllAndClaim(
        address recipient, 
        address[] memory tokens,
        bool withdrawWethAsEth
    ) external returns (
        uint256[] memory tokenAmounts,
        uint256 ethWithdrawn,
        uint256 ethClaimed,
        uint256 biosClaimed
    );

    /// @param user The address of the user claiming ETH rewards
    function claimEthRewards(address user) external returns (uint256 ethClaimed);

    /// @notice Allows users to claim their BIOS rewards for each token
    /// @param recipient The address of the usuer claiming BIOS rewards
    function claimBiosRewards(address recipient) external returns (uint256 biosClaimed);

    /// @param asset Address of the ERC20 token contract
    /// @return The total balance of the asset deposited in the system
    function totalTokenBalance(address asset) external view returns (uint256);

    /// @param asset Address of the ERC20 token contract
    /// @param account Address of the user account
    function userTokenBalance(address asset, address account) external view returns (uint256);

    /// @return The Bios Rewards Duration
    function getBiosRewardsDuration() external view returns (uint32);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IYieldManager {
    /// @param gasAccountTargetEthBalance_ The target ETH balance of the gas account
    function updateGasAccountTargetEthBalance(uint256 gasAccountTargetEthBalance_) external;

    /// @param biosBuyBackEthWeight_ The relative weight of ETH to send to BIOS buy back
    /// @param treasuryEthWeight_ The relative weight of ETH to send to the treasury
    /// @param protocolFeeEthWeight_ The relative weight of ETH to send to protocol fee accrual
    /// @param rewardsEthWeight_ The relative weight of ETH to send to user rewards
    function updateEthDistributionWeights(
        uint32 biosBuyBackEthWeight_,
        uint32 treasuryEthWeight_,
        uint32 protocolFeeEthWeight_,
        uint32 rewardsEthWeight_
    ) external;

    /// @param gasAccount_ The address of the account to send ETH to gas for executing bulk system functions
    function updateGasAccount(address payable gasAccount_) external;

    /// @param treasuryAccount_ The address of the system treasury account
    function updateTreasuryAccount(address payable treasuryAccount_) external;

    /// @notice Withdraws and then re-deploys tokens to integrations according to configured weights
    function rebalance() external;

    /// @notice Deploys all tokens to all integrations according to configured weights
    function deploy() external;

    /// @notice Harvests available yield from all tokens and integrations
    function harvestYield() external;

    /// @notice Swaps harvested yield for all tokens for ETH
    function processYield() external;

    /// @notice Distributes ETH to the gas account, BIOS buy back, treasury, protocol fee accrual, and user rewards
    function distributeEth() external;

    /// @notice Uses WETH to buy back BIOS which is sent to the Kernel
    function biosBuyBack() external;

    /// @param tokenAddress The address of the token ERC20 contract
    /// @return harvestedTokenBalance The amount of the token yield harvested held in the Kernel
    function getHarvestedTokenBalance(address tokenAddress) external view returns (uint256);

    /// @param tokenAddress The address of the token ERC20 contract
    /// @return The amount of the token held in the Kernel as reserves
    function getReserveTokenBalance(address tokenAddress) external view returns (uint256);

    /// @param tokenAddress The address of the token ERC20 contract
    /// @return The desired amount of the token to hold in the Kernel as reserves
    function getDesiredReserveTokenBalance(address tokenAddress) external view returns (uint256);

    /// @return ethWeightSum The sum of ETH distribution weights
    function getEthWeightSum() external view returns (uint32 ethWeightSum);

    /// @return processedWethSum The sum of yields processed into WETH
    function getProcessedWethSum() external view returns (uint256 processedWethSum);

    /// @param tokenAddress The address of the token ERC20 contract
    /// @return The amount of WETH received from token yield processing
    function getProcessedWethByToken(address tokenAddress) external view returns (uint256);

    /// @return processedWethByTokenSum The sum of processed WETH
    function getProcessedWethByTokenSum() external view returns (uint256 processedWethByTokenSum);

    /// @param tokenAddress The address of the token ERC20 contract
    /// @return tokenTotalIntegrationBalance The total amount of the token that can be withdrawn from integrations
    function getTokenTotalIntegrationBalance(address tokenAddress) external view returns (uint256 tokenTotalIntegrationBalance);

    /// @return The address of the gas account
    function getGasAccount() external view returns (address);

    /// @return The address of the treasury account
    function getTreasuryAccount() external view returns (address);

    /// @return The last amount of ETH distributed to rewards
    function getLastEthRewardsAmount() external view returns (uint256);

    /// @return The target ETH balance of the gas account
    function getGasAccountTargetEthBalance() external view returns (uint256);

    /// @return The BIOS buyback ETH weight
    /// @return The Treasury ETH weight
    /// @return The Protocol fee ETH weight
    /// @return The rewards ETH weight
    function getEthDistributionWeights() external view returns (uint32, uint32, uint32, uint32);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IWeth9 {
    event Deposit(address indexed dst, uint256 wad);
    event Withdrawal(address indexed src, uint256 wad);

    function deposit() external payable;

    /// @param wad The amount of wETH to withdraw into ETH
    function withdraw(uint256 wad) external;
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface IUniswapTrader {    
    /// @param tokenA The address of tokenA ERC20 contract
    /// @param tokenB The address of tokenB ERC20 contract
    /// @param fee The Uniswap pool fee
    /// @param slippageNumerator The value divided by the slippage denominator
    /// to calculate the allowable slippage
    function addPool(address tokenA, address tokenB, uint24 fee, uint24 slippageNumerator) external;

    /// @param tokenA The address of tokenA of the pool
    /// @param tokenB The address of tokenB of the pool
    /// @param poolIndex The index of the pool for the specified token pair
    /// @param slippageNumerator The new slippage numerator to update the pool
    function updatePoolSlippageNumerator(address tokenA, address tokenB, uint256 poolIndex, uint24 slippageNumerator) external;

    /// @notice Changes which Uniswap pool to use as the default pool 
    /// @notice when swapping between token0 and token1
    /// @param tokenA The address of tokenA of the pool
    /// @param tokenB The address of tokenB of the pool
    /// @param primaryPoolIndex The index of the Uniswap pool to make the new primary pool
    function updatePairPrimaryPool(address tokenA, address tokenB, uint256 primaryPoolIndex) external;
 
    /// @param tokenIn The address of the input token
    /// @param tokenOut The address of the output token
    /// @param recipient The address to receive the tokens
    /// @param amountIn The exact amount of the input to swap
    /// @return tradeSuccess Indicates whether the trade succeeded
    function swapExactInput(
        address tokenIn,
        address tokenOut,
        address recipient,
        uint256 amountIn
    ) external returns (bool tradeSuccess);

    /// @param tokenIn The address of the input token
    /// @param tokenOut The address of the output token
    /// @param recipient The address to receive the tokens
    /// @param amountOut The exact amount of the output token to receive
    /// @return tradeSuccess Indicates whether the trade succeeded
    function swapExactOutput(
        address tokenIn,
        address tokenOut,
        address recipient,
        uint256 amountOut
    ) external returns (bool tradeSuccess);

    /// @param tokenIn The address of the input token
    /// @param tokenOut The address of the output token
    /// @param amountOut The exact amount of token being swapped for
    /// @return amountInMaximum The maximum amount of tokenIn to spend, factoring in allowable slippage
    function getAmountInMaximum(address tokenIn, address tokenOut, uint256 amountOut) external view returns (uint256 amountInMaximum);

    /// @param tokenIn The address of the input token
    /// @param tokenOut The address of the output token
    /// @param amountIn The exact amount of the input to swap
    /// @return amountOut The estimated amount of tokenOut to receive
    function getEstimatedTokenOut(address tokenIn, address tokenOut, uint256 amountIn) external view returns (uint256 amountOut);

    /// @param tokenA The address of tokenA
    /// @param tokenB The address of tokenB
    /// @return token0 The address of the sorted token0
    /// @return token1 The address of the sorted token1
    function getTokensSorted(address tokenA, address tokenB) external pure returns (address token0, address token1);

    /// @return The number of token pairs configured
    function getTokenPairsLength() external view returns (uint256);

    /// @param tokenA The address of tokenA
    /// @param tokenB The address of tokenB
    /// @return The quantity of pools configured for the specified token pair
    function getTokenPairPoolsLength(address tokenA, address tokenB) external view returns (uint256);

    /// @param tokenA The address of tokenA
    /// @param tokenB The address of tokenB
    /// @param poolId The index of the pool in the pools mapping
    /// @return feeNumerator The numerator that gets divided by the fee denominator
    function getPoolFeeNumerator(address tokenA, address tokenB, uint256 poolId) external view returns (uint24 feeNumerator);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

interface ISushiSwapTrader {
    /// @param slippageNumerator_ The number divided by the slippage denominator to get the slippage percentage
    function updateSlippageNumerator(uint24 slippageNumerator_) external;

    /// @notice Swaps all WETH held in this contract for BIOS and sends to the kernel
    /// @return Bool indicating whether the trade succeeded
    function biosBuyBack() external returns (bool);

    /// @param tokenIn The address of the input token
    /// @param tokenOut The address of the output token
    /// @param recipient The address of the token out recipient
    /// @param amountIn The exact amount of the input to swap
    /// @param amountOutMin The minimum amount of tokenOut to receive from the swap
    /// @return bool Indicates whether the swap succeeded
    function swapExactInput(
        address tokenIn,
        address tokenOut,
        address recipient,
        uint256 amountIn,
        uint256 amountOutMin
    ) external returns (bool);
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.4;

import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "../interfaces/IModuleMap.sol";

abstract contract ModuleMapConsumer is Initializable {
    IModuleMap public moduleMap;

    function __ModuleMapConsumer_init(address moduleMap_) internal initializer {
        moduleMap = IModuleMap(moduleMap_);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/ContextUpgradeable.sol";
import "../utils/StringsUpgradeable.sol";
import "../utils/introspection/ERC165Upgradeable.sol";
import "../proxy/utils/Initializable.sol";

/**
 * @dev External interface of AccessControl declared to support ERC165 detection.
 */
interface IAccessControlUpgradeable {
    function hasRole(bytes32 role, address account) external view returns (bool);
    function getRoleAdmin(bytes32 role) external view returns (bytes32);
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role, address account) external;
}

/**
 * @dev Contract module that allows children to implement role-based access
 * control mechanisms. This is a lightweight version that doesn't allow enumerating role
 * members except through off-chain means by accessing the contract event logs. Some
 * applications may benefit from on-chain enumerability, for those cases see
 * {AccessControlEnumerable}.
 *
 * Roles are referred to by their `bytes32` identifier. These should be exposed
 * in the external API and be unique. The best way to achieve this is by
 * using `public constant` hash digests:
 *
 * ```
 * bytes32 public constant MY_ROLE = keccak256("MY_ROLE");
 * ```
 *
 * Roles can be used to represent a set of permissions. To restrict access to a
 * function call, use {hasRole}:
 *
 * ```
 * function foo() public {
 *     require(hasRole(MY_ROLE, msg.sender));
 *     ...
 * }
 * ```
 *
 * Roles can be granted and revoked dynamically via the {grantRole} and
 * {revokeRole} functions. Each role has an associated admin role, and only
 * accounts that have a role's admin role can call {grantRole} and {revokeRole}.
 *
 * By default, the admin role for all roles is `DEFAULT_ADMIN_ROLE`, which means
 * that only accounts with this role will be able to grant or revoke other
 * roles. More complex role relationships can be created by using
 * {_setRoleAdmin}.
 *
 * WARNING: The `DEFAULT_ADMIN_ROLE` is also its own admin: it has permission to
 * grant and revoke this role. Extra precautions should be taken to secure
 * accounts that have been granted it.
 */
abstract contract AccessControlUpgradeable is Initializable, ContextUpgradeable, IAccessControlUpgradeable, ERC165Upgradeable {
    function __AccessControl_init() internal initializer {
        __Context_init_unchained();
        __ERC165_init_unchained();
        __AccessControl_init_unchained();
    }

    function __AccessControl_init_unchained() internal initializer {
    }
    struct RoleData {
        mapping (address => bool) members;
        bytes32 adminRole;
    }

    mapping (bytes32 => RoleData) private _roles;

    bytes32 public constant DEFAULT_ADMIN_ROLE = 0x00;

    /**
     * @dev Emitted when `newAdminRole` is set as ``role``'s admin role, replacing `previousAdminRole`
     *
     * `DEFAULT_ADMIN_ROLE` is the starting admin for all roles, despite
     * {RoleAdminChanged} not being emitted signaling this.
     *
     * _Available since v3.1._
     */
    event RoleAdminChanged(bytes32 indexed role, bytes32 indexed previousAdminRole, bytes32 indexed newAdminRole);

    /**
     * @dev Emitted when `account` is granted `role`.
     *
     * `sender` is the account that originated the contract call, an admin role
     * bearer except when using {_setupRole}.
     */
    event RoleGranted(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Emitted when `account` is revoked `role`.
     *
     * `sender` is the account that originated the contract call:
     *   - if using `revokeRole`, it is the admin role bearer
     *   - if using `renounceRole`, it is the role bearer (i.e. `account`)
     */
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed sender);

    /**
     * @dev Modifier that checks that an account has a specific role. Reverts
     * with a standardized message including the required role.
     *
     * The format of the revert reason is given by the following regular expression:
     *
     *  /^AccessControl: account (0x[0-9a-f]{20}) is missing role (0x[0-9a-f]{32})$/
     *
     * _Available since v4.1._
     */
    modifier onlyRole(bytes32 role) {
        _checkRole(role, _msgSender());
        _;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAccessControlUpgradeable).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev Returns `true` if `account` has been granted `role`.
     */
    function hasRole(bytes32 role, address account) public view override returns (bool) {
        return _roles[role].members[account];
    }

    /**
     * @dev Revert with a standard message if `account` is missing `role`.
     *
     * The format of the revert reason is given by the following regular expression:
     *
     *  /^AccessControl: account (0x[0-9a-f]{20}) is missing role (0x[0-9a-f]{32})$/
     */
    function _checkRole(bytes32 role, address account) internal view {
        if(!hasRole(role, account)) {
            revert(string(abi.encodePacked(
                "AccessControl: account ",
                StringsUpgradeable.toHexString(uint160(account), 20),
                " is missing role ",
                StringsUpgradeable.toHexString(uint256(role), 32)
            )));
        }
    }

    /**
     * @dev Returns the admin role that controls `role`. See {grantRole} and
     * {revokeRole}.
     *
     * To change a role's admin, use {_setRoleAdmin}.
     */
    function getRoleAdmin(bytes32 role) public view override returns (bytes32) {
        return _roles[role].adminRole;
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function grantRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        _grantRole(role, account);
    }

    /**
     * @dev Revokes `role` from `account`.
     *
     * If `account` had been granted `role`, emits a {RoleRevoked} event.
     *
     * Requirements:
     *
     * - the caller must have ``role``'s admin role.
     */
    function revokeRole(bytes32 role, address account) public virtual override onlyRole(getRoleAdmin(role)) {
        _revokeRole(role, account);
    }

    /**
     * @dev Revokes `role` from the calling account.
     *
     * Roles are often managed via {grantRole} and {revokeRole}: this function's
     * purpose is to provide a mechanism for accounts to lose their privileges
     * if they are compromised (such as when a trusted device is misplaced).
     *
     * If the calling account had been granted `role`, emits a {RoleRevoked}
     * event.
     *
     * Requirements:
     *
     * - the caller must be `account`.
     */
    function renounceRole(bytes32 role, address account) public virtual override {
        require(account == _msgSender(), "AccessControl: can only renounce roles for self");

        _revokeRole(role, account);
    }

    /**
     * @dev Grants `role` to `account`.
     *
     * If `account` had not been already granted `role`, emits a {RoleGranted}
     * event. Note that unlike {grantRole}, this function doesn't perform any
     * checks on the calling account.
     *
     * [WARNING]
     * ====
     * This function should only be called from the constructor when setting
     * up the initial roles for the system.
     *
     * Using this function in any other way is effectively circumventing the admin
     * system imposed by {AccessControl}.
     * ====
     */
    function _setupRole(bytes32 role, address account) internal virtual {
        _grantRole(role, account);
    }

    /**
     * @dev Sets `adminRole` as ``role``'s admin role.
     *
     * Emits a {RoleAdminChanged} event.
     */
    function _setRoleAdmin(bytes32 role, bytes32 adminRole) internal virtual {
        emit RoleAdminChanged(role, getRoleAdmin(role), adminRole);
        _roles[role].adminRole = adminRole;
    }

    function _grantRole(bytes32 role, address account) private {
        if (!hasRole(role, account)) {
            _roles[role].members[account] = true;
            emit RoleGranted(role, account, _msgSender());
        }
    }

    function _revokeRole(bytes32 role, address account) private {
        if (hasRole(role, account)) {
            _roles[role].members[account] = false;
            emit RoleRevoked(role, account, _msgSender());
        }
    }
    uint256[49] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Library for managing
 * https://en.wikipedia.org/wiki/Set_(abstract_data_type)[sets] of primitive
 * types.
 *
 * Sets have the following properties:
 *
 * - Elements are added, removed, and checked for existence in constant time
 * (O(1)).
 * - Elements are enumerated in O(n). No guarantees are made on the ordering.
 *
 * ```
 * contract Example {
 *     // Add the library methods
 *     using EnumerableSet for EnumerableSet.AddressSet;
 *
 *     // Declare a set state variable
 *     EnumerableSet.AddressSet private mySet;
 * }
 * ```
 *
 * As of v3.3.0, sets of type `bytes32` (`Bytes32Set`), `address` (`AddressSet`)
 * and `uint256` (`UintSet`) are supported.
 */
library EnumerableSetUpgradeable {
    // To implement this library for multiple types with as little code
    // repetition as possible, we write it in terms of a generic Set type with
    // bytes32 values.
    // The Set implementation uses private functions, and user-facing
    // implementations (such as AddressSet) are just wrappers around the
    // underlying Set.
    // This means that we can only create new EnumerableSets for types that fit
    // in bytes32.

    struct Set {
        // Storage of set values
        bytes32[] _values;

        // Position of the value in the `values` array, plus 1 because index 0
        // means a value is not in the set.
        mapping (bytes32 => uint256) _indexes;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function _add(Set storage set, bytes32 value) private returns (bool) {
        if (!_contains(set, value)) {
            set._values.push(value);
            // The value is stored at length-1, but we add 1 to all indexes
            // and use 0 as a sentinel value
            set._indexes[value] = set._values.length;
            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function _remove(Set storage set, bytes32 value) private returns (bool) {
        // We read and store the value's index to prevent multiple reads from the same storage slot
        uint256 valueIndex = set._indexes[value];

        if (valueIndex != 0) { // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;

            // When the value to delete is the last one, the swap operation is unnecessary. However, since this occurs
            // so rarely, we still do the swap anyway to avoid the gas cost of adding an 'if' statement.

            bytes32 lastvalue = set._values[lastIndex];

            // Move the last value to the index where the value to delete is
            set._values[toDeleteIndex] = lastvalue;
            // Update the index for the moved value
            set._indexes[lastvalue] = valueIndex; // Replace lastvalue's index to valueIndex

            // Delete the slot where the moved value was stored
            set._values.pop();

            // Delete the index for the deleted slot
            delete set._indexes[value];

            return true;
        } else {
            return false;
        }
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function _contains(Set storage set, bytes32 value) private view returns (bool) {
        return set._indexes[value] != 0;
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function _length(Set storage set) private view returns (uint256) {
        return set._values.length;
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function _at(Set storage set, uint256 index) private view returns (bytes32) {
        require(set._values.length > index, "EnumerableSet: index out of bounds");
        return set._values[index];
    }

    // Bytes32Set

    struct Bytes32Set {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _add(set._inner, value);
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(Bytes32Set storage set, bytes32 value) internal returns (bool) {
        return _remove(set._inner, value);
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(Bytes32Set storage set, bytes32 value) internal view returns (bool) {
        return _contains(set._inner, value);
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(Bytes32Set storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(Bytes32Set storage set, uint256 index) internal view returns (bytes32) {
        return _at(set._inner, index);
    }

    // AddressSet

    struct AddressSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(AddressSet storage set, address value) internal returns (bool) {
        return _add(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(AddressSet storage set, address value) internal returns (bool) {
        return _remove(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(AddressSet storage set, address value) internal view returns (bool) {
        return _contains(set._inner, bytes32(uint256(uint160(value))));
    }

    /**
     * @dev Returns the number of values in the set. O(1).
     */
    function length(AddressSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(AddressSet storage set, uint256 index) internal view returns (address) {
        return address(uint160(uint256(_at(set._inner, index))));
    }


    // UintSet

    struct UintSet {
        Set _inner;
    }

    /**
     * @dev Add a value to a set. O(1).
     *
     * Returns true if the value was added to the set, that is if it was not
     * already present.
     */
    function add(UintSet storage set, uint256 value) internal returns (bool) {
        return _add(set._inner, bytes32(value));
    }

    /**
     * @dev Removes a value from a set. O(1).
     *
     * Returns true if the value was removed from the set, that is if it was
     * present.
     */
    function remove(UintSet storage set, uint256 value) internal returns (bool) {
        return _remove(set._inner, bytes32(value));
    }

    /**
     * @dev Returns true if the value is in the set. O(1).
     */
    function contains(UintSet storage set, uint256 value) internal view returns (bool) {
        return _contains(set._inner, bytes32(value));
    }

    /**
     * @dev Returns the number of values on the set. O(1).
     */
    function length(UintSet storage set) internal view returns (uint256) {
        return _length(set._inner);
    }

   /**
    * @dev Returns the value stored at position `index` in the set. O(1).
    *
    * Note that there are no guarantees on the ordering of values inside the
    * array, and it may change when more values are added or removed.
    *
    * Requirements:
    *
    * - `index` must be strictly less than {length}.
    */
    function at(UintSet storage set, uint256 index) internal view returns (uint256) {
        return uint256(_at(set._inner, index));
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
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
    uint256[50] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev String operations.
 */
library StringsUpgradeable {
    bytes16 private constant alphabet = "0123456789abcdef";

    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }
        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation.
     */
    function toHexString(uint256 value) internal pure returns (string memory) {
        if (value == 0) {
            return "0x00";
        }
        uint256 temp = value;
        uint256 length = 0;
        while (temp != 0) {
            length++;
            temp >>= 8;
        }
        return toHexString(value, length);
    }

    /**
     * @dev Converts a `uint256` to its ASCII `string` hexadecimal representation with fixed length.
     */
    function toHexString(uint256 value, uint256 length) internal pure returns (string memory) {
        bytes memory buffer = new bytes(2 * length + 2);
        buffer[0] = "0";
        buffer[1] = "x";
        for (uint256 i = 2 * length + 1; i > 1; --i) {
            buffer[i] = alphabet[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }

}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC165Upgradeable.sol";
import "../../proxy/utils/Initializable.sol";

/**
 * @dev Implementation of the {IERC165} interface.
 *
 * Contracts that want to implement ERC165 should inherit from this contract and override {supportsInterface} to check
 * for the additional interface id that will be supported. For example:
 *
 * ```solidity
 * function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
 *     return interfaceId == type(MyInterface).interfaceId || super.supportsInterface(interfaceId);
 * }
 * ```
 *
 * Alternatively, {ERC165Storage} provides an easier to use but more expensive implementation.
 */
abstract contract ERC165Upgradeable is Initializable, IERC165Upgradeable {
    function __ERC165_init() internal initializer {
        __ERC165_init_unchained();
    }

    function __ERC165_init_unchained() internal initializer {
    }
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165Upgradeable).interfaceId;
    }
    uint256[50] private __gap;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Interface of the ERC165 standard, as defined in the
 * https://eips.ethereum.org/EIPS/eip-165[EIP].
 *
 * Implementers can declare support of contract interfaces, which can then be
 * queried by others ({ERC165Checker}).
 *
 * For an implementation, see {ERC165}.
 */
interface IERC165Upgradeable {
    /**
     * @dev Returns true if this contract implements the interface defined by
     * `interfaceId`. See the corresponding
     * https://eips.ethereum.org/EIPS/eip-165#how-interfaces-are-identified[EIP section]
     * to learn more about how these ids are created.
     *
     * This function call must use less than 30 000 gas.
     */
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
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

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev Collection of functions related to the address type
 */
library AddressUpgradeable {
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
        // solhint-disable-next-line no-inline-assembly
        assembly { size := extcodesize(account) }
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

        // solhint-disable-next-line avoid-low-level-calls, avoid-call-value
        (bool success, ) = recipient.call{ value: amount }("");
        require(success, "Address: unable to send value, recipient may have reverted");
    }

    /**
     * @dev Performs a Solidity function call using a low level `call`. A
     * plain`call` is an unsafe replacement for a function call: use this
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
    function functionCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
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
    function functionCallWithValue(address target, bytes memory data, uint256 value) internal returns (bytes memory) {
        return functionCallWithValue(target, data, value, "Address: low-level call with value failed");
    }

    /**
     * @dev Same as {xref-Address-functionCallWithValue-address-bytes-uint256-}[`functionCallWithValue`], but
     * with `errorMessage` as a fallback revert reason when `target` reverts.
     *
     * _Available since v3.1._
     */
    function functionCallWithValue(address target, bytes memory data, uint256 value, string memory errorMessage) internal returns (bytes memory) {
        require(address(this).balance >= value, "Address: insufficient balance for call");
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: value }(data);
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
    function functionStaticCall(address target, bytes memory data, string memory errorMessage) internal view returns (bytes memory) {
        require(isContract(target), "Address: static call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.staticcall(data);
        return _verifyCallResult(success, returndata, errorMessage);
    }

    function _verifyCallResult(bool success, bytes memory returndata, string memory errorMessage) private pure returns(bytes memory) {
        if (success) {
            return returndata;
        } else {
            // Look for revert reason and bubble it up if present
            if (returndata.length > 0) {
                // The easiest way to bubble the revert reason is using memory via assembly

                // solhint-disable-next-line no-inline-assembly
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
pragma solidity ^0.8.4;

enum Modules {
    Kernel, // 0
    UserPositions, // 1
    YieldManager, // 2
    IntegrationMap, // 3
    BiosRewards, // 4
    EtherRewards, // 5
    SushiSwapTrader, // 6
    UniswapTrader // 7
}

interface IModuleMap {
    function getModuleAddress(Modules key) external view returns (address);
}

{
  "optimizer": {
    "enabled": true,
    "runs": 1000
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