// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import "solmate/tokens/ERC721.sol";

/// @notice NFT that is mintable by the AuctionFactory, used as Fixed Loan NFT and Borrower NFT
contract MintableNFT is ERC721 {

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Reference to the AuctionFactory, used for minting
    address public immutable auctionFactory;

    /// @notice Base URI of the NFT
    string public baseURI;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/


    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error OnlyFactoryCanMint();
    error InvalidFactoryAddress();
    error TokenNotMinted();
    
    constructor(string memory _name, string memory _symbol, address _auctionFactory, string memory _baseURI) ERC721(_name, _symbol) {
        if (_auctionFactory.code.length == 0)
            revert InvalidFactoryAddress();
        auctionFactory = _auctionFactory;
        baseURI = _baseURI;
    }

    function mint(address _to, uint _id) public {
        if (msg.sender != auctionFactory)
            revert OnlyFactoryCanMint();
        _mint(_to, _id); // _safeMint is not used on purpose because the recipient could avoid the finalization of an auction, otherwise
    }

    function tokenURI(uint256 id) public view override returns (string memory) {
        if (_ownerOf[id] == address(0)) // According to ERC721, this revert for non-existing tokens is required
            revert TokenNotMinted();
        return string(abi.encodePacked(baseURI, id, ".json"));
    }
}
