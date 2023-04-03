// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

interface ILoan {
    // **Events**
    event dueNextTerm(address indexed lender, address indexed borrower, uint indexed termIndex, uint amount);
    event addLateTerm(address indexed lender, address indexed borrower, uint indexed termIndex, uint newAmount);
    event paymentDone(address indexed borrower, address indexed lender, uint indexed termIndex, uint paidAmount, uint time, bool fullTermPaid);

    // *Functions*
    // Agreement
    function borrowerSigning(bytes32 _sign) external;
    function lenderSigning(bytes32 _sign) external;
    // Terms building
    function buildAmortizationSchedule() external;
    // Terms actions
    /* Compare current time with next initial term date.
     * If current is greater, the term is activated and dued to payment
    */
    function checkNextTerm() external;
}
