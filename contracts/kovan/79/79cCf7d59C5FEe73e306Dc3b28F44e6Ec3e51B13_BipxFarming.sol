// SPDX-License-Identifier: UNLICENSED
pragma solidity =0.8.0;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/utils/cryptography/MerkleProof.sol";

contract BipxFarming {
	// This event is triggered whenever a call to #claim succeeds.
	event Claimed(uint256 index, address account);

	address public immutable bipxToken;
	address public immutable usdtToken;

	bytes32 public bipxMerkleRoot;
	bytes32 public usdtMerkleRoot;
	address owner;
	bool isClaimingStopped;

	mapping(bytes32 => mapping(uint256 => uint256)) private claimedBitMap;

	constructor(address bipx_, address usdt_) public {
		bipxToken = bipx_;
		usdtToken = usdt_;
		owner = msg.sender;
		isClaimingStopped = true;
	}

	modifier _ownerOnly() {
		require(msg.sender == owner);
		_;
	}

	function setMerkleRoot(bytes32 bipxMerkleRoot_, bytes32 usdtMerkleRoot_) public _ownerOnly {
		bipxMerkleRoot = bipxMerkleRoot_;
		usdtMerkleRoot = usdtMerkleRoot_;
	}

	function stopClaiming() public _ownerOnly {
		isClaimingStopped = true;
	}

	function startClaiming() public _ownerOnly {
		isClaimingStopped = false;
	}

	function isClaimed(uint256 index) public view returns (bool) {
		uint256 claimedWordIndex = index / 256;
		uint256 claimedBitIndex = index % 256;
		uint256 claimedWord = claimedBitMap[bipxMerkleRoot][claimedWordIndex];
		uint256 mask = (1 << claimedBitIndex);
		return claimedWord & mask == mask;
	}

	function _setClaimed(uint256 index) private {
		uint256 claimedWordIndex = index / 256;
		uint256 claimedBitIndex = index % 256;
		claimedBitMap[bipxMerkleRoot][claimedWordIndex] = claimedBitMap[bipxMerkleRoot][claimedWordIndex] | (1 << claimedBitIndex);
	}

	function claim(uint256 index, address account, uint256 bipxAmount, bytes32[] calldata bipxMerkleProof, uint256 usdtAmount, bytes32[] calldata usdtMerkleProof) external {
		require(!isClaimed(index), 'MerkleDistributor: Drop already claimed.');
		require(!isClaimingStopped, 'Claim is not available currently.');

		// Verify the merkle proof.
		bytes32 bipxNode = keccak256(abi.encodePacked(index, account, bipxAmount));
		bytes32 usdtNode = keccak256(abi.encodePacked(index, account, usdtAmount));
		require(MerkleProof.verify(bipxMerkleProof, bipxMerkleRoot, bipxNode), 'MerkleDistributor: Invalid BIPX proof.');
		require(MerkleProof.verify(usdtMerkleProof, usdtMerkleRoot, usdtNode), 'MerkleDistributor: Invalid USDT proof.');

		// Mark it claimed and send the token.
		_setClaimed(index);
		require(IERC20(bipxToken).transfer(account, bipxAmount), 'MerkleDistributor: Transfer failed.');
		require(IERC20(usdtToken).transfer(account, usdtAmount), 'MerkleDistributor: Transfer failed.');

		emit Claimed(index, account);
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

/**
 * @dev These functions deal with verification of Merkle trees (hash trees),
 */
library MerkleProof {
    /**
     * @dev Returns true if a `leaf` can be proved to be a part of a Merkle tree
     * defined by `root`. For this, a `proof` must be provided, containing
     * sibling hashes on the branch from the leaf to the root of the tree. Each
     * pair of leaves and each pair of pre-images are assumed to be sorted.
     */
    function verify(bytes32[] memory proof, bytes32 root, bytes32 leaf) internal pure returns (bool) {
        bytes32 computedHash = leaf;

        for (uint256 i = 0; i < proof.length; i++) {
            bytes32 proofElement = proof[i];

            if (computedHash <= proofElement) {
                // Hash(current computed hash + current element of the proof)
                computedHash = keccak256(abi.encodePacked(computedHash, proofElement));
            } else {
                // Hash(current element of the proof + current computed hash)
                computedHash = keccak256(abi.encodePacked(proofElement, computedHash));
            }
        }

        // Check if the computed hash (root) is equal to the provided root
        return computedHash == root;
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