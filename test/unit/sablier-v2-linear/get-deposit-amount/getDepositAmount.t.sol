// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import { SablierV2LinearUnitTest } from "../SablierV2LinearUnitTest.t.sol";

contract SablierV2Linear__GetDepositAmount__UnitTest is SablierV2LinearUnitTest {
    /// @dev When the stream does not exist, it should return zero.
    function testGetDepositAmount__StreamNonExistent() external {
        uint256 nonStreamId = 1729;
        uint256 actualDepositAmount = sablierV2Linear.getDepositAmount(nonStreamId);
        uint256 expectedDepositAmount = 0;
        assertEq(actualDepositAmount, expectedDepositAmount);
    }

    /// @dev When the stream exists, it should return the correct deposit amount.
    function testGetDepositAmount() external {
        uint256 streamId = createDefaultStream();
        uint256 actualDepositAmount = sablierV2Linear.getDepositAmount(streamId);
        uint256 expectedDepositAmount = stream.depositAmount;
        assertEq(actualDepositAmount, expectedDepositAmount);
    }
}
