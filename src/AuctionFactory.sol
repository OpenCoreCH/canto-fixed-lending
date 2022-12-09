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

    /// @notice Reference to the Auction contract
    Auction public immutable auction;

    /// @notice Reference to the Fixed Loan NFT that is minted after a successful auction
    MintableNFT public immutable fixedLoanNft;

    /// @notice Reference to the Borrower NFT that is minted after a successful auction
    MintableNFT public immutable borrowerNft;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event AuctionCreated(address indexed owner, uint auctionId, uint csrNftID, uint principalAmount, uint maxRate);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error InvalidCSRNFT();
    error InvalidMaxRate(uint16 rate);
    error OnlyAuctionCanDeployLoan();
    
    constructor(address _csrNft, address _auctionContract, address _fixedLoanNft, address _borrowerNft) {
        if (_csrNft.code.length == 0)
            revert InvalidCSRNFT();
        csrNft = _csrNft;
        auction = Auction(_auctionContract);
        fixedLoanNft = MintableNFT(_fixedLoanNft);
        borrowerNft = MintableNFT(_borrowerNft);
    }

    function startAuction(uint _csrNftID, uint _principalAmount, uint16 _maxRate) external returns (uint auctionId) {
        if (_maxRate > 1000)
            revert InvalidMaxRate(_maxRate);
        auctionId = auction.createAuction(msg.sender, _csrNftID, _principalAmount, _maxRate);
        ERC721(csrNft).transferFrom(msg.sender, address(auction), _csrNftID);
        emit AuctionCreated(msg.sender, auctionId, _csrNftID, _principalAmount, _maxRate);
    }

    /// @notice Function that is called by the auction after a succesful auction to deploy the loan and NFTs
    function deployLoan(uint auctionId, address lender, address borrower) external {
        if (msg.sender != address(auction))
            revert OnlyAuctionCanDeployLoan();
        fixedLoanNft.mint(lender, auctionId);
        borrowerNft.mint(borrower, auctionId);
        // TODO: Deploy loan object
        
    }
}
