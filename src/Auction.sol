// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import "solmate/tokens/ERC721.sol";
import "solmate/utils/SafeTransferLib.sol";
import "./AuctionFactory.sol";

contract Auction {

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice The auctioned NFT collection
    ERC721 public immutable baseNft;

    /// @notice Reference to the AuctionFactory
    AuctionFactory private immutable auctionFactory;

    /// @notice Data that is associated with one auction
    struct AuctionData {
        /// @notice Creator of the auction that owned the NFT
        address creator;
        /// @notice The auctioned NFT ID
        uint nftId;
        /// @notice Principal amount for buying the NFT
        uint principalAmount;
        /// @notice Maximum rate that can be bid
        uint16 maxRate;
        /// @notice End of the auction, can be extended by additional bids
        uint40 auctionEnd;
        /// @notice The currently lowest bid rate, type(uint16).max if there was no bid
        uint16 currentBidRate;
        /// @notice Highest bidder at the moment, address(0) if there were no bids
        address highestBidder;
    }

    /// @notice Amount that is claimable (because a higher bid was received or for the owner when the auction was succesful). 
    /// The mapping is over all auctions. We use pull payment pattern to avoid griefing
    mapping (address => uint) refundAmounts;

    /// @notice Data of all auctions, position in list is auction ID
    AuctionData[] public auctions;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event NewBid(address bidder, uint16 rate);
    event AuctionExtended(uint40 newEndTime);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error NoBiddingAfterAuctionEndPossible(uint40 auctionEnd);
    error AuctionNotOverYet(uint40 auctionEnd);
    error BidRateMustBeLowerThanCurrentRate(uint16 bidRate, uint16 currentRate);
    error BidRateHigherThanMaxRate(uint16 bidRate);
    error MustPayPrincipalAmount(uint biddedAmount);
    error OnlyFactoryCanCreateAuctions();
    
    /// @param _factory Address of the AuctionFactory
    /// @param _baseNft Address of the auctioned NFT colleciton
    constructor(address _factory, address _baseNft ) {
        auctionFactory = AuctionFactory(_factory);
        baseNft = ERC721(_baseNft);
    }

    /// @dev Parameter validation happens in factory and the parameters are not validated here on purpose.
    /// Furthermore, the transfer of the NFT is initiated by the factory
    /// @param _creator Creator of the auction, gets the NFT back if no bids were made
    /// @param _nftId ID of the auctioned NFT
    /// @param _principalAmount Amount that must be paid for the NFT
    /// @param _maxRate Maximum rate that can be bid.
    /// @return auctionId ID of the auction
    function createAuction(address _creator, uint _nftId, uint _principalAmount, uint16 _maxRate) external returns (uint auctionId) {
        if (msg.sender != address(auctionFactory))
            revert OnlyFactoryCanCreateAuctions();
        AuctionData memory auctionData;
        auctionData.creator = _creator;
        auctionData.nftId = _nftId;
        auctionData.principalAmount = _principalAmount;
        auctionData.maxRate = _maxRate;
        auctionData.auctionEnd = uint40(block.timestamp + 24 hours); // No overflow until February 20, 36812
        auctionData.currentBidRate = type(uint16).max;
        auctions.push(auctionData);
        return auctions.length - 1;
    }

    /// @notice Create a new bid
    /// @dev Uses pull pattern to reimburse current highest bidder, i.e. does not transfer it to him (to avoid griefing)
    /// @param _bidRate The rate to bid
    function bid(uint auctionId, uint16 _bidRate) external payable {
        AuctionData storage auction = auctions[auctionId]; // Reverts when auctionId does not exist
        uint40 auctionEnd = auction.auctionEnd;
        if (block.timestamp >= auctionEnd)
            revert NoBiddingAfterAuctionEndPossible(auctionEnd);
        if (_bidRate >= auction.maxRate)
            revert BidRateHigherThanMaxRate(_bidRate);
        uint16 currentBidRate = auction.currentBidRate;
        if (_bidRate >= currentBidRate)
            revert BidRateMustBeLowerThanCurrentRate(_bidRate, currentBidRate);
        uint principalAmount = auction.principalAmount;
        if (msg.value != principalAmount)
            revert MustPayPrincipalAmount(msg.value);
        address highestBidder = auction.highestBidder;
        if (highestBidder != address(0)) {
            // Instead of sending the value to the current highest bidder, we store it in refundAmounts such that griefing the bid is not possible
            refundAmounts[highestBidder] += principalAmount; // Note that we need to increase the value because there can be multiple failed bids for a user.
        }
        auction.highestBidder = msg.sender; // It is possible that the current highest bidder bids again with a lower rate, but there is no reason to prevent that
        auction.currentBidRate = _bidRate;
        emit NewBid(msg.sender, _bidRate); 

        // Cannot underflow because of end time validation
        if (auctionEnd - block.timestamp <= 15 minutes) {
            uint40 newEnd = uint40(block.timestamp + 15 minutes);
            auction.auctionEnd = newEnd;
            emit AuctionExtended(newEnd);
        }
    }

    /// @notice Finalize an auction. Can be called by anyone after the auction is over.
    /// If there were no bids, transfers the NFT back to the owner.
    function finalizeAuction(uint auctionId) external {
        AuctionData storage auction = auctions[auctionId];
        uint40 auctionEnd = auction.auctionEnd;
        if (block.timestamp < auctionEnd)
            revert AuctionNotOverYet(auctionEnd);
        auction.auctionEnd = type(uint40).max; // Ensure that auction can only be finalized once (even if NFT is later again in this contract)
        address highestBidder = auction.highestBidder;
        if (highestBidder == address(0)) {
            // There were no bids
            baseNft.transferFrom(address(this), auction.creator, auction.nftId);
        } else {
            refundAmounts[auction.creator] += auction.principalAmount; // We also increase refundAmounts here to avoid griefing / failed transfers caused by the creator
            auctionFactory.deployLoan(auctionId, auction.creator, auction.highestBidder);
            // TODO: Transfer NFT
        }
    }

    /// @notice Function to refund funds to users whose bid was unsuccesful or to get principal as the creator when the bid is over
    function getFunds() external {
        uint refundAmount = refundAmounts[msg.sender];
        refundAmounts[msg.sender] = 0; // Set first to 0 to avoid reentering and claiming again
        SafeTransferLib.safeTransferETH(msg.sender, refundAmount);
    }
}
