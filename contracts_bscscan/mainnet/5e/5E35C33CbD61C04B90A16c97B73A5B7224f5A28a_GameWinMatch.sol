// SPDX-License-Identifier: MIT
pragma solidity ^0.6.12;

import "./interfaces/IERC20.sol";
import "./interfaces/IWETH.sol";
import "./interfaces/IUniswap.sol";
import "./lib/ReentrancyGuard.sol";
import "./lib/Ownable.sol";
import "./lib/SafeMath.sol";
import "./lib/Math.sol";
import "./lib/Address.sol";
import "./lib/SafeERC20.sol";
import "./lib/ERC20.sol";

contract GameWinFarming is ReentrancyGuard, Ownable {
    using SafeMath for uint256;
    using Address for address;
    using SafeERC20 for IERC20;

    event Staked(address indexed from, uint256 amountETH, uint256 amountLP);
    event Withdrawn(address indexed to, uint256 amountETH, uint256 amountLP);
    event Claimed(address indexed to, uint256 amount);
    event Halving(uint256 amount);
    event Received(address indexed from, uint256 amount);

    ERC20 public gameToken;
    IUniswapV2Factory public factory;
    IUniswapV2Router02 public router;
    address public weth;
    address public pairAddress;

    struct UserInfo {
        // Staked LP token balance
        uint256 balance;
        uint256 peakBalance;
        uint256 withdrawTimestamp;
        uint256 reward;
        uint256 rewardPerTokenPaid;
    }
    mapping(address => UserInfo) public userInfos;

    // Staked LP token total supply
    uint256 private _totalSupply = 0;

    uint256 public lastUpdateTimestamp = 0;

    uint256 rewardPerDay = 10 * 1e18;
    uint256 secondsPerDay = 1 days;

    uint256 public rewardRate = 0;
    uint256 public rewardPerTokenStored = 0;

    // Farming will be open on this timestamp
    uint256 public startTimestamp = 1625097600; // Thursday, July 1, 2021 12:00:00 AM
    bool public farmingStarted = false;

    // Max 25% / day LP withdraw
    uint256 public withdrawLimit = 25;
    uint256 public withdrawCycle = 24 hours;

    // Burn address
    address constant BURN_ADDRESS = 0x000000000000000000000000000000000000dEaD;
    uint256 public burnFee = 300; // BurnFee Percent * 100

    constructor(address _gameToken) public {
        gameToken = ERC20(address(_gameToken));

        router = IUniswapV2Router02(0x10ED43C718714eb63d5aA57B78B54704E256024E); // PancakeSwap Router V2
        factory = IUniswapV2Factory(router.factory());
        weth = router.WETH();
        pairAddress = factory.getPair(address(gameToken), weth);

        rewardRate = rewardPerDay.div(secondsPerDay);
    }

    receive() external payable {
        emit Received(msg.sender, msg.value);
    }

    function stakeLp(uint256 amount) external nonReentrant {
        activateFarming();
        updateReward(msg.sender);

        require(amount > 0, "Cannot stake 0");
        require(
            !address(msg.sender).isContract(),
            "Please use your individual account"
        );

        require(
            IERC20(pairAddress).balanceOf(msg.sender) >= amount,
            "Insufficient Balance"
        );

        // Transfer LP to this contract
        IERC20(pairAddress).safeTransferFrom(msg.sender, address(this), amount);
        // Add LP token to total supply
        _totalSupply = _totalSupply.add(amount);

        // Add to balance
        userInfos[msg.sender].balance = userInfos[msg.sender].balance.add(
            amount
        );
        // Set peak balance
        if (userInfos[msg.sender].balance > userInfos[msg.sender].peakBalance) {
            userInfos[msg.sender].peakBalance = userInfos[msg.sender].balance;
        }

        // Set stake timestamp as withdraw timestamp
        // to prevent withdraw immediately after first staking
        if (userInfos[msg.sender].withdrawTimestamp == 0) {
            userInfos[msg.sender].withdrawTimestamp = block.timestamp;
        }

        emit Staked(msg.sender, amount, amount);
    }

    function stakeEth() external payable nonReentrant {
        activateFarming();
        updateReward(msg.sender);

        require(msg.value > 0, "Cannot stake 0");
        require(
            !address(msg.sender).isContract(),
            "Please use your individual account"
        );

        // 50% used to buy START
        address[] memory swapPath = new address[](2);
        swapPath[0] = address(weth);
        swapPath[1] = address(gameToken);

        gameToken.approve(address(router), 0);
        gameToken.approve(address(router), msg.value.div(2));
        uint256[] memory amounts = router.swapExactETHForTokens{
            value: msg.value.div(2)
        }(uint256(0), swapPath, address(this), block.timestamp + 1 days);

        uint256 boughtGame = amounts[amounts.length - 1];

        // Add liquidity
        uint256 amountETHDesired = msg.value.sub(msg.value.div(2));
        IERC20(gameToken).approve(address(router), boughtGame);
        (, , uint256 liquidity) = router.addLiquidityETH{
            value: amountETHDesired
        }(
            address(gameToken),
            boughtGame,
            1,
            1,
            address(this),
            block.timestamp + 1 days
        );

        // Add LP token to total supply
        _totalSupply = _totalSupply.add(liquidity);

        // Add to balance
        userInfos[msg.sender].balance = userInfos[msg.sender].balance.add(
            liquidity
        );
        // Set peak balance
        if (userInfos[msg.sender].balance > userInfos[msg.sender].peakBalance) {
            userInfos[msg.sender].peakBalance = userInfos[msg.sender].balance;
        }

        // Set stake timestamp as withdraw timestamp
        // to prevent withdraw immediately after first staking
        if (userInfos[msg.sender].withdrawTimestamp == 0) {
            userInfos[msg.sender].withdrawTimestamp = block.timestamp;
        }

        emit Staked(msg.sender, msg.value, liquidity);
    }

    function withdraw() external nonReentrant {
        activateFarming();
        updateReward(msg.sender);

        require(
            userInfos[msg.sender].withdrawTimestamp + withdrawCycle <=
                block.timestamp,
            "You must wait more time since your last withdraw or stake"
        );
        require(userInfos[msg.sender].balance > 0, "Cannot withdraw 0");

        // Limit withdraw LP token
        uint256 amount = userInfos[msg.sender]
            .peakBalance
            .mul(withdrawLimit)
            .div(100);

        if (userInfos[msg.sender].balance < amount) {
            amount = userInfos[msg.sender].balance;
        }

        // Reduce total supply
        _totalSupply = _totalSupply.sub(amount);
        // Reduce balance
        userInfos[msg.sender].balance = userInfos[msg.sender].balance.sub(
            amount
        );
        if (userInfos[msg.sender].balance == 0) {
            userInfos[msg.sender].peakBalance = 0;
        }
        // Set timestamp
        userInfos[msg.sender].withdrawTimestamp = block.timestamp;

        // Remove liquidity in uniswap
        IERC20(pairAddress).approve(address(router), amount);
        (uint256 tokenAmount, uint256 bnbAmount) = router.removeLiquidity(
            address(gameToken),
            weth,
            amount,
            0,
            0,
            address(this),
            block.timestamp + 1 days
        );

        // Burn 3% START, send balance to sender
        uint256 burnAmount = tokenAmount.mul(burnFee).div(10000);
        if (burnAmount > 0) {
            tokenAmount = tokenAmount.sub(burnAmount);
            gameToken.transfer(address(BURN_ADDRESS), burnAmount);
        }
        gameToken.transfer(msg.sender, tokenAmount);

        // Withdraw BNB and send to sender
        IWETH(weth).withdraw(bnbAmount);
        msg.sender.transfer(bnbAmount);

        emit Withdrawn(msg.sender, bnbAmount, amount);
    }

    function claim() external nonReentrant {
        activateFarming();
        updateReward(msg.sender);

        uint256 reward = userInfos[msg.sender].reward;
        require(reward > 0, "There is no reward to claim");

        if (reward > 0) {
            // Reduce first
            userInfos[msg.sender].reward = 0;
            // Apply fee
            uint256 fee = reward.mul(getClaimFee()).div(10000);
            reward = reward.sub(fee);

            // Send reward
            gameToken.transfer(msg.sender, reward);
            if (fee > 0) {
                gameToken.transfer(BURN_ADDRESS, fee);
            }

            emit Claimed(msg.sender, reward);
        }
    }

    function withdrawGame() external onlyOwner {
        gameToken.transfer(owner, gameToken.balanceOf(address(this)));
    }

    function totalSupply() external view returns (uint256) {
        return _totalSupply;
    }

    function balanceOf(address account) external view returns (uint256) {
        return userInfos[account].balance;
    }

    function burnedTokenAmount() public view returns (uint256) {
        return gameToken.balanceOf(BURN_ADDRESS);
    }

    function rewardPerToken() public view returns (uint256) {
        if (_totalSupply == 0) {
            return rewardPerTokenStored;
        }

        return
            rewardPerTokenStored.add(
                block
                    .timestamp
                    .sub(lastUpdateTimestamp)
                    .mul(rewardRate)
                    .mul(1e18)
                    .div(_totalSupply)
            );
    }

    function rewardEarned(address account) public view returns (uint256) {
        return
            userInfos[account]
                .balance
                .mul(
                    rewardPerToken().sub(userInfos[account].rewardPerTokenPaid)
                )
                .div(1e18)
                .add(userInfos[account].reward);
    }

    // Token price in eth
    function tokenPrice() public view returns (uint256) {
        uint256 bnbAmount = IERC20(weth).balanceOf(pairAddress);
        uint256 tokenAmount = IERC20(gameToken).balanceOf(pairAddress);
        return bnbAmount.mul(1e18).div(tokenAmount);
    }

    function getClaimFee() public view returns (uint256) {
        if (block.timestamp < startTimestamp + 7 days) {
            return 2500;
        } else if (block.timestamp < startTimestamp + 14 days) {
            return 2000;
        } else if (block.timestamp < startTimestamp + 30 days) {
            return 1000;
        } else if (block.timestamp < startTimestamp + 45 days) {
            return 500;
        } else {
            return 50;
        }
    }

    function updateReward(address account) internal {
        rewardPerTokenStored = rewardPerToken();
        lastUpdateTimestamp = block.timestamp;
        if (account != address(0)) {
            userInfos[account].reward = rewardEarned(account);
            userInfos[account].rewardPerTokenPaid = rewardPerTokenStored;
        }
    }

    // Check if farming is started
    function activateFarming() internal {
        require(
            startTimestamp <= block.timestamp,
            "Please wait until farming started"
        );
        if (!farmingStarted) {
            farmingStarted = true;
            lastUpdateTimestamp = block.timestamp;
        }
    }

    function setFarmingStartTimestamp(
        uint256 _farmingTimestamp,
        bool _farmingStarted
    ) external onlyOwner {
        startTimestamp = _farmingTimestamp;
        farmingStarted = _farmingStarted;
    }

    function setBurnFee(uint256 _burnFee) external onlyOwner {
        burnFee = _burnFee;
    }

    function setWithdrawInfo(uint256 _withdrawLimit, uint256 _withdrawCycle)
        external
        onlyOwner
    {
        withdrawLimit = _withdrawLimit;
        withdrawCycle = _withdrawCycle;
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;

import "./lib/SafeMath.sol";
import "./interfaces/IERC20.sol";
import "./interfaces/IUniswap.sol";
import "./GameWinMatchLibrary.sol";

contract GameWinMatch {
    using SafeMath for uint256;

    address payable public factoryAddress; // address that creates the match contracts
    address payable public devAddress; // address where dev fees will be transferred to
    GameWinMatchLibrary public gameLibrary;

    IERC20 public fundingToken; // raising token (BNB, USDT, USDC or ...)
    IERC20 public gameToken; // system token

    address payable public matchCreatorAddress; // address where percentage of invested wei will be transferred to

    mapping(address => uint256) public investments; // total wei invested per address
    mapping(address => uint256) public investedTeamIds; // invested team id

    mapping(uint256 => uint256) public totalCollected; // total betted wei for each team
    mapping(uint256 => uint256) public totalInvestorsCount; // total Investors count for each team

    bool public onlyWhitelistedAddressesAllowed = false; // if true, only whitelisted addresses can invest
    mapping(address => bool) public whitelistedAddresses; // addresses eligible in match

    mapping(address => bool) public claimed; // if true, it means investor already claimed the tokens or got a refund
    uint256 public gameId; // used for fetching match without referencing its address

    uint256 public openTime; // time when match starts, betting is not allowed
    uint256 public closeTime; // time when match closes, betting is not allowed
    uint256 public teamCount = 2; // team counts on this match (normally 2)

    uint256[] public teamIds; // team ids (team informations are live on Library)

    bool public matchFinished = false; // if true, liquidity is added in PancakeSwap and lp tokens are locked
    bool public matchCancelled = false; // if true, investing will not be allowed, investors can withdraw, match creator can withdraw their tokens
    uint256 public winner = 0; // won team id
    uint256 public winnedTeamWei = 0; // amount of winned team collected
    uint256 public lostTeamWei = 0; // amount of lost team collected
    uint256 public rewardAmount = 0; // GameWin Reward Amount for winners

    string public matchTitle;
    string public matchUrl;
    string public liveUrl;
    string public linkWebsite;
    string public description;
    string public tournament;

    string public draw;
    uint256 public gameType; // 0: CUSTOM, 1: DOTA2, 2: COUNTER_STRIKE

    constructor(
        address _factoryAddress,
        address _gameLibrary,
        address _devAddress
    ) public {
        require(_factoryAddress != address(0));
        require(_devAddress != address(0));

        factoryAddress = payable(_factoryAddress);
        devAddress = payable(_devAddress);
        gameLibrary = GameWinMatchLibrary(_gameLibrary);
    }

    modifier onlyDev() {
        require(
            factoryAddress == msg.sender ||
                devAddress == msg.sender ||
                gameLibrary.getDev(msg.sender)
        );
        _;
    }

    modifier onlyFactoryOrDev() {
        require(
            matchCreatorAddress == msg.sender ||
                factoryAddress == msg.sender ||
                devAddress == msg.sender ||
                gameLibrary.getDev(msg.sender),
            "1"
        );
        _;
    }

    modifier isWhitelisted() {
        require(
            !onlyWhitelistedAddressesAllowed ||
                whitelistedAddresses[msg.sender],
            "2"
        );
        _;
    }

    modifier matchIsNotCancelled() {
        require(!matchCancelled, "3");
        _;
    }

    modifier isInvestor() {
        require(investments[msg.sender] > 0, "4");
        _;
    }

    modifier isClaimed() {
        require(!claimed[msg.sender], "5");
        _;
    }

    function setAddressInfo(
        address _matchCreator,
        address _tokenAddress,
        address _gameTokenAddress
    ) external onlyFactoryOrDev {
        matchCreatorAddress = payable(_matchCreator);
        fundingToken = IERC20(_tokenAddress);
        gameToken = IERC20(_gameTokenAddress);
    }

    function setGeneralInfo(
        uint256 _gameId,
        uint256 _openTime,
        uint256 _closeTime,
        uint256 _teamCount,
        uint256[] calldata _teamIds
    ) external onlyFactoryOrDev {
        gameId = _gameId;
        openTime = _openTime;
        closeTime = _closeTime;
        teamCount = _teamCount;
        teamIds = _teamIds;
    }

    function setMatchTitle(
        string calldata _matchTitle,
        string calldata _matchUrl,
        string calldata _liveUrl,
        uint256 _gameType
    ) external onlyFactoryOrDev {
        matchTitle = _matchTitle;
        matchUrl = _matchUrl;
        liveUrl = _liveUrl;
        gameType = _gameType;
    }

    function setStringInfo(
        string calldata _linkWebsite,
        string calldata _description,
        string calldata _tournament
    ) external onlyFactoryOrDev {
        linkWebsite = _linkWebsite;
        description = _description;
        tournament = _tournament;
    }

    function setGameDraw(string calldata _draw) external onlyFactoryOrDev {
        draw = _draw;
    }

    function setOnlyWhitelistedAddressesAllowed(
        bool _onlyWhitelistedAddressesAllowed
    ) external onlyFactoryOrDev {
        onlyWhitelistedAddressesAllowed = _onlyWhitelistedAddressesAllowed;
    }

    function addWhitelistedAddresses(address[] calldata _whitelistedAddresses)
        external
        onlyFactoryOrDev
    {
        onlyWhitelistedAddressesAllowed = _whitelistedAddresses.length > 0;
        for (uint256 i = 0; i < _whitelistedAddresses.length; i++) {
            whitelistedAddresses[_whitelistedAddresses[i]] = true;
        }
    }

    function swapUserToken(address userToken, uint256 amount)
        internal
        returns (uint256)
    {
        IUniswapV2Router02 router = IUniswapV2Router02(
            gameLibrary.getPancakeSwapRouter()
        );

        address[] memory swapPath = new address[](2);
        swapPath[0] = address(userToken);
        swapPath[1] = address(fundingToken);

        if (userToken == gameLibrary.getWBNB()) {
            uint256[] memory amounts = router.swapExactETHForTokens{
                value: amount
            }(uint256(0), swapPath, address(this), block.timestamp + 1 hours);

            return (amounts[amounts.length - 1]);
        } else {
            IERC20(userToken).approve(address(router), 0);
            IERC20(userToken).approve(address(router), amount);
            if (address(fundingToken) == gameLibrary.getWBNB()) {
                uint256[] memory amounts = router.swapExactTokensForETH(
                    amount,
                    uint256(0),
                    swapPath,
                    address(this),
                    block.timestamp + 1 hours
                );
                return (amounts[amounts.length - 1]);
            } else {
                uint256[] memory amounts = router.swapExactTokensForTokens(
                    amount,
                    uint256(0),
                    swapPath,
                    address(this),
                    block.timestamp + 1 hours
                );
                return (amounts[amounts.length - 1]);
            }
        }
    }

    function bet(
        uint256 sideIndex,
        address userToken,
        uint256 amount /// betting token {amount} to teamIds[sideIndex] here...
    ) public payable isWhitelisted matchIsNotCancelled {
        require(block.timestamp < openTime && block.timestamp < closeTime, "6");

        uint256 minStakedBalance = gameLibrary.getMinStakedBalance();

        if (minStakedBalance > 0) {
            uint256 stakedBalance = gameLibrary.getStakedBalance(msg.sender);
            require(stakedBalance >= minStakedBalance, "7");
        }

        if (address(userToken) == address(fundingToken)) {
            if (address(fundingToken) == gameLibrary.getWBNB()) {
                amount = msg.value;
            } else {
                fundingToken.transferFrom(msg.sender, address(this), amount);
            }
        } else {
            if (address(userToken) == gameLibrary.getWBNB()) {
                amount = msg.value;
            } else {
                IERC20(userToken).transferFrom(
                    msg.sender,
                    address(this),
                    amount
                );
            }
            amount = swapUserToken(userToken, amount);
        }

        require(amount > 0, "8");
        if (investments[msg.sender] > 0) {
            require(investedTeamIds[msg.sender] == sideIndex, "9");
        }

        uint256 totalAmount = investments[msg.sender].add(amount);

        uint256 minInvestAmount = gameLibrary.getMinInvestBalance(
            address(fundingToken)
        );
        uint256 maxInvestAmount = gameLibrary.getMaxInvestBalance(
            address(fundingToken)
        );

        if (minInvestAmount > 0) {
            require(totalAmount >= minInvestAmount, "10");
        }

        if (maxInvestAmount > 0) {
            require(totalAmount <= maxInvestAmount, "11");
        }

        totalCollected[sideIndex] = totalCollected[sideIndex].add(amount);
        if (investments[msg.sender] == 0) {
            totalInvestorsCount[sideIndex] = totalInvestorsCount[sideIndex].add(
                1
            );
        }
        investedTeamIds[msg.sender] = sideIndex;
        investments[msg.sender] = totalAmount;
    }

    receive() external payable {}

    function finishGame(uint256 winningSide, uint256 _rewardAmount)
        external
        onlyDev
    {
        require(block.timestamp > openTime, "12");
        require(!matchFinished, "13");

        uint256 totalCollectedWei = 0;
        winner = winningSide;
        winnedTeamWei = 0;

        for (uint256 i = 0; i < teamIds.length; i++) {
            totalCollectedWei = totalCollectedWei.add(totalCollected[i]);
            if (i == winner) {
                winnedTeamWei = winnedTeamWei.add(totalCollected[i]);
            }
        }

        totalCollectedWei = payFees(totalCollectedWei);
        if (winnedTeamWei >= totalCollectedWei) {
            lostTeamWei = 0;
        } else {
            lostTeamWei = totalCollectedWei.sub(winnedTeamWei);
        }
        if (_rewardAmount > 0) {
            rewardAmount = _rewardAmount;
            gameToken.transferFrom(msg.sender, address(this), _rewardAmount);
        }
        matchFinished = true;
        closeTime = block.timestamp;
    }

    function payFees(uint256 totalCollectedWei) internal returns (uint256) {
        uint256 finalTotalCollectedWei = totalCollectedWei;
        uint256 devFeePercent = gameLibrary.getDevFeePercentage();
        uint256 creatorFeePercent = gameLibrary.getCreatorFeePercentage();

        uint256 devFeeInWei = totalCollectedWei.mul(devFeePercent).div(100);
        uint256 creatorFeeInWei = totalCollectedWei.mul(creatorFeePercent).div(
            100
        );

        if (devFeeInWei > 0) {
            finalTotalCollectedWei = finalTotalCollectedWei.sub(devFeeInWei);
            devAddress.transfer(devFeeInWei);
        }
        if (creatorFeeInWei > 0) {
            finalTotalCollectedWei = finalTotalCollectedWei.sub(
                creatorFeeInWei
            );
            matchCreatorAddress.transfer(creatorFeeInWei);
        }
    }

    function cancelGame() external onlyDev {
        require(!matchFinished && !matchCancelled, "14");
        matchCancelled = true;
    }

    function getPendingReward(address sender) public view returns (uint256) {
        if (!matchFinished || block.timestamp <= openTime) {
            return 0;
        }
        if (investedTeamIds[sender] != winner) {
            return 0;
        }
        return lostTeamWei.mul(investments[sender]).div(totalCollected[winner]);
    }

    function getPendingGame(address sender) public view returns (uint256) {
        if (!matchFinished || block.timestamp <= openTime) {
            return 0;
        }
        if (investedTeamIds[sender] != winner) {
            return 0;
        }
        if (rewardAmount == 0) {
            return 0;
        }
        return
            rewardAmount.mul(investments[sender]).div(totalCollected[winner]);
    }

    function claim()
        external
        isWhitelisted
        matchIsNotCancelled
        isInvestor
        isClaimed
    {
        require(block.timestamp >= closeTime, "15");
        require(matchFinished, "16");
        require(investedTeamIds[msg.sender] == winner, "17");

        claimed[msg.sender] = true;
        fundingToken.transfer(msg.sender, investments[msg.sender]);
        uint256 pendingReward = getPendingReward(msg.sender);
        if (pendingReward > 0) {
            fundingToken.transfer(msg.sender, pendingReward);
        }
        uint256 gameReward = getPendingGame(msg.sender);
        if (gameReward > 0) {
            gameToken.transfer(msg.sender, gameReward);
        }
    }

    function getRefund() external isWhitelisted isInvestor isClaimed {
        require(matchCancelled, "0");

        claimed[msg.sender] = true; // make sure this goes first before transfer to prevent reentrancy
        uint256 investment = investments[msg.sender];

        if (address(fundingToken) == gameLibrary.getWBNB()) {
            uint256 matchBalance = address(this).balance;
            if (investment > matchBalance) {
                investment = matchBalance;
            }
            if (investment > 0) {
                msg.sender.transfer(investment);
            }
        } else {
            uint256 matchBalance = fundingToken.balanceOf(address(this));
            if (investment > matchBalance) {
                investment = matchBalance;
            }
            if (investment > 0) {
                fundingToken.transfer(msg.sender, investment);
            }
        }
    }
}

// SPDX-License-Identifier: MIT
pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "./lib/Ownable.sol";
import "./lib/SafeMath.sol";
import "./lib/ERC20.sol";
import "./GameWinFarming.sol";

interface IGameWinMatch {
    function investments(address _user) external view returns (uint256);

    function investedTeamIds(address _user) external view returns (uint256);

    function getPendingReward(address _user) external view returns (uint256);
}

contract GameWinMatchLibrary is Ownable {
    using SafeMath for uint256;

    uint256 private devFeePercentage = 1;
    uint256 private creatorFeePercentage = 1;
    mapping(address => bool) private gameDevs;
    mapping(address => bool) private gameCreators;

    address[] private matchAddresses; // track all matches created

    mapping(address => uint256) private minInvestBalance; // min amount to invest
    mapping(address => uint256) private maxInvestBalance; // max amount to invest

    //  PancakeSwap Infos
    address private pancakeSwapRouter =
        address(0x10ED43C718714eb63d5aA57B78B54704E256024E); // PancakeSwapV2 Router
    address private pancakeSwapFactory =
        address(0xcA143Ce32Fe78f1f7019d7d551a6402fC5350c73); // PancakeSwapV2 Factory
    bytes32 private initCodeHash =
        0x00fb7f630766e6a796048ea87d01acd3068e8ff67d078148a3fa3f4a84f69bd5; // PancakeSwapV2 InitCodeHash
    address private wbnb = address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c);

    // GameWin Token and Factory Contract Addresses
    address private factoryAddress;
    address private gameToken;

    address private stakingPool; // GameWin LP Farming & Staking Pool
    uint256 private minStakedBalance = 0; // GameWin Min Staked Balance for users

    struct GameTeamInfo {
        string teamName;
        string teamLogo;
        string description;
        string linkUrl;
        string facebookUrl;
        string twitterUrl;
        string youtubeUrl;
        string twitchUrl;
        string externalUrl;
        uint256 gameType; // 0: CUSTOM, 1: DOTA2, 2: COUNTER_STRIKE
    }

    struct GameJoinedInfo {
        uint256 gameId;
        uint256 sideId;
        uint256 amount;
        uint256 reward;
    }
    mapping(uint256 => mapping(uint256 => GameTeamInfo)) public gameTeams;
    mapping(uint256 => uint256) private gameTeamCount;

    constructor() public {
        gameDevs[address(msg.sender)] = true;
        minInvestBalance[wbnb] = 0;
        maxInvestBalance[wbnb] = 1000 * 1e18;
    }

    modifier onlyFactory() {
        require(
            factoryAddress == msg.sender ||
                owner == msg.sender ||
                gameDevs[msg.sender],
            "onlyFactoryOrDev"
        );
        _;
    }

    modifier onlyDev() {
        require(owner == msg.sender || gameDevs[msg.sender], "onlyDev");
        _;
    }

    modifier onlyGameCreators() {
        require(
            owner == msg.sender ||
                gameDevs[msg.sender] ||
                gameCreators[msg.sender],
            "onlyDev"
        );
        _;
    }

    function getCakeV2LPAddress(address tokenA, address tokenB)
        public
        view
        returns (address pair)
    {
        (address token0, address token1) = tokenA < tokenB
            ? (tokenA, tokenB)
            : (tokenB, tokenA);
        pair = address(
            uint256(
                keccak256(
                    abi.encodePacked(
                        hex"ff",
                        pancakeSwapFactory,
                        keccak256(abi.encodePacked(token0, token1)),
                        initCodeHash // init code hash
                    )
                )
            )
        );
    }

    function getDev(address _dev) external view returns (bool) {
        return gameDevs[_dev];
    }

    function setDevAddress(address _newDev) external onlyOwner {
        gameDevs[_newDev] = true;
    }

    function removeDevAddress(address _oldDev) external onlyOwner {
        gameDevs[_oldDev] = false;
    }

    function getCreator(address _creator) external view returns (bool) {
        return gameCreators[_creator];
    }

    function setCreatorAddress(address _newCreator) external onlyOwner {
        gameCreators[_newCreator] = true;
    }

    function removeCreatorAddress(address _oldCreator) external onlyOwner {
        gameCreators[_oldCreator] = false;
    }

    function getFactoryAddress() external view returns (address) {
        return factoryAddress;
    }

    function setFactoryAddress(address _newFactoryAddress) external onlyDev {
        factoryAddress = _newFactoryAddress;
    }

    function getStakingPool() external view returns (address) {
        return stakingPool;
    }

    function setStakingPool(address _stakingPool) external onlyDev {
        stakingPool = _stakingPool;
    }

    function addMatchAddress(address _match)
        external
        onlyFactory
        returns (uint256)
    {
        matchAddresses.push(_match);
        return matchAddresses.length - 1;
    }

    function getMatchCount() external view returns (uint256) {
        return matchAddresses.length;
    }

    function getMatchAddress(uint256 id) external view returns (address) {
        return matchAddresses[id];
    }

    function setMatchAddress(uint256 id, address _newAddress) external onlyDev {
        matchAddresses[id] = _newAddress;
    }

    function getDevFeePercentage() external view returns (uint256) {
        return devFeePercentage;
    }

    function setDevFeePercentage(uint256 _devFeePercentage) external onlyDev {
        devFeePercentage = _devFeePercentage;
    }

    function getCreatorFeePercentage() external view returns (uint256) {
        return creatorFeePercentage;
    }

    function setCreatorFeePercentage(uint256 _creatorFeePercentage)
        external
        onlyDev
    {
        creatorFeePercentage = _creatorFeePercentage;
    }

    function getMinInvestBalance(address fundingToken)
        external
        view
        returns (uint256)
    {
        return minInvestBalance[fundingToken];
    }

    function setMinInvestBalance(
        address fundingToken,
        uint256 _minInvestBalance
    ) external onlyDev {
        minInvestBalance[fundingToken] = _minInvestBalance;
    }

    function getMaxInvestBalance(address fundingToken)
        external
        view
        returns (uint256)
    {
        return maxInvestBalance[fundingToken];
    }

    function setMaxInvestBalance(
        address fundingToken,
        uint256 _maxInvestBalance
    ) external onlyDev {
        maxInvestBalance[fundingToken] = _maxInvestBalance;
    }

    function getPancakeSwapRouter() external view returns (address) {
        return pancakeSwapRouter;
    }

    function setPancakeSwapRouter(address _pancakeSwapRouter) external onlyDev {
        pancakeSwapRouter = _pancakeSwapRouter;
    }

    function getPancakeSwapFactory() external view returns (address) {
        return pancakeSwapFactory;
    }

    function setPancakeSwapFactory(address _pancakeSwapFactory)
        external
        onlyDev
    {
        pancakeSwapFactory = _pancakeSwapFactory;
    }

    function getInitCodeHash() external view returns (bytes32) {
        return initCodeHash;
    }

    function setInitCodeHash(bytes32 _initCodeHash) external onlyDev {
        initCodeHash = _initCodeHash;
    }

    function getWBNB() external view returns (address) {
        return wbnb;
    }

    function setWBNB(address _wbnb) external onlyDev {
        wbnb = _wbnb;
    }

    function getMinStakedBalance() external view returns (uint256) {
        return minStakedBalance;
    }

    function setMinStakedBalance(uint256 _minStakedBalance) external onlyDev {
        minStakedBalance = _minStakedBalance;
    }

    function getStakedBalance(address payable sender)
        public
        view
        returns (uint256)
    {
        uint256 balance;
        (balance, , , , ) = GameWinFarming(payable(stakingPool)).userInfos(
            address(sender)
        );
        return balance;
    }

    function setTeamInfo(
        uint256 gameType,
        uint256 teamIndex,
        GameTeamInfo calldata _teamInfo
    ) public onlyDev {
        gameTeams[gameType][teamIndex].teamName = _teamInfo.teamName;
        gameTeams[gameType][teamIndex].teamLogo = _teamInfo.teamLogo;
        gameTeams[gameType][teamIndex].description = _teamInfo.description;
        gameTeams[gameType][teamIndex].linkUrl = _teamInfo.linkUrl;
        gameTeams[gameType][teamIndex].twitterUrl = _teamInfo.twitterUrl;
        gameTeams[gameType][teamIndex].youtubeUrl = _teamInfo.youtubeUrl;
        gameTeams[gameType][teamIndex].twitchUrl = _teamInfo.twitchUrl;
        gameTeams[gameType][teamIndex].externalUrl = _teamInfo.externalUrl;
        gameTeams[gameType][teamIndex].gameType = _teamInfo.gameType;
    }

    function addTeamInfo(uint256 gameType, GameTeamInfo calldata _teamInfo)
        external
        onlyGameCreators
    {
        setTeamInfo(gameType, gameTeamCount[gameType], _teamInfo);
        gameTeamCount[gameType] = gameTeamCount[gameType].add(1);
    }

    function getTeamCounts(uint256 gameType) external view returns (uint256) {
        return gameTeamCount[gameType];
    }

    function getJoinedGames(address _user)
        external
        view
        returns (GameJoinedInfo[] memory)
    {
        GameJoinedInfo[] memory joinedInfos = new GameJoinedInfo[](
            matchAddresses.length
        );

        for (uint256 i = 0; i < matchAddresses.length; i++) {
            IGameWinMatch gameMatch = IGameWinMatch(payable(matchAddresses[i]));
            joinedInfos[i].gameId = i;
            joinedInfos[i].amount = gameMatch.investments(_user);
            joinedInfos[i].sideId = gameMatch.investedTeamIds(_user);
            joinedInfos[i].reward = gameMatch.getPendingReward(_user);
        }
        return joinedInfos;
    }
}

pragma solidity ^0.6.12;

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

pragma solidity ^0.6.12;

interface IUniswapV2Pair {
    event Approval(
        address indexed owner,
        address indexed spender,
        uint256 value
    );
    event Transfer(address indexed from, address indexed to, uint256 value);

    function name() external pure returns (string memory);

    function symbol() external pure returns (string memory);

    function decimals() external pure returns (uint8);

    function totalSupply() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function allowance(address owner, address spender)
        external
        view
        returns (uint256);

    function approve(address spender, uint256 value) external returns (bool);

    function transfer(address to, uint256 value) external returns (bool);

    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);

    function PERMIT_TYPEHASH() external pure returns (bytes32);

    function nonces(address owner) external view returns (uint256);

    function permit(
        address owner,
        address spender,
        uint256 value,
        uint256 deadline,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external;

    event Mint(address indexed sender, uint256 amount0, uint256 amount1);
    event Burn(
        address indexed sender,
        uint256 amount0,
        uint256 amount1,
        address indexed to
    );
    event Swap(
        address indexed sender,
        uint256 amount0In,
        uint256 amount1In,
        uint256 amount0Out,
        uint256 amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint256);

    function factory() external view returns (address);

    function token0() external view returns (address);

    function token1() external view returns (address);

    function getReserves()
        external
        view
        returns (
            uint112 reserve0,
            uint112 reserve1,
            uint32 blockTimestampLast
        );

    function price0CumulativeLast() external view returns (uint256);

    function price1CumulativeLast() external view returns (uint256);

    function kLast() external view returns (uint256);

    function mint(address to) external returns (uint256 liquidity);

    function burn(address to)
        external
        returns (uint256 amount0, uint256 amount1);

    function swap(
        uint256 amount0Out,
        uint256 amount1Out,
        address to,
        bytes calldata data
    ) external;

    function skim(address to) external;

    function sync() external;

    function initialize(address, address) external;
}

interface IUniswapV2Factory {
    event PairCreated(
        address indexed token0,
        address indexed token1,
        address pair,
        uint256
    );

    function feeTo() external view returns (address);

    function feeToSetter() external view returns (address);

    function getPair(address tokenA, address tokenB)
        external
        view
        returns (address pair);

    function allPairs(uint256) external view returns (address pair);

    function allPairsLength() external view returns (uint256);

    function createPair(address tokenA, address tokenB)
        external
        returns (address pair);

    function setFeeTo(address) external;

    function setFeeToSetter(address) external;
}

interface IUniswapV2Router01 {
    function factory() external pure returns (address);

    function WETH() external pure returns (address);

    function addLiquidity(
        address tokenA,
        address tokenB,
        uint256 amountADesired,
        uint256 amountBDesired,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    )
        external
        returns (
            uint256 amountA,
            uint256 amountB,
            uint256 liquidity
        );

    function addLiquidityETH(
        address token,
        uint256 amountTokenDesired,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    )
        external
        payable
        returns (
            uint256 amountToken,
            uint256 amountETH,
            uint256 liquidity
        );

    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETH(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountToken, uint256 amountETH);

    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint256 liquidity,
        uint256 amountAMin,
        uint256 amountBMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountA, uint256 amountB);

    function removeLiquidityETHWithPermit(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountToken, uint256 amountETH);

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapTokensForExactTokens(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactETHForTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function swapTokensForExactETH(
        uint256 amountOut,
        uint256 amountInMax,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapExactTokensForETH(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external returns (uint256[] memory amounts);

    function swapETHForExactTokens(
        uint256 amountOut,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable returns (uint256[] memory amounts);

    function quote(
        uint256 amountA,
        uint256 reserveA,
        uint256 reserveB
    ) external pure returns (uint256 amountB);

    function getAmountOut(
        uint256 amountIn,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountOut);

    function getAmountIn(
        uint256 amountOut,
        uint256 reserveIn,
        uint256 reserveOut
    ) external pure returns (uint256 amountIn);

    function getAmountsOut(uint256 amountIn, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);

    function getAmountsIn(uint256 amountOut, address[] calldata path)
        external
        view
        returns (uint256[] memory amounts);
}

interface IUniswapV2Router02 is IUniswapV2Router01 {
    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline
    ) external returns (uint256 amountETH);

    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint256 liquidity,
        uint256 amountTokenMin,
        uint256 amountETHMin,
        address to,
        uint256 deadline,
        bool approveMax,
        uint8 v,
        bytes32 r,
        bytes32 s
    ) external returns (uint256 amountETH);

    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external payable;

    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 deadline
    ) external;
}

pragma solidity ^0.6.12;

interface IWETH {
    function deposit() external payable;

    function transfer(address to, uint256 value) external returns (bool);

    function withdraw(uint256) external;
}

pragma solidity ^0.6.12;

// File: @openzeppelin/contracts/utils/Address.sol

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
        // This method relies in extcodesize, which returns 0 for contracts in
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
        return _functionCallWithValue(target, data, 0, errorMessage);
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
        return _functionCallWithValue(target, data, value, errorMessage);
    }

    function _functionCallWithValue(address target, bytes memory data, uint256 weiValue, string memory errorMessage) private returns (bytes memory) {
        require(isContract(target), "Address: call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.call{ value: weiValue }(data);
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

pragma solidity ^0.6.12;

// File: @openzeppelin/contracts/GSN/Context.sol

/*
 * @dev Provides information about the current execution context, including the
 * sender of the transaction and its data. While these are generally available
 * via msg.sender and msg.data, they should not be accessed in such a direct
 * manner, since when dealing with GSN meta-transactions the account sending and
 * paying for execution may not be the actual sender (as far as an application
 * is concerned).
 *
 * This contract is only required for intermediate, library-like contracts.
 */
abstract contract Context {
    function _msgSender() internal view virtual returns (address payable) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes memory) {
        this; // silence state mutability warning without generating bytecode - see https://github.com/ethereum/solidity/issues/2691
        return msg.data;
    }
}

pragma solidity ^0.6.12;

import "./Address.sol";
import "./Context.sol";
import "./SafeMath.sol";
import "../interfaces/IERC20.sol";

// File: @openzeppelin/contracts/token/ERC20/ERC20.sol

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
contract ERC20 is Context, IERC20 {
    using SafeMath for uint256;
    using Address for address;

    mapping (address => uint256) _balances;

    mapping (address => mapping (address => uint256)) _allowances;

    uint256 _totalSupply;

    string private _name;
    string private _symbol;
    uint8 private _decimals;

    /**
     * @dev Sets the values for {name} and {symbol}, initializes {decimals} with
     * a default value of 18.
     *
     * To select a different value for {decimals}, use {_setupDecimals}.
     *
     * All three of these values are immutable: they can only be set once during
     * construction.
     */
    constructor (string memory name, string memory symbol) public {
        _name = name;
        _symbol = symbol;
        _decimals = 18;
    }

    /**
     * @dev Returns the name of the token.
     */
    function name() public view returns (string memory) {
        return _name;
    }

    /**
     * @dev Returns the symbol of the token, usually a shorter version of the
     * name.
     */
    function symbol() public view returns (string memory) {
        return _symbol;
    }

    /**
     * @dev Returns the number of decimals used to get its user representation.
     * For example, if `decimals` equals `2`, a balance of `505` tokens should
     * be displayed to a user as `5,05` (`505 / 10 ** 2`).
     *
     * Tokens usually opt for a value of 18, imitating the relationship between
     * Ether and Wei. This is the value {ERC20} uses, unless {_setupDecimals} is
     * called.
     *
     * NOTE: This information is only used for _display_ purposes: it in
     * no way affects any of the arithmetic of the contract, including
     * {IERC20-balanceOf} and {IERC20-transfer}.
     */
    function decimals() public view returns (uint8) {
        return _decimals;
    }

    /**
     * @dev See {IERC20-totalSupply}.
     */
    function totalSupply() public view override returns (uint256) {
        return _totalSupply;
    }

    /**
     * @dev See {IERC20-balanceOf}.
     */
    function balanceOf(address account) public view override returns (uint256) {
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
     * required by the EIP. See the note at the beginning of {ERC20};
     *
     * Requirements:
     * - `sender` and `recipient` cannot be the zero address.
     * - `sender` must have a balance of at least `amount`.
     * - the caller must have allowance for ``sender``'s tokens of at least
     * `amount`.
     */
    function transferFrom(address sender, address recipient, uint256 amount) public virtual override returns (bool) {
        _transfer(sender, recipient, amount);
        _approve(sender, _msgSender(), _allowances[sender][_msgSender()].sub(amount, "ERC20: transfer amount exceeds allowance"));
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
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].add(addedValue));
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
        _approve(_msgSender(), spender, _allowances[_msgSender()][spender].sub(subtractedValue, "ERC20: decreased allowance below zero"));
        return true;
    }

    /**
     * @dev Moves tokens `amount` from `sender` to `recipient`.
     *
     * This is internal function is equivalent to {transfer}, and can be used to
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
    function _transfer(address sender, address recipient, uint256 amount) internal virtual {
        require(sender != address(0), "ERC20: transfer from the zero address");
        require(recipient != address(0), "ERC20: transfer to the zero address");

        _beforeTokenTransfer(sender, recipient, amount);

        _balances[sender] = _balances[sender].sub(amount, "ERC20: transfer amount exceeds balance");
        _balances[recipient] = _balances[recipient].add(amount);
        emit Transfer(sender, recipient, amount);
    }

    /** @dev Creates `amount` tokens and assigns them to `account`, increasing
     * the total supply.
     *
     * Emits a {Transfer} event with `from` set to the zero address.
     *
     * Requirements
     *
     * - `to` cannot be the zero address.
     */
    function _mint(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: mint to the zero address");
        _beforeTokenTransfer(address(0), account, amount);

        _totalSupply = _totalSupply.add(amount);
        _balances[account] = _balances[account].add(amount);
        emit Transfer(address(0), account, amount);
    }

    /**
     * @dev Destroys `amount` tokens from `account`, reducing the
     * total supply.
     *
     * Emits a {Transfer} event with `to` set to the zero address.
     *
     * Requirements
     *
     * - `account` cannot be the zero address.
     * - `account` must have at least `amount` tokens.
     */
    function _burn(address account, uint256 amount) internal virtual {
        require(account != address(0), "ERC20: burn from the zero address");

        _beforeTokenTransfer(account, address(0), amount);

        _balances[account] = _balances[account].sub(amount, "ERC20: burn amount exceeds balance");
        _totalSupply = _totalSupply.sub(amount);
        emit Transfer(account, address(0), amount);
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
    function _approve(address owner, address spender, uint256 amount) internal virtual {
        require(owner != address(0), "ERC20: approve from the zero address");
        require(spender != address(0), "ERC20: approve to the zero address");

        _allowances[owner][spender] = amount;
        emit Approval(owner, spender, amount);
    }

    /**
     * @dev Sets {decimals} to a value other than the default one of 18.
     *
     * WARNING: This function should only be called from the constructor. Most
     * applications that interact with token contracts will not expect
     * {decimals} to ever change, and may work incorrectly if it does.
     */
    function _setupDecimals(uint8 decimals_) internal {
        _decimals = decimals_;
    }

    /**
     * @dev Hook that is called before any transfer of tokens. This includes
     * minting and burning.
     *
     * Calling conditions:
     *
     * - when `from` and `to` are both non-zero, `amount` of ``from``'s tokens
     * will be to transferred to `to`.
     * - when `from` is zero, `amount` tokens will be minted for `to`.
     * - when `to` is zero, `amount` of ``from``'s tokens will be burned.
     * - `from` and `to` are never both zero.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual { }
}

pragma solidity ^0.6.12;

// File: @openzeppelin/contracts/math/Math.sol

/**
 * @dev Standard math utilities missing in the Solidity language.
 */
library Math {
    /**
     * @dev Returns the largest of two numbers.
     */
    function max(uint256 a, uint256 b) internal pure returns (uint256) {
        return a >= b ? a : b;
    }

    /**
     * @dev Returns the smallest of two numbers.
     */
    function min(uint256 a, uint256 b) internal pure returns (uint256) {
        return a < b ? a : b;
    }

    /**
     * @dev Returns the average of two numbers. The result is rounded towards
     * zero.
     */
    function average(uint256 a, uint256 b) internal pure returns (uint256) {
        // (a + b) / 2 can overflow, so we distribute
        return (a / 2) + (b / 2) + ((a % 2 + b % 2) / 2);
    }
}

pragma solidity ^0.6.12;

/**
 * @title Owned
 * @dev Basic contract for authorization control.
 * @author dicether
 */
contract Ownable {
    address public owner;
    address public pendingOwner;

    event LogOwnerShipTransferred(address indexed previousOwner, address indexed newOwner);
    event LogOwnerShipTransferInitiated(address indexed previousOwner, address indexed newOwner);

    /**
     * @dev Modifier, which throws if called by other account than owner.
     */
    modifier onlyOwner {
        require(msg.sender == owner);
        _;
    }

    /**
     * @dev Modifier throws if called by any account other than the pendingOwner.
     */
    modifier onlyPendingOwner() {
        require(msg.sender == pendingOwner);
        _;
    }

    /**
     * @dev Set contract creator as initial owner
     */
    constructor() public {
        owner = msg.sender;
        pendingOwner = address(0);
    }

    /**
     * @dev Allows the current owner to set the pendingOwner address.
     * @param _newOwner The address to transfer ownership to.
     */
    function transferOwnership(address _newOwner) public onlyOwner {
        pendingOwner = _newOwner;
        emit LogOwnerShipTransferInitiated(owner, _newOwner);
    }

    /**
     * @dev PendingOwner can accept ownership.
     */
    function claimOwnership() public onlyPendingOwner {
        owner = pendingOwner;
        pendingOwner = address(0);
        emit LogOwnerShipTransferred(owner, pendingOwner);
    }
}

pragma solidity ^0.6.12;

// File: @openzeppelin/contracts/utils/ReentrancyGuard.sol

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
contract ReentrancyGuard {
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

    constructor () internal {
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

pragma solidity ^0.6.12;

import "./Address.sol";
import "./SafeMath.sol";

import "../interfaces/IERC20.sol";

// File: @openzeppelin/contracts/token/ERC20/SafeERC20.sol

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
    using SafeMath for uint256;
    using Address for address;

    function safeTransfer(IERC20 token, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transfer.selector, to, value));
    }

    function safeTransferFrom(IERC20 token, address from, address to, uint256 value) internal {
        _callOptionalReturn(token, abi.encodeWithSelector(token.transferFrom.selector, from, to, value));
    }

    /**
     * @dev Deprecated. This function has issues similar to the ones found in
     * {IERC20-approve}, and its usage is discouraged.
     *
     * Whenever possible, use {safeIncreaseAllowance} and
     * {safeDecreaseAllowance} instead.
     */
    function safeApprove(IERC20 token, address spender, uint256 value) internal {
        // safeApprove should only be called when setting an initial allowance,
        // or when resetting it to zero. To increase and decrease it, use
        // 'safeIncreaseAllowance' and 'safeDecreaseAllowance'
        // solhint-disable-next-line max-line-length
        require((value == 0) || (token.allowance(address(this), spender) == 0),
            "SafeERC20: approve from non-zero to non-zero allowance"
        );
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, value));
    }

    function safeIncreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).add(value);
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
        uint256 newAllowance = token.allowance(address(this), spender).sub(value, "SafeERC20: decreased allowance below zero");
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
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
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

pragma solidity ^0.6.12;

// File: @openzeppelin/contracts/math/SafeMath.sol

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
     *
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
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b) internal pure returns (uint256) {
        return sub(a, b, "SafeMath: subtraction overflow");
    }

    /**
     * @dev Returns the subtraction of two unsigned integers, reverting with custom message on
     * overflow (when the result is negative).
     *
     * Counterpart to Solidity's `-` operator.
     *
     * Requirements:
     *
     * - Subtraction cannot overflow.
     */
    function sub(uint256 a, uint256 b, string memory errorMessage) internal pure returns (uint256) {
        require(b <= a, errorMessage);
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
     *
     * - Multiplication cannot overflow.
     */
    function mul(uint256 a, uint256 b) internal pure returns (uint256) {
        // Gas optimization: this is cheaper than requiring 'a' not being zero, but the
        // benefit is lost if 'b' is also tested.
        // See: https://github.com/OpenZeppelin/openzeppelin-contracts/pull/522
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
     *
     * - The divisor cannot be zero.
     */
    function div(uint256 a, uint256 b) internal pure returns (uint256) {
        return div(a, b, "SafeMath: division by zero");
    }

    /**
     * @dev Returns the integer division of two unsigned integers. Reverts with custom message on
     * division by zero. The result is rounded towards zero.
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
        require(b > 0, errorMessage);
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
     *
     * - The divisor cannot be zero.
     */
    function mod(uint256 a, uint256 b) internal pure returns (uint256) {
        return mod(a, b, "SafeMath: modulo by zero");
    }

    /**
     * @dev Returns the remainder of dividing two unsigned integers. (unsigned integer modulo),
     * Reverts with custom message when dividing by zero.
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
        require(b != 0, errorMessage);
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