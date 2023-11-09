// SPDX-License-Identifier: MIT
pragma solidity 0.8.20;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "@openzeppelin/contracts/utils/Counters.sol";

/**
 * @title Verifier Contract
 * @dev This contract represents a verification badge as an NFT.
 * The badge indicates that certain unique data (like an iris scan or fingerprints)
 * has been fed to the contract and transformed into a unique identifier.
 * The NFT also contains a random string that symbolizes the uniqueness of an individual.
 */
contract Verifier is ERC721Enumerable {
    //
    // Contract custom errors
    //
    error NotOwner(address _address);
    error AlreadyVerified(address _address);
    error NotTokenWithID(uint256 _id);

    //
    // Contract state data
    //

    // Mapping from token ID to unique data string
    mapping(uint256 => string) private _uniqueData;

    // Mapping from address to boolean indicating if the address has minted a token
    mapping(address => bool) private _isVerified;

    // Variable to keep track of total NFTs minted, the number is monotonically increasing and even when NFTs are burnt, it is never decreased
    using Counters for Counters.Counter;
    Counters.Counter private _tokenIdCounter;

    constructor() ERC721("VerifiedBadge", "VBADGE") {}

    /**
     * @dev Returns the base URI for the token's metadata.
     * @return string representing the base URI.
     */
    function _baseURI() internal pure override returns (string memory) {
        return ""; // Placeholder for base URI, we are not using this here since we use _uniqueData mapping
    }

    /**
     * @dev Mints a new verified badge with unique data.
     * The caller can only mint for themselves (hence not address is passed as parameter) and only once.
     */
    function mintBadge() external {
        if (_isVerified[msg.sender]) {
            revert AlreadyVerified(msg.sender);
        }

        _tokenIdCounter.increment();
        uint256 newTokenId = _tokenIdCounter.current();
        _safeMint(msg.sender, newTokenId);
        _uniqueData[newTokenId] = _generateRandomData();

        _isVerified[msg.sender] = true;
    }

    /**
     * @dev Burns a verified badge.
     * @param _tokenId ID of the badge to be burned.
     */
    function burnBadge(uint256 _tokenId) external {
        if (_ownerOf(_tokenId) != msg.sender) {
            revert NotOwner(msg.sender);
        }

        _burn(_tokenId);
    }

    /**
     * @dev Generates a random data string based on block attributes.
     * @return string representing the random data.
     */
    function _generateRandomData() internal view returns (string memory) {
        // This is a simple pseudo-random technique, this isn't being used for anything in the project, this is just a concept
        bytes32 hash = keccak256(abi.encodePacked(block.timestamp, block.prevrandao, msg.sender));
        return bytes32ToHexString(hash);
    }

    /**
     * @dev Fetches the unique data associated with a token.
     * @param _tokenId ID of the token to fetch data for.
     * @return string representing the unique data.
     */
    function getUniqueData(uint256 _tokenId) external view returns (string memory) {
        if (_ownerOf(_tokenId) == address(0)) {
            revert NotTokenWithID(_tokenId);
        }

        return _uniqueData[_tokenId];
    }

/**
 * @dev Converts a bytes32 value to its hexadecimal string representation.
 *
 * This function takes a bytes32 input and translates each byte into its corresponding
 * two-character hexadecimal representation. The resulting string will always have
 * a fixed length of 64 characters, which corresponds to the 32 bytes from the input.
 *
 * @param _bytes32 The bytes32 value to convert.
 * @return A string that represents the hexadecimal format of the input bytes32 value.
 */
    function bytes32ToHexString(bytes32 _bytes32) internal pure returns (string memory) {
        bytes memory ALPHABET = "0123456789abcdef";
        bytes memory str = new bytes(64);  // Since 1 byte = 2 hexadecimal characters

        for (uint i = 0; i < 32; i++) {
            str[i * 2] = ALPHABET[uint8(_bytes32[i] >> 4)];
            str[1 + i * 2] = ALPHABET[uint8(_bytes32[i] & 0x0f)];
        }

        return string(str);
    }
}
