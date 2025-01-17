/*

██████╗░██████╗░██╗███╗░░░███╗███████╗██████╗░░█████╗░░█████╗░
██╔══██╗██╔══██╗██║████╗░████║██╔════╝██╔══██╗██╔══██╗██╔══██╗
██████╔╝██████╔╝██║██╔████╔██║█████╗░░██║░░██║███████║██║░░██║
██╔═══╝░██╔══██╗██║██║╚██╔╝██║██╔══╝░░██║░░██║██╔══██║██║░░██║
██║░░░░░██║░░██║██║██║░╚═╝░██║███████╗██████╔╝██║░░██║╚█████╔╝
╚═╝░░░░░╚═╝░░╚═╝╚═╝╚═╝░░░░░╚═╝╚══════╝╚═════╝░╚═╝░░╚═╝░╚════╝░

*/

// SPDX-License-Identifier: GPL-3.0-or-later

// solium-disable linebreak-style
pragma solidity ^0.8.6;

import "../utils/CloneFactory.sol";
import "openzeppelin-solidity/contracts/access/Ownable.sol";
import "./LBPManager.sol";

/**
 * @title LBPManager Factory
 * @dev   Governance to create new LBPManager contracts.
 */
contract LBPManagerFactory is CloneFactory, Ownable {
    address public masterCopy;
    address public LBPFactory;

    event LBPManagerDeployed(
        address indexed lbpManager,
        address indexed admin,
        bytes metadata
    );

    event LBPFactoryChanged(
        address indexed oldLBPFactory,
        address indexed newLBPFactory
    );

    event MastercopyChanged(
        address indexed oldMasterCopy,
        address indexed newMasterCopy
    );

    /**
     * @dev                             Constructor.
     * @param _LBPFactory               The address of Balancers LBP factory.
     */
    constructor(address _LBPFactory) {
        require(_LBPFactory != address(0), "LBPMFactory: LBPFactory is zero");
        LBPFactory = _LBPFactory;
    }

    modifier validAddress(address addressToCheck) {
        require(addressToCheck != address(0), "LBPMFactory: address is zero");
        require(
            addressToCheck != address(this),
            "LBPMFactory: address same as LBPManagerFactory"
        );
        _;
    }

    /**
     * @dev                             Set LBPManager contract which works as a base for clones.
     * @param _masterCopy               The address of the new LBPManager basis.
     */
    function setMasterCopy(address _masterCopy)
        external
        onlyOwner
        validAddress(_masterCopy)
    {
        emit MastercopyChanged(masterCopy, _masterCopy);
        masterCopy = _masterCopy;
    }

    /**
     * @dev                             Set Balancers LBP Factory contract as basis for deploying LBPs.
     * @param _LBPFactory               The address of Balancers LBP factory.
     */
    function setLBPFactory(address _LBPFactory)
        external
        onlyOwner
        validAddress(_LBPFactory)
    {
        emit LBPFactoryChanged(LBPFactory, _LBPFactory);
        LBPFactory = _LBPFactory;
    }

    /**
     * @dev                             Deploy and initialize LBPManager.
     * @param _admin                    The address of the admin of the LBPManager.
     * @param _beneficiary              The address that receives the _fees.
     * @param _name                     Name of the LBP.
     * @param _symbol                   Symbol of the LBP.
     * @param _tokenList                Numerically sorted array (ascending) containing two addresses:
                                            - The address of the project token being distributed.
                                            - The address of the funding token being exchanged for the project token.
     * @param _amounts                  Sorted array to match the _tokenList, containing two parameters:
                                            - The amounts of project token to be added as liquidity to the LBP.
                                            - The amounts of funding token to be added as liquidity to the LBP.
     * @param _startWeights                  Sorted array to match the _tokenList, containing two parametes:
                                            - The start weight for the project token in the LBP.
                                            - The start weight for the funding token in the LBP.
     * @param _startTimeEndtime         Array containing two parameters:
                                            - Start time for the LBP.
                                            - End time for the LBP.
     * @param _endWeights               Sorted array to match the _tokenList, containing two parametes:
                                            - The end weight for the project token in the LBP.
                                            - The end weight for the funding token in the LBP.
     * @param _fees                     Array containing two parameters:
                                            - Percentage of fee paid for every swap in the LBP.
                                            - Percentage of fee paid to the _beneficiary for providing the service of the LBP Manager.
     * @param _metadata                 IPFS Hash of the LBP creation wizard information.
     */
    function deployLBPManager(
        address _admin,
        address _beneficiary,
        string memory _name,
        string memory _symbol,
        IERC20[] memory _tokenList,
        uint256[] memory _amounts,
        uint256[] memory _startWeights,
        uint256[] memory _startTimeEndtime,
        uint256[] memory _endWeights,
        uint256[] memory _fees,
        bytes memory _metadata
    ) external onlyOwner {
        require(
            masterCopy != address(0),
            "LBPMFactory: LBPManager mastercopy not set"
        );

        address lbpManager = createClone(masterCopy);

        LBPManager(lbpManager).initializeLBPManager(
            LBPFactory,
            _beneficiary,
            _name,
            _symbol,
            _tokenList,
            _amounts,
            _startWeights,
            _startTimeEndtime,
            _endWeights,
            _fees,
            _metadata
        );

        LBPManager(lbpManager).transferAdminRights(_admin);

        emit LBPManagerDeployed(lbpManager, _admin, _metadata);
    }
}

/*

██████╗░██████╗░██╗███╗░░░███╗███████╗██████╗░░█████╗░░█████╗░
██╔══██╗██╔══██╗██║████╗░████║██╔════╝██╔══██╗██╔══██╗██╔══██╗
██████╔╝██████╔╝██║██╔████╔██║█████╗░░██║░░██║███████║██║░░██║
██╔═══╝░██╔══██╗██║██║╚██╔╝██║██╔══╝░░██║░░██║██╔══██║██║░░██║
██║░░░░░██║░░██║██║██║░╚═╝░██║███████╗██████╔╝██║░░██║╚█████╔╝
╚═╝░░░░░╚═╝░░╚═╝╚═╝╚═╝░░░░░╚═╝╚══════╝╚═════╝░╚═╝░░╚═╝░╚════╝░

* ===========
*
* CloneFactory.sol was originally published under MIT license.
* Republished by PrimeDAO under GNU General Public License v3.0.
*
*/

/*
The MIT License (MIT)
Copyright (c) 2018 Murray Software, LLC.
Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:
The above copyright notice and this permission notice shall be included
in all copies or substantial portions of the Software.
THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS
OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
*/

// SPDX-License-Identifier: GPL-3.0-or-later
// solium-disable linebreak-style
// solhint-disable max-line-length
// solhint-disable no-inline-assembly

pragma solidity 0.8.6;

contract CloneFactory {
    function createClone(address target) internal returns (address result) {
        bytes20 targetBytes = bytes20(target);
        assembly {
            let clone := mload(0x40)
            mstore(
                clone,
                0x3d602d80600a3d3981f3363d3d373d3d3d363d73000000000000000000000000
            )
            mstore(add(clone, 0x14), targetBytes)
            mstore(
                add(clone, 0x28),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )
            result := create(0, clone, 0x37)
        }
    }

    function isClone(address target, address query)
        internal
        view
        returns (bool result)
    {
        bytes20 targetBytes = bytes20(target);
        assembly {
            let clone := mload(0x40)
            mstore(
                clone,
                0x363d3d373d3d3d363d7300000000000000000000000000000000000000000000
            )
            mstore(add(clone, 0xa), targetBytes)
            mstore(
                add(clone, 0x1e),
                0x5af43d82803e903d91602b57fd5bf30000000000000000000000000000000000
            )

            let other := add(clone, 0x40)
            extcodecopy(query, other, 0, 0x2d)
            result := and(
                eq(mload(clone), mload(other)),
                eq(mload(add(clone, 0xd)), mload(add(other, 0xd)))
            )
        }
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

/*
██████╗░██████╗░██╗███╗░░░███╗███████╗██████╗░░█████╗░░█████╗░
██╔══██╗██╔══██╗██║████╗░████║██╔════╝██╔══██╗██╔══██╗██╔══██╗
██████╔╝██████╔╝██║██╔████╔██║█████╗░░██║░░██║███████║██║░░██║
██╔═══╝░██╔══██╗██║██║╚██╔╝██║██╔══╝░░██║░░██║██╔══██║██║░░██║
██║░░░░░██║░░██║██║██║░╚═╝░██║███████╗██████╔╝██║░░██║╚█████╔╝
╚═╝░░░░░╚═╝░░╚═╝╚═╝╚═╝░░░░░╚═╝╚══════╝╚═════╝░╚═╝░░╚═╝░╚════╝░
*/

// SPDX-License-Identifier: GPL-3.0-or-later

// solium-disable linebreak-style
pragma solidity 0.8.6;

import "openzeppelin-contracts-sol8/token/ERC20/IERC20.sol";
import "../utils/interface/ILBPFactory.sol";
import "../utils/interface/IVault.sol";
import "../utils/interface/ILBP.sol";

/**
 * @title LBPManager contract.
 * @dev   Smart contract for managing interactions with a Balancer LBP.
 */
contract LBPManager {
    // Constants
    uint256 private constant HUNDRED_PERCENT = 10e18; // Used in calculating the fee.

    // Locked parameter
    string public symbol; // Symbol of the LBP.
    string public name; // Name of the LBP.
    address public admin; // Address of the admin of this contract.
    address public beneficiary; // Address that recieves fees.
    uint256 public feePercentage; // Fee expressed as a % (e.g. 10**18 = 100% fee, toWei('1') = 100%)
    uint256 public swapFeePercentage; // Percentage of fee paid for every swap in the LBP.
    IERC20[] public tokenList; // Tokens that are used in the LBP, sorted by address in numerical order (ascending).
    uint256[] public amounts; // Amount of tokens to be added as liquidity in LBP.
    uint256[] public startWeights; // Array containing the startWeights for the project & funding token.
    uint256[] public endWeights; // Array containing the endWeights for the project & funding token.
    uint256[] public startTimeEndTime; // Array containing the startTime and endTime for the LBP.
    ILBP public lbp; // Address of LBP that is managed by this contract.
    bytes public metadata; // IPFS Hash of the LBP creation wizard information.
    uint8 private projectTokenIndex; // Index repesenting the project token in the tokenList.
    address public LBPFactory; // Address of Balancers LBP factory.

    // Contract logic
    bool public poolFunded; // true:- LBP is funded; false:- LBP is not funded.
    bool public initialized; // true:- LBPManager initialized; false:- LBPManager not initialized. Makes sure, only initialized once.

    event LBPManagerAdminChanged(
        address indexed oldAdmin,
        address indexed newAdmin
    );
    event FeeTransferred(
        address indexed beneficiary,
        address tokenAddress,
        uint256 amount
    );
    event PoolTokensWithdrawn(address indexed LbpAddress, uint256 amount);
    event MetadataUpdated(bytes indexed metadata);

    modifier onlyAdmin() {
        require(msg.sender == admin, "LBPManager: caller is not admin");
        _;
    }

    /**
     * @dev                             Transfer admin rights.
     * @param _newAdmin                 Address of the new admin.
     */
    function transferAdminRights(address _newAdmin) external onlyAdmin {
        require(_newAdmin != address(0), "LBPManager: new admin is zero");

        emit LBPManagerAdminChanged(admin, _newAdmin);
        admin = _newAdmin;
    }

    /**
     * @dev                             Initialize LBPManager.
     * @param _LBPFactory               LBP factory address.
     * @param _beneficiary              The address that receives the feePercentage.
     * @param _name                     Name of the LBP.
     * @param _symbol                   Symbol of the LBP.
     * @param _tokenList                Array containing two addresses in order of:
                                            1. The address of the project token being distributed.
                                            2. The address of the funding token being exchanged for the project token.
     * @param _amounts                  Array containing two parameters in order of:
                                            1. The amounts of project token to be added as liquidity to the LBP.
                                            2. The amounts of funding token to be added as liquidity to the LBP.
     * @param _startWeights             Array containing two parametes in order of:
                                            1. The start weight for the project token in the LBP.
                                            2. The start weight for the funding token in the LBP.
     * @param _startTimeEndTime         Array containing two parameters in order of:
                                            1. Start time for the LBP.
                                            2. End time for the LBP.
     * @param _endWeights               Array containing two parametes in order of:
                                            1. The end weight for the project token in the LBP.
                                            2. The end weight for the funding token in the LBP.
    * @param _fees                      Array containing two parameters in order of:
                                            1. Percentage of fee paid for every swap in the LBP.
                                            2. Percentage of fee paid to the _beneficiary for providing the service of the LBP Manager.
     * @param _metadata                 IPFS Hash of the LBP creation wizard information.
     */
    function initializeLBPManager(
        address _LBPFactory,
        address _beneficiary,
        string memory _name,
        string memory _symbol,
        IERC20[] memory _tokenList,
        uint256[] memory _amounts,
        uint256[] memory _startWeights,
        uint256[] memory _startTimeEndTime,
        uint256[] memory _endWeights,
        uint256[] memory _fees,
        bytes memory _metadata
    ) external {
        require(!initialized, "LBPManager: already initialized");
        require(_beneficiary != address(0), "LBPManager: _beneficiary is zero");

        initialized = true;
        admin = msg.sender;
        swapFeePercentage = _fees[0];
        feePercentage = _fees[1];
        beneficiary = _beneficiary;
        metadata = _metadata;
        startTimeEndTime = _startTimeEndTime;
        name = _name;
        symbol = _symbol;
        LBPFactory = _LBPFactory;

        // Token addresses are sorted in numerical order (ascending) as specified by Balancer
        if (address(_tokenList[0]) > address(_tokenList[1])) {
            projectTokenIndex = 1;
            tokenList.push(_tokenList[1]);
            tokenList.push(_tokenList[0]);

            amounts.push(_amounts[1]);
            amounts.push(_amounts[0]);

            startWeights.push(_startWeights[1]);
            startWeights.push(_startWeights[0]);

            endWeights.push(_endWeights[1]);
            endWeights.push(_endWeights[0]);
        } else {
            projectTokenIndex = 0;
            tokenList = _tokenList;
            amounts = _amounts;
            startWeights = _startWeights;
            endWeights = _endWeights;
        }
    }

    /**
     * @dev                             Subtracts the fee and adds liquidity to the LBP.
     * @param _sender                   Address of the liquidity provider.
     */
    function initializeLBP(address _sender) external onlyAdmin {
        require(
            initialized == true,
            "LBPManager: LBPManager in not initialized"
        );
        require(!poolFunded, "LBPManager: pool already funded");
        poolFunded = true;

        lbp = ILBP(
            ILBPFactory(LBPFactory).create(
                name,
                symbol,
                tokenList,
                startWeights,
                swapFeePercentage,
                address(this),
                true // SwapEnabled is set to true at pool creation.
            )
        );

        lbp.updateWeightsGradually(
            startTimeEndTime[0],
            startTimeEndTime[1],
            endWeights
        );

        IVault vault = lbp.getVault();

        if (feePercentage != 0) {
            // Transfer fee to beneficiary.
            tokenList[projectTokenIndex].transferFrom(
                _sender,
                beneficiary,
                _feeAmountRequired()
            );
            emit FeeTransferred(
                beneficiary,
                address(tokenList[projectTokenIndex]),
                _feeAmountRequired()
            );
        }

        for (uint8 i; i < tokenList.length; i++) {
            tokenList[i].transferFrom(_sender, address(this), amounts[i]);
            tokenList[i].approve(address(vault), amounts[i]);
        }

        IVault.JoinPoolRequest memory request = IVault.JoinPoolRequest({
            maxAmountsIn: amounts,
            userData: abi.encode(0, amounts), // JOIN_KIND_INIT = 0, used when adding liquidity for the first time.
            fromInternalBalance: false, // It is not possible to add liquidity through the internal Vault balance.
            assets: tokenList
        });

        vault.joinPool(lbp.getPoolId(), address(this), address(this), request);
    }

    /**
     * @dev                             Exit pool or remove liquidity from pool.
     * @param _receiver                 Address of the liquidity receiver, after exiting the LBP.
     */
    function removeLiquidity(address payable _receiver) external onlyAdmin {
        require(
            _receiver != payable(address(0)),
            "LBPManager: receiver is zero"
        );
        require(
            lbp.balanceOf(address(this)) > 0,
            "LBPManager: no BPT token balance"
        );

        uint256 endTime;
        (, endTime, ) = lbp.getGradualWeightUpdateParams();

        require(block.timestamp >= endTime, "LBPManager: endtime not reached");

        IVault vault = lbp.getVault();

        IVault.ExitPoolRequest memory request = IVault.ExitPoolRequest({
            minAmountsOut: new uint256[](tokenList.length), // To remove all funding from the pool. Initializes to [0, 0]
            userData: abi.encode(1, lbp.balanceOf(address(this))),
            toInternalBalance: false,
            assets: tokenList
        });

        lbp.approve(address(vault), lbp.balanceOf(address(this)));

        vault.exitPool(lbp.getPoolId(), address(this), _receiver, request);
    }

    /*
        DISCLAIMER:
        The method below is an advanced functionality. By invoking this method, you are withdrawing
        the BPT tokens, which are necessary to exit the pool. If you chose to remove the BPT tokens,
        the LBPManager will no longer be able to remove liquidity. By withdrawing the BPT tokens
        you agree on removing all the responsibility from the LBPManger for removing liquidity from
        the pool and transferring this responsibility to the holder of the BPT tokens. Any possible
        loss of funds by choosing to withdraw the BPT tokens is not the responsibility of
        LBPManager or PrimeDao. After withdrawing the BPT tokens, liquidity has to be withdrawn
        directly from Balancer's LBP. LBPManager or PrimeDAO will no longer provide support to do so.
    */
    /**
     * @dev                             Withdraw pool tokens if available.
     * @param _receiver                 Address of the BPT tokens receiver.
     */
    function withdrawPoolTokens(address _receiver) external onlyAdmin {
        require(_receiver != address(0), "LBPManager: receiver is zero");

        uint256 endTime;
        (, endTime, ) = lbp.getGradualWeightUpdateParams();
        require(block.timestamp >= endTime, "LBPManager: endtime not reached");

        require(
            lbp.balanceOf(address(this)) > 0,
            "LBPManager: no BPT token balance"
        );

        emit PoolTokensWithdrawn(address(lbp), lbp.balanceOf(address(this)));
        lbp.transfer(_receiver, lbp.balanceOf(address(this)));
    }

    /**
     * @dev                             Can pause/unpause trading.
     * @param _swapEnabled              Enables/disables swapping.
     */
    function setSwapEnabled(bool _swapEnabled) external onlyAdmin {
        lbp.setSwapEnabled(_swapEnabled);
    }

    /**
     * @dev             Get required amount of project tokens to cover for fees and the actual LBP.
     */
    function projectTokensRequired()
        external
        view
        returns (uint256 projectTokenAmounts)
    {
        projectTokenAmounts = amounts[projectTokenIndex] + _feeAmountRequired();
    }

    /**
     * @dev                             Updates metadata.
     * @param _metadata                 LBP wizard contract metadata, that is an IPFS Hash.
     */
    function updateMetadata(bytes memory _metadata) external onlyAdmin {
        metadata = _metadata;
        emit MetadataUpdated(_metadata);
    }

    /**
     * @dev             Get required amount of project tokens to cover for fees.
     */
    function _feeAmountRequired() internal view returns (uint256 feeAmount) {
        feeAmount =
            (amounts[projectTokenIndex] * feePercentage) /
            HUNDRED_PERCENT;
    }
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

/*

██████╗░██████╗░██╗███╗░░░███╗███████╗██████╗░░█████╗░░█████╗░
██╔══██╗██╔══██╗██║████╗░████║██╔════╝██╔══██╗██╔══██╗██╔══██╗
██████╔╝██████╔╝██║██╔████╔██║█████╗░░██║░░██║███████║██║░░██║
██╔═══╝░██╔══██╗██║██║╚██╔╝██║██╔══╝░░██║░░██║██╔══██║██║░░██║
██║░░░░░██║░░██║██║██║░╚═╝░██║███████╗██████╔╝██║░░██║╚█████╔╝
╚═╝░░░░░╚═╝░░╚═╝╚═╝╚═╝░░░░░╚═╝╚══════╝╚═════╝░╚═╝░░╚═╝░╚════╝░

*/

// SPDX-License-Identifier: GPL-3.0-or-later

/* solium-disable */
pragma solidity ^0.8.6;

import "openzeppelin-contracts-sol8/token/ERC20/IERC20.sol";

interface ILBPFactory {
    function create(
        string memory name,
        string memory symbol,
        IERC20[] memory tokens,
        uint256[] memory weights,
        uint256 swapFeePercentage,
        address owner,
        bool swapEnabledOnStart
    ) external returns (address);
}

/*

██████╗░██████╗░██╗███╗░░░███╗███████╗██████╗░░█████╗░░█████╗░
██╔══██╗██╔══██╗██║████╗░████║██╔════╝██╔══██╗██╔══██╗██╔══██╗
██████╔╝██████╔╝██║██╔████╔██║█████╗░░██║░░██║███████║██║░░██║
██╔═══╝░██╔══██╗██║██║╚██╔╝██║██╔══╝░░██║░░██║██╔══██║██║░░██║
██║░░░░░██║░░██║██║██║░╚═╝░██║███████╗██████╔╝██║░░██║╚█████╔╝
╚═╝░░░░░╚═╝░░╚═╝╚═╝╚═╝░░░░░╚═╝╚══════╝╚═════╝░╚═╝░░╚═╝░╚════╝░

*/

// SPDX-License-Identifier: GPL-3.0-or-later

/* solium-disable */
pragma solidity ^0.8.6;

import "openzeppelin-contracts-sol8/token/ERC20/IERC20.sol";

interface IVault {
    struct JoinPoolRequest {
        IERC20[] assets;
        uint256[] maxAmountsIn;
        bytes userData;
        bool fromInternalBalance;
    }

    struct ExitPoolRequest {
        IERC20[] assets;
        uint256[] minAmountsOut;
        bytes userData;
        bool toInternalBalance;
    }

    function joinPool(
        bytes32 poolId,
        address sender,
        address recipient,
        JoinPoolRequest memory request
    ) external payable;

    function exitPool(
        bytes32 poolId,
        address sender,
        address payable recipient,
        ExitPoolRequest memory request
    ) external;
}

/*

██████╗░██████╗░██╗███╗░░░███╗███████╗██████╗░░█████╗░░█████╗░
██╔══██╗██╔══██╗██║████╗░████║██╔════╝██╔══██╗██╔══██╗██╔══██╗
██████╔╝██████╔╝██║██╔████╔██║█████╗░░██║░░██║███████║██║░░██║
██╔═══╝░██╔══██╗██║██║╚██╔╝██║██╔══╝░░██║░░██║██╔══██║██║░░██║
██║░░░░░██║░░██║██║██║░╚═╝░██║███████╗██████╔╝██║░░██║╚█████╔╝
╚═╝░░░░░╚═╝░░╚═╝╚═╝╚═╝░░░░░╚═╝╚══════╝╚═════╝░╚═╝░░╚═╝░╚════╝░

*/

// SPDX-License-Identifier: GPL-3.0-or-later
/* solium-disable */

import "openzeppelin-contracts-sol8/token/ERC20/IERC20.sol";
import "./IVault.sol";

pragma solidity ^0.8.6;

interface ILBP is IERC20 {
    function updateWeightsGradually(
        uint256 startTime,
        uint256 endTime,
        uint256[] memory endWeights
    ) external;

    function getGradualWeightUpdateParams()
        external
        view
        returns (
            uint256 startTime,
            uint256 endTime,
            uint256[] memory endWeights
        );

    function getPoolId() external view returns (bytes32);

    function getVault() external view returns (IVault);

    function setSwapEnabled(bool swapEnabled) external;

    function getSwapEnabled() external view returns (bool);

    function getSwapFeePercentage() external view returns (uint256);
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
        "devdoc",
        "userdoc",
        "metadata",
        "abi"
      ]
    }
  },
  "metadata": {
    "useLiteralContent": true
  },
  "libraries": {}
}