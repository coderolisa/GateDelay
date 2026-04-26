// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/Test.sol";
import "../contracts/Voting.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

contract MockGovToken is ERC20 {
    constructor() ERC20("GovToken", "GOV") {
        _mint(msg.sender, 1_000_000 ether);
    }
    function mint(address to, uint256 amount) external { _mint(to, amount); }
}

contract VotingTest is Test {
    Voting         internal voting;
    MockGovToken   internal govToken;

    address internal alice = address(0xA11CE);
    address internal bob   = address(0xB0B);
    address internal carol = address(0xCA401);

    uint256 constant DURATION = 7 days;

    function setUp() public {
        govToken = new MockGovToken();
        voting   = new Voting(address(govToken));

        govToken.mint(alice, 1_000 ether);
        govToken.mint(bob,   500 ether);
        govToken.mint(carol, 200 ether);
    }

    // ── Helpers ────────────────────────────────────────────────────────────────

    function _createProposal() internal returns (uint256) {
        return voting.createProposal("Test proposal", DURATION);
    }

    // ── Proposal creation ──────────────────────────────────────────────────────

    function test_createProposal_storesData() public {
        uint256 id = _createProposal();
        Voting.Proposal memory p = voting.getProposal(id);
        assertEq(p.id, id);
        assertTrue(p.active);
        assertEq(p.endTime, p.startTime + DURATION);
    }

    function test_createProposal_incrementsCount() public {
        _createProposal();
        _createProposal();
        assertEq(voting.proposalCount(), 2);
    }

    function test_createProposal_revertsIfNotOwner() public {
        vm.prank(alice);
        vm.expectRevert();
        voting.createProposal("Unauthorized", DURATION);
    }

    // ── Vote casting ───────────────────────────────────────────────────────────

    function test_castVote_for() public {
        uint256 id = _createProposal();
        vm.prank(alice);
        voting.castVote(id, Voting.VoteChoice.FOR);

        (uint256 forVotes,,) = voting.getResults(id);
        assertEq(forVotes, 1_000 ether);
    }

    function test_castVote_against() public {
        uint256 id = _createProposal();
        vm.prank(bob);
        voting.castVote(id, Voting.VoteChoice.AGAINST);

        (, uint256 againstVotes,) = voting.getResults(id);
        assertEq(againstVotes, 500 ether);
    }

    function test_castVote_abstain() public {
        uint256 id = _createProposal();
        vm.prank(carol);
        voting.castVote(id, Voting.VoteChoice.ABSTAIN);

        (,, uint256 abstainVotes) = voting.getResults(id);
        assertEq(abstainVotes, 200 ether);
    }

    function test_castVote_revertsDoubleVote() public {
        uint256 id = _createProposal();
        vm.startPrank(alice);
        voting.castVote(id, Voting.VoteChoice.FOR);
        vm.expectRevert(Voting.AlreadyVoted.selector);
        voting.castVote(id, Voting.VoteChoice.AGAINST);
        vm.stopPrank();
    }

    function test_castVote_revertsAfterDeadline() public {
        uint256 id = _createProposal();
        vm.warp(block.timestamp + DURATION + 1);
        vm.prank(alice);
        vm.expectRevert(Voting.VotingEnded.selector);
        voting.castVote(id, Voting.VoteChoice.FOR);
    }

    function test_castVote_revertsZeroVotingPower() public {
        uint256 id = _createProposal();
        address nobody = address(0xDEAD);
        vm.prank(nobody);
        vm.expectRevert(Voting.ZeroVotingPower.selector);
        voting.castVote(id, Voting.VoteChoice.FOR);
    }

    // ── Delegation ─────────────────────────────────────────────────────────────

    function test_delegate_transfersPower() public {
        vm.prank(bob);
        voting.delegate(alice);

        // Alice's power = own (1000) + delegated (500)
        assertEq(voting.getVotingPower(alice), 1_500 ether);
        // Bob's own power is now 0 (delegated away)
        assertEq(voting.getVotingPower(bob), 0);
    }

    function test_delegate_voteUsesFullPower() public {
        vm.prank(bob);
        voting.delegate(alice);

        uint256 id = _createProposal();
        vm.prank(alice);
        voting.castVote(id, Voting.VoteChoice.FOR);

        (uint256 forVotes,,) = voting.getResults(id);
        assertEq(forVotes, 1_500 ether);
    }

    function test_delegate_revertsOnSelfDelegation() public {
        vm.prank(alice);
        vm.expectRevert(Voting.SelfDelegation.selector);
        voting.delegate(alice);
    }

    function test_delegate_revertsOnLoop() public {
        vm.prank(alice);
        voting.delegate(bob);

        vm.prank(bob);
        vm.expectRevert(Voting.DelegationLoop.selector);
        voting.delegate(alice);
    }

    function test_delegate_removeDelegation() public {
        vm.prank(bob);
        voting.delegate(alice);
        assertEq(voting.getVotingPower(alice), 1_500 ether);

        // Remove delegation by delegating to address(0)
        vm.prank(bob);
        voting.delegate(address(0));

        assertEq(voting.getVotingPower(alice), 1_000 ether);
        assertEq(voting.getVotingPower(bob), 500 ether);
    }

    // ── Queries ────────────────────────────────────────────────────────────────

    function test_getVote_returnsRecord() public {
        uint256 id = _createProposal();
        vm.prank(alice);
        voting.castVote(id, Voting.VoteChoice.FOR);

        Voting.VoteRecord memory r = voting.getVote(id, alice);
        assertEq(uint8(r.choice), uint8(Voting.VoteChoice.FOR));
        assertEq(r.weight, 1_000 ether);
    }

    function test_getVotingPower_ownBalance() public {
        assertEq(voting.getVotingPower(alice), 1_000 ether);
    }

    // ── Close proposal ─────────────────────────────────────────────────────────

    function test_closeProposal_marksInactive() public {
        uint256 id = _createProposal();
        vm.warp(block.timestamp + DURATION + 1);
        voting.closeProposal(id);
        Voting.Proposal memory p = voting.getProposal(id);
        assertFalse(p.active);
    }

    function test_closeProposal_revertsBeforeEnd() public {
        uint256 id = _createProposal();
        vm.expectRevert(Voting.VotingNotEnded.selector);
        voting.closeProposal(id);
    }

    // ── Fuzz ───────────────────────────────────────────────────────────────────

    function testFuzz_votingPowerMatchesBalance(uint128 amount) public {
        vm.assume(amount > 0);
        address voter = address(0x1234);
        govToken.mint(voter, uint256(amount));
        assertEq(voting.getVotingPower(voter), uint256(amount));
    }
}
