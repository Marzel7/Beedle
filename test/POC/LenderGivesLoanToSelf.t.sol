// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "forge-std/console.sol";
import "../../src/Lender.sol";

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

contract LenderTest is Test {
    Lender public lender;

    TERC20 public loanToken;
    TERC20 public collateralToken;

    address public lender1 = address(0x1);
    address public borrower = address(0x3);
    address public fees = address(0x4);

    uint256 LENDER_LOAN_TOKEN_BALANCE = 100000 * 10 ** 18;
    uint256 COLLATERAL_BALANCE = 100000 * 10 ** 18;
    uint256 BORROWER_LOAN_TOKEN_BALANCE = 100000 * 10 ** 18;

    uint256 POOL_LOAN_TOKEN_BALANCE = 10000 * 10 ** 18;
    uint256 LOAN_AMOUNT = 1000 * 10 ** 18;

    function setUp() public {
        lender = new Lender();
        loanToken = new TERC20();
        collateralToken = new TERC20();

        loanToken.mint(address(lender1), LENDER_LOAN_TOKEN_BALANCE);
        loanToken.mint(address(borrower), BORROWER_LOAN_TOKEN_BALANCE);

        collateralToken.mint(address(borrower), COLLATERAL_BALANCE);

        vm.startPrank(lender1);
        loanToken.approve(address(lender), LENDER_LOAN_TOKEN_BALANCE);
        collateralToken.approve(address(lender), COLLATERAL_BALANCE);

        vm.startPrank(borrower);
        loanToken.approve(address(lender), LENDER_LOAN_TOKEN_BALANCE);
        collateralToken.approve(address(lender), COLLATERAL_BALANCE);
    }

    function test_LenderGivesLoanToSelf() public {
        bytes32 poolIdOne;

        // create pool1
        vm.startPrank(lender1);
        Pool memory p1 = Pool({
            lender: lender1,
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            minLoanSize: 100 * 10 ** 18,
            poolBalance: POOL_LOAN_TOKEN_BALANCE,
            maxLoanRatio: 2 * 10 ** 18,
            auctionLength: 1 days,
            interestRate: 10,
            outstandingLoans: 0
        });
        poolIdOne = lender.setPool(p1);
        (,,,, uint256 poolBalance,,,, uint256 p1OutStandingLoans) = lender.pools(poolIdOne);

        // poolBalance 10000000000000000000000
        // p1OutStandingLoans 0

        vm.startPrank(borrower);
        uint256 borrowerTokenAmount = loanToken.balance(borrower);
        assertEq(borrowerTokenAmount, BORROWER_LOAN_TOKEN_BALANCE);

        // borrow from pool1
        Borrow memory b1 = Borrow({poolId: poolIdOne, debt: LOAN_AMOUNT, collateral: 1000 * 10 ** 18});
        Borrow[] memory borrows = new Borrow[](1);
        borrows[0] = b1;
        lender.borrow(borrows);

        (,,,, poolBalance,,,, p1OutStandingLoans) = lender.pools(poolIdOne);
        assertEq(p1OutStandingLoans, 1000 * 10 ** 18);
        assertEq(poolBalance, POOL_LOAN_TOKEN_BALANCE - (1000 * 10 ** 18));

        // poolBalance 9000000000000000000000
        // p1OutStandingLoans 1000000000000000000000

        // pool balance and outstanding loans prior to giveLoan
        (,,,, poolBalance,,,, p1OutStandingLoans) = lender.pools(poolIdOne);
        assertEq(p1OutStandingLoans, LOAN_AMOUNT);
        assertEq(poolBalance, POOL_LOAN_TOKEN_BALANCE - LOAN_AMOUNT);

        // loanId, poolId for lender to pay loan
        uint256[] memory loanIds = new uint256[](1);
        loanIds[0] = 0;

        bytes32[] memory poolIds = new bytes32[](1);
        poolIds[0] = poolIdOne;

        vm.warp(10 days);

        vm.startPrank(lender1);
        lender.giveLoan(loanIds, poolIds);

        // // pool balance and outstanding loans after giveLoan from lender to self
        (,,,, poolBalance,,,, p1OutStandingLoans) = lender.pools(poolIdOne);
        assertGt(p1OutStandingLoans, LOAN_AMOUNT);

        // poolBalance 8999997260277143581939
        // p1OutStandingLoans 1000027397228564180618
    }
}
