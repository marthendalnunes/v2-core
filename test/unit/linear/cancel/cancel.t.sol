// SPDX-License-Identifier: UNLICENSED
pragma solidity >=0.8.13;

import { IERC20 } from "@prb/contracts/token/erc20/IERC20.sol";

import { Errors } from "src/libraries/Errors.sol";
import { Events } from "src/libraries/Events.sol";
import { LinearStream } from "src/types/Structs.sol";

import { LinearTest } from "../LinearTest.t.sol";

contract Cancel__Test is LinearTest {
    uint256 internal defaultStreamId;

    function setUp() public override {
        LinearTest.setUp();

        // Make the recipient the caller in this test suite.
        changePrank(users.recipient);
    }

    /// @dev it should revert.
    function testCannotCancel__StreamNonExistent() external {
        uint256 nonStreamId = 1729;
        vm.expectRevert(abi.encodeWithSelector(Errors.SablierV2__StreamNonExistent.selector, nonStreamId));
        linear.cancel(nonStreamId);
    }

    modifier StreamExistent() {
        // Create the default stream.
        defaultStreamId = createDefaultStream();
        _;
    }

    /// @dev it should revert.
    function testCannotCancel__StreamNonCancelable() external StreamExistent {
        // Create the non-cancelable stream.
        uint256 streamId = createDefaultStreamNonCancelable();

        // Run the test.
        vm.expectRevert(abi.encodeWithSelector(Errors.SablierV2__StreamNonCancelable.selector, streamId));
        linear.cancel(streamId);
    }

    modifier StreamCancelable() {
        _;
    }

    /// @dev it should revert.
    function testCannotCancel__CallerUnauthorized__MaliciousThirdParty(
        address eve
    ) external StreamExistent StreamCancelable {
        vm.assume(eve != address(0) && eve != defaultStream.sender && eve != users.recipient);

        // Make the unauthorized user the caller in this test.
        changePrank(eve);

        // Run the test.
        vm.expectRevert(abi.encodeWithSelector(Errors.SablierV2__Unauthorized.selector, defaultStreamId, eve));
        linear.cancel(defaultStreamId);
    }

    /// @dev it should revert.
    function testCannotCancel__CallerUnauthorized__ApprovedOperator(
        address operator
    ) external StreamExistent StreamCancelable {
        vm.assume(operator != address(0) && operator != defaultStream.sender && operator != users.recipient);

        // Approve Alice for the stream.
        linear.approve({ to: operator, tokenId: defaultStreamId });

        // Make Alice the caller in this test.
        changePrank(operator);

        // Run the test.
        vm.expectRevert(abi.encodeWithSelector(Errors.SablierV2__Unauthorized.selector, defaultStreamId, operator));
        linear.cancel(defaultStreamId);
    }

    /// @dev it should revert.
    function testCannotCancel__CallerUnauthorized__FormerRecipient() external StreamExistent StreamCancelable {
        // Transfer the stream to Alice.
        linear.transferFrom({ from: users.recipient, to: users.alice, tokenId: defaultStreamId });

        // Run the test.
        vm.expectRevert(
            abi.encodeWithSelector(Errors.SablierV2__Unauthorized.selector, defaultStreamId, users.recipient)
        );
        linear.cancel(defaultStreamId);
    }

    modifier CallerAuthorized() {
        _;
    }

    modifier CallerSender() {
        // Make the sender the caller in this test suite.
        changePrank(users.sender);
        _;
    }

    /// @dev it should delete the stream.
    function testCancel__Sender__RecipientNotContract()
        external
        StreamExistent
        StreamCancelable
        CallerAuthorized
        CallerSender
    {
        linear.cancel(defaultStreamId);
        LinearStream memory deletedStream = linear.getStream(defaultStreamId);
        LinearStream memory expectedStream;
        assertEq(deletedStream, expectedStream);
    }

    modifier RecipientContract() {
        _;
    }

    /// @dev it should delete the stream.
    function testCancel__Sender__RecipientDoesNotImplementHook()
        external
        StreamExistent
        StreamCancelable
        CallerAuthorized
        CallerSender
        RecipientContract
    {
        uint256 streamId = createDefaultStreamWithRecipient(address(empty));
        linear.cancel(streamId);
        LinearStream memory deletedStream = linear.getStream(streamId);
        LinearStream memory expectedStream;
        assertEq(deletedStream, expectedStream);
    }

    modifier RecipientImplementsHook() {
        _;
    }

    /// @dev it should ignore the revert and cancel the stream.
    function testCancel__Sender__RecipientReverts()
        external
        StreamExistent
        StreamCancelable
        CallerAuthorized
        CallerSender
        RecipientContract
        RecipientImplementsHook
    {
        uint256 streamId = createDefaultStreamWithRecipient(address(revertingRecipient));
        linear.cancel(streamId);
        LinearStream memory deletedStream = linear.getStream(streamId);
        LinearStream memory expectedStream;
        assertEq(deletedStream, expectedStream);
    }

    modifier RecipientDoesNotRevert() {
        _;
    }

    /// @dev it should ignore the revert and cancel the stream.
    function testCancel__Sender__RecipientReentrancy()
        external
        StreamExistent
        StreamCancelable
        CallerAuthorized
        CallerSender
        RecipientContract
        RecipientImplementsHook
        RecipientDoesNotRevert
    {
        uint256 streamId = createDefaultStreamWithRecipient(address(reentrantRecipient));
        linear.cancel(streamId);
        LinearStream memory deletedStream = linear.getStream(streamId);
        LinearStream memory expectedStream;
        assertEq(deletedStream, expectedStream);
    }

    modifier NoRecipientReentrancy() {
        _;
    }

    /// @dev it should perform the ERC-20 transfers, emit a Cancel event, and cancel the stream.
    ///
    /// The fuzzing ensures that all of the following scenarios are tested:
    ///
    /// - Stream ongoing.
    /// - Stream ended.
    function testCancel__Sender(
        uint256 timeWarp
    )
        external
        StreamExistent
        StreamCancelable
        CallerAuthorized
        CallerSender
        RecipientContract
        RecipientImplementsHook
        RecipientDoesNotRevert
        NoRecipientReentrancy
    {
        timeWarp = bound(timeWarp, 0, DEFAULT_TOTAL_DURATION * 2);

        // Create the stream.
        uint256 streamId = createDefaultStreamWithRecipient(address(goodRecipient));

        // Warp into the future.
        vm.warp({ timestamp: defaultStream.range.start + timeWarp });

        // Expect the tokens to be withdrawn to the recipient.
        uint128 recipientAmount = linear.getWithdrawableAmount(streamId);
        if (recipientAmount > 0) {
            vm.expectCall(
                defaultStream.token,
                abi.encodeCall(IERC20.transfer, (address(goodRecipient), recipientAmount))
            );
        }

        // Expect the tokens to be returned to the sender.
        uint128 senderAmount = defaultStream.amounts.deposit - recipientAmount;
        if (senderAmount > 0) {
            vm.expectCall(defaultStream.token, abi.encodeCall(IERC20.transfer, (defaultStream.sender, senderAmount)));
        }

        // Expect an event to be emitted.
        vm.expectEmit({ checkTopic1: true, checkTopic2: true, checkTopic3: true, checkData: true });
        emit Events.Cancel(streamId, defaultStream.sender, address(goodRecipient), senderAmount, recipientAmount);

        // Cancel the stream.
        linear.cancel(streamId);

        // Assert that the stream was deleted.
        LinearStream memory deletedStream = linear.getStream(streamId);
        LinearStream memory expectedStream;
        assertEq(deletedStream, expectedStream);

        // Assert that the NFT was not burned.
        address actualNFTOwner = linear.ownerOf({ tokenId: streamId });
        address expectedNFTOwner = address(goodRecipient);
        assertEq(actualNFTOwner, expectedNFTOwner);
    }

    modifier CallerRecipient() {
        _;
    }

    /// @dev it should delete the stream.
    function testCancel__Recipient__SenderNotContract()
        external
        StreamExistent
        StreamCancelable
        CallerAuthorized
        CallerRecipient
    {
        linear.cancel(defaultStreamId);
        LinearStream memory deletedStream = linear.getStream(defaultStreamId);
        LinearStream memory expectedStream;
        assertEq(deletedStream, expectedStream);
    }

    modifier SenderContract() {
        _;
    }

    /// @dev it should delete the stream.
    function testCancel__Recipient__SenderDoesNotImplementHook()
        external
        StreamExistent
        StreamCancelable
        CallerAuthorized
        CallerRecipient
        SenderContract
    {
        uint256 streamId = createDefaultStreamWithSender(address(empty));
        linear.cancel(streamId);

        // Assert that the stream was deleted.
        LinearStream memory deletedStream = linear.getStream(streamId);
        LinearStream memory expectedStream;
        assertEq(deletedStream, expectedStream);
    }

    modifier SenderImplementsHook() {
        _;
    }

    /// @dev it should delete the stream.
    function testCancel__Recipient__SenderReverts()
        external
        StreamExistent
        StreamCancelable
        CallerAuthorized
        CallerRecipient
        SenderContract
        SenderImplementsHook
    {
        uint256 streamId = createDefaultStreamWithSender(address(revertingSender));
        linear.cancel(streamId);

        // Assert that the stream was deleted.
        LinearStream memory deletedStream = linear.getStream(streamId);
        LinearStream memory expectedStream;
        assertEq(deletedStream, expectedStream);
    }

    modifier SenderDoesNotRevert() {
        _;
    }

    /// @dev it should ignore the revert and make the withdrawal and cancel the stream.
    function testCancel__Recipient__SenderReentrancy()
        external
        StreamExistent
        StreamCancelable
        CallerAuthorized
        CallerRecipient
        SenderContract
        SenderImplementsHook
        SenderDoesNotRevert
    {
        uint256 streamId = createDefaultStreamWithSender(address(reentrantSender));
        linear.cancel(streamId);

        // Assert that the stream was deleted.
        LinearStream memory deletedStream = linear.getStream(streamId);
        LinearStream memory expectedStream;
        assertEq(deletedStream, expectedStream);
    }

    modifier NoSenderReentrancy() {
        _;
    }

    /// @dev it should perform the ERC-20 transfers, emit a Cancel event, and cancel the stream.
    ///
    /// The fuzzing ensures that all of the following scenarios are tested:
    ///
    /// - Stream ongoing.
    /// - Stream ended.
    function testCancel__Recipient(
        uint256 timeWarp
    )
        external
        StreamExistent
        StreamCancelable
        CallerAuthorized
        CallerRecipient
        SenderContract
        SenderImplementsHook
        SenderDoesNotRevert
        NoSenderReentrancy
    {
        timeWarp = bound(timeWarp, 0, DEFAULT_TOTAL_DURATION * 2);

        // Warp into the future.
        vm.warp({ timestamp: defaultStream.range.start + timeWarp });

        // Create the stream.
        uint256 streamId = createDefaultStreamWithSender(address(goodSender));

        // Warp into the future.
        vm.warp({ timestamp: defaultStream.range.start + timeWarp });

        // Expect the tokens to be withdrawn to the recipient, if not zero.
        uint128 recipientAmount = linear.getWithdrawableAmount(streamId);
        if (recipientAmount > 0) {
            vm.expectCall(defaultStream.token, abi.encodeCall(IERC20.transfer, (users.recipient, recipientAmount)));
        }

        // Expect the tokens to be returned to the sender, if not zero.
        uint128 senderAmount = defaultStream.amounts.deposit - recipientAmount;
        if (senderAmount > 0) {
            vm.expectCall(defaultStream.token, abi.encodeCall(IERC20.transfer, (address(goodSender), senderAmount)));
        }

        // Expect an event to be emitted.
        vm.expectEmit({ checkTopic1: true, checkTopic2: true, checkTopic3: true, checkData: true });
        emit Events.Cancel(streamId, address(goodSender), users.recipient, senderAmount, recipientAmount);

        // Cancel the stream.
        linear.cancel(streamId);

        // Assert that the stream was deleted.
        LinearStream memory deletedStream = linear.getStream(streamId);
        LinearStream memory expectedStream;
        assertEq(deletedStream, expectedStream);

        // Assert that the NFT was not burned.
        address actualNFTOwner = linear.ownerOf({ tokenId: streamId });
        address expectedNFTOwner = users.recipient;
        assertEq(actualNFTOwner, expectedNFTOwner);
    }
}
