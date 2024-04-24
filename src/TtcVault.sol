// SPDX-License-Identifier: GPL-3.0
pragma solidity 0.8.20;

import {ITtcVault} from "./interfaces/ITtcVault.sol";
import {Token} from "./types/types.sol";

import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/** 
 * @title TtcVault
 * @author Ruslan Akhtariev
 * @notice Vault contract for storing TTC constituent tokens
*/
contract TtcVault is ITtcVault, ReentrancyGuard {
    address public continuumModerator;
    address public ttcLogicContract;

    // only moderator
    modifier onlyModerator() {
        require(msg.sender == continuumModerator, "Only owner can call this function");
        _;
    }

    /**
     * @notice Constructor to initialize a TTC vault contract
     */
    constructor() {
        continuumModerator = msg.sender;
    }

    /** 
     * @notice Transfer ownership of the contract
     * @param _newOwner Address of the new owner
     * @dev Will be used to eventually transfer ownerwhip to DAO contract
     */
    function transferOwnership(address _newOwner) public onlyModerator {
        continuumModerator = _newOwner;

        emit OwnershipTransferred(msg.sender, _newOwner);
    }

    /** 
     * @notice Set the address of the TTC logic contract
     * @param _ttcLogicContract Address of the TTC logic contract
     * @dev Subject to change on logic upgrades
     */
    function setTtcLogicContract(address _ttcLogicContract) public onlyModerator {
        ttcLogicContract = _ttcLogicContract;

        emit TtcLogicContractSet(_ttcLogicContract);
    }

    /** 
     * @notice Approve spending of TTC constituent tokens to the logic contract
     * @param tokens Array of Token structs
     */
    function approveSpendToLogicContract(Token[10] calldata tokens) public onlyModerator {
        for (uint256 i = 0; i < tokens.length; i++) {
            IERC20(tokens[i].tokenAddress).approve(ttcLogicContract, type(uint256).max);
            emit SpendApproved(tokens[i].tokenAddress, ttcLogicContract, type(uint256).max);
        }

        emit Approval(address(this), ttcLogicContract, type(uint256).max);
    }
}