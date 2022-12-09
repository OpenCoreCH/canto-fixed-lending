// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import "solmate/tokens/ERC721.sol";
import "./Auction.sol";
import "./MintableNFT.sol";

contract AuctionFactory {

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Reference to the CSR NFT
    address public immutable csrNft;

    /// @notice Reference to the Fixed Loan NFT that is minted after a successful auction
    MintableNFT public immutable fixedLoanNft;

    /// @notice Reference to the Borrower NFT that is minted after a successful auction
    MintableNFT public immutable borrowerNft;

    /// @notice Stores all created auctions and their ID
    mapping (address => uint) private auctions;

    /// @notice Consecutive Auction IDs, used for minting NFTs. TODO: Maybe use CSR NFT ID, but 0 is valid ID and need to check regarding burning and recreating Auction for same CSR
    uint private currentAuctionID;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event AuctionCreated(address indexed owner, address indexed auction, uint csrNftID, uint principalAmount, uint maxRate);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidCSRNFT();
    error InvalidMaxRate(uint16 rate);
    error NoAuctionRegistered(address caller);
    
    constructor(address _csrNft, address _fixedLoanNft, address _borrowerNft) {
        if (_csrNft.code.length == 0)
            revert InvalidCSRNFT();
        csrNft = _csrNft;
        fixedLoanNft = MintableNFT(_fixedLoanNft);
        borrowerNft = MintableNFT(_borrowerNft);
    }

    function startAuction(uint _csrNftID, uint _principalAmount, uint16 _maxRate) external returns (address auction) {
        if (_maxRate > 1000)
            revert InvalidMaxRate(_maxRate);
        auction = address(new Auction(msg.sender, address(this), csrNft, _csrNftID, _principalAmount, _maxRate));
        ERC721(csrNft).transferFrom(msg.sender, auction, _csrNftID);
        auctions[auction] = ++currentAuctionID;
        emit AuctionCreated(msg.sender, auction, _csrNftID, _principalAmount, _maxRate);
    }

    /// @notice Function that is called by the auction after a succesful auction to deploy the loan and NFTs
    function deployLoan(address lender, address borrower) external {
        uint auctionId = auctions[msg.sender];
        if (auctionId == 0)
            revert NoAuctionRegistered(msg.sender);
        fixedLoanNft.mint(lender, auctionId);
        borrowerNft.mint(borrower, auctionId);
        // TODO: Deploy loan object
        
    }
}
