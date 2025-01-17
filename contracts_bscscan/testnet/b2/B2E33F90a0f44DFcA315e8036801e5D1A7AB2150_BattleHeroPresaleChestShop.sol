// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;
import "../node_modules/@openzeppelin/contracts/access/AccessControlEnumerable.sol";
import "./shared/IBattleHero.sol";
import "./shared/IBattleHeroGenScience.sol";
import "./shared/IBattleHeroBreeder.sol";
import "../node_modules/@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../node_modules/@openzeppelin/contracts/access/Ownable.sol";

contract BattleHeroPresaleChestShop is Context, AccessControlEnumerable, Ownable {

    IBattleHeroGenScience _genScience;
    IBattleHeroBreeder _breeder;

    using SafeMath for uint256;
    

    bytes32 public constant ECOSYSTEM_ROLE = keccak256("ECOSYSTEM_ROLE");

    enum ChestType {
        CHARACTER,
        WEAPON,
        MIX
    }
    enum ChestRarity {
        COMMON,
        LOW_RARE,
        RARE,
        EPIC,
        LEGEND,
        MITIC,
        RANDOM
    }

    struct Chest{
        ChestType chestType;
        ChestRarity chestRarity;
        bool opened;
        uint index;
        uint when;
    }

    mapping(ChestType => mapping(ChestRarity => mapping(uint => uint))) _caps;
    mapping(ChestRarity => uint) _prices;
    uint256 _presaleStart;
    mapping(address => Chest[]) _buyed;
    address _beneficiary;

    uint256 MAX_DAYS = 3 days;
    uint256 ROUND_DURATION = 1 days;

    event ChestOpened(uint index, address from,uint when, uint[] tokenIds);

    constructor(
        address erc20address,
        address genScience,
        address breeder
    ) {
        _setupRole(ECOSYSTEM_ROLE, _msgSender());
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _genScience   = IBattleHeroGenScience(genScience);
        _breeder      = IBattleHeroBreeder(breeder);
        _beneficiary  = 0xb8Ce421729232eCD5DFc7BD0adFe1f4DAd9D9CcE;
        _presaleStart = 1633114800; // 1 October 2021 at 19:00 GMT on mainnet         

        _prices[ChestRarity.LOW_RARE] = 80000000000000000 wei;
        _prices[ChestRarity.RARE]     = 250000000000000000 wei;         
        _prices[ChestRarity.EPIC]     = 600000000000000000 wei; 
        _prices[ChestRarity.LEGEND]   = 1350000000000000000 wei;        
        _prices[ChestRarity.MITIC]    = 1980000000000000000 wei;

        _caps[ChestType.CHARACTER][ChestRarity.LOW_RARE][0] = 600;
        _caps[ChestType.WEAPON][ChestRarity.LOW_RARE][0]    = 600;
        _caps[ChestType.CHARACTER][ChestRarity.RARE][0]     = 375;
        _caps[ChestType.WEAPON][ChestRarity.RARE][0]        = 375; 
        _caps[ChestType.CHARACTER][ChestRarity.EPIC][0]     = 150;
        _caps[ChestType.WEAPON][ChestRarity.EPIC][0]        = 150; 
        _caps[ChestType.CHARACTER][ChestRarity.LEGEND][0]   = 10;
        _caps[ChestType.WEAPON][ChestRarity.LEGEND][0]      = 10; 
        _caps[ChestType.CHARACTER][ChestRarity.MITIC][0]    = 3;
        _caps[ChestType.WEAPON][ChestRarity.MITIC][0]       = 3; 

        _caps[ChestType.CHARACTER][ChestRarity.LOW_RARE][1] = 600;
        _caps[ChestType.WEAPON][ChestRarity.LOW_RARE][1]    = 600;
        _caps[ChestType.CHARACTER][ChestRarity.RARE][1]     = 375;
        _caps[ChestType.WEAPON][ChestRarity.RARE][1]        = 375; 
        _caps[ChestType.CHARACTER][ChestRarity.EPIC][1]     = 150;
        _caps[ChestType.WEAPON][ChestRarity.EPIC][1]        = 150; 
        _caps[ChestType.CHARACTER][ChestRarity.LEGEND][1]   = 10;
        _caps[ChestType.WEAPON][ChestRarity.LEGEND][1]      = 10; 
        _caps[ChestType.CHARACTER][ChestRarity.MITIC][1]    = 3;
        _caps[ChestType.WEAPON][ChestRarity.MITIC][1]       = 3; 

        _caps[ChestType.CHARACTER][ChestRarity.LOW_RARE][2] = 600;
        _caps[ChestType.WEAPON][ChestRarity.LOW_RARE][2]    = 600;
        _caps[ChestType.CHARACTER][ChestRarity.RARE][2]     = 375;
        _caps[ChestType.WEAPON][ChestRarity.RARE][2]        = 375; 
        _caps[ChestType.CHARACTER][ChestRarity.EPIC][2]     = 150;
        _caps[ChestType.WEAPON][ChestRarity.EPIC][2]        = 150; 
        _caps[ChestType.CHARACTER][ChestRarity.LEGEND][2]   = 10;
        _caps[ChestType.WEAPON][ChestRarity.LEGEND][2]      = 10; 
        _caps[ChestType.CHARACTER][ChestRarity.MITIC][2]    = 3;
        _caps[ChestType.WEAPON][ChestRarity.MITIC][2]       = 3; 

    }
    modifier isSetup() {
        require(address(_genScience) != address(0), "Setup not correctly");
        require(address(_breeder) != address(0), "Setup not correctly");
        _;
    }
    function chestsOf(address from, uint256 page) public view returns(Chest[] memory) {
        uint results_per_page       = 10;
        uint greater_than           = results_per_page * page;
        uint start_pointer          = (results_per_page * page) - results_per_page;
        Chest[] memory chests       = new Chest[](results_per_page);   
        uint counter                = 0;
        for(uint i = start_pointer; i < greater_than; i++){
            if(i < _buyed[from].length){
                Chest memory ch = _buyed[from][i];
                chests[counter] = ch;
                counter = counter + 1;
            }           
        }
        return chests;
    }
    function buy(ChestType chestType, ChestRarity chestRarity) external payable {
        require(msg.value >= _prices[chestRarity], "Insufficient BNB");
        require(block.timestamp >= _presaleStart && block.timestamp <= (_presaleStart + MAX_DAYS), "Time out");
        if(block.timestamp >= _presaleStart && block.timestamp <= _presaleStart + ROUND_DURATION){
            require(_caps[chestType][chestRarity][0] > 0, "Sold out");            
            _caps[chestType][chestRarity][0] = _caps[chestType][chestRarity][0].sub(1);
            _buyed[msg.sender].push(Chest(chestType, chestRarity, false, _buyed[msg.sender].length, block.timestamp));
            payable(_beneficiary).transfer(msg.value);
            return;
        }
        if(block.timestamp >= _presaleStart + ROUND_DURATION && block.timestamp <= _presaleStart + (ROUND_DURATION * 2)){
            require(_caps[chestType][chestRarity][1] > 0, "Sold out");
            _caps[chestType][chestRarity][1] = _caps[chestType][chestRarity][1].sub(1);
            _buyed[msg.sender].push(Chest(chestType, chestRarity, false, _buyed[msg.sender].length, block.timestamp));
            payable(_beneficiary).transfer(msg.value);
            return;
        }
        if(block.timestamp >= _presaleStart + (ROUND_DURATION * 2) && block.timestamp <= MAX_DAYS){
            require(_caps[chestType][chestRarity][2] > 0, "Sold out");
            _caps[chestType][chestRarity][2] = _caps[chestType][chestRarity][2].sub(1);
            _buyed[msg.sender].push(Chest(chestType, chestRarity, false, _buyed[msg.sender].length, block.timestamp));
            payable(_beneficiary).transfer(msg.value);
            return;
        }
        revert();
    }
    function open(uint index) public {
        Chest memory chest = _buyed[msg.sender][index];
        uint[] memory ids = new uint[](2);           
        require(chest.opened == false, "Chest is currently opened");
        require(chest.chestRarity != ChestRarity.RANDOM, "Invalid chest on presale");    
        require(chest.when > 0, "Invalid chest");
        if (chest.chestType == ChestType.WEAPON) {
            string memory weapon = _genScience.generateWeapon(
                chestRaritytoRarity(chest.chestRarity)
            );
            ids[0] = _breeder.breed(msg.sender, weapon);
            emit ChestOpened(index, msg.sender, block.timestamp, ids);
        }
        if (chest.chestType == ChestType.CHARACTER) {
            string memory character = _genScience.generateCharacter(
                chestRaritytoRarity(chest.chestRarity)
            );
            ids[0] = _breeder.breed(msg.sender, character);
            emit ChestOpened(index, msg.sender, block.timestamp, ids);
        }    
        _buyed[msg.sender][index].opened = true;
    }
    function setGenScience(address genScience) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()));
        _genScience = IBattleHeroGenScience(genScience);
    }
    function setBreeder(address breeder) public {
        require(hasRole(DEFAULT_ADMIN_ROLE, _msgSender()));
        _breeder = IBattleHeroBreeder(breeder);
    }
    function chestRaritytoRarity(ChestRarity chestRarity) public pure returns(IBattleHeroGenScience.Rarity){
        if(chestRarity == ChestRarity.COMMON){
            return IBattleHeroGenScience.Rarity.COMMON;
        }
        if(chestRarity == ChestRarity.LOW_RARE){
            return IBattleHeroGenScience.Rarity.LOW_RARE;
        }
        if(chestRarity == ChestRarity.RARE){
            return IBattleHeroGenScience.Rarity.RARE;
        }
        if(chestRarity == ChestRarity.EPIC){
            return IBattleHeroGenScience.Rarity.EPIC;
        }
        if(chestRarity == ChestRarity.LEGEND){
            return IBattleHeroGenScience.Rarity.LEGEND;
        }
        if(chestRarity == ChestRarity.MITIC){
            return IBattleHeroGenScience.Rarity.MITIC;
        }
        return IBattleHeroGenScience.Rarity.COMMON;
    }
    function selling() public view returns(uint256[5][5] memory){
        uint256[5][5] memory chestCaps;

        if(block.timestamp >= _presaleStart && block.timestamp <= _presaleStart + ROUND_DURATION){        
            
            chestCaps[0][0] = _caps[ChestType.CHARACTER][ChestRarity.LOW_RARE][0];
            chestCaps[0][1] = _caps[ChestType.CHARACTER][ChestRarity.RARE][0];
            chestCaps[0][2] = _caps[ChestType.CHARACTER][ChestRarity.EPIC][0];
            chestCaps[0][3] = _caps[ChestType.CHARACTER][ChestRarity.LEGEND][0];
            chestCaps[0][4] = _caps[ChestType.CHARACTER][ChestRarity.MITIC][0];

            chestCaps[1][0] = _caps[ChestType.WEAPON][ChestRarity.LOW_RARE][0];  
            chestCaps[1][1] = _caps[ChestType.WEAPON][ChestRarity.RARE][0];
            chestCaps[1][2] = _caps[ChestType.WEAPON][ChestRarity.EPIC][0];        
            chestCaps[1][3] = _caps[ChestType.WEAPON][ChestRarity.LEGEND][0];
            chestCaps[1][4] = _caps[ChestType.WEAPON][ChestRarity.MITIC][0];
        }
        if(block.timestamp >= _presaleStart + ROUND_DURATION && block.timestamp <= _presaleStart + (ROUND_DURATION * 2)){
            chestCaps[0][0] = _caps[ChestType.CHARACTER][ChestRarity.LOW_RARE][1];
            chestCaps[0][1] = _caps[ChestType.CHARACTER][ChestRarity.RARE][1];
            chestCaps[0][2] = _caps[ChestType.CHARACTER][ChestRarity.EPIC][1];
            chestCaps[0][3] = _caps[ChestType.CHARACTER][ChestRarity.LEGEND][1];
            chestCaps[0][4] = _caps[ChestType.CHARACTER][ChestRarity.MITIC][1];

            chestCaps[1][0] = _caps[ChestType.WEAPON][ChestRarity.LOW_RARE][1];  
            chestCaps[1][1] = _caps[ChestType.WEAPON][ChestRarity.RARE][1];
            chestCaps[1][2] = _caps[ChestType.WEAPON][ChestRarity.EPIC][1];        
            chestCaps[1][3] = _caps[ChestType.WEAPON][ChestRarity.LEGEND][1];
            chestCaps[1][4] = _caps[ChestType.WEAPON][ChestRarity.MITIC][1];
        }
        if(block.timestamp >= _presaleStart + (ROUND_DURATION * 2) && block.timestamp <= _presaleStart + (ROUND_DURATION * 3)){
            chestCaps[0][0] = _caps[ChestType.CHARACTER][ChestRarity.LOW_RARE][2];
            chestCaps[0][1] = _caps[ChestType.CHARACTER][ChestRarity.RARE][2];
            chestCaps[0][2] = _caps[ChestType.CHARACTER][ChestRarity.EPIC][2];
            chestCaps[0][3] = _caps[ChestType.CHARACTER][ChestRarity.LEGEND][2];
            chestCaps[0][4] = _caps[ChestType.CHARACTER][ChestRarity.MITIC][2];

            chestCaps[1][0] = _caps[ChestType.WEAPON][ChestRarity.LOW_RARE][2];  
            chestCaps[1][1] = _caps[ChestType.WEAPON][ChestRarity.RARE][2];
            chestCaps[1][2] = _caps[ChestType.WEAPON][ChestRarity.EPIC][2];        
            chestCaps[1][3] = _caps[ChestType.WEAPON][ChestRarity.LEGEND][2];
            chestCaps[1][4] = _caps[ChestType.WEAPON][ChestRarity.MITIC][2];
        } 
        return chestCaps;
    }
    function emergencyWithdraw() public onlyOwner{
        payable(_beneficiary).transfer(payable(address(this)).balance);
    }
}

pragma solidity ^0.8.0;


contract BattleHeroData { 

    enum Asset{
        CHARACTER, 
        WEAPON
    }

    enum Rare{
        COMMON,
        LOW_RARE,
        RARE,
        EPIC,
        LEGEND,
        MITIC      
    }

    struct Rarity{
        uint256 min;
        uint256 max;
        string rarity;
        Rare rare;
    }

    struct AssetType{
        uint256 min;
        uint256 max;
        string assetType;
        Asset asset;
    }
    

    struct TrainingLevel { 
        uint256 min;
        uint256 max;
        uint256 level;
        uint256 pct;
    }


  
    struct DeconstructedGen{
        uint256 _type;
        uint256 _asset;
        uint256 _rarity;
        uint256 _stat;
        uint256 _transferible;
    }

    uint minStat = 6;

    Rarity[] rarities;
    AssetType[] assetTypes;    
    
    constructor(){
        rarities.push(Rarity(0   , 4993, "COMMON", Rare.COMMON));
        rarities.push(Rarity(4994, 8139, "LOW RARE", Rare.LOW_RARE));
        rarities.push(Rarity(8140, 9611, "RARE", Rare.RARE));
        rarities.push(Rarity(9612, 9953, "EPIC", Rare.EPIC));
        rarities.push(Rarity(9954, 9984, "LEGEND", Rare.LEGEND));
        rarities.push(Rarity(9985, 9999, "MITIC", Rare.MITIC));

        assetTypes.push(AssetType(0 , 49, "CHARACTER", Asset.CHARACTER));
        assetTypes.push(AssetType(50, 99, "WEAPON", Asset.WEAPON));
    }

    function getCommonLevels() public pure returns(TrainingLevel[16] memory){
        TrainingLevel[16] memory _levels;
        _levels[1] = TrainingLevel(0  , 331,  1, 15);          
        _levels[2] = TrainingLevel(332, 664,  2, 15);
        _levels[3] = TrainingLevel(665, 997,  3, 15);
        _levels[4] = TrainingLevel(998, 1330, 4, 15);
        _levels[5] = TrainingLevel(1331, 1663, 5, 15);
        _levels[6] = TrainingLevel(1664, 1996, 6, 15);
        _levels[7] = TrainingLevel(1997, 2329, 7, 15);
        _levels[8] = TrainingLevel(2330, 2662, 8, 15);
        _levels[9] = TrainingLevel(2663, 2995, 9, 15);
        _levels[10] = TrainingLevel(2996, 3328, 10, 15);
        _levels[11] = TrainingLevel(3329, 3661, 11, 15);
        _levels[12] = TrainingLevel(3662, 3994, 12, 15);
        _levels[13] = TrainingLevel(3995, 4327, 13, 15);
        _levels[14] = TrainingLevel(4328, 4660, 14, 15);
        _levels[15] = TrainingLevel(4661, 4993, 15, 15);
        return _levels;
    }

    function getLowRareLevels() public pure returns(TrainingLevel[16] memory){
        TrainingLevel[16] memory _levels;
        _levels[1] = TrainingLevel(4994, 5199, 16, 30);
        _levels[2] = TrainingLevel(5200, 5409, 17, 30);
        _levels[3] = TrainingLevel(5410, 5619, 18, 30);
        _levels[4] = TrainingLevel(5620, 5829, 19, 30);
        _levels[5] = TrainingLevel(5830, 6039, 20, 30);
        _levels[6] = TrainingLevel(6040, 6249, 21, 30);
        _levels[7] = TrainingLevel(6250, 6459, 22, 30);
        _levels[8] = TrainingLevel(6460, 6669, 23, 30);
        _levels[9] = TrainingLevel(6670, 6879, 24, 30);
        _levels[10] = TrainingLevel(6880, 7089, 25, 30);
        _levels[11] = TrainingLevel(7090, 7299, 26, 30);
        _levels[12] = TrainingLevel(7300, 7509, 27, 30);
        _levels[13] = TrainingLevel(7510, 7719, 28, 30);
        _levels[14] = TrainingLevel(7720, 7929, 29, 30);
        _levels[15] = TrainingLevel(7930, 8139, 30, 30);
        return _levels;
    }

    function getRareLevels() public pure returns(TrainingLevel[16] memory){
        TrainingLevel[16] memory _levels;
        _levels[1] = TrainingLevel(8140, 8225, 31, 35);
        _levels[2] = TrainingLevel(8226, 8324, 32, 35);
        _levels[3] = TrainingLevel(8325, 8423, 33, 35);
        _levels[4] = TrainingLevel(8424, 8522, 34, 35);
        _levels[5] = TrainingLevel(8523, 8621, 35, 35);
        _levels[6] = TrainingLevel(8622, 8720, 36, 35);
        _levels[7] = TrainingLevel(8721, 8819, 37, 35);
        _levels[8] = TrainingLevel(8820, 8918, 38, 35);
        _levels[9] = TrainingLevel(8919, 9017, 39, 35);
        _levels[10] = TrainingLevel(9018, 9116, 40, 35);
        _levels[11] = TrainingLevel(9117, 9215, 41, 35);
        _levels[12] = TrainingLevel(9216, 9314, 42, 35);
        _levels[13] = TrainingLevel(9315, 9413, 43, 35);
        _levels[14] = TrainingLevel(9414, 9512, 44, 35);
        _levels[15] = TrainingLevel(9513, 9611, 45, 35);
        return _levels;
    }

    function getEpicLevels() public pure returns(TrainingLevel[16] memory){
        TrainingLevel[16] memory _levels;
        _levels[1] = TrainingLevel(9612, 9631, 46, 40);
        _levels[2] = TrainingLevel(9632, 9654, 47, 40);
        _levels[3] = TrainingLevel(9655, 9677, 48, 40);
        _levels[4] = TrainingLevel(9678, 9700, 49, 40);
        _levels[5] = TrainingLevel(9701, 9723, 50, 40);
        _levels[6] = TrainingLevel(9724, 9746, 51, 40);
        _levels[7] = TrainingLevel(9747, 9769, 52, 40);
        _levels[8] = TrainingLevel(9770, 9792, 53, 40);
        _levels[9] = TrainingLevel(9793, 9815, 54, 40);
        _levels[10] = TrainingLevel(9816, 9838, 55, 40);
        _levels[11] = TrainingLevel(9839, 9861, 56, 40);
        _levels[12] = TrainingLevel(9862, 9884, 57, 40);
        _levels[13] = TrainingLevel(9885, 9907, 58, 40);
        _levels[14] = TrainingLevel(9908, 9930, 59, 40);
        _levels[15] = TrainingLevel(9931, 9953, 60, 40);
        return _levels;
    }

    function getLegendLevels() public pure returns(TrainingLevel[16] memory){
        TrainingLevel[16] memory _levels;
        _levels[1] = TrainingLevel(9954, 9956, 61, 70);
        _levels[2] = TrainingLevel(9957, 9958, 62, 70);
        _levels[3] = TrainingLevel(9959, 9960, 63, 70);
        _levels[4] = TrainingLevel(9961, 9962, 64, 70);
        _levels[5] = TrainingLevel(9963, 9964, 65, 70);
        _levels[6] = TrainingLevel(9965, 9966, 66, 70);
        _levels[7] = TrainingLevel(9967, 9968, 67, 70);
        _levels[8] = TrainingLevel(9969, 9970, 68, 70);
        _levels[9] = TrainingLevel(9971, 9972, 69, 70);
        _levels[10] = TrainingLevel(9973, 9974, 70, 70);
        _levels[11] = TrainingLevel(9975, 9976, 71, 70);
        _levels[12] = TrainingLevel(9977, 9978, 72, 70);
        _levels[13] = TrainingLevel(9979, 9980, 73, 70);
        _levels[14] = TrainingLevel(9981, 9982, 74, 70);
        _levels[15] = TrainingLevel(9983, 9984, 75, 70);
        return _levels;
    }

    function getMiticLevels() public pure returns(TrainingLevel[16] memory){
        TrainingLevel[16] memory _levels;
        _levels[1] = TrainingLevel(9985, 9985, 76, 120);
        _levels[2] = TrainingLevel(9986, 9986, 77, 120);
        _levels[3] = TrainingLevel(9987, 9987, 78, 120);
        _levels[4] = TrainingLevel(9988, 9988, 79, 120);
        _levels[5] = TrainingLevel(9989, 9989, 80, 120);
        _levels[6] = TrainingLevel(9990, 9990, 81, 120);
        _levels[7] = TrainingLevel(9991, 9991, 82, 120);
        _levels[8] = TrainingLevel(9992, 9992, 83, 120);
        _levels[9] = TrainingLevel(9993, 9993, 84, 120);
        _levels[10] = TrainingLevel(9994, 9994, 85, 120);
        _levels[11] = TrainingLevel(9995, 9995, 86, 120);
        _levels[12] = TrainingLevel(9996, 9996, 87, 120);
        _levels[13] = TrainingLevel(9997, 9997, 88, 120);
        _levels[14] = TrainingLevel(9998, 9998, 89, 120);
        _levels[15] = TrainingLevel(9999, 9999, 90, 120);
        return _levels;
    }
    
    function getLevels(Rarity memory _rarity) public pure returns(TrainingLevel[16] memory){
        if(strcmp(_rarity.rarity, "COMMON")){
            return getCommonLevels();
        }
        if(strcmp(_rarity.rarity, "LOW RARE")){
            return getLowRareLevels();
        }
        if(strcmp(_rarity.rarity, "RARE")){
            return getRareLevels();
        }
        if(strcmp(_rarity.rarity, "EPIC")){
            return getEpicLevels();
        }
        if(strcmp(_rarity.rarity, "LEGEND")){
            return getLegendLevels();
        }
        if(strcmp(_rarity.rarity, "MITIC")){
            return getMiticLevels();
        }
        TrainingLevel[16] memory _empty;
        return _empty;
    }

    function memcmp(bytes memory a, bytes memory b) internal pure returns(bool){
        return (a.length == b.length) && (keccak256(a) == keccak256(b));
    }
    
    function strcmp(string memory a, string memory b) internal pure returns(bool){
        return memcmp(bytes(a), bytes(b));
    }

    function getTrainingLevel(uint256 gen) public view returns(TrainingLevel memory){
        TrainingLevel memory trainingLevelSelected;
        Rarity memory rarity = getRarity(gen);
        for(uint256 i = 1; i <= 15; i++){
            TrainingLevel memory _trainingLevel = getLevels(rarity)[i];
             if(gen >= _trainingLevel.min && gen <= _trainingLevel.max){
                 trainingLevelSelected = _trainingLevel;
             }
        }
        return trainingLevelSelected;
    }

    function getRarity(uint256 gen) public view returns(Rarity memory){        
        Rarity memory r;        
        for(uint256 i = 0; i <= rarities.length - 1; i++){            
            Rarity memory _rarity = rarities[i];
            if(gen >= _rarity.min && gen <= _rarity.max){
                r = _rarity;
            }
        }
        return r;
    }
    
    function getAssetType(uint256 gen) public view returns(AssetType memory){
        AssetType memory assetType;        
        for(uint256 i = 0; i <= assetTypes.length - 1; i++){
            AssetType memory _assetType = assetTypes[i];
            if(gen >= _assetType.min && gen <= _assetType.max){
                assetType = _assetType;
            }
        }
        return assetType;
    }
    
    function deconstructGen(string calldata gen) public pure returns(DeconstructedGen memory){
        require(bytes(gen).length >= 12, "Gen length is not correctly");
        // Weapon or Character
        string memory _type   = slice(bytes(gen), bytes(gen).length - 2, 2);
        // Which weapon or which character
        string memory _asset  = slice(bytes(gen), bytes(gen).length - 4, 2);
        // Rarity
        string memory _rarity = slice(bytes(gen), bytes(gen).length - 8, 4);
        
        string memory _transferible   = slice(bytes(gen), bytes(gen).length - 12, 2);
        
        string memory _stat = slice(bytes(gen), bytes(gen).length - 14, 2);
        
        return DeconstructedGen(parseInt(_type), parseInt(_asset), parseInt(_rarity), parseInt(_stat), parseInt(_transferible));
    }

    function parseInt(string memory _a)
        public
        pure
        returns (uint) {
        bytes memory bresult = bytes(_a);
        uint mint = 0;
        bool decimals = false;
        for (uint i=0; i<bresult.length; i++){
            if ((uint8(bresult[i]) >= 48)&&(uint8(bresult[i]) <= 57)){                
                mint *= 10;
                mint += uint(uint8(bresult[i])) - 48;
            } else if (uint8(bresult[i]) == 46) decimals = true;
        }
        return mint;
    }
    
    function slice(
        bytes memory _bytes,
        uint256 _start,
        uint256 _length
        ) public pure returns (string memory){
        bytes memory tempBytes;
        assembly {
            switch iszero(_length)
            case 0 {
                // Get a location of some free memory and store it in tempBytes as
                // Solidity does for memory variables.
                tempBytes := mload(0x40)

                // The first word of the slice result is potentially a partial
                // word read from the original array. To read it, we calculate
                // the length of that partial word and start copying that many
                // bytes into the array. The first word we copy will start with
                // data we don't care about, but the last `lengthmod` bytes will
                // land at the beginning of the contents of the new array. When
                // we're done copying, we overwrite the full first word with
                // the actual length of the slice.
                let lengthmod := and(_length, 31)

                // The multiplication in the next line is necessary
                // because when slicing multiples of 32 bytes (lengthmod == 0)
                // the following copy loop was copying the origin's length
                // and then ending prematurely not copying everything it should.
                let mc := add(add(tempBytes, lengthmod), mul(0x20, iszero(lengthmod)))
                let end := add(mc, _length)

                for {
                    // The multiplication in the next line has the same exact purpose
                    // as the one above.
                    let cc := add(add(add(_bytes, lengthmod), mul(0x20, iszero(lengthmod))), _start)
                } lt(mc, end) {
                    mc := add(mc, 0x20)
                    cc := add(cc, 0x20)
                } {
                    mstore(mc, mload(cc))
                }

                mstore(tempBytes, _length)

                //update free-memory pointer
                //allocating the array padded to 32 bytes like the compiler does now
                mstore(0x40, and(add(mc, 31), not(31)))
            }
            //if we want a zero-length slice let's just return a zero-length array
            default {
                tempBytes := mload(0x40)
                //zero out the 32 bytes slice we are about to return
                //we need to do it because Solidity does not garbage collect
                mstore(tempBytes, 0)

                mstore(0x40, add(tempBytes, 0x20))
            }
        }

        return string(tempBytes);
    }

}

pragma solidity ^0.8.0;

contract IBattleHero{
    function transferFrom(
        address sender,
        address recipient,
        uint256 amount
    ) public virtual returns (bool) {}
    function balanceOf(address account) public view virtual returns (uint256) {}
    function allowance(address owner, address spender) public view virtual returns (uint256) {}
    function burn(uint256 amount) public virtual {}
    function burnFrom(address account, uint256 amount) public virtual {}
}

pragma solidity ^0.8.0;

import "./BattleHeroData.sol";

contract IBattleHeroBreeder{
    function breed(address to, string memory gen) public returns(uint)  {}
}

pragma solidity ^0.8.0;


contract IBattleHeroGenScience{
    enum Rarity{
        COMMON, 
        LOW_RARE, 
        RARE, 
        EPIC, 
        LEGEND,
        MITIC
    }
    function generateWeapon(Rarity _rarity) public returns (string memory){}
    function generateWeapon() public returns (string memory){}
    function generateCharacter(Rarity _rarity) public returns (string memory){}
    function generateCharacter() public returns (string memory){}
    function generate() public returns(string memory){}
    function generateIntransferibleWeapon(Rarity _rarity) public returns (string memory){}
    function generateIntransferibleCharacter(Rarity _rarity) public returns (string memory){}
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../utils/Context.sol";
import "../utils/Strings.sol";
import "../utils/introspection/ERC165.sol";

/**
 * @dev External interface of AccessControl declared to support ERC165 detection.
 */
interface IAccessControl {
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
abstract contract AccessControl is Context, IAccessControl, ERC165 {
    struct RoleData {
        mapping(address => bool) members;
        bytes32 adminRole;
    }

    mapping(bytes32 => RoleData) private _roles;

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
        return interfaceId == type(IAccessControl).interfaceId || super.supportsInterface(interfaceId);
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
        if (!hasRole(role, account)) {
            revert(
                string(
                    abi.encodePacked(
                        "AccessControl: account ",
                        Strings.toHexString(uint160(account), 20),
                        " is missing role ",
                        Strings.toHexString(uint256(role), 32)
                    )
                )
            );
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
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./AccessControl.sol";
import "../utils/structs/EnumerableSet.sol";

/**
 * @dev External interface of AccessControlEnumerable declared to support ERC165 detection.
 */
interface IAccessControlEnumerable {
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);

    function getRoleMemberCount(bytes32 role) external view returns (uint256);
}

/**
 * @dev Extension of {AccessControl} that allows enumerating the members of each role.
 */
abstract contract AccessControlEnumerable is IAccessControlEnumerable, AccessControl {
    using EnumerableSet for EnumerableSet.AddressSet;

    mapping(bytes32 => EnumerableSet.AddressSet) private _roleMembers;

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IAccessControlEnumerable).interfaceId || super.supportsInterface(interfaceId);
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
 * @dev String operations.
 */
library Strings {
    bytes16 private constant _HEX_SYMBOLS = "0123456789abcdef";

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
            buffer[i] = _HEX_SYMBOLS[value & 0xf];
            value >>= 4;
        }
        require(value == 0, "Strings: hex length insufficient");
        return string(buffer);
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC165.sol";

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
abstract contract ERC165 is IERC165 {
    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override returns (bool) {
        return interfaceId == type(IERC165).interfaceId;
    }
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
interface IERC165 {
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
    function sub(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b <= a, errorMessage);
            return a - b;
        }
    }

    /**
     * @dev Returns the integer division of two unsigned integers, reverting with custom message on
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
    function div(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
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
    function mod(
        uint256 a,
        uint256 b,
        string memory errorMessage
    ) internal pure returns (uint256) {
        unchecked {
            require(b > 0, errorMessage);
            return a % b;
        }
    }
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
library EnumerableSet {
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
        mapping(bytes32 => uint256) _indexes;
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

        if (valueIndex != 0) {
            // Equivalent to contains(set, value)
            // To delete an element from the _values array in O(1), we swap the element to delete with the last one in
            // the array, and then remove the last element (sometimes called as 'swap and pop').
            // This modifies the order of the array, as noted in {at}.

            uint256 toDeleteIndex = valueIndex - 1;
            uint256 lastIndex = set._values.length - 1;

            if (lastIndex != toDeleteIndex) {
                bytes32 lastvalue = set._values[lastIndex];

                // Move the last value to the index where the value to delete is
                set._values[toDeleteIndex] = lastvalue;
                // Update the index for the moved value
                set._indexes[lastvalue] = valueIndex; // Replace lastvalue's index to valueIndex
            }

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