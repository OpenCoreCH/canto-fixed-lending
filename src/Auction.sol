// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import "solmate/tokens/ERC721.sol";
import "solmate/utils/SafeTransferLib.sol";

contract Auction {

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Creator of the auction that owned the NFT
    address public creator;

    /// @notice The auctioned NFT collection
    ERC721 public immutable baseNft;

    /// @notice The auctioned NFT ID
    uint public immutable nftId;

    /// @notice Principal amount for buying the NFT
    uint public immutable principalAmount;

    /// @notice Maximum rate that can be bid
    uint16 public immutable maxRate;

    /// @notice End of the auction, can be extended by additional bids
    uint40 public auctionEnd;

    /// @notice The currently lowest bid rate, type(uint16).max if there was no bid
    uint16 public currentBidRate = type(uint16).max;

    /// @notice Highest bidder at the moment, address(0) if there were no bids
    address public highestBidder;

    /// @notice Amount that is refunded to the bidders because a higher bid was received. We use pull payment pattern to avoid griefing
    mapping (address => uint) refundAmounts;

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
    
    /// @dev While the intended use case is the usage with the AuctionFactory (and we therefore do not validate the _maxRate here for instance),
    /// the contracts are written in a generic way and could also be used for auctioning other NFTs
    /// @param _creator Creator of the auction, gets the NFT back if no bids were made
    /// @param _baseNFT Address of the auctioned NFT colleciton
    /// @param _nftId ID of the auctioned NFT
    /// @param _principalAmount Amount that must be paid for the NFT
    /// @param _maxRate Maximum rate that can be bid
    constructor(address _creator, address _baseNft, uint _nftId, uint _principalAmount, uint16 _maxRate) {
        creator = _creator;
        ERC721(_baseNft).transferFrom(_creator, address(this), _nftId); // TODO: This does not work because of approval...
        baseNft = ERC721(_baseNft);
        nftId = _nftId;
        principalAmount = _principalAmount;
        maxRate = _maxRate;
        auctionEnd = uint40(block.timestamp + 24 hours); // No overflow until February 20, 36812
    }

    /// @notice Create a new bid
    /// @dev Uses pull pattern to reimburse current highest bidder, i.e. does not transfer it to him (to avoid griefing)
    /// @param _bidRate The rate to bid
    function bid(uint16 _bidRate) external payable returns (address auction) {
        if (block.timestamp >= auctionEnd)
            revert NoBiddingAfterAuctionEndPossible(auctionEnd);
        if (_bidRate >= maxRate)
            revert BidRateHigherThanMaxRate(_bidRate);
        if (_bidRate >= currentBidRate)
            revert BidRateMustBeLowerThanCurrentRate(_bidRate, currentBidRate);
        if (msg.value != principalAmount)
            revert MustPayPrincipalAmount(msg.value);
        if (highestBidder != address(0)) {
            // Instead of sending the value to the current highest bidder, we store it in refundAmounts such that griefing the bid is not possible
            refundAmounts[highestBidder] += principalAmount; // Note that we need to increase the value because there can be multiple failed bids for a user.
        }
        highestBidder = msg.sender; // It is possible that the current highest bidder bids again with a lower rate, but there is no reason to prevent that
        currentBidRate = _bidRate;
        emit NewBid(msg.sender, _bidRate); 

        // Cannot underflow because of end time validation
        if (auctionEnd - block.timestamp <= 15 minutes) {
            uint40 newEnd = uint40(block.timestamp + 15 minutes);
            auctionEnd = newEnd;
            emit AuctionExtended(newEnd);
        }
    }

    /// @notice Finalize an auction. Can be called by anyone after the auction is over.
    /// If there were no bids, transfers the NFT back to the owner.
    function finalizeAuction() external {
        if (block.timestamp < auctionEnd)
            revert AuctionNotOverYet(auctionEnd);
        address bidder = highestBidder;
        if (highestBidder == address(0)) {
            // There were no bids
            baseNft.transferFrom(address(this), creator, nftId);
        } else {
            refundAmounts[creator] += principalAmount; // We also increase refundAmounts here to avoid griefing / failed transfers caused by the creator
        }
    }

    /// @notice Function to refund funds to users whose bid was unsuccesful or to get principal as the creator when the bid is over
    function getFunds() external {
        uint refundAmount = refundAmounts[msg.sender];
        refundAmounts[msg.sender] = 0; // Set first to 0 to avoid reentering and claiming again
        SafeTransferLib.safeTransferETH(msg.sender, refundAmount);
    }
}
