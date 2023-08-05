// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import "./utils/Errors.sol";
import "./utils/Structs.sol";

import {IERC20} from "./interfaces/IERC20.sol";
import {Ownable} from "./utils/Ownable.sol";

contract Lender is Ownable {
    event PoolCreated(bytes32 indexed poolId, Pool pool);
    event PoolUpdated(bytes32 indexed poolId, Pool pool);
    event PoolBalanceUpdated(bytes32 indexed poolId, uint256 newBalance);
    event PoolInterestRateUpdated(bytes32 indexed poolId, uint256 newInterestRate);
    event PoolMaxLoanRatioUpdated(bytes32 indexed poolId, uint256 newMaxLoanRatio);
    event Borrowed(
        address indexed borrower,
        address indexed lender,
        uint256 indexed loanId,
        uint256 debt,
        uint256 collateral,
        uint256 interestRate,
        uint256 startTimestamp
    );
    event Repaid(
        address indexed borrower,
        address indexed lender,
        uint256 indexed loanId,
        uint256 debt,
        uint256 collateral,
        uint256 interestRate,
        uint256 startTimestamp
    );
    event AuctionStart(
        address indexed borrower,
        address indexed lender,
        uint256 indexed loanId,
        uint256 debt,
        uint256 collateral,
        uint256 auctionStartTime,
        uint256 auctionLength
    );
    event LoanBought(uint256 loanId);
    event LoanSiezed(address indexed borrower, address indexed lender, uint256 indexed loanId, uint256 collateral);
    event Refinanced(uint256 loanId);

    uint256 public constant MAX_INTEREST_RATE = 100000; // @audit maximum interest rate is %1000

    uint256 public constant MAX_AUCTION_LENGTH = 3 days; // @audit maximum auction length is 3 days

    uint256 public lenderFee = 1000; // @audit the fee taken by the protocol in BIPS = 1000

    uint256 public borrowerFee = 50; // @audit the fee taken by the protocol in BIPS = 50

    address public feeReceiver; // @audit the address of the fee receiver

    mapping(bytes32 => Pool) public pools; // @audit mapping of poolId to pool (poolId is keccak256(lender, loanToken, collateralToken))
    Loan[] public loans; // @audit array of Loans

    constructor() Ownable(msg.sender) {
        // @audit feeReceiver is msg.sender
        feeReceiver = msg.sender;
    }

    function setLenderFee(uint256 _fee) external onlyOwner {
        // @audit set the lender fee, _fee is the new fee
        if (_fee > 5000) revert FeeTooHigh(); // @audit only callable by the owner
        lenderFee = _fee; // @audit _fee must be below 5000
    }

    function setBorrowerFee(uint256 _fee) external onlyOwner {
        // @audit set the borrower fee, _fee is the new fee
        if (_fee > 500) revert FeeTooHigh(); // @audit only callable by the owner
        borrowerFee = _fee; // @audit _fee must be below 500
    }

    function setFeeReceiver(address _feeReceiver) external onlyOwner {
        // @audit set the fee receiver
        feeReceiver = _feeReceiver; // @audit only callable by the owner
    }

    /*                         LOAN INFO                          */
    function getPoolId(
        address lender,
        address loanToken,
        address collateralToken // @audit pure function to return poolId
    ) public pure returns (bytes32 poolId) {
        poolId = keccak256(abi.encode(lender, loanToken, collateralToken));
    }

    function getLoanDebt(uint256 loanId) external view returns (uint256 debt) {
        // @audit view function to return debt for loan id
        Loan memory loan = loans[loanId]; // @audit loan from loans mapping
            // @audit calculate the accrued interest
        (uint256 interest, uint256 fees) = _calculateInterest(loan); // @audit interest, fees from _calculateInterest(loan)
        debt = loan.debt + interest + fees; // @audit calculate debt
    }

    /*                        BASIC LOANS                         */
    // @audit set the info for a pool
    // @audit updates pool info for msg.sender
    // @param p = the new pool info

    function setPool(Pool calldata p) public returns (bytes32 poolId) {
        // validate the pool
        if ( // @audit validate pool, input Pool struct p
            p.lender != msg.sender || p.minLoanSize == 0 || p.maxLoanRatio == 0 || p.auctionLength == 0 // @audit p.lender = msg.sender
                || p.auctionLength > MAX_AUCTION_LENGTH || p.interestRate > MAX_INTEREST_RATE // @audit p.minLoanSize != 0
        ) revert PoolConfig(); // @audit p.maxLoanRatio != 0
            // @audit p.auctionLength != 0
            // @audit p.auctionLength !> MAX_AUCTION_LENGTH
            // @audit p.interestRate !> MAX_INTEREST_RATE
            // @audit check if they already have a pool balance
        poolId = getPoolId(p.lender, p.loanToken, p.collateralToken); // @audit getPoolId

        // @audit you can't change the outstanding loans
        if (p.outstandingLoans != pools[poolId].outstandingLoans) {
            // @audit p.outstandingLoans == pools[poolId].outstandingLoans
            revert PoolConfig(); // @audit TBD
        }

        uint256 currentBalance = pools[poolId].poolBalance; // @audit currentBalance = poolBalance for poolId

        if (p.poolBalance > currentBalance) {
            // @audit if p.poolBalance >  currentBalance
            // @audit if new balance > current balance then transfer the difference from the lender
            IERC20(p.loanToken).transferFrom(p.lender, address(this), p.poolBalance - currentBalance); // @audit transferFrom lender, address(this), updated balance
        } else if (p.poolBalance < currentBalance) {
            // @audit
            // @audit if new balance < current balance then transfer the difference back to the lender
            IERC20(p.loanToken).transfer(p.lender, currentBalance - p.poolBalance);
        }

        emit PoolBalanceUpdated(poolId, p.poolBalance);

        if (pools[poolId].lender == address(0)) {
            // @audit  if the pool doesn't exist then create it
            // @audit  if the pool does exist then update it
            emit PoolCreated(poolId, p);
        } else {
            emit PoolUpdated(poolId, p);
        }

        pools[poolId] = p;
    }

    /// @param poolId the id of the pool to add to
    /// @param amount the amount to add
    function addToPool(bytes32 poolId, uint256 amount) external {
        // @audit add to the pool balance
        if (pools[poolId].lender != msg.sender) revert Unauthorized(); // @audit can only be called by the pool lender
        if (amount == 0) revert PoolConfig(); // @audit cannot update with zero amount
        _updatePoolBalance(poolId, pools[poolId].poolBalance + amount); // @audit _updatePoolBalance with current balance + amount

        IERC20(pools[poolId].loanToken).transferFrom(msg.sender, address(this), amount); // @audit transfer the loan tokens from the lender to the contract
    }

    /// @param poolId the id of the pool to remove from
    /// @param amount the amount to remove
    function removeFromPool(bytes32 poolId, uint256 amount) external {
        // @audit remove from the pool balance
        if (pools[poolId].lender != msg.sender) revert Unauthorized(); // @audit can only be called by the pool lender
        if (amount == 0) revert PoolConfig(); // @audit cannot update with zero amount
        _updatePoolBalance(poolId, pools[poolId].poolBalance - amount); // @audit _updatePoolBalance with current balance - amount

        IERC20(pools[poolId].loanToken).transfer(msg.sender, amount); // @audit transfer the loan tokens from the contract to the lender
    }

    /// @param poolId the id of the pool to update
    /// @param maxLoanRatio the new max loan ratio
    function updateMaxLoanRatio(bytes32 poolId, uint256 maxLoanRatio) external {
        /// @notice update the max loan ratio for a pool
        if (pools[poolId].lender != msg.sender) revert Unauthorized(); // @audit  can only be called by the pool lender
        if (maxLoanRatio == 0) revert PoolConfig(); // @audit maxLoanRatio != 0
        pools[poolId].maxLoanRatio = maxLoanRatio; // @audit update poolId.maxLoanRatio
        emit PoolMaxLoanRatioUpdated(poolId, maxLoanRatio);
    }

    /// @param poolId the id of the pool to update
    /// @param interestRate the new interest rate
    function updateInterestRate(bytes32 poolId, uint256 interestRate) external {
        /// @notice update the interest rate for a pool
        if (pools[poolId].lender != msg.sender) revert Unauthorized(); // @audit can only be called by the pool lender
        if (interestRate > MAX_INTEREST_RATE) revert PoolConfig(); // @audit interestRate !> MAX_INTEREST_RATE
        pools[poolId].interestRate = interestRate; // @audit uopdate poolId.interestRate
        emit PoolInterestRateUpdated(poolId, interestRate);
    }

    /// @notice borrow a loan from a pool
    /// can be called by anyone
    /// you are allowed to open many borrows at once
    /// @param borrows a struct of all desired debt positions to be opened
    function borrow(Borrow[] calldata borrows) public {
        for (uint256 i = 0; i < borrows.length; i++) {
            // @audit iterate through borrows
            bytes32 poolId = borrows[i].poolId; // @audit retrieve poolId
            uint256 debt = borrows[i].debt; // @audit retrieve debt
            uint256 collateral = borrows[i].collateral; // @audit retrieve collateral

            Pool memory pool = pools[poolId]; // @audit retrieve pool using poolId, get the pool info

            if (pool.lender == address(0)) revert PoolConfig(); // @audit make sure the pool exists
                // @audit validate the loan
            if (debt < pool.minLoanSize) revert LoanTooSmall(); // @audit debt < pool.minLoanSize
            if (debt > pool.poolBalance) revert LoanTooLarge(); // @audit debt > pool.poolBalance
            if (collateral == 0) revert ZeroCollateral(); // @audit ZeroCollateral check
                // @audit make sure the user isn't borrowing too much
            uint256 loanRatio = (debt * 10 ** 18) / collateral; // @audit calculate loanRatio
            if (loanRatio > pool.maxLoanRatio) revert RatioTooHigh(); // @audit RatioTooHigh check

            Loan memory loan = Loan({ // @audit create the loan
                lender: pool.lender,
                borrower: msg.sender,
                loanToken: pool.loanToken,
                collateralToken: pool.collateralToken,
                debt: debt,
                collateral: collateral,
                interestRate: pool.interestRate, // @audit the interest rate of the loan per second (in debt tokens)
                startTimestamp: block.timestamp,
                auctionStartTimestamp: type(uint256).max, // @audit the timestamp of a refinance auction start
                auctionLength: pool.auctionLength // @audit the refinance auction length
            });
            // @audit update the pool balance
            _updatePoolBalance(poolId, pools[poolId].poolBalance - debt);
            pools[poolId].outstandingLoans += debt; // @audit add debt to poolid.outstandingLoans
                // @audit calculate the fees
            uint256 fees = (debt * borrowerFee) / 10000; // @audit-issue explain fees
                // @audit transfer fees
            IERC20(loan.loanToken).transfer(feeReceiver, fees);
            // @audit transfer the loan tokens from the pool to the borrower
            IERC20(loan.loanToken).transfer(msg.sender, debt - fees); // @audit fees subtracted from loanToken requested amount

            IERC20(loan.collateralToken).transferFrom(msg.sender, address(this), collateral); // @audit transfer the collateral tokens from the borrower to the contract
            loans.push(loan); // @audit push loan to Loans
            emit Borrowed(
                msg.sender, pool.lender, loans.length - 1, debt, collateral, pool.interestRate, block.timestamp
            );
        }
    }

    /// @notice repay a loan
    /// can be called by anyone
    /// @param loanIds the ids of the loans to repay
    function repay(uint256[] calldata loanIds) public {
        for (uint256 i = 0; i < loanIds.length; i++) {
            // @audit iterate through loanIds param
            uint256 loanId = loanIds[i]; // @audit retrieve loanId
                // @audit get the loan info
            Loan memory loan = loans[loanId]; // @audit copy loan into memory
                // @audit calculate the interest
            (uint256 lenderInterest, uint256 protocolInterest) = _calculateInterest(loan); // @audit lenderInterest & protocolInterest

            bytes32 poolId = getPoolId(loan.lender, loan.loanToken, loan.collateralToken); // @audit retrieve poolId

            // @audit update the pool balance
            _updatePoolBalance(poolId, pools[poolId].poolBalance + loan.debt + lenderInterest); // @audit _updatePoolBalance
            pools[poolId].outstandingLoans -= loan.debt; // @audit deduct loan.debt from pool.outstandingLoans

            // @audit transfer the loan tokens from the borrower to the pool
            IERC20(loan.loanToken).transferFrom(msg.sender, address(this), loan.debt + lenderInterest);
            // @audit transfer the protocol fee to the fee receiver
            IERC20(loan.loanToken).transferFrom(msg.sender, feeReceiver, protocolInterest);
            // @audit transfer the collateral tokens from the contract to the borrower
            IERC20(loan.collateralToken).transfer(loan.borrower, loan.collateral);
            emit Repaid(
                msg.sender, loan.lender, loanId, loan.debt, loan.collateral, loan.interestRate, loan.startTimestamp
            );
            // @audit-issue investigate
            delete loans[loanId]; // @audit delete the loan
        }
    }

    /*                         REFINANCE                          */

    /// @notice give your loans to another pool
    /// can only be called by the lender
    /// @param loanIds the ids of the loans to give
    /// @param poolIds the id of the pools to give to
    function giveLoan(uint256[] calldata loanIds, bytes32[] calldata poolIds) external {
        // @audit-issue no array length check for loanIds, poolIds
        for (uint256 i = 0; i < loanIds.length; i++) {
            // @audit lterate through loanIds
            uint256 loanId = loanIds[i]; // @audit retrieve loanId
            bytes32 poolId = poolIds[i]; // @audit retrieve poolId
                // @audit get the loan info
            Loan memory loan = loans[loanId];
            // @audit validate the loan
            if (msg.sender != loan.lender) revert Unauthorized(); // @audit msg.sender must be lender - Unauthorized()
                // @audit get the pool info
            Pool memory pool = pools[poolId]; // @audit copy pool into memory
                // @audit validate the new loan
            if (pool.loanToken != loan.loanToken) revert TokenMismatch(); // @audit TokenMismatch() for poolToken
            if (pool.collateralToken != loan.collateralToken) {
                // @audit TokenMismatch() for collateralToken
                revert TokenMismatch();
            }
            // @audit new interest rate cannot be higher than old interest rate
            if (pool.interestRate > loan.interestRate) revert RateTooHigh();
            // @audit auction length cannot be shorter than old auction length
            if (pool.auctionLength < loan.auctionLength) revert AuctionTooShort();
            // @audit calculate the interest from _calculateInterest
            (uint256 lenderInterest, uint256 protocolInterest) = _calculateInterest(loan); // @audit lenderInterest, protocolInterest
            uint256 totalDebt = loan.debt + lenderInterest + protocolInterest; // @audit calculate totalDebt, loan.debt + lenderInterest + protocolInterest
            if (pool.poolBalance < totalDebt) revert PoolTooSmall(); // @audit PoolTooSmall()
            if (totalDebt < pool.minLoanSize) revert LoanTooSmall(); // @audit LoanTooSmall()
            uint256 loanRatio = (totalDebt * 10 ** 18) / loan.collateral; // @audit-issue calculate loanRatio, why scale totalDebt?
            if (loanRatio > pool.maxLoanRatio) revert RatioTooHigh(); // @audit RatioTooHigh
                // @audit update the pool balance of the new lender
            _updatePoolBalance(poolId, pool.poolBalance - totalDebt); // @audit-issue why deduct totalDebt from poolId?
            pools[poolId].outstandingLoans += totalDebt; // @audit add totalDebt to poolId.outstandingLoans

            // @audit update the pool balance of the old lender
            bytes32 oldPoolId = getPoolId(loan.lender, loan.loanToken, loan.collateralToken); // @audit retrieve oldPoolId
            _updatePoolBalance(oldPoolId, pools[oldPoolId].poolBalance + loan.debt + lenderInterest); // @audit-issue _updatePoolBalance(oldPoolId), oldPoolId.poolBalance + loan.debt + lenderInterest
            pools[oldPoolId].outstandingLoans -= loan.debt; // @audit remove debt from oldPoolId

            IERC20(loan.loanToken).transfer(feeReceiver, protocolInterest); // @audit transfer the protocol fee to the governance

            emit Repaid(
                loan.borrower,
                loan.lender,
                loanId,
                loan.debt + lenderInterest + protocolInterest,
                loan.collateral,
                loan.interestRate,
                loan.startTimestamp
            );

            // @audit update the loan with the new info
            loans[loanId].lender = pool.lender; // @audit update lender
            loans[loanId].interestRate = pool.interestRate; // @audit update interestRate
            loans[loanId].startTimestamp = block.timestamp; // @audit update startTimestamp
            loans[loanId].auctionStartTimestamp = type(uint256).max; // @audit update auctionStartTimestamp
            loans[loanId].debt = totalDebt; // @audit-issue updated debt, includes lenderInterest + protocolInterest;

            emit Borrowed(
                loan.borrower,
                pool.lender,
                loanId,
                loans[loanId].debt,
                loans[loanId].collateral,
                pool.interestRate,
                block.timestamp
            );
        }
    }

    /// @notice start a refinance auction
    /// can only be called by the lender
    /// @param loanIds the ids of the loans to refinance
    function startAuction(uint256[] calldata loanIds) public {
        for (uint256 i = 0; i < loanIds.length; i++) {
            /// @audit iterate through loanIds
            uint256 loanId = loanIds[i]; // @audit retrieve loan
                // @audit get the loan info
            Loan memory loan = loans[loanId]; // @audit copy loan into memory
                // @audit validate the loan
            if (msg.sender != loan.lender) revert Unauthorized(); // @audit Unauthorized if not loan.lender
            if (loan.auctionStartTimestamp != type(uint256).max) {
                // @audit loan.auctionStartTimestamp must = type(uint256).max)
                revert AuctionStarted(); // @audit else revert AuctionStarted()
            }

            loans[loanId].auctionStartTimestamp = block.timestamp; // @audit-issue set the auction start timestamp (block.timestamp)
            emit AuctionStart(
                loan.borrower, loan.lender, loanId, loan.debt, loan.collateral, block.timestamp, loan.auctionLength
            );
        }
    }

    /// @notice buy a loan in a refinance auction
    /// can be called by anyone but you must have a pool with tokens
    /// @param loanId the id of the loan to refinance
    /// @param poolId the pool to accept
    function buyLoan(uint256 loanId, bytes32 poolId) public {
        // get the loan info
        Loan memory loan = loans[loanId];
        // validate the loan
        if (loan.auctionStartTimestamp == type(uint256).max) {
            // @audit auction must be live else revert AuctionNotStarted
            revert AuctionNotStarted();
        }
        if (block.timestamp > loan.auctionStartTimestamp + loan.auctionLength) {
            // @audit auction ended
            revert AuctionEnded();
        }
        // calculate the current interest rate
        uint256 timeElapsed = block.timestamp - loan.auctionStartTimestamp; // @audit timeElapsed from now - loan.auctionStartTimestamp
        uint256 currentAuctionRate = (MAX_INTEREST_RATE * timeElapsed) / loan.auctionLength; // @audit-issue currentAuctionRate calc
            // @audit validate the rate
        if (pools[poolId].interestRate > currentAuctionRate) revert RateTooHigh(); // @audit revert RateTooHigh();
            // calculate the interest
        (uint256 lenderInterest, uint256 protocolInterest) = _calculateInterest(loan); // @audit lenderInterest, protocolInterest

        // reject if the pool is not big enough
        uint256 totalDebt = loan.debt + lenderInterest + protocolInterest;
        if (pools[poolId].poolBalance < totalDebt) revert PoolTooSmall(); // @audit revert if PoolTooSmall

        // if they do have a big enough pool then transfer from their pool
        _updatePoolBalance(poolId, pools[poolId].poolBalance - totalDebt); // @audit-issue _updatePoolBalance - totalDebt
        pools[poolId].outstandingLoans += totalDebt; // @audit-issue add totalDebt to poolId.outstandingLoans

        // now update the pool balance of the old lender
        bytes32 oldPoolId = getPoolId(loan.lender, loan.loanToken, loan.collateralToken); // @audit retrieve oldPoolId
        _updatePoolBalance(oldPoolId, pools[oldPoolId].poolBalance + loan.debt + lenderInterest); // @audit _updatePoolBalance , oldPoolId balance + loan.debt + lenderInterest)
        pools[oldPoolId].outstandingLoans -= loan.debt; // @audit-issue oldPoolId.outstandingLoans -= loan.debt

        // transfer the protocol fee to the governance
        IERC20(loan.loanToken).transfer(feeReceiver, protocolInterest);

        emit Repaid(
            loan.borrower,
            loan.lender,
            loanId,
            loan.debt + lenderInterest + protocolInterest,
            loan.collateral,
            loan.interestRate,
            loan.startTimestamp
        );

        // update the loan with the new info
        loans[loanId].lender = msg.sender; // @audit update lender
        loans[loanId].interestRate = pools[poolId].interestRate; // @audit update interestRate
        loans[loanId].startTimestamp = block.timestamp; // @audit update startTimestamp
        loans[loanId].auctionStartTimestamp = type(uint256).max; // @audit reset auctionStartTimestamp to not up for auction
        loans[loanId].debt = totalDebt; // @audit loanId.debt = totalDebt

        emit Borrowed(
            loan.borrower,
            msg.sender,
            loanId,
            loans[loanId].debt,
            loans[loanId].collateral,
            pools[poolId].interestRate,
            block.timestamp
        );
        emit LoanBought(loanId);
    }

    /// @notice make a pool and buy the loan in one transaction
    /// can be called by anyone
    /// @param p the pool info
    /// @param loanId the id of the loan to refinance
    function zapBuyLoan(Pool calldata p, uint256 loanId) external {
        // @audit-issue what is this exactly
        bytes32 poolId = setPool(p); // @audit-issue create pool
        buyLoan(loanId, poolId); // @audit-issue buyLoan
    } // @audit-issue what's the point??

    /// @notice sieze a loan after a failed refinance auction
    /// can be called by anyone
    /// @param loanIds the ids of the loans to sieze
    function seizeLoan(uint256[] calldata loanIds) public {
        for (uint256 i = 0; i < loanIds.length; i++) {
            // @audit iterate through loanIds
            uint256 loanId = loanIds[i]; // @audit retrieve loanId
                // get the loan info
            Loan memory loan = loans[loanId]; // @audit copy loan into memory
                // validate the loan
            if (loan.auctionStartTimestamp == type(uint256).max) {
                // @audit loan is up for auction, else revert
                revert AuctionNotStarted();
            }
            if (block.timestamp < loan.auctionStartTimestamp + loan.auctionLength) revert AuctionNotEnded(); // @audit-issue auction not ended
                // calculate the fee
            uint256 govFee = (borrowerFee * loan.collateral) / 10000; // @audit calculate govFee
                // @audit transfer the protocol fee to governance
            IERC20(loan.collateralToken).transfer(feeReceiver, govFee);
            // @audit transfer the collateral tokens from the contract to the lender
            IERC20(loan.collateralToken).transfer(loan.lender, loan.collateral - govFee);

            bytes32 poolId = keccak256(abi.encode(loan.lender, loan.loanToken, loan.collateralToken)); // @audit get poolId

            // @audit update the pool outstanding loans
            pools[poolId].outstandingLoans -= loan.debt;

            emit LoanSiezed(loan.borrower, loan.lender, loanId, loan.collateral);
            // @audit delete the loan
            delete loans[loanId];
        }
    }

    /// @notice refinance a loan to a new offer
    /// can only be called by the borrower
    /// @param refinances a struct of all desired debt positions to be refinanced
    function refinance(Refinance[] calldata refinances) public {
        for (uint256 i = 0; i < refinances.length; i++) {
            // @audit iterate through refinances
            uint256 loanId = refinances[i].loanId; // @audit retrieve loanId
            bytes32 poolId = refinances[i].poolId; // @audit retrieve poolId
            bytes32 oldPoolId =
                keccak256(abi.encode(loans[loanId].lender, loans[loanId].loanToken, loans[loanId].collateralToken)); // @audit retrieve oldPoolId
            uint256 debt = refinances[i].debt; // @audit retrieve debt
            uint256 collateral = refinances[i].collateral; // @audit retrieve collateral

            // get the loan info
            Loan memory loan = loans[loanId]; // @audit copy loan into memory
                // validate the loan
            if (msg.sender != loan.borrower) revert Unauthorized();
            /// @audit can only be called by the borrower

            // get the pool info
            Pool memory pool = pools[poolId]; // @audit copy pool into memory
                // validate the new loan
            if (pool.loanToken != loan.loanToken) revert TokenMismatch(); // @audit TokenMismatch
            if (pool.collateralToken != loan.collateralToken) {
                // @audit TokenMismatch
                revert TokenMismatch();
            }
            if (pool.poolBalance < debt) revert LoanTooLarge(); // @audit LoanTooLarge
            if (debt < pool.minLoanSize) revert LoanTooSmall(); // @audit LoanTooSmall
            uint256 loanRatio = (debt * 10 ** 18) / collateral; // @audit loanRatio calc
            if (loanRatio > pool.maxLoanRatio) revert RatioTooHigh(); // @audit RatioTooHigh

            // calculate the interest
            (uint256 lenderInterest, uint256 protocolInterest) = _calculateInterest(loan); // @audit lenderInterest, protocolInterest
            uint256 debtToPay = loan.debt + lenderInterest + protocolInterest; // @audit debtToPay calc

            // update the old lenders pool
            _updatePoolBalance(oldPoolId, pools[oldPoolId].poolBalance + loan.debt + lenderInterest); // @audit-issue _updatePoolBalance(oldPoolId)
            pools[oldPoolId].outstandingLoans -= loan.debt; // @audit oldPoolId.outstandingLoans -= loan.debt

            // now lets deduct our tokens from the new pool
            _updatePoolBalance(poolId, pools[poolId].poolBalance - debt); // @audit _updatePoolBalance of new pool
            pools[poolId].outstandingLoans += debt; // @audit poolId.outstandingLoans += debt

            if (debtToPay > debt) {
                // @audit debt is the new desired debt amount
                // @audit debtToPay is the curent loan debt
                // @audit we owe more in debt so we need the borrower to give us more loan tokens
                IERC20(loan.loanToken).transferFrom(msg.sender, address(this), debtToPay - debt); // @audit-issue transfer the loan tokens from the borrower to the contract
            } else if (debtToPay < debt) {
                // we have excess loan tokens so we give some back to the borrower
                // first we take our borrower fee
                uint256 fee = (borrowerFee * (debt - debtToPay)) / 10000; // @audit fee calc
                IERC20(loan.loanToken).transfer(feeReceiver, fee); // @audit transfer loan token to feeReceiver
                    // @audit transfer the loan tokens from the contract to the borrower
                IERC20(loan.loanToken).transfer(msg.sender, debt - debtToPay - fee);
            }
            // transfer the protocol fee to governance
            IERC20(loan.loanToken).transfer(feeReceiver, protocolInterest); // @audit-issue transfer loan token to feeReceiver (again)

            loans[loanId].debt = debt; // @audit update loan debt
                // @audit update loan collateral
            if (collateral > loan.collateral) {
                // @audit if refanced collateral is > loan collateral
                // @audit transfer the collateral tokens from the borrower to the contract
                IERC20(loan.collateralToken).transferFrom(msg.sender, address(this), collateral - loan.collateral);
            } else if (collateral < loan.collateral) {
                // @audit if refanced collateral is < loan collateral
                // @audit transfer the collateral tokens from the contract to the borrower
                IERC20(loan.collateralToken).transfer(msg.sender, loan.collateral - collateral); // @audit-issue - Is this OK??
            }

            emit Repaid(msg.sender, loan.lender, loanId, debt, collateral, loan.interestRate, loan.startTimestamp);

            loans[loanId].collateral = collateral; // update loan collateral
            loans[loanId].interestRate = pool.interestRate; // update loan interest rate
            loans[loanId].startTimestamp = block.timestamp; // update loan start timestamp
            loans[loanId].auctionStartTimestamp = type(uint256).max; // update loan auction start timestamp
            loans[loanId].auctionLength = pool.auctionLength; // update loan auction length
            loans[loanId].lender = pool.lender; // update loan lender
            pools[poolId].poolBalance -= debt; // update pool balance
            emit Borrowed(msg.sender, pool.lender, loanId, debt, collateral, pool.interestRate, block.timestamp);
            emit Refinanced(loanId);
        }
    }

    /*                         INTERNAL                           */

    /// @notice calculates interest accrued on a loan
    /// @param l the loan to calculate for
    /// @return interest the interest accrued
    /// @return fees the fees accrued
    function _calculateInterest(Loan memory l) internal view returns (uint256 interest, uint256 fees) {
        uint256 timeElapsed = block.timestamp - l.startTimestamp; // @audit timeElapsed from start of Loan
        interest = (l.interestRate * l.debt * timeElapsed) / 10000 / 365 days; // @audit-issue interest calc
        fees = (lenderFee * interest) / 10000; // @audit-issue
        interest -= fees; // @audit return interest - fees
    }

    /// @notice update the balance of a pool and emit the event
    /// @param poolId the id of the pool to update
    /// @param newBalance the new balance of the pool
    function _updatePoolBalance(bytes32 poolId, uint256 newBalance) internal {
        pools[poolId].poolBalance = newBalance; // @audit update poolId with newBalance
        emit PoolBalanceUpdated(poolId, newBalance);
    }
}
