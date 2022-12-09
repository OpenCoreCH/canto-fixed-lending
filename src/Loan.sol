// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import "solmate/tokens/ERC721.sol";
import "./interface/ITurnstile.sol";
import "./MintableNFT.sol";

contract Loan {

    /*//////////////////////////////////////////////////////////////
                                 STATE
    //////////////////////////////////////////////////////////////*/

    /// @notice Reference to the Factory
    address private immutable factory;

    /// @notice Reference to the CSR NFT
    ITurnstile public immutable csrNft;

    /// @notice Reference to the Fixed Loan NFT
    ERC721 public immutable fixedLoanNft;

    /// @notice Reference to the Borrower NFT
    ERC721 public immutable borrowerNft;

    /// @notice The principal amount (the same for all loans)
    uint private immutable principalAmount;

    /// @notice Date that is associated with a loan
    struct LoanData {
      /// @notice The CSR NFT ID that is associated with the loan
      uint csrNftId;
      /// @notice The accrued debt
      uint accruedDebt;
      /// @notice Amount that is withdrawable by the owner of the fixed loan NFT
      uint withdrawable;
      /// @notice Last time interest was accrued
      uint40 lastAccrued;
      /// @notice The interest rate
      uint16 rate;
    }

    /// @notice Mapping containing the informations about the loans
    mapping (uint => LoanData) public loans;

    /*//////////////////////////////////////////////////////////////
                                 EVENTS
    //////////////////////////////////////////////////////////////*/

    event AuctionCreated(address indexed owner, uint auctionId, uint csrNftID, uint principalAmount, uint maxRate);

    /*//////////////////////////////////////////////////////////////
                                 ERRORS
    //////////////////////////////////////////////////////////////*/

    error OnlyBorrower();
    error OnlyLender();
    error OnlyFactoryCanCreateLoans();

    modifier onlyBorrower(uint _loanId) {
      if (msg.sender != borrowerNft.ownerOf(_loanId))
        revert OnlyBorrower();
      _;
    }

    modifier onlyLender(uint _loanId) {
      if (msg.sender != fixedLoanNft.ownerOf(_loanId))
        revert OnlyLender();
      _;
    }
    
    constructor(address _csrNft, address _factory, address _fixedLoanNft, address _borrowerNft, uint _principalAmount) {
        csrNft = ITurnstile(_csrNft);
        factory = _factory;
        fixedLoanNft = ERC721(_fixedLoanNft);
        borrowerNft = ERC721(_borrowerNft);
        principalAmount = _principalAmount;
    }

    function createLoan(uint _loanId, uint _csrNftId, uint16 _rate) external {
      if (msg.sender != factory)
        revert OnlyFactoryCanCreateLoans();
      LoanData memory loanData;
      loanData.accruedDebt = principalAmount;
      loanData.csrNftId = _csrNftId;
      loanData.lastAccrued = uint40(block.timestamp);
      loanData.rate = _rate;
      loans[_loanId] = loanData;
    }
}
