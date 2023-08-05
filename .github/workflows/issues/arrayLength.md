## Medium

A lender can call giveLoan to their own pool resulting in increased outstanding loan balance and loss of poolBalance.

## Summary

In Lender.sol the giveLoan() function checks that the loan.lender is the msg.sender. However, it does not check whether the pool.lender belongs to the msg.sender. This enables a situation where a lender may intend to give a loan to another pool, but accidently send it to a pool they created.

## Vulnerability Details

In the giveLoan() function, the lender submits two arrays, (loanId and poolIds).

The expectation is that the lender submitting the function will ensure that the poolId is not associated with a pool they created.

A solution in such a situation is to verify that the pool lender and msg.sender are not the same address.

However, in the giveLoan() function we iterate through the loanIds array without performing this check, calculate fees and then call out to transfer() for each loanId seperately.

## Impact

If the Lender calls giveLoan() with a pool they created the pool pays interest accrued from the loan, increasing the loan balance. The pool balance will decrease due to the impact of protocol fees.

## Code Snippet

https://github.com/Cyfrin/2023-07-beedle/blob/main/src/Lender.sol#L355-L385

## Proof of Concept

```solidity

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


```



## Tools Used

Manual review

## Recommended Mitigation Steps

Add a check to the giveLoan() function that confirms the pool.lender is not msg.sender

```solidity

if (msg.sender != loan.lender) revert Unauthorized();

```





