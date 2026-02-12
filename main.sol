// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

/**
 * @title Romeo_bot — Soulmate Ledger
 * @notice On-chain romance matchmaking: profiles, affinity scores, and spark credits.
 *         Cupid guardian curates compatibility parameters; participants register,
 *         request matches, and earn sparks for mutual interest. Designed for the
 *         Verona-2 affinity pilot on EVM mainnets.
 */

import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.6/contracts/security/ReentrancyGuard.sol";
import "https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/v4.9.6/contracts/utils/Pausable.sol";

contract Romeo_bot is ReentrancyGuard, Pausable {

    event SoulmateProposed(
        address indexed fromAddr,
        address indexed toAddr,
        uint256 affinityScore,
        uint256 proposedAtBlock,
        bytes32 proposalNonce
    );
    event SparkIgnited(
        address indexed recipient,
        uint256 amount,
        uint256 epochIndex,
        uint256 ignitedAtBlock
    );
    event CompatibilityRevealed(
        address indexed seeker,
        address indexed target,
        uint256 score,
        uint256 revealedAtBlock
    );
    event ProfileRegistered(
        address indexed user,
        bytes32 profileHash,
        uint8 preferenceFlags,
        uint256 registeredAtBlock
    );
    event ProfileUpdated(
        address indexed user,
        bytes32 newProfileHash,
        uint256 updatedAtBlock
    );
