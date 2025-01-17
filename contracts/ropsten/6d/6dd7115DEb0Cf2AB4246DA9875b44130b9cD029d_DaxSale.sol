/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {

  /**
  * @dev Multiplies two numbers, throws on overflow.
  */
  function mul(uint256 a, uint256 b) internal pure returns (uint256 c) {
    // Gas optimization: this is cheaper than asserting &#39;a&#39; not being zero, but the
    // benefit is lost if &#39;b&#39; is also tested.
    // See: https://github.com/OpenZeppelin/openzeppelin-solidity/pull/522
    if (a == 0) {
      return 0;
    }

    c = a * b;
    assert(c / a == b);
    return c;
  }

  /**
  * @dev Integer division of two numbers, truncating the quotient.
  */
  function div(uint256 a, uint256 b) internal pure returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    // uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn&#39;t hold
    return a / b;
  }

  /**
  * @dev Subtracts two numbers, throws on overflow (i.e. if subtrahend is greater than minuend).
  */
  function sub(uint256 a, uint256 b) internal pure returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  /**
  * @dev Adds two numbers, throws on overflow.
  */
  function add(uint256 a, uint256 b) internal pure returns (uint256 c) {
    c = a + b;
    assert(c >= a);
    return c;
  }
}


/**
 * @title ERC20Basic
 * @dev Simpler version of ERC20 interface
 * See https://github.com/ethereum/EIPs/issues/179
 */
contract ERC20Basic {
  function totalSupply() public view returns (uint256);
  function balanceOf(address who) public view returns (uint256);
  function transfer(address to, uint256 value) public returns (bool);
  event Transfer(address indexed from, address indexed to, uint256 value);
}


/**
 * @title Basic token
 * @dev Basic version of StandardToken, with no allowances.
 */
contract BasicToken is ERC20Basic {
  using SafeMath for uint256;

  mapping(address => uint256) balances;

  uint256 public totalSupply_;

  /**
  * @dev Total number of tokens in existence
  */
  function totalSupply() public view returns (uint256) {
    return totalSupply_;
  }

  /**
  * @dev Transfer token for a specified address
  * @param _to The address to transfer to.
  * @param _value The amount to be transferred.
  */
  function transfer(address _to, uint256 _value) public returns (bool) {
    require(_value <= balances[msg.sender]);
    require(_to != address(0));

    balances[msg.sender] = balances[msg.sender].sub(_value);
    balances[_to] = balances[_to].add(_value);
    emit Transfer(msg.sender, _to, _value);
    return true;
  }

  /**
  * @dev Gets the balance of the specified address.
  * @param _owner The address to query the the balance of.
  * @return An uint256 representing the amount owned by the passed address.
  */
  function balanceOf(address _owner) public view returns (uint256) {
    return balances[_owner];
  }

}



/**
 * @title ERC20 interface
 * @dev see https://github.com/ethereum/EIPs/issues/20
 */
contract ERC20 is ERC20Basic {


  function allowance(address owner, address spender)
  public view returns (uint256);

  function transferFrom(address from, address to, uint256 value)
  public returns (bool);

  function approve(address spender, uint256 value) public returns (bool);
  event Approval(
    address indexed owner,
    address indexed spender,
    uint256 value
  );
}

/**
 * @title Standard ERC20 token
 *
 * @dev Implementation of the basic standard token.
 * https://github.com/ethereum/EIPs/issues/20
 * Based on code by FirstBlood: https://github.com/Firstbloodio/token/blob/master/smart_contract/FirstBloodToken.sol
 */
contract StandardToken is ERC20, BasicToken {


  mapping (address => uint256) balances;
  /**
  *burning balances for return btc, save amount satoshi
  */
  mapping (address => uint256) public burn_balances_btc;


  mapping (address => mapping (address => uint256)) internal allowed;


 

  /**
   * @dev Transfer tokens from one address to another
   * @param _from address The address which you want to send tokens from
   * @param _to address The address which you want to transfer to
   * @param _value uint256 the amount of tokens to be transferred
   */
  function transferFrom(
    address _from,
    address _to,
    uint256 _value
  )
    public
    returns (bool)
  {
    require(_value <= balances[_from]);
    require(_value <= allowed[_from][msg.sender]);
    require(_to != address(0));

    balances[_from] = balances[_from].sub(_value);
    balances[_to] = balances[_to].add(_value);
    allowed[_from][msg.sender] = allowed[_from][msg.sender].sub(_value);
    emit Transfer(_from, _to, _value);
    return true;
  }

  
  /**
  * @dev Transfer token for a specified address
  * @param to The address to transfer to.
  * @param value The amount to be transferred.
  */
  function transfer(address to, uint256 value) public returns (bool) {
    require(value <= balances[msg.sender]);
    require(to != address(0));

    balances[msg.sender] = balances[msg.sender].sub(value);
    balances[to] = balances[to].add(value);
    emit Transfer(msg.sender, to, value);
    return true;
  }

  /**
   * @dev Approve the passed address to spend the specified amount of tokens on behalf of msg.sender.
   * Beware that changing an allowance with this method brings the risk that someone may use both the old
   * and the new allowance by unfortunate transaction ordering. One possible solution to mitigate this
   * race condition is to first reduce the spender&#39;s allowance to 0 and set the desired value afterwards:
   * https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
   * @param _spender The address which will spend the funds.
   * @param _value The amount of tokens to be spent.
   */
  function approve(address _spender, uint256 _value) public returns (bool) {
    allowed[msg.sender][_spender] = _value;
    emit Approval(msg.sender, _spender, _value);
    return true;
  }

  /**
   * @dev Function to check the amount of tokens that an owner allowed to a spender.
   * @param _owner address The address which owns the funds.
   * @param _spender address The address which will spend the funds.
   * @return A uint256 specifying the amount of tokens still available for the spender.
   */
  function allowance(
    address _owner,
    address _spender
  )
    public
    view
    returns (uint256)
  {
    return allowed[_owner][_spender];
  }

  /**
   * @dev Increase the amount of tokens that an owner allowed to a spender.
   * approve should be called when allowed[_spender] == 0. To increment
   * allowed value is better to use this function to avoid 2 calls (and wait until
   * the first transaction is mined)
   * From MonolithDAO Token.sol
   * @param _spender The address which will spend the funds.
   * @param _addedValue The amount of tokens to increase the allowance by.
   */
  function increaseApproval(
    address _spender,
    uint256 _addedValue
  )
    public
    returns (bool)
  {
    allowed[msg.sender][_spender] = (
    allowed[msg.sender][_spender].add(_addedValue));
    emit Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
    return true;
  }

  /**
   * @dev Decrease the amount of tokens that an owner allowed to a spender.
   * approve should be called when allowed[_spender] == 0. To decrement
   * allowed value is better to use this function to avoid 2 calls (and wait until
   * the first transaction is mined)
   * From MonolithDAO Token.sol
   * @param _spender The address which will spend the funds.
   * @param _subtractedValue The amount of tokens to decrease the allowance by.
   */
  function decreaseApproval(
    address _spender,
    uint256 _subtractedValue
  )
    public
    returns (bool)
  {
    uint256 oldValue = allowed[msg.sender][_spender];
    if (_subtractedValue >= oldValue) {
      allowed[msg.sender][_spender] = 0;
    } else {
      allowed[msg.sender][_spender] = oldValue.sub(_subtractedValue);
    }
    emit Approval(msg.sender, _spender, allowed[msg.sender][_spender]);
    return true;
  }

   /**
   * @dev Gets the balance of the specified address.
   * @param _owner The address to query the the balance of.
   * @return An uint256 representing the amount owned by the passed address.
   */
  function balanceOf(address _owner) public constant returns (uint256 balance) {
    return balances[_owner];
  }

}

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {
  address public owner;


  event OwnershipTransferred(
    address indexed previousOwner,
    address indexed newOwner
  );


  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender
   * account.
   */
  constructor() public {
    owner = msg.sender;
  }

  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }

  /**
   * @dev Allows the current owner to transfer control of the contract to a newOwner.
   * @param _newOwner The address to transfer ownership to.
   */
  function transferOwnership(address _newOwner) public onlyOwner {
    _transferOwnership(_newOwner);
  }

  /**
   * @dev Transfers control of the contract to a newOwner.
   * @param _newOwner The address to transfer ownership to.
   */
  function _transferOwnership(address _newOwner) internal {
    require(_newOwner != address(0));
    emit OwnershipTransferred(owner, _newOwner);
    owner = _newOwner;
  }
}


/**
 * @title Mintable token
 * @dev Simple ERC20 Token example, with mintable token creation
 * Based on code by TokenMarketNet: https://github.com/TokenMarketNet/ico/blob/master/contracts/MintableToken.sol
 */
contract MintableToken is StandardToken, Ownable {
  event Mint(address indexed to, uint256 amount);
  event Burn(address indexed burner, uint256 value);
  event MintFinished();

  bool public mintingFinished = false;


  modifier canMint() {
    require(!mintingFinished);
    _;
  }

  modifier hasMintPermission() {
    require(msg.sender == owner);
    _;
  }

  /**
   * @dev Function to mint tokens
   * @param _to The address that will receive the minted tokens.
   * @param _amount The amount of tokens to mint.
   * @return A boolean that indicates if the operation was successful.
   */
  function mint(
    address _to,
    uint256 _amount
  )
    public
    hasMintPermission
    canMint
    returns (bool)
  {
    totalSupply_ = totalSupply_.add(_amount);
    balances[_to] = balances[_to].add(_amount);
    emit Mint(_to, _amount);
    emit Transfer(address(0), _to, _amount);
    return true;
  }

  /**
   * @dev Burns a specific amount of tokens.
   * @param _addr The address that will have _amount of tokens burned
   * @param _value The amount of token to be burned.
   */
  function burn(
    address _addr,
    uint256 _value
  )
    public onlyOwner
  {
    _burn(_addr, _value);
  }

  function _burn(
    address _who,
    uint256 _value
  )
    internal
  {
    require(_value <= balances[_who]);
    // no need to require value <= totalSupply, since that would imply the
    // sender&#39;s balance is greater than the totalSupply, which *should* be an assertion failure

    balances[_who] = balances[_who].sub(_value);
    totalSupply_ = totalSupply_.sub(_value);
    emit Burn(_who, _value);
    emit Transfer(_who, address(0), _value);
  }

  /**
   * @dev Function to stop minting new tokens.
   * @return True if the operation was successful.
   */
  function finishMinting() public onlyOwner canMint returns (bool) {
    mintingFinished = true;
    emit MintFinished();
    return true;
  }
}

contract DaxToken is MintableToken {

    string public constant name = &#39;Dax&#39;;

    string public constant symbol = &#39;DAX&#39;;

    uint32 public constant decimals = 18;

  function addSupply(uint256 _supply) external onlyOwner returns (bool){
       totalSupply_ =totalSupply_.add(_supply);
       balances[owner] = balances[owner].add(_supply);
      return true;
  }

  function saveReturnSatoshi( address _addr,uint256 _satoshi) external onlyOwner returns (bool){
      require(_addr != address(0));
      require(_satoshi>0);
      burn_balances_btc[_addr] = burn_balances_btc[_addr].add(_satoshi);
      return true;
  }
  
}


contract DaxSale is Ownable {

    using SafeMath for uint;

    /**
     *  how many {tokens*10^(-18)} get per 1wei
     */
    uint public DaxInBtcSatoshi = 10 ** 7;
    /**
     *  multiplicator for rate
     */
    uint public DaxInUsd = 10 ** 7;


    uint public Capitalization = 0;




    // reference to DAX token contract
    DaxToken private daxToken;


    /**
     * @dev The Referral constructor to set up the first depositer,
     * reference to system wbt token, dax token, data and set ethUsdRate
     */
    constructor(
        address _daxToken
    )
        public
    {
        daxToken = DaxToken(_daxToken);
    }

    /**
     * @dev Callback function
     */
    function() payable public {

    }


    /**
     * @dev Withdraw corresponding amount of ETH to _addr and burn _value tokens
     * @param _addr buyer address
     * @param _amount amount of tokens to buy
     */
    function transferDaxsToken(
        address _addr,
        uint _amount
    )
        onlyOwner public
    {
        require(daxToken.balanceOf(this) >= _amount);
        daxToken.transfer(_addr, _amount);
    }


  

    /**
     * @dev Transfer ownership of wbtToken contract to _addr
     * @param _addr address
     */
    function transferTokenOwnership(
        address _addr
    )
        onlyOwner public
    {
        daxToken.transferOwnership(_addr);
    }


  function emission(address _to, uint256 _value, bytes32 _transactionHash, uint256 _typeNet) external onlyOwner returns (bool) {
    require(_to != address(0));
    require(_value>0);
    DaxToken(daxToken).mint(_to, _value*(10**10));
    return true;
  }


 function emissionMas(address[] _adresses_to, uint256[] _values, bytes32[] _transactionHashes, uint256[] _typeNetes) external onlyOwner returns (bool) {
   
   require( _adresses_to.length ==  _values.length);
   require( _values.length ==  _transactionHashes.length);
   require( _transactionHashes.length ==  _typeNetes.length);
   
   for(uint i =0;i< _adresses_to.length;i++){
        require(_adresses_to[i] != address(0));
        require(_values[i]>0);
   }
   for (uint i2 = 0; i2 < _adresses_to.length; i2++) {
       DaxToken(daxToken).mint(_adresses_to[i2], _values[i2]*(10**10));
   }
   return true;
  }

 function emissionMasOneType(address[] _adresses_to, uint256[] _values, bytes32[] _transactionHashes, uint256 _typeNetes) external onlyOwner returns (bool) {
      
   require( _adresses_to.length ==  _values.length);
   require( _values.length ==  _transactionHashes.length);
      
   for(uint i =0;i< _adresses_to.length;i++){
        require(_adresses_to[i] != address(0));
        require(_values[i]>0);
   }

   for (uint i2 = 0; i2 < _adresses_to.length; i2++) {
       DaxToken(daxToken).mint(_adresses_to[i2], _values[i2]*(10**10));
   }
   return true;
  }




    function setDaxInBtcSatoshi(uint _daxInBtcSatoshi) onlyOwner public returns (bool) {
        require(_daxInBtcSatoshi>0);
        DaxInBtcSatoshi = _daxInBtcSatoshi;
    }

    function setCapitalization(uint _capitalization) onlyOwner public {
        require( _capitalization>0);
        DaxInUsd = (_capitalization*10**18)/uint(DaxToken(daxToken).totalSupply());
        Capitalization = _capitalization;
    }

      function burn(address _to, uint256 _value,uint _daxInBtcSatoshi) onlyOwner public returns (bool) {
        require(_to != address(0));
        require(_value>0);
        require(_daxInBtcSatoshi>0);
        DaxInBtcSatoshi = _daxInBtcSatoshi;
        _value=_value*(10**10);
        uint value_Satoshi =(uint(_value)*DaxInBtcSatoshi)/((10**18));

        DaxToken(daxToken).burn(_to, _value);
        DaxToken(daxToken).saveReturnSatoshi(_to, value_Satoshi);
        return true;
    }

    function burnMas(address[] _adresses_to, uint256[] _values,uint _daxInBtcSatoshi) onlyOwner public returns (bool) {
        require( _adresses_to.length ==  _values.length);
        require(_daxInBtcSatoshi>0);
        DaxInBtcSatoshi = _daxInBtcSatoshi;
        for(uint i =0;i< _adresses_to.length;i++){
            require(_adresses_to[i] != address(0));
            require(_values[i]>0);
        }

        for(uint i2 =0;i2< _adresses_to.length;i2++){
            _values[i2]=_values[i2]*(10**10);
            uint value_Satoshi =(uint(_values[i2])*DaxInBtcSatoshi)/((10**18));

            DaxToken(daxToken).burn(_adresses_to[i2], _values[i2]);
            DaxToken(daxToken).saveReturnSatoshi(_adresses_to[i2], value_Satoshi);
        }
        return true;
    }
}