// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import { ISablierV2 } from "src/interfaces/ISablierV2.sol";

import { ClaimProtocolRevenues__Test } from "test/unit/shared/claim-protocol-revenues/claimProtocolRevenues.t.sol";
import { LinearTest } from "test/unit/linear/LinearTest.t.sol";
import { UnitTest } from "test/unit/UnitTest.t.sol";

contract ClaimProtocolRevenues__Linear__Test is LinearTest, ClaimProtocolRevenues__Test {
    function setUp() public virtual override(UnitTest, LinearTest) {
        LinearTest.setUp();
        sablierV2 = ISablierV2(linear);
    }
}
