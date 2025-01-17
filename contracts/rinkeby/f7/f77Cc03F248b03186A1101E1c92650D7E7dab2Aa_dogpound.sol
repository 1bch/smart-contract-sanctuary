pragma solidity ^0.8.0;

import "@openzeppelin/contracts/access/Ownable.sol";



interface iFeed {
    function feed (uint256) external ;
    function BattleAttack (uint256) external returns(uint256) ;
     function Attack (uint256, uint256) external returns(uint256) ;
     function _levelUp(uint256) external;
     function _levelDown(uint256) external;
     function ownerOf(uint256) external;
     function AFighter ( address addr, uint256 _tokenId) external returns (uint256);
     function getStrength (uint256) external returns (uint256);
     function getDogeOwner(uint256 tokenId) external returns(address);
}

contract dogpound{


    event GameCreated(address player, uint256 tokenId, uint256 _tokenId);
    event GameJoined(uint256 index, address player);
    event GameResult(uint256 index, address winner, uint256 amount);
    event NewDoge (string name);
    event Transfer (address to, uint256 amount, uint256 balance);

    address public addy;
    address private addr;
    address public Owner = msg.sender;
    mapping(address => uint256) public DogeFighter;
    address fighterAddy;
    uint256 _num;
    uint256 equationResult;
    uint256 public g;

    uint256 index;
    mapping(uint256 => Game) gameIndex;
    mapping(bytes32 => Game) requestIndex;

    struct Game {
        uint256 index;
        uint256 player1;
        uint256 player2;
        uint256 amount;
        address winner;
       uint256 blockstamp;
        
    }
    
    

    modifier onlyOwner(){
        require(msg.sender == Owner);
        _;
    }
    
    function feed(uint256 _tokenId) external payable {
        iFeed(addy).feed(_tokenId);
    
    
    }

    function withdraw() public payable onlyOwner{
       require (payable(msg.sender).send(address(this).balance));
   }

   function setAddy(address _addy)public onlyOwner returns(address){
           addy = _addy;
           return addy;


   }

   function BattleAttack(uint256 _tokenId) external {
       iFeed(addy).BattleAttack(_tokenId);

   }

   function Attack(uint256 tokenId, uint256 _tokenId) external{
       iFeed(addy).Attack(tokenId , _tokenId);
   }

    function AFighter (uint256 _tokenId) public {
        iFeed(addy).AFighter(msg.sender,_tokenId);
      

   }

   function Battle (uint256 tokenId, uint256 _tokenId) public returns (address _winner){
       uint256 a = iFeed(addy).getStrength(tokenId);
       uint256 b = iFeed(addy).getStrength(_tokenId);
       uint256 c = a + b ;

        bytes32 predictableRandom = keccak256(abi.encodePacked( blockhash(block.number-1), msg.sender, address(this) ));
           //bytes2 equation = bytes2(predictableRandom[0]) | ( bytes2(predictableRandom[1]) >> 8 ) | ( bytes2(predictableRandom[2]) >> 16 );
        uint256 base = 35+((55*uint256(uint8(predictableRandom[3])))/255);



       _num = 100+((55*uint256(uint8(predictableRandom[3])))/255) / 2;

       equationResult = ((_num +block.timestamp * base) % base);
       g =  equationResult % 3;

       if (((a % g)/c) > ((b % g)/c)){
            iFeed(addy)._levelUp(tokenId);
            iFeed(addy)._levelDown(_tokenId);
            _winner = iFeed(addy).getDogeOwner(tokenId);
          }

          else{
              iFeed(addy)._levelUp(_tokenId);
              iFeed(addy)._levelDown(tokenId);
              _winner = iFeed(addy).getDogeOwner(_tokenId);
          }

        Game memory newGame = Game(index, tokenId, _tokenId, _num, _winner, block.timestamp);
        gameIndex[index] = newGame;
        //index += 1;

        emit GameCreated(msg.sender, tokenId, _tokenId);

       return(_winner);
   } 
   
   function get_game_info(uint256 _index) external view returns(uint256 _i, uint256 tokenId, uint256 _tokenId, uint256 _number, address _winner, uint256 blockstamp) {
       
        Game memory game = gameIndex[_index];
        return (_index, game.player1, game.player2, game.amount, game.winner, block.timestamp);
    }

   

   
    
    
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
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

{
  "remappings": [],
  "optimizer": {
    "enabled": false,
    "runs": 200
  },
  "evmVersion": "london",
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