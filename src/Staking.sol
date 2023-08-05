// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

import {IERC20} from "./interfaces/IERC20.sol";
import {Ownable} from "./utils/Ownable.sol";

interface FeeDistribution {
    function claim(address) external;
}

contract Staking is Ownable {
    /// @notice the balance of @
    uint256 public balance = 0; //
    /// @notice the index of the last update
    uint256 public index = 0;

    /// @notice mapping of user indexes
    mapping(address => uint256) public supplyIndex;

    /// @notice mapping of user balances
    mapping(address => uint256) public balances;  // @audit deposit/withdrawal balance
    /// @notice mapping of user claimable rewards
    mapping(address => uint256) public claimable;

    /// @notice the staking token
    IERC20 public immutable TKN;
    /// @notice the reward token
    IERC20 public immutable WETH;

    constructor(address _token, address _weth) Ownable(msg.sender) {
        TKN = IERC20(_token);
        WETH = IERC20(_weth);
    }

    /// @notice deposit tokens to stake
    /// @param _amount the amount to deposit
    function deposit(uint256 _amount) external {
        TKN.transferFrom(msg.sender, address(this), _amount);
        updateFor(msg.sender);
        balances[msg.sender] += _amount;
    }

    /// @notice withdraw tokens from stake
    /// @param _amount the amount to withdraw
    function withdraw(uint256 _amount) external {
        updateFor(msg.sender);
        balances[msg.sender] -= _amount;
        TKN.transfer(msg.sender, _amount);
    }

    /// @notice claim rewards
    function claim() external {
        updateFor(msg.sender);
        WETH.transfer(msg.sender, claimable[msg.sender]);
        claimable[msg.sender] = 0;
        balance = WETH.balanceOf(address(this));
    }

    /// @notice update the global index of earned rewards
    function update() public {
        uint256 totalSupply = TKN.balanceOf(address(this)); // @audit get staking token balance
        if (totalSupply > 0) {                              // @audit if total supply of staking token is > 0, otherwise end
            uint256 _balance = WETH.balanceOf(address(this)); // @audit get WETH balance of Staking contract
            if (_balance > balance) {                          // @audit if WETH balance is > reward token balance
                uint256 _diff = _balance - balance;             // @audit calculate difference
                if (_diff > 0) {                                   // @audit if diff > 0
                    uint256 _ratio = _diff * 1e18 / totalSupply;    // @audit calculate _ratio
                    if (_ratio > 0) {                               // @audit if ratio > 0
                        index = index + _ratio;                      // @audit update index
                        balance = _balance;                          // @audit reset balance to staking contract WETH balance
                    }
                }
            }
        }
    }

    /// @notice update the index for a user
    /// @param recipient the user to update
    function updateFor(address recipient) public {
        update();
        uint256 _supplied = balances[recipient];                    // @audit get recipient
        if (_supplied > 0) {                                        // @audit if _supplied > 0
            uint256 _supplyIndex = supplyIndex[recipient];          // @audit _supplyIndex for recipient
            supplyIndex[recipient] = index;
            uint256 _delta = index - _supplyIndex;                  // @audit WHAT???????????
            if (_delta > 0) {
                uint256 _share = _supplied * _delta / 1e18;
                claimable[recipient] += _share;                     //@audit update user claimable amount
            }
        } else {
            supplyIndex[recipient] = index;
        }
    }
}
