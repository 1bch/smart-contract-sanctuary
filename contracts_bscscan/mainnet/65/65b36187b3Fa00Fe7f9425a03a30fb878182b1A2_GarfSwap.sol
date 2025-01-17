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

    constructor () {
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
        uint256 newAllowance = token.allowance(address(this), spender) + value;
        _callOptionalReturn(token, abi.encodeWithSelector(token.approve.selector, spender, newAllowance));
    }

    function safeDecreaseAllowance(IERC20 token, address spender, uint256 value) internal {
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
        if (returndata.length > 0) { // Return data is optional
            // solhint-disable-next-line max-line-length
            require(abi.decode(returndata, (bool)), "SafeERC20: ERC20 operation did not succeed");
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "./IERC721.sol";
import "./IERC721Receiver.sol";
import "./extensions/IERC721Metadata.sol";
import "../../utils/Address.sol";
import "../../utils/Context.sol";
import "../../utils/Strings.sol";
import "../../utils/introspection/ERC165.sol";

/**
 * @dev Implementation of https://eips.ethereum.org/EIPS/eip-721[ERC721] Non-Fungible Token Standard, including
 * the Metadata extension, but not including the Enumerable extension, which is available separately as
 * {ERC721Enumerable}.
 */
contract ERC721 is Context, ERC165, IERC721, IERC721Metadata {
    using Address for address;
    using Strings for uint256;

    // Token name
    string private _name;

    // Token symbol
    string private _symbol;

    // Mapping from token ID to owner address
    mapping (uint256 => address) private _owners;

    // Mapping owner address to token count
    mapping (address => uint256) private _balances;

    // Mapping from token ID to approved address
    mapping (uint256 => address) private _tokenApprovals;

    // Mapping from owner to operator approvals
    mapping (address => mapping (address => bool)) private _operatorApprovals;

    /**
     * @dev Initializes the contract by setting a `name` and a `symbol` to the token collection.
     */
    constructor (string memory name_, string memory symbol_) {
        _name = name_;
        _symbol = symbol_;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(bytes4 interfaceId) public view virtual override(ERC165, IERC165) returns (bool) {
        return interfaceId == type(IERC721).interfaceId
            || interfaceId == type(IERC721Metadata).interfaceId
            || super.supportsInterface(interfaceId);
    }

    /**
     * @dev See {IERC721-balanceOf}.
     */
    function balanceOf(address owner) public view virtual override returns (uint256) {
        require(owner != address(0), "ERC721: balance query for the zero address");
        return _balances[owner];
    }

    /**
     * @dev See {IERC721-ownerOf}.
     */
    function ownerOf(uint256 tokenId) public view virtual override returns (address) {
        address owner = _owners[tokenId];
        require(owner != address(0), "ERC721: owner query for nonexistent token");
        return owner;
    }

    /**
     * @dev See {IERC721Metadata-name}.
     */
    function name() public view virtual override returns (string memory) {
        return _name;
    }

    /**
     * @dev See {IERC721Metadata-symbol}.
     */
    function symbol() public view virtual override returns (string memory) {
        return _symbol;
    }

    /**
     * @dev See {IERC721Metadata-tokenURI}.
     */
    function tokenURI(uint256 tokenId) public view virtual override returns (string memory) {
        require(_exists(tokenId), "ERC721Metadata: URI query for nonexistent token");

        string memory baseURI = _baseURI();
        return bytes(baseURI).length > 0
            ? string(abi.encodePacked(baseURI, tokenId.toString()))
            : '';
    }

    /**
     * @dev Base URI for computing {tokenURI}. Empty by default, can be overriden
     * in child contracts.
     */
    function _baseURI() internal view virtual returns (string memory) {
        return "";
    }

    /**
     * @dev See {IERC721-approve}.
     */
    function approve(address to, uint256 tokenId) public virtual override {
        address owner = ERC721.ownerOf(tokenId);
        require(to != owner, "ERC721: approval to current owner");

        require(_msgSender() == owner || isApprovedForAll(owner, _msgSender()),
            "ERC721: approve caller is not owner nor approved for all"
        );

        _approve(to, tokenId);
    }

    /**
     * @dev See {IERC721-getApproved}.
     */
    function getApproved(uint256 tokenId) public view virtual override returns (address) {
        require(_exists(tokenId), "ERC721: approved query for nonexistent token");

        return _tokenApprovals[tokenId];
    }

    /**
     * @dev See {IERC721-setApprovalForAll}.
     */
    function setApprovalForAll(address operator, bool approved) public virtual override {
        require(operator != _msgSender(), "ERC721: approve to caller");

        _operatorApprovals[_msgSender()][operator] = approved;
        emit ApprovalForAll(_msgSender(), operator, approved);
    }

    /**
     * @dev See {IERC721-isApprovedForAll}.
     */
    function isApprovedForAll(address owner, address operator) public view virtual override returns (bool) {
        return _operatorApprovals[owner][operator];
    }

    /**
     * @dev See {IERC721-transferFrom}.
     */
    function transferFrom(address from, address to, uint256 tokenId) public virtual override {
        //solhint-disable-next-line max-line-length
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");

        _transfer(from, to, tokenId);
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) public virtual override {
        safeTransferFrom(from, to, tokenId, "");
    }

    /**
     * @dev See {IERC721-safeTransferFrom}.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes memory _data) public virtual override {
        require(_isApprovedOrOwner(_msgSender(), tokenId), "ERC721: transfer caller is not owner nor approved");
        _safeTransfer(from, to, tokenId, _data);
    }

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * `_data` is additional data, it has no specified format and it is sent in call to `to`.
     *
     * This internal function is equivalent to {safeTransferFrom}, and can be used to e.g.
     * implement alternative mechanisms to perform token transfer, such as signature-based.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeTransfer(address from, address to, uint256 tokenId, bytes memory _data) internal virtual {
        _transfer(from, to, tokenId);
        require(_checkOnERC721Received(from, to, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    /**
     * @dev Returns whether `tokenId` exists.
     *
     * Tokens can be managed by their owner or approved accounts via {approve} or {setApprovalForAll}.
     *
     * Tokens start existing when they are minted (`_mint`),
     * and stop existing when they are burned (`_burn`).
     */
    function _exists(uint256 tokenId) internal view virtual returns (bool) {
        return _owners[tokenId] != address(0);
    }

    /**
     * @dev Returns whether `spender` is allowed to manage `tokenId`.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function _isApprovedOrOwner(address spender, uint256 tokenId) internal view virtual returns (bool) {
        require(_exists(tokenId), "ERC721: operator query for nonexistent token");
        address owner = ERC721.ownerOf(tokenId);
        return (spender == owner || getApproved(tokenId) == spender || isApprovedForAll(owner, spender));
    }

    /**
     * @dev Safely mints `tokenId` and transfers it to `to`.
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function _safeMint(address to, uint256 tokenId) internal virtual {
        _safeMint(to, tokenId, "");
    }

    /**
     * @dev Same as {xref-ERC721-_safeMint-address-uint256-}[`_safeMint`], with an additional `data` parameter which is
     * forwarded in {IERC721Receiver-onERC721Received} to contract recipients.
     */
    function _safeMint(address to, uint256 tokenId, bytes memory _data) internal virtual {
        _mint(to, tokenId);
        require(_checkOnERC721Received(address(0), to, tokenId, _data), "ERC721: transfer to non ERC721Receiver implementer");
    }

    /**
     * @dev Mints `tokenId` and transfers it to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {_safeMint} whenever possible
     *
     * Requirements:
     *
     * - `tokenId` must not exist.
     * - `to` cannot be the zero address.
     *
     * Emits a {Transfer} event.
     */
    function _mint(address to, uint256 tokenId) internal virtual {
        require(to != address(0), "ERC721: mint to the zero address");
        require(!_exists(tokenId), "ERC721: token already minted");

        _beforeTokenTransfer(address(0), to, tokenId);

        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(address(0), to, tokenId);
    }

    /**
     * @dev Destroys `tokenId`.
     * The approval is cleared when the token is burned.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     *
     * Emits a {Transfer} event.
     */
    function _burn(uint256 tokenId) internal virtual {
        address owner = ERC721.ownerOf(tokenId);

        _beforeTokenTransfer(owner, address(0), tokenId);

        // Clear approvals
        _approve(address(0), tokenId);

        _balances[owner] -= 1;
        delete _owners[tokenId];

        emit Transfer(owner, address(0), tokenId);
    }

    /**
     * @dev Transfers `tokenId` from `from` to `to`.
     *  As opposed to {transferFrom}, this imposes no restrictions on msg.sender.
     *
     * Requirements:
     *
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     *
     * Emits a {Transfer} event.
     */
    function _transfer(address from, address to, uint256 tokenId) internal virtual {
        require(ERC721.ownerOf(tokenId) == from, "ERC721: transfer of token that is not own");
        require(to != address(0), "ERC721: transfer to the zero address");

        _beforeTokenTransfer(from, to, tokenId);

        // Clear approvals from the previous owner
        _approve(address(0), tokenId);

        _balances[from] -= 1;
        _balances[to] += 1;
        _owners[tokenId] = to;

        emit Transfer(from, to, tokenId);
    }

    /**
     * @dev Approve `to` to operate on `tokenId`
     *
     * Emits a {Approval} event.
     */
    function _approve(address to, uint256 tokenId) internal virtual {
        _tokenApprovals[tokenId] = to;
        emit Approval(ERC721.ownerOf(tokenId), to, tokenId);
    }

    /**
     * @dev Internal function to invoke {IERC721Receiver-onERC721Received} on a target address.
     * The call is not executed if the target address is not a contract.
     *
     * @param from address representing the previous owner of the given token ID
     * @param to target address that will receive the tokens
     * @param tokenId uint256 ID of the token to be transferred
     * @param _data bytes optional data to send along with the call
     * @return bool whether the call correctly returned the expected magic value
     */
    function _checkOnERC721Received(address from, address to, uint256 tokenId, bytes memory _data)
        private returns (bool)
    {
        if (to.isContract()) {
            try IERC721Receiver(to).onERC721Received(_msgSender(), from, tokenId, _data) returns (bytes4 retval) {
                return retval == IERC721Receiver(to).onERC721Received.selector;
            } catch (bytes memory reason) {
                if (reason.length == 0) {
                    revert("ERC721: transfer to non ERC721Receiver implementer");
                } else {
                    // solhint-disable-next-line no-inline-assembly
                    assembly {
                        revert(add(32, reason), mload(reason))
                    }
                }
            }
        } else {
            return true;
        }
    }

    /**
     * @dev Hook that is called before any token transfer. This includes minting
     * and burning.
     *
     * Calling conditions:
     *
     * - When `from` and `to` are both non-zero, ``from``'s `tokenId` will be
     * transferred to `to`.
     * - When `from` is zero, `tokenId` will be minted for `to`.
     * - When `to` is zero, ``from``'s `tokenId` will be burned.
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     *
     * To learn more about hooks, head to xref:ROOT:extending-contracts.adoc#using-hooks[Using Hooks].
     */
    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal virtual { }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../../utils/introspection/IERC165.sol";

/**
 * @dev Required interface of an ERC721 compliant contract.
 */
interface IERC721 is IERC165 {
    /**
     * @dev Emitted when `tokenId` token is transferred from `from` to `to`.
     */
    event Transfer(address indexed from, address indexed to, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables `approved` to manage the `tokenId` token.
     */
    event Approval(address indexed owner, address indexed approved, uint256 indexed tokenId);

    /**
     * @dev Emitted when `owner` enables or disables (`approved`) `operator` to manage all of its assets.
     */
    event ApprovalForAll(address indexed owner, address indexed operator, bool approved);

    /**
     * @dev Returns the number of tokens in ``owner``'s account.
     */
    function balanceOf(address owner) external view returns (uint256 balance);

    /**
     * @dev Returns the owner of the `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function ownerOf(uint256 tokenId) external view returns (address owner);

    /**
     * @dev Safely transfers `tokenId` token from `from` to `to`, checking first that contract recipients
     * are aware of the ERC721 protocol to prevent tokens from being forever locked.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must exist and be owned by `from`.
     * - If the caller is not `from`, it must be have been allowed to move this token by either {approve} or {setApprovalForAll}.
     * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
     *
     * Emits a {Transfer} event.
     */
    function safeTransferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Transfers `tokenId` token from `from` to `to`.
     *
     * WARNING: Usage of this method is discouraged, use {safeTransferFrom} whenever possible.
     *
     * Requirements:
     *
     * - `from` cannot be the zero address.
     * - `to` cannot be the zero address.
     * - `tokenId` token must be owned by `from`.
     * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
     *
     * Emits a {Transfer} event.
     */
    function transferFrom(address from, address to, uint256 tokenId) external;

    /**
     * @dev Gives permission to `to` to transfer `tokenId` token to another account.
     * The approval is cleared when the token is transferred.
     *
     * Only a single account can be approved at a time, so approving the zero address clears previous approvals.
     *
     * Requirements:
     *
     * - The caller must own the token or be an approved operator.
     * - `tokenId` must exist.
     *
     * Emits an {Approval} event.
     */
    function approve(address to, uint256 tokenId) external;

    /**
     * @dev Returns the account approved for `tokenId` token.
     *
     * Requirements:
     *
     * - `tokenId` must exist.
     */
    function getApproved(uint256 tokenId) external view returns (address operator);

    /**
     * @dev Approve or remove `operator` as an operator for the caller.
     * Operators can call {transferFrom} or {safeTransferFrom} for any token owned by the caller.
     *
     * Requirements:
     *
     * - The `operator` cannot be the caller.
     *
     * Emits an {ApprovalForAll} event.
     */
    function setApprovalForAll(address operator, bool _approved) external;

    /**
     * @dev Returns if the `operator` is allowed to manage all of the assets of `owner`.
     *
     * See {setApprovalForAll}
     */
    function isApprovedForAll(address owner, address operator) external view returns (bool);

    /**
      * @dev Safely transfers `tokenId` token from `from` to `to`.
      *
      * Requirements:
      *
      * - `from` cannot be the zero address.
      * - `to` cannot be the zero address.
      * - `tokenId` token must exist and be owned by `from`.
      * - If the caller is not `from`, it must be approved to move this token by either {approve} or {setApprovalForAll}.
      * - If `to` refers to a smart contract, it must implement {IERC721Receiver-onERC721Received}, which is called upon a safe transfer.
      *
      * Emits a {Transfer} event.
      */
    function safeTransferFrom(address from, address to, uint256 tokenId, bytes calldata data) external;
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @title ERC721 token receiver interface
 * @dev Interface for any contract that wants to support safeTransfers
 * from ERC721 asset contracts.
 */
interface IERC721Receiver {
    /**
     * @dev Whenever an {IERC721} `tokenId` token is transferred to this contract via {IERC721-safeTransferFrom}
     * by `operator` from `from`, this function is called.
     *
     * It must return its Solidity selector to confirm the token transfer.
     * If any other value is returned or the interface is not implemented by the recipient, the transfer will be reverted.
     *
     * The selector can be obtained in Solidity with `IERC721.onERC721Received.selector`.
     */
    function onERC721Received(address operator, address from, uint256 tokenId, bytes calldata data) external returns (bytes4);
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../IERC721.sol";

/**
 * @title ERC-721 Non-Fungible Token Standard, optional metadata extension
 * @dev See https://eips.ethereum.org/EIPS/eip-721
 */
interface IERC721Metadata is IERC721 {

    /**
     * @dev Returns the token collection name.
     */
    function name() external view returns (string memory);

    /**
     * @dev Returns the token collection symbol.
     */
    function symbol() external view returns (string memory);

    /**
     * @dev Returns the Uniform Resource Identifier (URI) for `tokenId` token.
     */
    function tokenURI(uint256 tokenId) external view returns (string memory);
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
    function functionDelegateCall(address target, bytes memory data, string memory errorMessage) internal returns (bytes memory) {
        require(isContract(target), "Address: delegate call to non-contract");

        // solhint-disable-next-line avoid-low-level-calls
        (bool success, bytes memory returndata) = target.delegatecall(data);
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

/**
 * @title Counters
 * @author Matt Condon (@shrugs)
 * @dev Provides counters that can only be incremented or decremented by one. This can be used e.g. to track the number
 * of elements in a mapping, issuing ERC721 ids, or counting request ids.
 *
 * Include with `using Counters for Counters.Counter;`
 */
library Counters {
    struct Counter {
        // This variable should never be directly accessed by users of the library: interactions must be restricted to
        // the library's function. As of Solidity v0.5.2, this cannot be enforced, though there is a proposal to add
        // this feature: see https://github.com/ethereum/solidity/issues/4637
        uint256 _value; // default: 0
    }

    function current(Counter storage counter) internal view returns (uint256) {
        return counter._value;
    }

    function increment(Counter storage counter) internal {
        unchecked {
            counter._value += 1;
        }
    }

    function decrement(Counter storage counter) internal {
        uint256 value = counter._value;
        require(value > 0, "Counter: decrement overflow");
        unchecked {
            counter._value = value - 1;
        }
    }
}

// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

/**
 * @dev String operations.
 */
library Strings {
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

// SPDX-License-Identifier: Apache
pragma solidity ^0.8.0;

import "./swap/GarfFomoWithLiquidity.sol";



contract GarfSwap is GarfFomoWithLiquidity{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    uint256 public constant NONCE=314*10**4;
    
    constructor(address garfToken_,address garfVault_,address fomo_,address swapRouter_){
        garfToken = IGarfToken(garfToken_);
        garfVault = IGarfVault(garfVault_);
        garfFomo = IGarfFomo(fomo_);
        swapRouter = IUniswapV2Router02(swapRouter_);
    }
    
}

// SPDX-License-Identifier: Apache
pragma solidity ^0.8.0;

import "../interfaces/IGarfVault.sol";
import "../interfaces/IUniswapV2Router02.sol";
import "../../3rdParty/@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../../3rdParty/@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../3rdParty/@openzeppelin/contracts/access/Ownable.sol";
import "../../3rdParty/@openzeppelin/contracts/token/ERC721/ERC721.sol";


import "../../3rdParty/@openzeppelin/contracts/utils/Counters.sol";
import "../../3rdParty/@openzeppelin/contracts/utils/math/SafeMath.sol";
import "../../3rdParty/@openzeppelin/contracts/security/ReentrancyGuard.sol";
import "../interfaces/IGarfToken.sol";
import "../interfaces/IGarfFomo.sol";

abstract contract GarfRouterBase is Ownable,ReentrancyGuard{
    using Counters for Counters.Counter;
    using SafeERC20 for IERC20;
    using SafeMath for uint256;

    IGarfToken public garfToken;
    IGarfVault public garfVault;
    IGarfFomo  public garfFomo;
    IUniswapV2Router02 public swapRouter;

    function ownerSetAddresses(address token_,address garfVault_,address fomo_,address swapRouter_) public onlyOwner{
        garfToken = IGarfToken(token_);
        garfVault = IGarfVault(garfVault_);
        garfFomo = IGarfFomo(fomo_);
        swapRouter = IUniswapV2Router02(swapRouter_);
    }

    function safeRewardTransfer(address _to,uint256 _amount) internal{
        safeTokenTransfer(garfToken, _to, _amount);
    }
    function safeTokenTransfer(IERC20 token,address to_,uint256 amount_) internal{
        uint256 bal = token.balanceOf(address(this));
        if (amount_ > bal){
            token.safeTransfer(to_,bal);
        }else{
            token.safeTransfer(to_,amount_);
        }
    }

}

// SPDX-License-Identifier: Apache
pragma solidity >=0.5.0;
import "../../3rdParty/@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGarfFomo{

    function getOwnerOfCode(string memory code) external view returns(address);
    function getAddrNftedOwnerAddr(address addr) external view returns(address);
}

// SPDX-License-Identifier: Apache
pragma solidity >=0.5.0;
import "../../3rdParty/@openzeppelin/contracts/token/ERC20/IERC20.sol";

interface IGarfToken is IERC20{
    function _inToWhiteList(address account)external view returns(bool);

    function swapAndLiquifyAnyToken(address token) external;

    function getFromSideTax(uint256 amount)external view returns(uint256);
    function getLpTax(uint256 amount) external view returns(uint256);
    function getToSideTax(address recipient,uint256 amount)external view returns(uint256,bool);
    function viewTryTransferTax(address from,address to,uint256 amount) external view returns(uint256 lpFee,uint256 fromTax,uint256 toTax,uint256 maxTransfer);
}

// SPDX-License-Identifier: Apache
pragma solidity >=0.5.0;

interface IGarfVault {

    function noticeRewardWithFrom(address from,uint256 reward) external;
    function noticeRewardWithTo(address to,uint256 initReward) external returns(uint256);
    function noticeFullRewardWithTo(address to,uint256 reward)external;


    function viewChainSplitWithTotal(address account,uint256 totalAmount) external view returns(address[] memory,uint256[] memory);
    function viewChainSplitWithInit(address account,uint256 initAmount) external view returns(address[] memory,uint256[] memory,uint256);

    
    function getAccountChainUp(address account)external view returns(address);
    function updateChainUp(address account,address up) external returns(address) ;
    function resetChainUp(address account) external;
}

// SPDX-License-Identifier: Apache
pragma solidity >=0.5.0;

interface IUniswapV2Factory {
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

// SPDX-License-Identifier: Apache
pragma solidity >=0.5.0;

interface IUniswapV2Pair {
    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);

    function name() external pure returns (string memory);
    function symbol() external pure returns (string memory);
    function decimals() external pure returns (uint8);
    function totalSupply() external view returns (uint);
    function balanceOf(address owner) external view returns (uint);
    function allowance(address owner, address spender) external view returns (uint);

    function approve(address spender, uint value) external returns (bool);
    function transfer(address to, uint value) external returns (bool);
    function transferFrom(address from, address to, uint value) external returns (bool);

    function DOMAIN_SEPARATOR() external view returns (bytes32);
    function PERMIT_TYPEHASH() external pure returns (bytes32);
    function nonces(address owner) external view returns (uint);

    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external;

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    function MINIMUM_LIQUIDITY() external pure returns (uint);
    function factory() external view returns (address);
    function token0() external view returns (address);
    function token1() external view returns (address);
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
    function price0CumulativeLast() external view returns (uint);
    function price1CumulativeLast() external view returns (uint);
    function kLast() external view returns (uint);

    function mint(address to) external returns (uint liquidity);
    function burn(address to) external returns (uint amount0, uint amount1);
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external;
    function skim(address to) external;
    function sync() external;

    function initialize(address, address) external;
}

// SPDX-License-Identifier: Apache
pragma solidity >=0.6.2;

interface IUniswapV2Router01 {
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

// SPDX-License-Identifier: Apache
pragma solidity >=0.6.2;

import './IUniswapV2Router01.sol';

interface IUniswapV2Router02 is IUniswapV2Router01 {
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

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.5.0;

interface IWETH {
    function deposit() external payable;
    function transfer(address to, uint value) external returns (bool);
    function withdraw(uint) external;
}

// SPDX-License-Identifier: GPL-3.0-or-later

pragma solidity >=0.6.0;

// helper methods for interacting with ERC20 tokens and sending ETH that do not consistently return true/false
library TransferHelper {
    function safeApprove(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('approve(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x095ea7b3, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper::safeApprove: approve failed'
        );
    }

    function safeTransfer(
        address token,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transfer(address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0xa9059cbb, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper::safeTransfer: transfer failed'
        );
    }

    function safeTransferFrom(
        address token,
        address from,
        address to,
        uint256 value
    ) internal {
        // bytes4(keccak256(bytes('transferFrom(address,address,uint256)')));
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(0x23b872dd, from, to, value));
        require(
            success && (data.length == 0 || abi.decode(data, (bool))),
            'TransferHelper::transferFrom: transferFrom failed'
        );
    }

    function safeTransferETH(address to, uint256 value) internal {
        (bool success, ) = to.call{value: value}(new bytes(0));
        require(success, 'TransferHelper::safeTransferETH: ETH transfer failed');
    }

    function safeTransferETHWithGas(address to, uint256 value,uint256 gas) internal {
        (bool success, ) = to.call{value: value,gas:gas}(new bytes(0));
        require(success, 'TransferHelper::safeTransferETHWithGas: ETH transfer failed');
    }
}

// SPDX-License-Identifier: Apache
pragma solidity ^0.8.0;

import "../base/GarfRouterBase.sol";
import "../lib/TransferHelper.sol";


abstract contract GarfFomoSwapBase is GarfRouterBase{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    uint256 public transferEthGasCost = 21000;

    receive() external payable {
        
    }
    fallback() external payable {
        
    }
    
    function factory() public view returns (address){
        return swapRouter.factory();
    }
    function WETH() public view returns (address){
        return swapRouter.WETH();
    }

    function quote(uint amountA, uint reserveA, uint reserveB) public view returns (uint amountB){
        return swapRouter.quote(amountA, reserveA, reserveB);
    }
    function getAmountOut(uint amountIn, uint reserveIn, uint reserveOut) public view returns (uint amountOut){
        return swapRouter.getAmountOut(amountIn, reserveIn, reserveOut);
    }
    function getAmountIn(uint amountOut, uint reserveIn, uint reserveOut) public view returns (uint amountIn){
        return swapRouter.getAmountIn(amountOut, reserveIn, reserveOut);
    }
    function getAmountsOut(uint amountIn, address[] calldata path) public view returns (uint[] memory amounts){
        return swapRouter.getAmountsOut(amountIn, path);
    }
    function getAmountsIn(uint amountOut, address[] calldata path) public view returns (uint[] memory amounts){
        return swapRouter.getAmountsIn(amountOut, path);
    }
    
    function _beforeSwap(uint sellAmount,address to,address upper,string memory code,address sellOutToken,address buyInToken) internal nonReentrant{
        //process referral
        __processCodeReferral(to, upper, code, sellOutToken, buyInToken);

        /**
         * SELL FEE - 5%
         *
         * OTO discourages excessive speculation. The code here charges a total of 5.0% fee
         * on any sell-like transaction.
         * 
         * This is called when the sell-like transacions are executed through the OTO Trade Page.
         */

        if (sellOutToken == address(garfToken)){
            address launcher = tx.origin;
            uint256 lpTax = garfToken.getLpTax(sellAmount);
            IERC20(garfToken).safeTransferFrom(launcher, address(garfToken), lpTax);

            uint256 fromSideTax = garfToken.getFromSideTax(sellAmount);
            IERC20(garfToken).safeTransferFrom(launcher, address(garfVault), fromSideTax);
            garfVault.noticeRewardWithFrom(launcher, fromSideTax);
            return;
        }
    }

    function _afterSwap(uint boughtAmount,address to,address buyInToken)internal nonReentrant returns(uint256){
        if (buyInToken == address(garfToken)){
            if (garfToken._inToWhiteList(to)){
                return boughtAmount;
            }

            /**
             * BUY FEE DISTRIBUTIONS
             *
             * OTO uses buy fees collected from buyers to incentivize REFERRERS who bring in new community members.
             *
             * Buy Fee is higher when a buyer has no referrer. This encourages buyers to seek out referrers. This is
             * done by getToSideTax, which charges 0.5% as a higher for a buy tx without referrer and 0.3% as a lower
             * fee when a buy tx has a referrer.
             * 
             */
            (uint256 totalFee,bool hasUp) = garfToken.getToSideTax(to,boughtAmount);

            if (totalFee>0){

                if (hasUp){
                    /**
                     * Buy fee is distributed in full as REFERRAL REWARDS when a buy tx has a referrer.
                     */
                    garfVault.noticeFullRewardWithTo(to, totalFee);
                }else{
                    /**
                     * Buy fee is distributed in full as STAKING REWARDS when a buy tx has no referrer.
                     */
                    garfVault.noticeRewardWithFrom(to, totalFee);
                }
                garfToken.transfer(address(garfVault), totalFee);
                return boughtAmount.sub(totalFee);
            }
        }
        return boughtAmount;
    }

    function __processCodeReferral(address to,address upper,string memory code,address sellOutToken,address buyInToken) internal{
        if (buyInToken!=address(garfToken) || 
            sellOutToken == address(garfToken) ||
            _msgSender()!=to) {
            return;
        }


        address ori = garfVault.getAccountChainUp(to);

        /**
         * REFERRAL RELATIONSHIP IS PERMANENT
         * 
         * Referral relationship is permanent. This is done by having this function to stop running if
         * a non-empty referrer address already exists.
         */
        if (ori!=address(0)){
            return;
        }
        
        if (bytes(code).length>0){
            address codeOwner = garfFomo.getOwnerOfCode(code);
            if (codeOwner != address(0) && codeOwner!=to){
                if (checkPassChainUp(codeOwner)){
                    garfVault.updateChainUp(to, codeOwner);
                    return;
                }
            }
        }
        if (upper != address(0) && upper!=to){
            address owner = garfFomo.getAddrNftedOwnerAddr(upper);
            if (checkPassChainUp(owner)){
                garfVault.updateChainUp(to, owner);
            }
        }
    }

    /**
     * REFERRAL PROGRAM ELIGIBILITY
     *
     * To be a referrer and start earning referral rewards, a user must have a referrer itself.
     * This is done by having this function return false if a user's referrer address is empty.
     */
    function checkPassChainUp(address addr) public view returns(bool){
        if (addr == address(garfVault)) return true;
        address upup = garfVault.getAccountChainUp(addr);
        if (upup!=address(0)) return true;
        return false;
    }

    function swapAndLiquifyAnyToken(address token) public nonReentrant {
        require(token!=address(garfToken),"token addr!");
        
        if (token!=address(0) && IERC20(token).balanceOf(address(this))==0){
            return;
        }
        if (token==address(0) && address(this).balance ==0){
            return;
        }
        if ( token==address(0) ){
            __safeThisEthTransfer(address(garfToken), address(this).balance);
        }else{
            IERC20(token).safeTransfer(address(garfToken),IERC20(token).balanceOf(address(this)));
        }
        garfToken.swapAndLiquifyAnyToken(token);
    }

    function __safeThisEthTransfer(address to,uint256 bal) internal {
        if (bal>address(this).balance){
            bal = address(this).balance;
        }
        TransferHelper.safeTransferETH(to, bal);
    }

    function ownerSetTransferEthGasCost(uint256 gas)public onlyOwner{
        transferEthGasCost = gas;
    }
}

// SPDX-License-Identifier: Apache
pragma solidity ^0.8.0;

import "./GarfFomoWithSwap.sol";
import "../interfaces/IWETH.sol";
import "../interfaces/IUniswapV2Pair.sol";
import "../interfaces/IUniswapV2Factory.sol";


abstract contract GarfFomoWithLiquidity is GarfFomoWithSwap{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    struct PairInfo{
        address token;
        uint desiredAmount;
        uint minAmount;
        uint256 inputAmount;
    }
    struct PermitInfo{
        address token;
        uint256 value;
        uint256 deadline;
        uint8 v; 
        bytes32 r;
        bytes32 s;

        address tokenA;
        address tokenB;
    }
    function _permit(PermitInfo memory p_)internal{
        IUniswapV2Pair(p_.token)
            .permit(
                msg.sender, 
                address(this), 
                p_.value, 
                p_.deadline, 
                p_.v, 
                p_.r, 
                p_.s
        );
    }
    function _addLiquidity(
        PairInfo memory infoA,
        PairInfo memory infoB,
        address to,
        uint deadline
    ) internal returns(uint,uint,uint){
        IERC20(infoA.token).safeApprove(address(swapRouter), infoA.desiredAmount);
        IERC20(infoB.token).safeApprove(address(swapRouter), infoB.desiredAmount);
        (uint amountA, uint amountB, uint liquidity) = 
            swapRouter.addLiquidity(infoA.token, infoB.token, 
                infoA.desiredAmount, infoB.desiredAmount,
                infoA.minAmount, infoB.minAmount, to, deadline);         
        {
            require(amountA<=infoA.inputAmount,"tokenA exceeds");
            if (amountA < infoA.inputAmount){
                TransferHelper.safeTransfer(infoA.token, _msgSender(), infoA.inputAmount.sub(amountA));
            }
        }
        {
            require(amountB<=infoB.inputAmount,"tokenB exceeds");
            if (amountB < infoB.inputAmount){
                TransferHelper.safeTransfer(infoB.token, _msgSender(),  infoB.inputAmount.sub(amountB));
            }
        }
        return (amountA,amountB,liquidity);
    }

    /**
     * NO FEE FOR LIQUIDITY RELATED ACTIONS
     * 
     * Adding or removing OTO liquidity through OTO's Liquidity Page is exempt from fees.
     */
    function __addLiquidityETH(
        PairInfo memory info,
        uint amountETHMin,
        address to,
        uint deadline,
        uint256 amountETHIn
    ) internal returns (uint,uint,uint){
        IERC20(info.token).safeApprove(address(swapRouter), info.desiredAmount);
        (uint amountToken,uint amountETH,uint liquidity) = swapRouter.addLiquidityETH{value: amountETHIn}(info.token, info.desiredAmount, 
            info.minAmount, amountETHMin, to, deadline);
        {
            require(amountToken<=info.inputAmount,"tokenA exceeds");
            if (amountToken < info.inputAmount){
                TransferHelper.safeTransfer(info.token, _msgSender(), info.inputAmount.sub(amountToken));
            }
        }
        {
            require(amountETH<=amountETHIn,"tokenB exceeds");
            if (amountETH < amountETHIn){
                //dust BNB
                __safeThisEthTransfer(_msgSender(), amountETHIn-amountETH);
            }
        }
        return (amountToken,amountETH,liquidity);
    }
    function addLiquidity(
        address tokenA,
        address tokenB,
        uint amountADesired,
        uint amountBDesired,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public returns (uint amountA, uint amountB, uint liquidity){
        PairInfo memory infoA = PairInfo({token:tokenA,desiredAmount:amountADesired,
            minAmount:amountAMin,inputAmount:0});
        uint256 tokenBeforeBal = IERC20(infoA.token).balanceOf(address(this));
        TransferHelper.safeTransferFrom(infoA.token, _msgSender(), address(this), infoA.desiredAmount);
        uint256 tokenAfterBal = IERC20(infoA.token).balanceOf(address(this));
        infoA.inputAmount = tokenAfterBal.sub(tokenBeforeBal);
        
        PairInfo memory infoB = PairInfo({token:tokenB,desiredAmount:amountBDesired,
            minAmount:amountBMin,inputAmount:0});
        tokenBeforeBal = IERC20(infoB.token).balanceOf(address(this));
        TransferHelper.safeTransferFrom(infoB.token, _msgSender(), address(this), infoB.desiredAmount);
        tokenAfterBal = IERC20(tokenB).balanceOf(address(this));
        infoB.inputAmount = tokenAfterBal.sub(tokenBeforeBal);
        
        return _addLiquidity(infoA, infoB, to, deadline);
    }

    function addLiquidityETH(
        address token,
        uint amountTokenDesired,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public payable returns (uint amountToken, uint amountETH, uint liquidity){
        PairInfo memory infoA = PairInfo({token:token,desiredAmount:amountTokenDesired,
            minAmount:amountTokenMin,inputAmount:0});
        uint256 tokenBeforeBal = IERC20(infoA.token).balanceOf(address(this));
        TransferHelper.safeTransferFrom(infoA.token, _msgSender(), address(this), infoA.desiredAmount);
        uint256 tokenAfterBal = IERC20(infoA.token).balanceOf(address(this));
        infoA.inputAmount = tokenAfterBal.sub(tokenBeforeBal);

        return __addLiquidityETH(infoA,amountETHMin,to,deadline,msg.value);
    }
    function removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline
    ) public returns (uint amountA, uint amountB){
        address pair = getPair(tokenA, tokenB);
        IERC20(pair).transferFrom(msg.sender, address(this), liquidity); // send liquidity to pair
        (amountA,amountB) = __removeLiquidity(
            tokenA,
            tokenB,
            liquidity,
            amountAMin,
            amountBMin,
            deadline
        );
        TransferHelper.safeTransfer(tokenA, to, amountA);
        TransferHelper.safeTransfer(tokenB, to, amountB);
    }

    /**
     * NO FEE FOR LIQUIDITY RELATED ACTIONS
     * 
     * Adding or removing OTO liquidity through OTO's Liquidity Page is exempt from fees.
     */
    function __removeLiquidity(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        uint deadline
    ) public returns (uint amountA, uint amountB){
        address pair = getPair(tokenA, tokenB);
        IERC20(pair).transferFrom(msg.sender, address(this), liquidity); // send liquidity to pair
        IERC20(pair).safeApprove(address(swapRouter), liquidity);
        return swapRouter.removeLiquidity(tokenA, tokenB, liquidity, amountAMin, amountBMin, payable(address(this)), deadline);
    }
    function removeLiquidityETH(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public returns (uint amountToken, uint amountETH){
        address WETH = swapRouter.WETH();
        (amountToken,amountETH) = __removeLiquidity(
            token,
            WETH, 
            liquidity, 
            amountTokenMin, 
            amountETHMin,
            deadline
        );
        TransferHelper.safeTransfer(token, to, amountToken);
        IWETH(WETH).withdraw(amountETH);
        __safeThisEthTransfer(to, amountETH);
    }
    function removeLiquidityWithPermit(
        address tokenA,
        address tokenB,
        uint liquidity,
        uint amountAMin,
        uint amountBMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) public returns (uint, uint){
        PermitInfo memory permit = PermitInfo({
            token:address(0),
            value:0,
            deadline:deadline,
            v:v,
            r:r,
            s:s,
            tokenA:tokenA,
            tokenB:tokenB
        });
        permit.token  = getPair(permit.tokenA,permit.tokenB);
        permit.value = approveMax ? ~uint256(0) : liquidity;
        _permit(permit);
        return removeLiquidity(
            tokenA,
            tokenB,
            liquidity,
            amountAMin,
            amountBMin,
            to,
            deadline
        );
    }
    function removeLiquidityETHWithPermit(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) public returns (uint amountToken, uint amountETH){
        PermitInfo memory permit = PermitInfo({
            token:address(0),
            value:0,
            deadline:deadline,
            v:v,
            r:r,
            s:s,
            tokenA:token,
            tokenB:swapRouter.WETH()
        });
        permit.token  = getPair(permit.tokenA,permit.tokenB);
        permit.value = approveMax ? ~uint256(0) : liquidity;
        _permit(permit);

        return removeLiquidityETH(token, liquidity, amountTokenMin, amountETHMin, to, deadline);
    }

    function getPair(address tokenA,address tokenB) public view returns(address){
        return IUniswapV2Factory(swapRouter.factory()).getPair(tokenA, tokenB);
    }

    function removeLiquidityETHSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline
    ) public returns (uint amountETH){
        address WETH = swapRouter.WETH();
        (,amountETH) = __removeLiquidity(
            token,
            WETH, 
            liquidity, 
            amountTokenMin, 
            amountETHMin,
            deadline
        );
        TransferHelper.safeTransfer(token, to, IERC20(token).balanceOf(address(this)));
        IWETH(WETH).withdraw(amountETH);
        __safeThisEthTransfer(to, amountETH);
        return amountETH;
    }
    function removeLiquidityETHWithPermitSupportingFeeOnTransferTokens(
        address token,
        uint liquidity,
        uint amountTokenMin,
        uint amountETHMin,
        address to,
        uint deadline,
        bool approveMax, uint8 v, bytes32 r, bytes32 s
    ) public returns (uint amountETH){
        address WETH = swapRouter.WETH();
        address pair = getPair(token, WETH);
        uint value = approveMax ? ~uint256(0) : liquidity;
        IUniswapV2Pair(pair).permit(msg.sender, address(this), value, deadline, v, r, s);
        return removeLiquidityETHSupportingFeeOnTransferTokens(
            token, 
            liquidity, 
            amountTokenMin, 
            amountETHMin, 
            to, 
            deadline
        );
    }

    
}

// SPDX-License-Identifier: Apache
pragma solidity ^0.8.0;

import "./GarfFomoSwapBase.sol";
import "../lib/TransferHelper.sol";

abstract contract GarfFomoWithSwap is GarfFomoSwapBase{
    using SafeERC20 for IERC20;
    using SafeMath for uint256;
    
    function swapExactTokensForTokensSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline,
        address upper,
        string memory code
    ) external{
        address token = path[0]; 
        address buyIn = path[path.length-1];
        _beforeSwap(amountIn,to,upper,code,token,buyIn);
        uint256 tokenBeforeBal = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(_msgSender(),address(this),amountIn);
        uint256 tokenAfterBal = IERC20(token).balanceOf(address(this));
        uint256 inputAmount = tokenAfterBal.sub(tokenBeforeBal);
        require(inputAmount>=amountIn,"input amount too small");

        IERC20(token).safeApprove(address(swapRouter),inputAmount);

        tokenBeforeBal = IERC20(buyIn).balanceOf(address(this));
        swapRouter.swapExactTokensForTokensSupportingFeeOnTransferTokens(amountIn,amountOutMin,path,address(this),deadline);
        tokenAfterBal = IERC20(buyIn).balanceOf(address(this)).sub(tokenBeforeBal);

        tokenAfterBal = _afterSwap(tokenAfterBal, to, buyIn);
        IERC20(buyIn).safeTransfer(to,tokenAfterBal);
    }

    function swapExactETHForTokensSupportingFeeOnTransferTokens(
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline,
        address upper,
        string memory code
    ) external payable{
        address token = path[0]; 
        address buyIn = path[path.length-1];
        uint amountIn = msg.value;
        _beforeSwap(amountIn,to,upper,code,token,buyIn);

        uint256 tokenBeforeBal = IERC20(buyIn).balanceOf(address(this));
        swapRouter.swapExactETHForTokensSupportingFeeOnTransferTokens{value: amountIn}(amountOutMin, path, address(this), deadline);
        uint256 tokenAfterBal = IERC20(buyIn).balanceOf(address(this)).sub(tokenBeforeBal);
        
        tokenAfterBal = _afterSwap(tokenAfterBal, to, buyIn);
        IERC20(buyIn).safeTransfer(to,tokenAfterBal);
    }
    function swapExactTokensForETHSupportingFeeOnTransferTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline,
        address upper,
        string memory code
    ) external{
        address sellToken = path[0]; 
        address buyIn = path[path.length-1];
        _beforeSwap(amountIn,to,upper,code,sellToken,buyIn);
        uint256 initBal = IERC20(sellToken).balanceOf(address(this));
        IERC20(sellToken).safeTransferFrom(_msgSender(),address(this),amountIn);
        uint256 transfered = IERC20(sellToken).balanceOf(address(this)).sub(initBal);
        require(transfered>=amountIn,"amountIn>");

        IERC20(sellToken).safeApprove(address(swapRouter),transfered);

        swapRouter.swapExactTokensForETHSupportingFeeOnTransferTokens(
            amountIn,
            amountOutMin,
            path,
            to,
            deadline
        );
    }

    function swapExactTokensForTokens(
        uint amountIn,
        uint amountOutMin,
        address[] calldata path,
        address to,
        uint deadline,
        address upper,
        string memory code
    ) external returns (uint[] memory amounts){
        address token = path[0];
        address buyIn = path[path.length-1];
        _beforeSwap(amountIn,to,upper,code,token,buyIn);

        uint256 tokenBeforeBal = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(_msgSender(),address(this),amountIn);
        uint256 tokenAfterBal = IERC20(token).balanceOf(address(this));
        uint256 inputAmount = tokenAfterBal.sub(tokenBeforeBal);
        require(inputAmount>=amountIn,"amountIn>");
        
        IERC20(token).safeApprove(address(swapRouter),inputAmount);

        tokenBeforeBal = IERC20(buyIn).balanceOf(address(this));
        amounts = swapRouter.swapExactTokensForTokens(amountIn,amountOutMin,path,address(this),deadline);
        tokenAfterBal = IERC20(buyIn).balanceOf(address(this)).sub(tokenBeforeBal);
        
        tokenAfterBal = _afterSwap(tokenAfterBal, to, buyIn);
        IERC20(buyIn).safeTransfer(to,tokenAfterBal);
    }
    function swapTokensForExactTokens(
        uint amountOut,
        uint amountInMax,
        address[] calldata path,
        address to,
        uint deadline,
        address upper,
        string memory code
    ) external returns (uint[] memory amounts){
        amounts = swapRouter.getAmountsIn(amountOut, path);
        uint256 amountIn = amounts[0];

        address sellToken = path[0]; 
        address buyIn = path[path.length-1];
        _beforeSwap(amountIn,to,upper,code,sellToken,buyIn);

        uint256 initBal = IERC20(sellToken).balanceOf(address(this));
        IERC20(sellToken).safeTransferFrom(_msgSender(),address(this),amountIn);
        uint256 transfered = IERC20(sellToken).balanceOf(address(this)).sub(initBal);
        require(transfered>=amountIn,"amountIn>");

        IERC20(sellToken).safeApprove(address(swapRouter),transfered);

        transfered = IERC20(buyIn).balanceOf(address(this));
        amounts = swapRouter.swapTokensForExactTokens(
            amountOut,
            amountInMax,
            path,address(this),deadline
        );
        transfered = IERC20(buyIn).balanceOf(address(this)).sub(transfered);
        transfered = _afterSwap(transfered, to,  buyIn);
        IERC20(buyIn).safeTransfer(to,transfered);
    }
    function swapExactETHForTokens(
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline,
        address upper,
        string memory code
    )external payable returns (uint[] memory amounts){
        address token = path[0]; 
        address buyIn = path[path.length-1];
        uint amountIn = msg.value;

        _beforeSwap(amountIn,to,upper,code,token,buyIn);

        uint256 transfered = IERC20(buyIn).balanceOf(address(this));
        amounts = swapRouter.swapExactETHForTokens{value:amountIn}(amountOutMin, path, address(this), deadline);
        transfered = IERC20(buyIn).balanceOf(address(this)).sub(transfered);
        transfered = _afterSwap(transfered, to,  buyIn);
        IERC20(buyIn).safeTransfer(to,transfered);
    }
    function swapTokensForExactETH(
        uint amountOut, 
        uint amountInMax, 
        address[] calldata path, 
        address to, 
        uint deadline,
        address upper,
        string memory code
    )external returns (uint[] memory amounts){
        amounts = swapRouter.getAmountsIn(amountOut, path);
        uint256 amountIn = amounts[0];

        address sellToken = path[0]; 
        address buyIn = path[path.length-1];
        _beforeSwap(amountIn,to,upper,code,sellToken,buyIn);

        uint256 initBal = IERC20(sellToken).balanceOf(address(this));
        IERC20(sellToken).safeTransferFrom(_msgSender(),address(this),amountIn);
        uint256 transfered = IERC20(sellToken).balanceOf(address(this)).sub(initBal);
        require(transfered>=amountIn,"amountIn>");

        IERC20(sellToken).safeApprove(address(swapRouter),transfered);

        return swapRouter.swapTokensForExactETH(amountOut, amountInMax, path, to, deadline);
    }
    function swapExactTokensForETH(
        uint amountIn, 
        uint amountOutMin, 
        address[] calldata path, 
        address to, 
        uint deadline,
        address upper,
        string memory code
    )external returns (uint[] memory amounts){
        address token = path[0]; 
        address buyIn = path[path.length-1];
        _beforeSwap(amountIn,to,upper,code,token,buyIn);
        uint256 tokenBeforeBal = IERC20(token).balanceOf(address(this));
        IERC20(token).safeTransferFrom(_msgSender(),address(this),amountIn);
        uint256 tokenAfterBal = IERC20(token).balanceOf(address(this));
        uint256 inputAmount = tokenAfterBal.sub(tokenBeforeBal);
        require(inputAmount>=amountIn,"amountIn>");

        IERC20(token).safeApprove(address(swapRouter),inputAmount);

        return swapRouter.swapExactTokensForETH(amountIn, amountOutMin, path, to, deadline);
    }
    function swapETHForExactTokens(
        uint amountOut, 
        address[] calldata path, 
        address to, 
        uint deadline,
        address upper,
        string memory code
    )external payable returns (uint[] memory amounts){
        amounts = swapRouter.getAmountsIn(amountOut, path);
        uint256 amountIn = amounts[0];

        address sellToken = path[0]; 
        address buyIn = path[path.length-1];
        _beforeSwap(amountIn,to,upper,code,sellToken,buyIn);
        require(amountIn <= msg.value, 'PancakeRouter: EXCESSIVE_INPUT_AMOUNT');

        uint256 initVal = address(this).balance;
        uint256 transfered = IERC20(buyIn).balanceOf(address(this));
        amounts = swapRouter.swapETHForExactTokens{value:amountIn}(amountOut, path, address(this), deadline);
        transfered = IERC20(buyIn).balanceOf(address(this)).sub(transfered);
        transfered = _afterSwap(transfered, to,  buyIn);
        IERC20(buyIn).safeTransfer(to,transfered);

        uint256 afterVal = address(this).balance;
        if (initVal>afterVal){
            uint256 consumed = initVal - afterVal;
            if (msg.value > consumed) __safeThisEthTransfer(_msgSender(),  msg.value - consumed);
        }
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