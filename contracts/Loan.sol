// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./ILoan.sol";
import "./LoanDataStructures.sol";

contract Loan is ILoan, LoanDataStructures, ERC1155, Ownable {
    // **States**
    // Contract address
    address payable immutable loanAddress;
    // Parties
    Agreement agreement;
    address private borrower;
    address private lender;
    uint private principal;
    Period periodicity;
    // Number of days between terms
    uint private periods;
    uint private prorrogationDays;
    // Percentage
    uint private interestRate;
    // Percentage
    uint private lateInterestRate;
    uint private termCost;
    uint private lastTermCost;
    uint private openDate;
    uint private closeDate;
    uint private lateCloseDate;
    // Term positions
    uint private currentTermIndex;
    uint private currentLateTermIndex;
    uint private nLateTerms;
    uint[] private lateTermIndices;
    // Payment type
    PaymentType private paymentType;
    // Amount of time to fully repay the loan
    Term[] private termsSchedule;
    // Loan totalBalance
    mapping(address => mapping(address => uint)) loanBalance;
    
    // Collateral
    
    // Constructor
    constructor() ERC1155("") {
        loanAddress = payable(address(this));
    }

    // Modifiers
    modifier scheduleBuilt() {
        require(termsSchedule.length != 0, "Schedule of amortization is not built");
        _;
    }
    modifier scheduleNotBuilt() {
        require(termsSchedule.length == 0, "Schedule of amortization is alreay built");
        _;
    }

    // ++ Functions ++

    receive() external payable {
        uint _amountAvailable = msg.value;
        // Late terms are due
        if (nLateTerms != 0)
            _amountAvailable = _liquidateLateTerms(_amountAvailable);
        // Current term is due
        if (block.timestamp >= termsSchedule[currentTermIndex].startDate && termsSchedule[currentTermIndex].isDue) {
            // Current due term can be liquidated
            if (_amountAvailable > 0) {
                _amountAvailable = _liquidateCurrentTerm(_amountAvailable);
            }
        }
        // Remaining amount to be returned after liquidation of due terms
        if (_amountAvailable > 0) {
            (bool success, ) = msg.sender.call{value: _amountAvailable}("");
            require(success, "Remaining amount transfer back failed");
        }
    }
    function borrowerSigning(bytes32 _sign) external {
        require(borrower != address(0), "Borrower does not exist");
        require(borrower == msg.sender, "It is not the borrower");
        agreement.borrowerSign = _sign;
        if (agreement.LenderSign != bytes32(0)) {
            agreement.agreed = true;
        }
    }
    function lenderSigning(bytes32 _sign) external {
        require(lender == msg.sender, "It is not the lender");
        agreement.LenderSign = _sign;
        if (agreement.borrowerSign != bytes32(0)) {
            agreement.agreed = true;
        }
    }
    function buildAmortizationSchedule() external scheduleNotBuilt() {
        uint time = block.timestamp;
        openDate = time;
        if (paymentType == PaymentType.Interest) {
            (termCost, lastTermCost) = _scheduleInterestTerm();
        } else if (paymentType == PaymentType.Full) {
            (termCost, lastTermCost) = _scheduleFullTerm();
        }
        //termsSchedule = new Term[](periods);
        Term memory _term;
        for (uint i=0; i<periods; i++) {
            time += _addPeriod(time);
            _term.startDate = time;
            _term.endDate = time + prorrogationDays * 1 days;
            termsSchedule.push(_term);
        }
    }
    function checkNextTerm() external scheduleBuilt() {
        //Term storage _nextTerm = termsSchedule[currentTermIndex];
        Term storage _nextTerm = termsSchedule[currentTermIndex];
        if (block.timestamp >= _nextTerm.startDate) {
            if (!_nextTerm.isDue)
                termsSchedule[currentTermIndex].isDue = true;
            if (block.timestamp >= _nextTerm.endDate) {
                termsSchedule[currentTermIndex].endDate = block.timestamp + prorrogationDays * 1 days;
                termsSchedule[currentTermIndex].paidAmount += _addLateAmount(_nextTerm.paidAmount);
                currentTermIndex += 1;
            }
        }
    }
    function _liquidateLateTerms(uint _msgValue) private returns (uint _amountAvailable) {
        uint[] memory _lateTermIndices = lateTermIndices;
        //Term[] storage _termsSchedule = termsSchedule;
        uint _termPaidAmount;
        uint _dueAmount;
        uint _termCost;
        if (currentTermIndex < termsSchedule.length - 1) {
            _termCost = lastTermCost;
        } else {
            _termCost = termCost;
        }
        for (uint i=currentLateTermIndex; i<nLateTerms; i++) {
            _termPaidAmount = termsSchedule[_lateTermIndices[i]].paidAmount;
            _dueAmount = termCost - _termPaidAmount;
            if (_msgValue >= _dueAmount) {
                _msgValue -= _dueAmount;
                _termPaidAmount += _dueAmount;
                if (_termPaidAmount == termCost) {
                    termsSchedule[_lateTermIndices[i]].paidAmount += _dueAmount;
                    loanBalance[lender][borrower] += _dueAmount;
                    currentLateTermIndex += 1;
                    nLateTerms -= 1;
                    emit paymentDone(borrower, lender, i, block.timestamp, _dueAmount, true);
                }
            } else {
                termsSchedule[_lateTermIndices[i]].paidAmount += _msgValue;
                loanBalance[lender][borrower] += _msgValue;
                _msgValue = 0;
                emit paymentDone(borrower, lender, i, block.timestamp, _msgValue, false);
                break;
            }
        }
        _amountAvailable = _msgValue;
    }
    function _liquidateCurrentTerm(uint _amount) private returns (uint _amountToReturn) {
        //Term storage _currentTerm = termsSchedule[currentTermIndex];
        Term storage _currentTerm = termsSchedule[currentTermIndex];
        uint _termCost;
        if (currentTermIndex < termsSchedule.length - 1) {
            _termCost = termCost;
        } else {
            _termCost = lastTermCost;
        }
        uint _dueAmount = _termCost - _currentTerm.paidAmount;
        // Amount paid is greater or equal than term due amount
        if (_amount >= _dueAmount) {
            _currentTerm.paidAmount = _termCost;
            loanBalance[lender][borrower] += _dueAmount;
            // Update amount to be returned
            _amountToReturn = _amount - _dueAmount;
            emit paymentDone(lender, borrower, currentTermIndex, _dueAmount, block.timestamp, true);

        } else {
            _currentTerm.paidAmount += _amount;
            loanBalance[lender][borrower] += _amount;
            emit paymentDone(lender, borrower, currentTermIndex, _dueAmount, block.timestamp, false);
        }
        termsSchedule[currentTermIndex] = _currentTerm;
    }
    function _addPeriod(uint _time) internal view returns(uint) {
        if (periodicity == Period.Weekly) {
            return _time + 1 * 7 days;
        } else if (periodicity == Period.BiWeekly) {
            return _time + 2 * 7 days;
        } else if (periodicity == Period.Monthly) {
            return _time + 4 * 7 days;
        } else if (periodicity == Period.Quaterly) {
            return _time + 12 * 7 days;
        }
        return _time + 4 * 7 days;
    }
    function _addLateAmount(uint _paidAmount) internal returns(uint lateAmount) {
        if (_paidAmount < termCost) {
            lateAmount = termCost * lateInterestRate / 100;
            nLateTerms += 1;
            if (nLateTerms > 1)
                currentLateTermIndex += 1;
            lateTermIndices.push(currentLateTermIndex);
        }
    }
    function _scheduleInterestTerm() internal view returns(uint, uint) {
        return (principal * (interestRate / 100) / periods, principal);
    }
    function _scheduleFullTerm() internal view returns(uint, uint) {
        uint _amount = principal * ( 1 + interestRate / 100) / periods;
        return (_amount, _amount);
    }
}
