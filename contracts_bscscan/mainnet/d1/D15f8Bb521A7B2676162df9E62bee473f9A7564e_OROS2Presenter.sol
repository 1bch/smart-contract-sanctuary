// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/math/SafeMath.sol";
import "./interfaces/ITokenPresenter.sol";
import "./interfaces/IPancakeRouter02.sol";
import "./interfaces/IPancakeFactory.sol";
import "./utils/Maintainable.sol";
import "./utils/AntiWhale.sol";

contract OROS2Presenter is ITokenPresenter, Maintainable, AntiWhale {
  
  using SafeMath for uint;
  struct Info {
    address addr;
    uint percentage;
    bool isEnabled;
    uint8 side; // 0 for buy, 1 for transfer, 2 for both
    bool isRegistered;
  }

  uint internal constant RATE_NOMINATOR = 10000; // rate nominator

  address public token;
  address public router;

  mapping(address => uint) public rewardPool;
  mapping(address => mapping(address => uint)) userDebt;
  mapping(address => mapping(address => uint)) userRewardExcluded;

  mapping(address => bool) public isExcludedFromFees;
  mapping(address => bool) public isExcludedTotalStaked;
  mapping(address => bool) public isExcludedTotalStakedRegistered;
  mapping(address => bool) public isUserRegistered;

  mapping(address => Info) public tokenInfo;
  mapping(address => Info) public teamInfo;


  Info public lpInfo;
  uint public lpAmount;
  uint public totalReward;
  uint public totalStaked;

  address[] public tokens;
  address[] public team;
  address[] public totalStakedExcludedAccounts;
  address[] public users;

  bool public regularTransfersHasFee;
  uint public burnPercentage;
  bool public buyEnabled;
  bool private swapping;
  bool private claiming;


  event SwapAndLiquify(uint256 tokensSwapped, uint256 ethReceived, uint256 tokensIntoLiqudity);
  event ExcludeFromFees(address indexed account, bool isExcluded);
  event ExcludeTotalStaked(address indexed account, bool isExcluded);
  event Received(address sender, uint amount);

  address public zeroAddress = 0x0000000000000000000000000000000000000001;

  /**
  * @dev restore from old contract to new
  * @param _oldContract address of old contract
  */
  function restore(address payable _oldContract) external onlyOwner {
    OROS2Presenter oldPresenter = OROS2Presenter(_oldContract);
    lpAmount = oldPresenter.lpAmount();
    totalReward = oldPresenter.totalReward();
    totalStaked = oldPresenter.totalStaked();
 
    uint tokensLength = oldPresenter.getTokensLength();
    for (uint i; i < tokensLength; i++) {
      address tokenAddress = oldPresenter.tokens(i);
      rewardPool[tokenAddress] = oldPresenter.getRewardPoolByToken(tokenAddress);
    }
  }

  /** 
  * @dev restore users from the old contract, must execute initialize and restore function before executing this function
  * @param _oldContract old contract address
  * @param _startIndex start Index
  * @param _endIndex end Index
  */
  function restoreUserData(address payable _oldContract, uint  _startIndex, uint _endIndex) external onlyOwner {
    OROS2Presenter oldPresenter = OROS2Presenter(_oldContract);
    uint length = oldPresenter.getUsersLength();

    for (uint i = _startIndex; i < _endIndex && i < length; i++){
      address userAddress = oldPresenter.users(i);
      uint[] memory debts = oldPresenter.getUserDebt(userAddress);
      uint[] memory rewardExcluded = oldPresenter.getUserRewardExcluded(userAddress);

      for(uint j = 0; j < tokens.length; j++){
        address tokenAddress = tokens[j];
        userDebt[tokenAddress][userAddress] = debts[j];
        userRewardExcluded[tokenAddress][userAddress] = rewardExcluded[j];
      }
   
      users.push(userAddress);
      isUserRegistered[userAddress] = true;
    }
  }

  /**
  * @dev in case we need to change presenter, we should call this function
  * @param _newPresenter address of new presenter
  */
  function restoreFundsToNewPresenter(address _newPresenter) external onlyOwner {
    uint balance = IERC20(token).balanceOf(address(this));
    IERC20(token).transfer(_newPresenter, balance);
  }

  /**
  * @dev allow contract to receive ethers
  */
  receive() external payable {
    emit Received(msg.sender, msg.value);
  }

  constructor() {
    token = address(0);
  }

  /**
  * @dev take snapshot of total staked
  */
  function _snapshotTotalStaked() internal {
    IERC20 mainToken = IERC20(token);
    uint totalSupply = mainToken.totalSupply();
    uint totalExcluded;
    for (uint i = 0; i < totalStakedExcludedAccounts.length; i++) {
      if (isExcludedTotalStaked[totalStakedExcludedAccounts[i]])
        totalExcluded = totalExcluded + mainToken.balanceOf(totalStakedExcludedAccounts[i]);
    }
    totalStaked = totalSupply - totalExcluded;
  }

  /**
  * @dev get the eth balance on the contract
  * @return eth balance
  */
  function getEthBalance() public view returns (uint) {
    return address(this).balance;
  }

  /**
  * @dev get rewardPool by token
  * @param _tokenAddress address of token
  */

  function getRewardPoolByToken(address _tokenAddress) external view returns (uint) {
    return rewardPool[_tokenAddress];
  }
  /**
  * @dev get the token balance
  * @param _tokenAddress token address
  */
  function getTokenBalance(address _tokenAddress) public view returns (uint) {
    IERC20 erc20 = IERC20(_tokenAddress);
    return erc20.balanceOf(address(this));
  }

  /**
  * @dev get the tokens Length
  */
  function getTokensLength() external view returns (uint) {
    return tokens.length;
  }
  
  /**
  * @dev get the users Length
  */
  function getUsersLength() external view returns (uint) {
    return users.length;
  }

  /**
  * @dev get the team Length
  */
  function getTeamLength() external view returns (uint) {
    return team.length;
  }

  /**
  * @dev get the reward token list
  */
  function getRewardTokenList() external view returns (Info[] memory){
    uint length = tokens.length;
    Info[] memory allTokens = new Info[](length);
    for (uint i = 0; i < length; i++) {
      allTokens[i] = tokenInfo[tokens[i]];
    }
    return allTokens;
  }

  /**
  * @dev initialize the contract, only call by owner
  * @param _token address of the main token
  * @param _router address of router exchange (Pancakeswap)
  * @param _burnPercentage burn percentage
  * @param _regularTransfersHasFee enable or disable regular transfer fee
  * @param _lpInfo lp info
  * @param _tokens array of tokens to add
  * @param _team array of team to add
  * @param _excludedAccounts list of excluded accounts
  */
  function initialize(
    address _token,
    address _router,
    uint _burnPercentage,
    bool _regularTransfersHasFee,
    Info memory _lpInfo,
    Info[] memory _tokens,
    Info[] memory _team,
    address[] memory _excludedAccounts,
    bool _buyEnabled) onlyOwner public {
    ifNotMaintenance();
    buyEnabled = _buyEnabled;
    token = _token;
    router = _router;
    burnPercentage = _burnPercentage;
    regularTransfersHasFee = _regularTransfersHasFee;

    IPancakeRouter02 pancakRouter = IPancakeRouter02(router);
    address lpAddress = IPancakeFactory(pancakRouter.factory()).getPair(token, pancakRouter.WETH());
    if(lpAddress == address(0))
      lpAddress = IPancakeFactory(pancakRouter.factory()).createPair(token, pancakRouter.WETH());

    addOrUpdateLPInfo(
      lpAddress,
      _lpInfo.percentage,
      _lpInfo.isEnabled,
      _lpInfo.side
    );
    excludeFromTotalStaked(lpAddress, true);

    for (uint i; i < _tokens.length; i++) {
      Info memory info = _tokens[i];
      addOrUpdateRewardToken(
        info.addr,
        info.percentage,
        info.isEnabled,
        info.side
      );
    }

    for (uint i; i < _team.length; i++) {
      Info memory info = _team[i];
      addOrUpdateTeam(
        info.addr,
        info.percentage,
        info.isEnabled,
        info.side
      );
      excludeFromTotalStaked(info.addr, true);
    }

    for (uint i; i < _excludedAccounts.length; i++) {
      excludeFromFees(_excludedAccounts[i], true);
    }

    excludeFromTotalStaked(owner(), true);
    excludeFromTotalStaked(address(this), true);
    excludeFromTotalStaked(zeroAddress, true);
    //exclude addresses
    excludeFromFees(owner(), true);
  }

  /**
  * @dev Allow buy
  */
  function enableBuy() onlyOwner public {
    buyEnabled = true;
  }

  /**
  * @dev Disable buy
  */
  function disableBuy() onlyOwner public {
    buyEnabled = false;
  }

  /**
  * @dev set the main token
  * @param _token address of main token
  */
  function setToken(address _token) onlyOwner public {
    ifNotMaintenance();
    token = _token;
  }

  /**
  * @dev set exchange router
  * @param _router address of main token
  */
  function setRouter(address _router) onlyOwner public {
    ifNotMaintenance();
    router = _router;
  }

  /**
  * @dev set the zero Address
  * @param _zeroAddress address of zero
  */
  function setZeroAddress(address _zeroAddress) onlyOwner external {
    ifNotMaintenance();
    zeroAddress = _zeroAddress;
  }
  /**
  * @dev set the burn percentage
  * @param _burnPercentage burn percentage
  */
  function setBurnPercentage(uint _burnPercentage) onlyOwner external {
    ifNotMaintenance();
    burnPercentage = _burnPercentage;
  }

  /**
  * @dev set regular transfer has fee
  * @param _regularTransfersHasFee enable or disable regular transfer fee
  */
  function setregularTransfersHasFee(bool _regularTransfersHasFee) onlyOwner external {
    ifNotMaintenance();
    regularTransfersHasFee = _regularTransfersHasFee;
  }

  /**
  * @dev add or update liquidity provider token
  * @param _addr address of token
  * @param _percentage tax percentage of token
  * @param _isEnabled enable the token
  * @param _side 0 for buy, 1 for sell, 2 for both
  */
  function addOrUpdateLPInfo(address _addr, uint _percentage, bool _isEnabled, uint8 _side) onlyOwner public {
    ifNotMaintenance();
    lpInfo.addr = _addr;
    lpInfo.percentage = _percentage;
    lpInfo.isEnabled = _isEnabled;
    lpInfo.side = _side;
  }

  /**
  * @dev add or update buy back/reward token
  * @param _addr address of token
  * @param _percentage tax percentage of token
  * @param _isEnabled enable the token
  * @param _side 0 for buy, 1 for sell, 2 for both
  */
  function addOrUpdateRewardToken(address _addr, uint _percentage, bool _isEnabled, uint8 _side) onlyOwner public {
    ifNotMaintenance();
    Info storage info = tokenInfo[_addr];

    info.percentage = _percentage;
    info.isEnabled = _isEnabled;
    info.addr = _addr;
    info.side = _side;
    if (info.isRegistered == false) {
      info.isRegistered = true;
      tokens.push(_addr);
    }
  }

  /**
  * @dev add or update buy back/reward token
  * @param _addr address of token
  * @param _percentage tax percentage of token
  * @param _isEnabled enable the token
  * @param _side 0 for buy, 1 for sell, 2 for both
  */
  function addOrUpdateTeam(address _addr, uint _percentage, bool _isEnabled, uint8 _side) onlyOwner public {
    ifNotMaintenance();
    Info storage info = teamInfo[_addr];

    info.percentage = _percentage;
    info.isEnabled = _isEnabled;
    info.addr = _addr;
    info.side = _side;
    if (info.isRegistered == false) {
      info.isRegistered = true;
      team.push(_addr);
    }
  }

  /**
  * @dev remove and delist token
  * @param _tokenAddress address of token
  */
  function delistToken(address _tokenAddress) onlyOwner public {
    ifNotMaintenance();
    Info storage info = tokenInfo[_tokenAddress];
    info.isEnabled = false;
  }

  /**
  * @dev remove and delist team member
  * @param _teamMemberAddress address of team member
  */
  function delistTeamMember(address _teamMemberAddress) onlyOwner public {
    ifNotMaintenance();
    Info storage info = teamInfo[_teamMemberAddress];
    info.isEnabled = false;
  }

  /**
  * @dev this is the main function to distribute the tokens call from only main token
  * @param _from from address
  * @param _to to address
  * @param _amount amount of tokens
  */
  function receiveTokens(address _from, address _to, uint256 _amount) public override returns (bool) {
    return receiveTokensFrom(_from, _from, _to, _amount);
  }

  /**
  * @dev this is the main function to distribute the tokens call from only main token via external app
  * @param _trigger trigger address
  * @param _from from address
  * @param _to to address
  * @param _amount amount of tokens
  */
  function receiveTokensFrom(address _trigger, address _from, address _to, uint256 _amount) public override returns (bool) {
    ifNotMaintenance();
    require(msg.sender == token, "OROS2Presenter::Only trigger from token");
    require(!isWhale(_from, _to, _amount), "Error: No time for whales!");
    //add unregistered users
    _addUser(_from, _to);

    // Trigger from router
    bool isViaRouter = _trigger == router;
    // Trigger from lp pair
    bool isViaLP = _trigger == lpInfo.addr;
    // Check is to user = _to not router && not lp
    bool isToUser = (_to != lpInfo.addr && _to != router);
    // Check is from user = _from not router && not lp
    bool isFromUser = (_from != lpInfo.addr && _from != router);
    // In case remove LP
    bool isRemoveLP = (_from == lpInfo.addr && _to == router) || (_from == router && isToUser);
    // In case buy: LP transfer to user directly
    bool isBuy = isViaLP && _from == lpInfo.addr && isToUser;
    // In case sell (Same with add LP case): User send to LP via router (using transferFrom)
    bool isSell = isViaRouter && (isFromUser && _to == lpInfo.addr);
    // In case normal transfer
    bool isTransfer = !isBuy && !isSell && !isRemoveLP;
    // Exclude from fees
    bool isExcluded = isExcludedFromFees[_from] || isExcludedFromFees[_to];
    if (isExcluded || isRemoveLP) {
      IERC20(token).transfer(_to, _amount);
    } else if (isTransfer) {
      // Add tax if regularTransfersHasFee = true
      if (regularTransfersHasFee) {
        _taxCollection(_from, _to, _amount, isTransfer, false);
      } else {
        IERC20(token).transfer(_to, _amount);
      }
    } else if (isBuy) {
      if(buyEnabled) {
        // Add tax
        _taxCollection(_from, _to, _amount, false, isBuy);
      } else {
        return false;
      }
    } else if (isSell) {
      // Remove tax, but consider 2 cases here:
      // (1): normal sell via psc => transfer all remaining reward to team
      // (2): claim case -> this contract trigger sell internally
      bool isClaimCase = _from == address(this);
      if (isClaimCase) {
        IERC20(token).transfer(_to, _amount);
      } else {
        // Transfer unclaimed reward to team
        _transferUnclaimedRewardInSellCase(_from, _to, _amount);
        // Transfer token to router normally
        IERC20(token).transfer(_to, _amount);
      }
    }
    _snapshotTotalStaked();
    return true;

  }

  function getUserDebt(address _userAddress) external view returns (uint[] memory){
    uint length = tokens.length;
    uint[] memory debts = new uint[](length);

    for (uint i; i < length; i++) {
      debts[i] = userDebt[tokens[i]][_userAddress];
    }
    return debts;
  }

  function getUserRewardExcluded(address _userAddress) external view returns (uint[] memory){
    uint length = tokens.length;
    uint[] memory rewardsExcluded = new uint[](length);

    for (uint i; i < length; i++) {
      rewardsExcluded[i] = userRewardExcluded[tokens[i]][_userAddress];
    }
    return rewardsExcluded;
  }

  /**
  * @dev get pending reward for
  * @param _userAddress address of user
  */
  function pendingReward(address _userAddress) external view returns (uint[] memory) {
    IERC20 mainToken = IERC20(token);
    uint userBalance = mainToken.balanceOf(_userAddress);
    uint length = tokens.length;
    uint[] memory rewards = new uint[](length);

    if (userBalance > 0 && totalStaked > 0) {
      for (uint i; i < length; i++) {
        address tokenAddress = tokens[i];
        uint debt = userDebt[tokenAddress][_userAddress];
        uint rewardExcluded = userRewardExcluded[tokenAddress][_userAddress];
        (, uint remainPool) = rewardPool[tokenAddress].trySub(rewardExcluded);
        uint share = (userBalance * 1e6) / totalStaked;
        uint userReward = ((share * remainPool) / 1e6);
        if (userReward > debt) {
          rewards[i] = userReward - debt;
        }
      }
    }
    return rewards;
  }

  /**
  * @dev anyone can claim all buy Back Amount
  */
  function claimAllReward() external {
    ifNotMaintenance();
    claiming = true;
    //claim all buy back Amount
    IERC20 mainToken = IERC20(token);
    uint userBalance = mainToken.balanceOf(msg.sender);
    uint remainingBalance = mainToken.balanceOf(address(this));
    if (userBalance > 0 && totalStaked > 0) {
      for (uint i; i < tokens.length; i++) {
        address tokenAddress = tokens[i];
        uint debt = userDebt[tokenAddress][msg.sender];
        uint rewardExcluded = userRewardExcluded[tokenAddress][msg.sender];
        (, uint remainPool) = rewardPool[tokenAddress].trySub(rewardExcluded);
        uint share = (userBalance * 1e6) / totalStaked;
        uint shareReward = ((share * remainPool) / 1e6);
        if (shareReward > debt) {
          uint userReward = shareReward - debt;
          if (userReward > remainingBalance) {
            userReward = remainingBalance;
          }
          if (userReward > 0) {
            _swapTokensTo(token, tokenAddress, userReward, msg.sender);
            remainingBalance = remainingBalance - userReward;
            userDebt[tokenAddress][msg.sender] += shareReward;
            if (totalReward >= userReward) {
              totalReward = totalReward - userReward;
            }
          }
        }
      }
    }
    //add liquidity
    if (lpAmount > remainingBalance) {
      lpAmount = remainingBalance;
    }
    if (lpAmount > 0) {
      _swapAndLiquify(token, lpAmount);
      lpAmount = 0;
    }

    claiming = false;
  }

  /**
  * @dev add buy back token amount to contract
  * @param _tokenAddress address of token
  * @param _amount amount of tokens
  */
  function addTokenBalance(address _tokenAddress, uint256 _amount) external {
    IERC20 erc20 = IERC20(_tokenAddress);
    erc20.transferFrom(msg.sender, address(this), _amount);
  }

  /**
  * @dev withdraw eth balance
  */
  function withdrawEthBalance() external onlyOwner {
    payable(owner()).transfer(getEthBalance());
  }

  /**
  * @dev withdraw token balance
  * @param _tokenAddress token address
  */
  function withdrawTokenBalance(address _tokenAddress) external onlyOwner {
    IERC20 erc20 = IERC20(_tokenAddress);
    erc20.transfer(
      owner(),
      getTokenBalance(_tokenAddress)
    );
  }

  /**
  * @dev function to exclude a account from tax
  * @param _account account to exclude
  * @param _excluded state of excluded account true or false
  */
  function excludeFromFees(address _account, bool _excluded) public onlyOwner {
    require(isExcludedFromFees[_account] != _excluded, "OROS2Presenter: Account is already the value of 'excluded'");
    isExcludedFromFees[_account] = _excluded;

    emit ExcludeFromFees(_account, _excluded);
  }

  /**
  * @dev function to exclude a account from tax
  * @param _account account to exclude
  * @param _excluded state of excluded account true or false
  */
  function excludeFromTotalStaked(address _account, bool _excluded) public onlyOwner {
    require(isExcludedTotalStaked[_account] != _excluded, "OROS2Presenter: Account is already the value of 'excluded'");
    isExcludedTotalStaked[_account] = _excluded;
    //ensure account will be added only one time
    if (isExcludedTotalStakedRegistered[_account] == false) {
      totalStakedExcludedAccounts.push(_account);
      isExcludedTotalStakedRegistered[_account] = true;
    }

    emit ExcludeTotalStaked(_account, _excluded);
  }

  /**
  * @dev swap tokens to this address
  * @param _tokenAddressFrom address of from token
  * @param _tokenAddressTo address of to token
  * @param _amount amount of tokens
  */
  function _swapTokens(address _tokenAddressFrom, address _tokenAddressTo, uint256 _amount) internal {
    _swapTokensTo(_tokenAddressFrom, _tokenAddressTo, _amount, address(this));
  }

  /**
  * @dev swap tokens
  * @param _tokenAddressFrom address of from token
  * @param _tokenAddressTo address of to token
  * @param _amount amount of tokens
  */
  function _swapTokensTo(address _tokenAddressFrom, address _tokenAddressTo, uint256 _amount, address _to) internal {
    address[] memory path = new address[](3);
    path[0] = _tokenAddressFrom;
    path[1] = IPancakeRouter02(router).WETH();
    path[2] = _tokenAddressTo;

    IERC20(_tokenAddressFrom).approve(router, _amount);

    // make the swap
    IPancakeRouter02(router).swapExactTokensForTokensSupportingFeeOnTransferTokens(
      _amount,
      0,
      path,
      _to,
      block.timestamp
    );
  }

  /**
  * @dev swap tokens and add liquidity
  * @param _tokenAddress address of token
  * @param _amount amount of tokens
  */
  function _swapAndLiquify(address _tokenAddress, uint256 _amount) internal {
    // split the contract balance into halves
    uint256 half = _amount / 2;
    uint256 otherHalf = _amount - half;

    // capture the contract's current ETH balance.
    // this is so that we can capture exactly the amount of ETH that the
    // swap creates, and not make the liquidity event include any ETH that
    // has been manually sent to the contract
    uint256 initialBalance = address(this).balance;

    // swap tokens for ETH
    _swapTokensForEth(half);
    // <- this breaks the ETH -> HATE swap when swap+liquify is triggered

    // how much ETH did we just swap into?
    uint256 newBalance = address(this).balance - initialBalance;

    // add liquidity to pancakeswap
    _addLiquidity(_tokenAddress, otherHalf, newBalance);

    emit SwapAndLiquify(half, newBalance, otherHalf);
  }

  /**
  * @dev add liquidity in pair
  * @param _tokenAddress address of token
  * @param _tokenAmount amount of tokens
  * @param _ethAmount amount of eth tokens
  */
  function _addLiquidity(address _tokenAddress, uint256 _tokenAmount, uint256 _ethAmount) internal {
    // approve token transfer to cover all possible scenarios
    IERC20(_tokenAddress).approve(router, _tokenAmount);

    // add the liquidity
    IPancakeRouter02(router).addLiquidityETH{value : _ethAmount}(
      address(token),
      _tokenAmount,
      0, // slippage is unavoidable
      0, // slippage is unavoidable
      address(0),
      block.timestamp
    );
  }

  /**
  * @dev swap tokens and get ETH
  * @param _amount amount of tokens
  */
  function _swapTokensForEth(uint256 _amount) internal {
    // generate the uniswap pair path of token -> weth
    address[] memory path = new address[](2);
    path[0] = token;
    path[1] = IPancakeRouter02(router).WETH();

    IERC20(token).approve(router, _amount);

    // make the swap
    IPancakeRouter02(router).swapExactTokensForETHSupportingFeeOnTransferTokens(
      _amount,
      0, // accept any amount of ETH
      path,
      address(this),
      block.timestamp
    );
  }

  /**
  * @dev internal function to transfer unclaimed reward to team
  * @param _from from address
  * @param _amount amount of tokens
  */
  function _transferUnclaimedRewardInSellCase(address _from, address, uint _amount) internal {
    // Find total tax for team
    uint teamTotalPercentage;
    for (uint i; i < team.length; i++) {
      Info memory info = teamInfo[team[i]];
      teamTotalPercentage = teamTotalPercentage + info.percentage;
    }
    // Transfer remaining reward to team
    uint contractBalance = IERC20(token).balanceOf(address(this));
    // In sale case, balance of user will update first
    uint userRemainBalance = IERC20(token).balanceOf(_from);
    uint userBalance = userRemainBalance + _amount;
    uint maxShare = (userBalance * 1e6) / totalStaked;
    uint sellPercent = (_amount * 1e6) / userBalance;
    address from = _from;
    uint teamReward;
    for (uint i; i < tokens.length; i++) {
      Info memory info = tokenInfo[tokens[i]];
      uint rewardExcluded = userRewardExcluded[info.addr][from];
      (, uint remainPool) = rewardPool[info.addr].trySub(rewardExcluded);
      uint maxShareReward = ((maxShare * remainPool) / 1e6);
      uint shareReward = ((sellPercent * maxShareReward) / 1e6);
      uint sellReduceAmount = ((sellPercent * rewardExcluded) / 1e6);
      if (sellReduceAmount > rewardExcluded) {
        sellReduceAmount = rewardExcluded;
      }
      if (sellReduceAmount > 0) {
        (,uint ur) = rewardExcluded.trySub(sellReduceAmount);
        userRewardExcluded[info.addr][from] = ur;
        (,uint r) = rewardPool[info.addr].trySub(sellReduceAmount);
        rewardPool[info.addr] = r;
      }
      uint userReward;
      uint debt = userDebt[info.addr][from];
      if (maxShareReward > debt) {
        (bool f1,) = shareReward.trySub(maxShareReward - debt);
        if (f1) {
          userReward = maxShareReward - debt;
        } else {
          userReward = shareReward;
        }
      }
      if (userReward > 0) {
        teamReward += userReward;
      }
    }
    // Safe transfer
    if (teamReward > 0 && teamReward <= contractBalance) {
      uint _teamTotalPercentage = teamTotalPercentage;
      uint remainDistribution = teamReward;
      for (uint j; j < team.length; j++) {
        Info memory tInfo = teamInfo[team[j]];
        if (tInfo.isEnabled) {
          uint tokenToTransfer = (teamReward * tInfo.percentage) / _teamTotalPercentage;
          if (tokenToTransfer > remainDistribution) {
            tokenToTransfer = remainDistribution;
          }
          if (tokenToTransfer > 0) {
            IERC20(token).transfer(team[j], tokenToTransfer);
            remainDistribution -= tokenToTransfer;
          }
        }
      }
    }
  }

  /**
  * @dev internal function to collect tax
  * @param _to to address
  * @param _amount amount of tokens
  * @param _isBuy true if buy order
  */
  function _taxCollection(address, address _to, uint256 _amount, bool _isTransfer, bool _isBuy) internal {
    swapping = true;
    uint totalTax;

    //Safe transfer checking
    uint remainingBalance = IERC20(token).balanceOf(address(this));
    //direct transfer to team
    uint teamTaxAccumulated;
    uint teamTotalPercentage;
    for (uint i; i < team.length; i++) {
      Info memory info = teamInfo[team[i]];
      if (info.isEnabled == true && (_isTransfer || _checkSide(_isBuy, _isTransfer, info.side))) {
        uint teamTax = (_amount * info.percentage) / RATE_NOMINATOR;
        if (teamTax > 0 && remainingBalance >= teamTax) {
          IERC20(token).transfer(team[i], teamTax);
          (,uint _r1) = remainingBalance.trySub(teamTax);
          remainingBalance = _r1;
        }
        teamTaxAccumulated = teamTaxAccumulated + teamTax;
        teamTotalPercentage = teamTotalPercentage + info.percentage;
      }
    }
    //add lp in main token
    if (lpInfo.isEnabled == true && (_isTransfer || _checkSide(_isBuy, _isTransfer, lpInfo.side))) {
      uint lpTax = (_amount * lpInfo.percentage) / RATE_NOMINATOR;
      lpAmount = lpAmount + lpTax;
      totalTax = totalTax + lpTax;
    }
    //transferring tokens to buy back tokens
    for (uint i; i < tokens.length; i++) {
      Info memory info = tokenInfo[tokens[i]];
      if (info.isEnabled == true && (_isTransfer || _checkSide(_isBuy, _isTransfer, info.side))) {
        //store dividend
        uint buyBackTax = (_amount * info.percentage) / RATE_NOMINATOR;
        //track dividend
        rewardPool[info.addr] += buyBackTax;
        userRewardExcluded[info.addr][_to] += buyBackTax;
        totalTax = totalTax + buyBackTax;
        totalReward = totalReward + buyBackTax;
      }
    }
    uint burnTax = (_amount * burnPercentage) / RATE_NOMINATOR;
    if (burnTax > 0 && remainingBalance >= burnTax) {
      IERC20(token).transfer(zeroAddress, burnTax);
      (,uint _r1) = remainingBalance.trySub(burnTax);
      remainingBalance = _r1;
    }
    //send total tax collected to contract
    if (totalTax > 0 && remainingBalance >= totalTax) {
      IERC20(token).transfer(address(this), totalTax);
      (,uint _r1) = remainingBalance.trySub(totalTax);
      remainingBalance = _r1;
    }
    //send remaining amount
    uint allTax = totalTax + teamTaxAccumulated + burnTax;
    (,uint _t1) = _amount.trySub(allTax);
    if (_t1 > 0 && remainingBalance >= _t1) {
      IERC20(token).transfer(_to, _t1);
    }

    swapping = false;
  }

  /**
  * @dev internal function to check side configuration.
  * @param _isBuy see if buy is true -> enable buy tax
  * @param _isTransfer see if _isTransfer is true -> enable buy tax
  * @param _side see if side = 0 -> buy tax, side = 1 -> transfer, side = 2 -> both
  */
  function _checkSide(bool _isBuy, bool _isTransfer, uint8 _side) internal pure returns (bool) {
    if (
      (_isBuy == true && _side == 0) ||
      (_isTransfer == true && _side == 1) ||
      ((_isBuy == true || _isTransfer == true) && _side == 2)
    ) return true;
    return false;
  }

  /** 
  * @dev add unregistered users/stakers
  * @param _from from address
  * @param _to to address
  */
  function _addUser(address _from, address _to) internal {
    if(isUserRegistered[_from] == false && isExcludedTotalStaked[_from] == false) {
      users.push(_from);
      isUserRegistered[_from] = true;
    }

    if(isUserRegistered[_to] == false && isExcludedTotalStaked[_to] == false) {
      users.push(_to);
      isUserRegistered[_to] = true;
    }
  }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

interface IPancakeFactory {
  event PairCreated(address indexed token0, address indexed token1, address pair, uint);

  function feeTo() external view returns (address);

  function feeToSetter() external view returns (address);

  function getPair(address tokenA, address tokenB) external view returns (address pair);

  function allPairs(uint) external view returns (address pair);

  function allPairsLength() external view returns (uint);

  function createPair(address tokenA, address tokenB) external returns (address pair);

  function setFeeTo(address) external;

  function setFeeToSetter(address) external;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

interface IPancakeRouter01 {
  function factory() external pure returns (address);

  function WETH() external pure returns (address);

  function addLiquidity(
    address tokenA,
    address tokenB,
    uint amountADesired,
    uint amountBDesired,
    uint amountAMin,
    uint amountBMin,
    address to,
    uint deadline
  ) external returns (uint amountA, uint amountB, uint liquidity);

  function addLiquidityETH(
    address token,
    uint amountTokenDesired,
    uint amountTokenMin,
    uint amountETHMin,
    address to,
    uint deadline
  ) external payable returns (uint amountToken, uint amountETH, uint liquidity);

  function removeLiquidity(
    address tokenA,
    address tokenB,
    uint liquidity,
    uint amountAMin,
    uint amountBMin,
    address to,
    uint deadline
  ) external returns (uint amountA, uint amountB);

  function removeLiquidityETH(
    address token,
    uint liquidity,
    uint amountTokenMin,
    uint amountETHMin,
    address to,
    uint deadline
  ) external returns (uint amountToken, uint amountETH);

  function removeLiquidityWithPermit(
    address tokenA,
    address tokenB,
    uint liquidity,
    uint amountAMin,
    uint amountBMin,
    address to,
    uint deadline,
    bool approveMax, uint8 v, bytes32 r, bytes32 s
  ) external returns (uint amountA, uint amountB);

  function removeLiquidityETHWithPermit(
    address token,
    uint liquidity,
    uint amountTokenMin,
    uint amountETHMin,
    address to,
    uint deadline,
    bool approveMax, uint8 v, bytes32 r, bytes32 s
  ) external returns (uint amountToken, uint amountETH);

  function swapExactTokensForTokens(
    uint amountIn,
    uint amountOutMin,
    address[] calldata path,
    address to,
    uint deadline
  ) external returns (uint[] memory amounts);

  function swapTokensForExactTokens(
    uint amountOut,
    uint amountInMax,
    address[] calldata path,
    address to,
    uint deadline
  ) external returns (uint[] memory amounts);

  function swapExactETHForTokens(uint amountOutMin, address[] calldata path, address to, uint deadline)
  external
  payable
  returns (uint[] memory amounts);

  function swapTokensForExactETH(uint amountOut, uint amountInMax, address[] calldata path, address to, uint deadline)
  external
  returns (uint[] memory amounts);

  function swapExactTokensForETH(uint amountIn, uint amountOutMin, address[] calldata path, address to, uint deadline)
  external
  returns (uint[] memory amounts);

  function swapETHForExactTokens(uint amountOut, address[] calldata path, address to, uint deadline)
  external
  payable
  returns (uint[] memory amounts);

  function quote(uint amountA, uint reserveA, uint reserveB) external pure returns (uint amountB);

  function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) external pure returns (uint amountOut);

  function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) external pure returns (uint amountIn);

  function getAmountsOut(uint amountIn, address[] calldata path) external view returns (uint[] memory amounts);

  function getAmountsIn(uint amountOut, address[] calldata path) external view returns (uint[] memory amounts);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import './IPancakeRouter01.sol';

interface IPancakeRouter02 is IPancakeRouter01 {
  function removeLiquidityETHSupportingFeeOnTransferTokens(
    address token,
    uint liquidity,
    uint amountTokenMin,
    uint amountETHMin,
    address to,
    uint deadline
  ) external returns (uint amountETH);

  function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
    address token,
    uint liquidity,
    uint amountTokenMin,
    uint amountETHMin,
    address to,
    uint deadline,
    bool approveMax, uint8 v, bytes32 r, bytes32 s
  ) external returns (uint amountETH);

  function swapExactTokensForTokensSupportingFeeOnTransferTokens(
    uint amountIn,
    uint amountOutMin,
    address[] calldata path,
    address to,
    uint deadline
  ) external;

  function swapExactETHForTokensSupportingFeeOnTransferTokens(
    uint amountOutMin,
    address[] calldata path,
    address to,
    uint deadline
  ) external payable;

  function swapExactTokensForETHSupportingFeeOnTransferTokens(
    uint amountIn,
    uint amountOutMin,
    address[] calldata path,
    address to,
    uint deadline
  ) external;
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

interface ITokenPresenter {
  function receiveTokens(address _from, address _to, uint256 _amount) external returns (bool);
  function receiveTokensFrom(address trigger, address _from, address _to, uint256 _amount) external returns (bool);
}

// SPDX-License-Identifier: MIT
pragma solidity 0.8.3;

import "@openzeppelin/contracts/access/Ownable.sol";

contract AntiWhale is Ownable {
    uint256 public startDate;
    uint256 public endDate;
    uint256 public limitWhale;
    bool public antiWhaleActivated;

    /** 
    * @dev activte antiwhale
    */
    function activateAntiWhale() public onlyOwner {
        require(antiWhaleActivated == false);
        antiWhaleActivated = true;
    }

    /** 
    * @dev deactivte antiwhale
    */
    function deActivateAntiWhale() public onlyOwner {
        require(antiWhaleActivated == true);
        antiWhaleActivated = false;
    }

    /** 
    * @dev set antiwhale settings
    * @param _startDate start date of the antiwhale
    * @param _endDate end date of the antiwhale
    * @param _limitWhale limit amount of antiwhale
    */
    function setAntiWhale(uint256 _startDate, uint256 _endDate, uint256 _limitWhale) public onlyOwner {
        startDate = _startDate;
        endDate = _endDate;
        limitWhale = _limitWhale;
        antiWhaleActivated = true;
    }

    /** 
    * @dev check if antiwhale is enable and amount should be less than to whale in specify duration
    * @param _from from address
    * @param _to to address
    * @param _amount amount to check antiwhale
    */
    function isWhale(address _from, address _to, uint256 _amount) public view returns (bool) {
        if (
            _from == owner() ||
            _to == owner() ||
            antiWhaleActivated == false ||
            _amount <= limitWhale
        ) return false;

        if (block.timestamp >= startDate && block.timestamp <= endDate)
            return true;

        return false;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity ^0.8.3;

import "@openzeppelin/contracts/access/Ownable.sol";

contract Maintainable is Ownable {

  bool public isMaintenance = false;
  bool public isOutdated = false;

  // Check if contract is not in maintenance
  function ifNotMaintenance() internal view {
    require(!isMaintenance, "Maintenance");
    require(!isOutdated, "Outdated");
  }

  // Check if contract on maintenance for restore
  function ifMaintenance() internal view {
    require(isMaintenance, "!Maintenance");
  }

  // Enable maintenance
  function enableMaintenance(bool status) onlyOwner public {
    isMaintenance = status;
  }

  // Enable outdated
  function enableOutdated(bool status) onlyOwner public {
    isOutdated = status;
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
    constructor () {
        address msgSender = _msgSender();
        _owner = msgSender;
        emit OwnershipTransferred(address(0), msgSender);
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
        emit OwnershipTransferred(_owner, address(0));
        _owner = address(0);
    }

    /**
     * @dev Transfers ownership of the contract to a new account (`newOwner`).
     * Can only be called by the current owner.
     */
    function transferOwnership(address newOwner) public virtual onlyOwner {
        require(newOwner != address(0), "Ownable: new owner is the zero address");
        emit OwnershipTransferred(_owner, newOwner);
        _owner = newOwner;
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
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

// CAUTION
// This version of SafeMath should only be used with Solidity 0.8 or later,
// because it relies on the compiler's built in overflow checks.

/**
 * @dev Wrappers over Solidity's arithmetic operations.
 *
 * NOTE: `SafeMath` is no longer needed starting with Solidity 0.8. The compiler
 * now has built in overflow checking.
 */
library SafeMath {
    /**
     * @dev Returns the addition of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryAdd(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            uint256 c = a + b;
            if (c < a) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the substraction of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function trySub(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b > a) return (false, 0);
            return (true, a - b);
        }
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, with an overflow flag.
     *
     * _Available since v3.4._
     */
    function tryMul(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
            // benefit is lost if 'b' is also tested.
            // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
            if (a == 0) return (true, 0);
            uint256 c = a * b;
            if (c / a != b) return (false, 0);
            return (true, c);
        }
    }

    /**
     * @dev Returns the division of two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryDiv(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a / b);
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers, with a division by zero flag.
     *
     * _Available since v3.4._
     */
    function tryMod(uint256 a, uint256 b) internal pure returns (bool, uint256) {
        unchecked {
            if (b == 0) return (false, 0);
            return (true, a % b);
        }
    }

    /**
     * @dev Returns the addition of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `+` operator.
     *
     * Requirements:
     *
     * - Addition cannot overflow.
     */
    function add(uint256 a, uint256 b) internal pure returns (uint256) {
        return a + b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return a - b;
    }

    /**
     * @dev Returns the multiplication of two unsigned integers, reverting on
     * overflow.
     *
     * Counterpart to Solidity's `*` operator.
     *
     * Requirements:
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        return a * b;
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `/` operator.
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return a / b;
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting when dividing by zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return a % b;
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {trySub}.
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
     * division by zero. The result is rounded towards zero.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Counterpart to Solidity's `/` operator. Note: this function uses a
     * `revert` opcode (which leaves remaining gas untouched) while Solidity
     * uses an invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a / b;
        }
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * reverting with custom message when dividing by zero.
     *
     * CAUTION: This function is deprecated because it requires allocating memory for the error
     * message unnecessarily. For custom revert reasons use {tryMod}.
     *
     * Counterpart to Solidity's `%` operator. This function uses a `revert`
     * opcode (which leaves remaining gas untouched) while Solidity uses an
     * invalid opcode to revert (consuming all remaining gas).
     *
     * Requirements:
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
}

{
  "remappings": [],
  "optimizer": {
    "enabled": true,
    "runs": 200
  },
  "evmVersion": "byzantium",
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