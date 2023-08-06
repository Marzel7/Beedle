// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../../src/Lender.sol";
import "forge-std/console.sol";

import {ERC20} from "solady/src/tokens/ERC20.sol";

contract TERC20 is ERC20 {
    function name() public pure override returns (string memory) {
        return "Test ERC20";
    }

    function symbol() public pure override returns (string memory) {
        return "TERC20";
    }

    function mint(address _to, uint256 _amount) public {
        _mint(_to, _amount);
    }

    function balance(address owner) public view returns (uint256) {
        return balanceOf(owner);
    }
}

contract BuyLoanRedeemCollateral is Test {
    Lender public lender;

    TERC20 public loanToken;
    TERC20 public collateralToken;

    address public lender1 = address(0x1);
    address public lender2 = address(0x2);
    address public borrower = address(0x3);
    address public fees = address(0x4);
    address public lender3 = address(0x6);

    uint256 public borrowerFee = 50;
    uint256 LOANTOKEN_BALANCE = 100000 * 10 ** 18;
    uint256 COLLATERAL_BALANCE = 100000 * 10 ** 18;
    uint256 BORROWER_INIT_LOANTOKEN_BALANCE = 100000 * 10 ** 18;

    uint256 POOL_LOAN_TOKEN_BALANCE = 1000 * 10 ** 18;
    uint256 LOAN_AMOUNT = 1000 * 10 ** 18;

    function setUp() public {
        lender = new Lender();
        loanToken = new TERC20();
        collateralToken = new TERC20();

        loanToken.mint(address(lender1), LOANTOKEN_BALANCE);
        loanToken.mint(address(lender2), 4 * LOANTOKEN_BALANCE);
        loanToken.mint(address(lender3), 2 * LOANTOKEN_BALANCE);
        loanToken.mint(address(borrower), BORROWER_INIT_LOANTOKEN_BALANCE);

        collateralToken.mint(address(borrower), COLLATERAL_BALANCE);
        collateralToken.mint(address(lender2), COLLATERAL_BALANCE);

        vm.startPrank(lender1);
        loanToken.approve(address(lender), LOANTOKEN_BALANCE);
        collateralToken.approve(address(lender), COLLATERAL_BALANCE);

        vm.startPrank(lender2);
        loanToken.approve(address(lender), LOANTOKEN_BALANCE);
        collateralToken.approve(address(lender), COLLATERAL_BALANCE);

        vm.startPrank(lender3);
        loanToken.approve(address(lender), LOANTOKEN_BALANCE);
        collateralToken.approve(address(lender), COLLATERAL_BALANCE);

        vm.startPrank(borrower);
        loanToken.approve(address(lender), LOANTOKEN_BALANCE);
        collateralToken.approve(address(lender), COLLATERAL_BALANCE);
    }

    function test_BuyLoan() public {
        assertEq(collateralToken.balance(address(lender)), 0);
        assertEq(collateralToken.balance(address(lender2)), COLLATERAL_BALANCE);
        assertEq(collateralToken.balance(address(borrower)), COLLATERAL_BALANCE);

        vm.startPrank(lender1);
        Pool memory p1 = Pool({
            lender: lender1,
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            minLoanSize: 100 * 10 ** 18,
            poolBalance: POOL_LOAN_TOKEN_BALANCE,
            maxLoanRatio: 2 * 10 ** 18,
            auctionLength: 1 days,
            interestRate: 1000,
            outstandingLoans: 0
        });

        Pool memory p2 = Pool({
            lender: lender2,
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            minLoanSize: 100 * 10 ** 18,
            poolBalance: 3 * POOL_LOAN_TOKEN_BALANCE,
            maxLoanRatio: 10000000000 * 10 ** 18,
            auctionLength: 1 days,
            interestRate: 1100,
            outstandingLoans: 0
        });

        Pool memory p3 = Pool({
            lender: lender3,
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            minLoanSize: 100 * 10 ** 18,
            poolBalance: 3 * POOL_LOAN_TOKEN_BALANCE,
            maxLoanRatio: 1 * 10 ** 18,
            auctionLength: 2 days,
            interestRate: 1100,
            outstandingLoans: 0
        });

        bytes32 poolIdOne = lender.setPool(p1);

        vm.startPrank(lender2);

        bytes32 poolIdTwo = lender.setPool(p2);

        vm.startPrank(lender3);
        bytes32 poolIdThree = lender.setPool(p3);

        bytes32[] memory poolIds = new bytes32[](3);
        poolIds[0] = poolIdOne;
        poolIds[1] = poolIdTwo;
        poolIds[2] = poolIdThree;

        uint256[] memory loansIds = new uint256[](1);
        loansIds[0] = 0;

        vm.startPrank(borrower);
        Borrow memory b = Borrow({poolId: poolIdOne, debt: 1000 * 10 ** 18, collateral: 1000 * 10 ** 18});
        Borrow[] memory borrows = new Borrow[](1);
        borrows[0] = b;
        lender.borrow(borrows);

        console.log("*** Loan from Pool 1 ***");
        (address loandLender, address loanBorrower,,,,,,,,) = lender.loans(0);

        stages(poolIdOne, poolIdTwo, poolIdThree, loandLender, loanBorrower, true, true);
        vm.startPrank(lender1);
        lender.startAuction(loansIds);

        vm.warp(1 days);

        vm.startPrank(lender2);
        lender.buyLoan(loansIds[0], poolIds[2]);

        console.log("*** Loan is Auctioned from Pool 1 to Pool 3  ***");
        (loandLender, loanBorrower,,,,,,,,) = lender.loans(0);

        stages(poolIdOne, poolIdTwo, poolIdThree, loandLender, loanBorrower, true, true);

        vm.startPrank(lender2);

        // calculate debt to create a loan against Pool2, with a huge maxLoanRatio, minimal collateral
        uint256 debt = lender.getLoanDebt(0);

        Borrow memory b2 = Borrow({poolId: poolIdTwo, debt: debt, collateral: 1 * 10 ** 18});
        borrows = new Borrow[](1);
        borrows[0] = b2;
        //lender.zapBuyLoan(p2, 1);
        lender.borrow(borrows);

        console.log("*** Loan from Pool 2 ***");
        (loandLender, loanBorrower,,,,,,,,) = lender.loans(0);

        stages(poolIdOne, poolIdTwo, poolIdThree, loandLender, loanBorrower, true, true);

        console.log("Seize loan and remove liquidity");
        lender.startAuction(loansIds);
        vm.warp(2 days);
        lender.seizeLoan(loansIds);

        Pool memory p = Pool({
            lender: lender2,
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            minLoanSize: 100 * 10 ** 18,
            poolBalance: 0,
            maxLoanRatio: 10000000000 * 10 ** 18,
            auctionLength: 1 days,
            interestRate: 1100,
            outstandingLoans: 0
        });

        lender.removeFromPool(poolIdTwo, debt);
        lender.setPool(p);

        stages(poolIdOne, poolIdTwo, poolIdThree, loandLender, loanBorrower, true, true);

        assertEq(collateralToken.balance(address(lender)), 1 * 1e18); // Fees
        assertGt(collateralToken.balance(address(lender2)), COLLATERAL_BALANCE);
        assertLt(collateralToken.balance(address(borrower)), COLLATERAL_BALANCE);
    }

    function collateralBalances() public view {
        console.log("*********************************");
        console.log("CollateralToken balance");
        console.log("*********************************");
        console.log("Lender1", (collateralToken.balance(address(lender1)) / 1e18), "CTK");
        console.log("Lender2", (collateralToken.balance(address(lender2)) / 1e18), "CTK");
        console.log("borrower", (collateralToken.balance(address(borrower)) / 1e18), "CTK");
        console.log("LenderContract", (collateralToken.balance(address(lender)) / 1e18), "CTK");
        console.log("*********************************");
    }

    function loanTokenBalances() public view {
        console.log("*********************************");
        console.log("LoanToken balance");
        console.log("Lender1", (loanToken.balance(address(lender1)) / 1e18), "LTK");
        console.log("Lender2", (loanToken.balance(address(lender2)) / 1e18), "LTK");
        console.log("borrower", (loanToken.balance(address(borrower)) / 1e18), "LTK");
        console.log("LenderContract", (loanToken.balance(address(lender)) / 1e18), "LTK");
        console.log("*********************************");
    }

    function stages(
        bytes32 poolIdOne,
        bytes32 poolIdTwo,
        bytes32 poolIdThree,
        address loandLender,
        address loanBorrower,
        bool loansData,
        bool tokenBalances
    ) public {
        if (tokenBalances) {
            //collateralBalances();
            // loanTokenBalances();
        }
        if (loansData) {
            loanLogs(poolIdOne, poolIdTwo, poolIdThree, loandLender, loanBorrower);
        }
    }

    function loanLogs(
        bytes32 poolIdOne,
        bytes32 poolIdTwo,
        bytes32 poolIdThree,
        address loandLender,
        address loanBorrower
    ) public {
        console.log("*********************************");
        (,,,, uint256 poolBalance,,,, uint256 outstandingLoans) = lender.pools(poolIdOne);
        console.log("Pool1, Loans", outstandingLoans, "Balance", poolBalance);
        (,,,, poolBalance,,,, outstandingLoans) = lender.pools(poolIdTwo);
        console.log("Pool2, Loans", outstandingLoans, "Balance", poolBalance);
        (,,,, poolBalance,,,, outstandingLoans) = lender.pools(poolIdThree);
        console.log("Pool3, Loans", outstandingLoans, "Balance", poolBalance);
        console.log("*********************************");
        console.log("Lender", loandLender);
        console.log("Borrower", loanBorrower);
        console.log("*********************************");
    }
}

// Loan must be active
// Loan must be up for auction
