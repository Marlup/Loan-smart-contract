// SPDX-License-Identifier: MIT
pragma solidity >=0.7.0 <0.9.0;

contract LoanDataStructures {
    // Data structures
    enum PaymentType {
        Interest,
        Full
    }
    enum Period {
        Weekly,
        BiWeekly,
        Monthly,
        Quaterly
    }
    struct Term {
        uint startDate;
        uint endDate;
        uint paidAmount;
        bool isDue;
    }
    struct Agreement {
        bytes32 borrowerSign;
        bytes32 LenderSign;
        bool agreed;
    }
}
