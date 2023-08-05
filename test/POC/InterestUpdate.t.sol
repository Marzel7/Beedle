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
    address public lender2 = address(0x2);
    address public borrower = address(0x3);

    uint256 public lenderFee = 1000;

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
        loanToken.mint(address(lender2), LENDER_LOAN_TOKEN_BALANCE);
        loanToken.mint(address(borrower), BORROWER_LOAN_TOKEN_BALANCE);

        collateralToken.mint(address(borrower), COLLATERAL_BALANCE);

        vm.startPrank(lender1);
        loanToken.approve(address(lender), LENDER_LOAN_TOKEN_BALANCE);
        collateralToken.approve(address(lender), COLLATERAL_BALANCE);

        vm.startPrank(lender2);
        loanToken.approve(address(lender), LENDER_LOAN_TOKEN_BALANCE);
        collateralToken.approve(address(lender), COLLATERAL_BALANCE);

        vm.startPrank(borrower);
        loanToken.approve(address(lender), LENDER_LOAN_TOKEN_BALANCE);
        collateralToken.approve(address(lender), COLLATERAL_BALANCE);
    }

    function test_InterestRateIncrease() public {
        bytes32 poolIdOne;
        bytes32 poolIdTwo;

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
            interestRate: 0,
            outstandingLoans: 0
        });

        poolIdOne = lender.setPool(p1);

        Pool memory p2 = Pool({
            lender: lender2,
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            minLoanSize: 100 * 10 ** 18,
            poolBalance: POOL_LOAN_TOKEN_BALANCE,
            maxLoanRatio: 2 * 10 ** 18,
            auctionLength: 1 days,
            interestRate: 5000,
            outstandingLoans: 0
        });
        vm.startPrank(lender2);
        poolIdTwo = lender.setPool(p2);

        vm.startPrank(borrower);
        Borrow memory b = Borrow({poolId: poolIdOne, debt: LOAN_AMOUNT, collateral: 1000 * 10 ** 18});
        Borrow[] memory borrows = new Borrow[](1);
        borrows[0] = b;
        lender.borrow(borrows);

        (,,,,,, uint256 interestRate,,,) = lender.loans(0);
        console.log(interestRate);

        uint256[] memory loanIds = new uint256[](1);
        loanIds[0] = 0;

        bytes32[] memory poolIds = new bytes32[](1);
        poolIds[0] = poolIdTwo;
    }
}
