// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity 0.8.20;

import {Token} from "../types/types.sol";
interface ITtcVault {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);
    event TtcLogicContractSet(address indexed ttcLogicContract);
    event SpendApproved(address indexed token, address indexed spender, uint256 amount);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    function transferOwnership(address _newOwner) external;
    function setTtcLogicContract(address _ttcLogicContract) external;
    function approveSpendToLogicContract(Token[10] calldata tokens) external;
}
