// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.13;

import "forge-std/Test.sol";
import "../src/Lender.sol";

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
    address public fees = address(0x4);

    uint256 public borrowerFee = 50;
    uint256 LOANTOKEN_BALANCE = 100000 * 10 ** 18;
    uint256 COLLATERAL_BALANCE = 100000 * 10 ** 18;
    uint256 BORROWER_INIT_LOANTOKEN_BALANCE = 100000 * 10 ** 18;

    uint256 POOLA_LOAN_TOKEN_BALANCE = 4000 * 10 ** 18;
    uint256 POOLB_LOAN_TOKEN_BALANCE = 1000 * 10 ** 18;

    function setUp() public {
        lender = new Lender();
        loanToken = new TERC20();
        collateralToken = new TERC20();

        loanToken.mint(address(lender1), LOANTOKEN_BALANCE);
        loanToken.mint(address(lender2), LOANTOKEN_BALANCE);
        loanToken.mint(address(borrower), BORROWER_INIT_LOANTOKEN_BALANCE);

        collateralToken.mint(address(borrower), COLLATERAL_BALANCE);

        vm.startPrank(lender1);
        loanToken.approve(address(lender), LOANTOKEN_BALANCE);
        collateralToken.approve(address(lender), COLLATERAL_BALANCE);

        vm.startPrank(borrower);
        loanToken.approve(address(lender), LOANTOKEN_BALANCE);
        collateralToken.approve(address(lender), COLLATERAL_BALANCE);
    }

    function test_createPool() public {
        vm.startPrank(lender1);
        Pool memory p = Pool({
            lender: lender1,
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            minLoanSize: 100 * 10 ** 18,
            poolBalance: 1000 * 10 ** 18,
            maxLoanRatio: 2 * 10 ** 18,
            auctionLength: 1 days,
            interestRate: 1000,
            outstandingLoans: 0
        });
        lender.setPool(p);

        uint256 loanTokenBalance = loanToken.balance(address(lender));
        assertEq(loanTokenBalance, 1000 * 10 ** 18);

        vm.startPrank(lender2);
        Pool memory p2 = Pool({
            lender: lender2,
            loanToken: address(loanToken),
            collateralToken: address(collateralToken),
            minLoanSize: 100 * 10 ** 18,
            poolBalance: 1000 * 10 ** 18,
            maxLoanRatio: 2 * 10 ** 18,
            auctionLength: 1 days,
            interestRate: 1000,
            outstandingLoans: 0
        });
        lender.setPool(p2);

        loanTokenBalance = loanToken.balance(address(lender));
        assertEq(loanTokenBalance, 2000 * 10 ** 18);

        bytes32 poolId2 = lender.getPoolId(address(lender2), address(loanToken), address(collateralToken));
        lender.removeFromPool(poolId2, p.poolBalance);
    }
}
