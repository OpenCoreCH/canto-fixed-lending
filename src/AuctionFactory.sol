// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import "./Auction.sol";

contract AuctionFactory {

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Reference to the CSR NFT
    address public immutable csrNft;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event AuctionCreated(address indexed owner, address indexed auction, uint csrNftID, uint principalAmount, uint maxRate);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidCSRNFT();
    error InvalidMaxRate(uint16 rate);
    
    constructor(address _csrNft) {
        if (_csrNft.code.length == 0)
            revert InvalidCSRNFT();
        csrNft = _csrNft;
    }

    function startAuction(uint _csrNftID, uint _principalAmount, uint16 _maxRate) external returns (address auction) {
        if (_maxRate > 1000)
            revert InvalidMaxRate(_maxRate);
        auction = address(new Auction(msg.sender, csrNft, _csrNftID, _principalAmount, _maxRate));
        emit AuctionCreated(msg.sender, auction, _csrNftID, _principalAmount, _maxRate);
    }
}
