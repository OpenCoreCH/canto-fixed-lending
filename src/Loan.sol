// SPDX-License-Identifier: GPL-3.0-only
pragma solidity >=0.8.0;

import "solmate/tokens/ERC721.sol";
import "solmate/utils/SafeTransferLib.sol";
import "solmate/utils/SignedWadMath.sol";
import "solmate/utils/FixedPointMathLib.sol";
import "./interface/ITurnstile.sol";
import "./MintableNFT.sol";

contract Loan {

    int constant DAYS_WAD = 365250000000000000000; // 365.25 as wad (with 18 decimals)

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
      /// @notice The interest rate, stored with 18 decimals. Stored as int to avoid casting for the rate calculations
      int rateWad;
      /// @notice Last time interest was accrued
      uint40 lastAccrued;
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
    error TooMuchTooWithdrawRequested();
    error AccruedDebtRemaining(uint accruedDebt);

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
      // Provided rate is in 10 BPS, we therefore divide by 1,000
      loanData.rateWad = toWadUnsafe(_rate) / 1_000; // No overflow possible because _rate is uint16
      loans[_loanId] = loanData;
    }

    function repayWithClaimable(uint _loanId) onlyBorrower(_loanId) external {
      _accrueInterest(_loanId);
      LoanData storage loan = loans[_loanId];
      uint tokenId = loan.csrNftId;
      uint toClaim = csrNft.balances(tokenId);
      uint debtOutstanding = loan.accruedDebt;
      if (toClaim > debtOutstanding) {
        toClaim = debtOutstanding;
      }
      uint claimed = csrNft.withdraw(tokenId, payable(address(this)), toClaim); // claimed should always be equal to toClaim because of the logic above
      loan.accruedDebt -= claimed;
      loan.withdrawable += claimed;
    }

    function repayWithExternal(uint _loanId) onlyBorrower(_loanId) external payable {
      _accrueInterest(_loanId);
      LoanData storage loan = loans[_loanId];
      uint debtOutstanding = loan.accruedDebt;
      if (msg.value > debtOutstanding) {
        // Reimburse user if he paid too much
        loan.accruedDebt = 0;
        loan.withdrawable += debtOutstanding;
        SafeTransferLib.safeTransferETH(msg.sender, msg.value - debtOutstanding);
      } else {
        loan.accruedDebt -= msg.value;
        loan.withdrawable += msg.value;
      }
    }

    /// @param _amount Amount to withdraw. 0 if everything should be withdrawn
    function withdrawPayable(uint _loanId, uint _amount) onlyLender(_loanId) external {
      LoanData storage loan = loans[_loanId];
      uint withdrawable = loan.withdrawable;
      if (_amount > withdrawable) {
        // We could also only send withdrawable in this case.
        // But this might be confusing for integrations that expect to receive the requested amount when it is > 0
        revert TooMuchTooWithdrawRequested();
      }
      if (_amount == 0) {
        _amount = withdrawable;
      }
      loan.withdrawable -= _amount;
      SafeTransferLib.safeTransferETH(msg.sender, _amount);
    }

    function withdrawNFT(uint _loanId) onlyBorrower(_loanId) external {
      LoanData storage loan = loans[_loanId];
      uint accruedDebt = loan.accruedDebt;
      if (accruedDebt != 0)
        revert AccruedDebtRemaining(accruedDebt);
      csrNft.transferFrom(address(this), msg.sender, loan.csrNftId);
      // TODO: Burn borrower NFT? Can something else (malicious) be done with it afterwards
    }

    function _accrueInterest(uint _loanId) internal {
      LoanData storage loan = loans[_loanId];
      uint secondsPassed = loan.lastAccrued - block.timestamp;
      if (secondsPassed == 0) {
        return;
      }
      int daysPassedWad = toDaysWadUnsafe(secondsPassed);
      int yearsPassedWad = wadDiv(daysPassedWad, DAYS_WAD);
      uint debtMultiplerWad = uint(wadExp(wadMul(yearsPassedWad, loan.rateWad))); // exp(r * Δt). Cast to uint is safe here because result is always positive
      loan.accruedDebt = FixedPointMathLib.mulWadUp(loan.accruedDebt, debtMultiplerWad); // Divides by WAD to bring result back to original unit
      loan.lastAccrued = uint40(block.timestamp);
    }
}
