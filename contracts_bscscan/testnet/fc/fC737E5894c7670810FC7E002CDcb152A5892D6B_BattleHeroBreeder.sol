// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

abstract contract Context {
    function _msgSender() internal view virtual returns (address) {
        return msg.sender;
    }

    function _msgData() internal view virtual returns (bytes calldata) {
        return msg.data;
    }
}
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
contract ERC721Factory{
    function mint(address to, bytes32 genes) public virtual {}
    function balanceOf(address owner) public view virtual returns (uint256) {}
}
contract ERC20{
    function transferFrom(address from, address buyer, uint256 numTokens) public returns (bool) {}
    function balanceOf(address tokenOwner) public view returns (uint256) {}
    function burn(uint256 _value) public{}
    function allowance(address from, address delegate) public view returns (uint) {}
}
contract BattleHeroBreeder is Ownable {

    address public bhfAddress;
    address public bhAddress;

    ERC721Factory _bhf;
    ERC20 _bh;

    enum ChestType{WEAPON, CHARACTER, MIX}
    
    int _weapon    = 0x0;
    int _character = 0x1;




    struct Chest{
        uint blockUnlock;
        uint when;
        bool opened;
        ChestType chestType;
        uint256 contentGenetic;
    }

    uint8 public constant decimals                 = 18;
    uint256 public constant TOKEN_ESCALE           = 1 * 10 ** uint256(decimals);

    uint256 CHARACTER_CHEST_PRICE                  = 2;
    uint256 WEAPON_CHEST_PRICE                     = 2;
    uint256 MIX_CHEST_PRICE                        = 3;

    mapping(address => Chest[]) _chests;
    mapping(ChestType => uint256) public chestPrices;

    constructor() {
        chestPrices[ChestType.CHARACTER] = CHARACTER_CHEST_PRICE;
        chestPrices[ChestType.WEAPON]    = WEAPON_CHEST_PRICE;
        chestPrices[ChestType.MIX]       = MIX_CHEST_PRICE;
    }
    function getChestPrice(ChestType chestType) public view returns(uint256){
        return chestPrices[chestType];
    }
    function setFactoryContract(address factoryContract) public onlyOwner { 
        bhfAddress = factoryContract;
        _bhf = ERC721Factory(bhfAddress);                
    }

    function setTokenContract(address tokenContract) public onlyOwner{
        bhAddress = tokenContract;
        _bh = ERC20(bhAddress);
    }

    function tokenBalance(address ownerToken) public view returns(uint256){
        return _bh.balanceOf(ownerToken);
    }

    function generateWeaponGenetic(uint blockBreed) public view returns(uint256) {
        return uint256(keccak256(abi.encodePacked(_weapon, blockhash(blockBreed), blockhash(block.number))));        
    }

    function generateCharacterGenetic(uint blockBreed) public view returns(uint256) {
        return uint256(keccak256(abi.encodePacked(_character, blockhash(blockBreed), blockhash(block.number))));        
    }    

    function generateRandomGenetic() public view returns(uint256){
        return uint256(keccak256(abi.encodePacked(blockhash(block.number - 120), blockhash(block.number))));        
    }

    function mintNFT(uint256 gen) internal returns(bool) {
        (bool success, bytes memory result) = address(bhfAddress).call{gas: 900000}(abi.encodeWithSignature("mint(address,uint256)", msg.sender, gen));
        return success;
    }    

    function hasSuficientTokens(address _owner, ChestType _type) public view returns(bool){
        return _bh.balanceOf(_owner) >= chestPrices[_type];
    }

    function hasSuficientAllowance(address _owner, ChestType _type) public view returns(bool){
        uint allowance = _bh.allowance(_owner, address(this));
        return allowance >= chestPrices[_type];    
    }

    function hasAllowance(address _owner) public view returns(bool){
        uint allowance = _bh.allowance(_owner, address(this));
        return allowance > 0;
    }

    function buyChest(ChestType chestType) public{
        // require(hasSuficientAllowance(msg.sender, chestType) == true);
        _chests[msg.sender].push(Chest(
            block.number + 5, 
            block.timestamp,
            false, 
            chestType, 
            0x0
        ));        
        (bool success, bytes memory result) = address(bhAddress).call{gas: 900000}(abi.encodeWithSignature("burnFrom(address, uint256)", msg.sender, chestPrices[chestType]));
        string memory str = string(abi.encodePacked(result));
        require(success == true, str);
    }

    function openChest(uint chestIndex) public{        
        Chest memory chest = _chests[msg.sender][chestIndex];
        require(chest.contentGenetic == 0x0);
        chest.contentGenetic = chest.chestType == ChestType.CHARACTER ? generateCharacterGenetic(chest.blockUnlock) : generateWeaponGenetic(chest.blockUnlock);                
        require(chest.opened == false);
        mintNFT(chest.contentGenetic);
        chest.opened = true;
        _chests[msg.sender][chestIndex] = chest;
        require(_chests[msg.sender][chestIndex].opened == true);
    }
    
    function mintRandom() public onlyOwner{
        uint256 randomGen = generateRandomGenetic();
        mintNFT(randomGen);
    }   

    function getChests(address _owner) public view returns(uint[] memory , uint[] memory , bool[] memory, ChestType[] memory, uint256[] memory){
        uint length = _chests[_owner].length;                                             //Length of array        
        uint[] memory blockUnlock       = new uint[](length);
        uint[] memory when              = new uint[](length);
        bool[] memory opened            = new bool[](length);
        ChestType[] memory chestType    = new ChestType[](length);
        uint256[] memory contentGenetic = new uint256[](length);
        for(uint i = 0; i < length; i++){                        
            blockUnlock[i]    = _chests[_owner][i].blockUnlock;
            when[i]           = _chests[_owner][i].when;
            opened[i]         = _chests[_owner][i].opened;
            chestType[i]      = _chests[_owner][i].chestType;
            contentGenetic[i] = _chests[_owner][i].contentGenetic;            
        }
        return (blockUnlock , when , opened, chestType, contentGenetic);        
    }
}

{
  "remappings": [],
  "optimizer": {
    "enabled": false,
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